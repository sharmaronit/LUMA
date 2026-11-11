// Measure the opt-in, 30-second frame probe in a release performance APK.
const fs = require('node:fs');
const {execFileSync, spawn} = require('node:child_process');
const output = process.argv[2];
const mode = process.argv[3] || 'mixed';
if (!['home','apps','programmes','menus','mixed'].includes(mode)) throw Error('Scenario must be home, apps, programmes, menus or mixed');
if (!output) throw Error('Supply an output JSON path');
const adb = args => execFileSync('adb', args, {encoding:'utf8'});
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const pkg = 'app.luma.tvlauncher.profile';
(async () => {
  adb(['shell','am','force-stop',pkg]);
  adb(['shell','input','keyevent','224']);
  // Match a real Home launch. A bare component start creates a standard task;
  // subsequently pressing Home can create a second launcher activity/engine.
  adb(['shell','am','start','-a','android.intent.action.MAIN',
    '-c','android.intent.category.HOME','-n',`${pkg}/app.luma.tvlauncher.MainActivity`]);
  let pid = '';
  for (let attempt = 0; attempt < 20; attempt++) {
    try { pid = adb(['shell','pidof',pkg]).trim(); } catch (_) {}
    if (/^\d+$/.test(pid)) break;
    await delay(250);
  }
  if (!/^\d+$/.test(pid)) throw Error('Performance app did not start');
  const logs = () => adb(['logcat','-d','-s','flutter']).split('\n')
    .filter(line => new RegExp(`\\s${pid}\\s`).test(line));
  let ready = false;
  for (let attempt = 0; attempt < 25; attempt++) {
    if (logs().some(line => line.includes('LUMA_FRAME_PROBE_READY'))) {ready=true;break;}
    await delay(1000);
  }
  if (!ready) throw Error('Release frame probe did not become ready');
  // Back returns a remembered All apps route to Home; on Home it resets focus.
  adb(['shell','input','keyevent','4']);
  await delay(400);
  console.log(`Measuring release ${mode} navigation.`);
  const sequence = 'for r in 1 2; do for i in 1 2 3 4 5 6 7 8; do input keyevent 22; sleep 0.12; done; for i in 1 2 3 4 5 6 7 8; do input keyevent 21; sleep 0.12; done; done';
  const openApps = 'input keyevent 19; input keyevent 22; input keyevent 22; input keyevent 23; sleep 0.5';
  // Home -> programme cards. Pause longer than the 420 ms focus
  // motion so the sample includes complete transitions, plus row scrolling.
  const programmes = 'input keyevent 20; sleep 0.6; ' +
    'for r in 1 2 3; do for i in 1 2 3 4; do input keyevent 22; sleep 0.48; done; ' +
    'for i in 1 2 3 4; do input keyevent 21; sleep 0.48; done; done';
  const menus = 'for i in 1 2 3 4 5 6 7 8 9 10 11 12; do input keyevent 82; sleep 0.35; input keyevent 4; sleep 0.35; done; ' +
    'input keyevent 19; input keyevent 22; input keyevent 22; input keyevent 22; ' +
    'for i in 1 2 3 4 5 6; do input keyevent 23; sleep 0.45; input keyevent 4; sleep 0.45; done';
  const mixed = mode === 'home'  ? `${sequence}; ${sequence}`
    : mode === 'apps' ? `${openApps}; ${sequence}; ${sequence}`
    : mode === 'programmes' ? programmes
    : mode === 'menus' ? menus
    : `${sequence}; ${openApps}; ${sequence}`;
  const navigation = spawn('adb', ['shell', mixed], {stdio:'ignore'});
  let found;
  for (let attempt = 0; attempt < 45; attempt++) {
    const line = logs().find(line => line.includes('LUMA_FRAME_TIMINGS '));
    if (line) {found=JSON.parse(line.split('LUMA_FRAME_TIMINGS ')[1]);break;}
    await delay(1000);
  }
  if (!found) throw Error('No release frame timings returned');
  found.scenario = mode;
  await new Promise(resolve => navigation.exitCode !== null ? resolve() : navigation.on('exit',resolve));
  fs.writeFileSync(output, JSON.stringify(found,null,2));
  console.log(JSON.stringify(found,null,2));
})().catch(error => {console.error(error);process.exit(1);});
