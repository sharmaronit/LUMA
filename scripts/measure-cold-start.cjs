// Cold-start and memory benchmark for Luma on a connected TV.
//
//   node scripts/measure-cold-start.cjs [runs=10] [package=app.luma.tvlauncher.profile] [out.json]
//
// Each run force-stops the launcher, starts it through the HOME intent (as the
// remote's Home button does) and records ActivityManager's TotalTime. After the
// final run it waits for the home screen to settle and records memory.
const fs = require('node:fs');
const {execFileSync} = require('node:child_process');

const runs = Number(process.argv[2] || 10);
const pkg = process.argv[3] || 'app.luma.tvlauncher.profile';
const out = process.argv[4];
const activity = `${pkg}/app.luma.tvlauncher.MainActivity`;
const adb = (...args) => execFileSync('adb', args, {encoding: 'utf8'}).replace(/\r/g, '');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function stats(values) {
  const v = [...values].sort((a, b) => a - b);
  const q = p => v[Math.min(v.length - 1, Math.floor(v.length * p))];
  return {count: v.length, min: v[0], p50: q(0.5), p90: q(0.9), max: v[v.length - 1],
    mean: Math.round(v.reduce((a, b) => a + b, 0) / v.length)};
}

function memory() {
  const full = adb('shell', 'dumpsys', 'meminfo', pkg);
  // Read the "App Summary" block; its labels are unambiguous. Some GPUs (Mali
  // on Mi Box) report Graphics as 0, with decoded images counted in Native Heap.
  const info = full.includes('App Summary') ? full.slice(full.indexOf('App Summary')) : full;
  const kb = label => {
    const m = info.match(new RegExp(`^\\s*${label}:?\\s+(\\d+)`, 'm'));
    return m ? Math.round(Number(m[1]) / 1024) : null;
  };
  return {totalPssMb: kb('TOTAL PSS') ?? kb('TOTAL'), graphicsMb: kb('Graphics'),
    nativeHeapMb: kb('Native Heap'), javaHeapMb: kb('Java Heap')};
}

(async () => {
  const model = adb('shell', 'getprop', 'ro.product.model').trim();
  const version = (adb('shell', 'dumpsys', 'package', pkg).match(/versionName=(\S+)/) || [])[1];
  console.log(`Device ${model}, ${pkg} ${version}, ${runs} cold starts`);

  // Warm-up launch so the first measured run isn't paying for post-install dexopt.
  adb('shell', 'am', 'force-stop', pkg);
  adb('shell', 'am', 'start', '-W', '-a', 'android.intent.action.MAIN',
    '-c', 'android.intent.category.HOME', '-n', activity);
  await sleep(6000);

  const totals = [];
  for (let i = 0; i < runs; i++) {
    adb('shell', 'am', 'force-stop', pkg);
    await sleep(1500);
    const result = adb('shell', 'am', 'start', '-W', '-a', 'android.intent.action.MAIN',
      '-c', 'android.intent.category.HOME', '-n', activity);
    const total = Number((result.match(/TotalTime:\s+(\d+)/) || [])[1]);
    if (!total) throw Error(`No TotalTime in:\n${result}`);
    totals.push(total);
    console.log(`  run ${i + 1}: ${total} ms`);
    await sleep(4000);
  }

  await sleep(8000);
  const report = {device: model, package: pkg, version, coldStartMs: stats(totals),
    raw: totals, memory: memory(), at: new Date().toISOString()};
  console.log(JSON.stringify(report, null, 2));
  if (out) fs.writeFileSync(out, JSON.stringify(report, null, 2));
})().catch(error => { console.error(error.message); process.exit(1); });
