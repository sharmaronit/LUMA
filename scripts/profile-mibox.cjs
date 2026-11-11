// Capture Flutter UI/raster timings on a connected TV without DevTools UI overhead.
// Usage: node scripts/profile-mibox.cjs <forwarded VM service URL> <output prefix> [seconds]
const fs = require('node:fs');
const {spawn, execFileSync} = require('node:child_process');
let [service, output, seconds = '15'] = process.argv.slice(2);
if (!service || !output) throw Error('Provide VM service URL and output prefix');
if (service === 'auto') {
  const matches = [...execFileSync('adb',['logcat','-d','-s','flutter']).toString()
    .matchAll(/The Dart VM service is listening on (http:\/\/127\.0\.0\.1:(\d+)\/\S+)/g)];
  const latest = matches.at(-1);
  if (!latest) throw Error('No running Flutter VM service found');
  execFileSync('adb',['forward','tcp:8181',`tcp:${latest[2]}`]);
  service = latest[1].replace(`:${latest[2]}/`, ':8181/');
}
const ws = new WebSocket(service.replace(/^http/, 'ws').replace(/\/?$/, '/ws'));
let sequence = 0;
const pending = new Map();
const frames = [];
ws.onmessage = ({data}) => {
  const message = JSON.parse(data);
  if (message.method === 'streamNotify' &&
      message.params?.event?.extensionKind === 'Flutter.Frame') {
    frames.push(message.params.event.extensionData);
  }
  if (message.id && pending.has(message.id)) {
    const {resolve, reject} = pending.get(message.id);
    pending.delete(message.id);
    message.error ? reject(Error(JSON.stringify(message.error))) : resolve(message.result);
  }
};
const rpc = (method, params = {}) => new Promise((resolve, reject) => {
  const id = String(++sequence);
  pending.set(id, {resolve, reject});
  ws.send(JSON.stringify({jsonrpc:'2.0', id, method, params}));
});
function stats(values) {
  values.sort((a,b) => a-b);
  const q = p => values[Math.min(values.length-1, Math.floor(values.length*p))];
  return {count:values.length, p50:q(.5), p90:q(.9), p99:q(.99), max:values.at(-1),
    overBudget:values.filter(v => v > 1000/59.94006).length};
}
(async () => {
  await new Promise((resolve,reject) => {ws.onopen=resolve;ws.onerror=reject;});
  await rpc('streamListen', {streamId:'Extension'});
  await rpc('setVMTimelineFlags', {recordedStreams:['Dart','Embedder','GC']});
  await rpc('clearVMTimeline');
  console.log(`Recording ${seconds}s; navigate with the remote now.`);
  if (process.env.LUMA_PROFILE_DPAD === '1') {
    // Focus only: no launch, preference, or destructive commands.
    const script = 'for r in 1 2 3; do for i in 1 2 3 4 5 6 7 8; do input keyevent 22; sleep 0.12; done; for i in 1 2 3 4 5 6 7 8; do input keyevent 21; sleep 0.12; done; done';
    spawn('adb', ['shell', script], {stdio:'ignore'});
  }
  await new Promise(resolve => setTimeout(resolve, Number(seconds)*1000));
  const timeline = await rpc('getVMTimeline');
  fs.writeFileSync(`${output}.timeline.json`, JSON.stringify(timeline));
  fs.writeFileSync(`${output}.frames.json`, JSON.stringify(frames));
  const durations = new Map(), stacks = new Map();
  for (const event of timeline.traceEvents) {
    const key = `${event.pid}/${event.tid}`;
    let duration;
    if (event.ph === 'B') {
      if (!stacks.has(key)) stacks.set(key, []);
      stacks.get(key).push(event);
    } else if (event.ph === 'E') {
      const begin = stacks.get(key)?.pop();
      if (begin) {duration=(event.ts-begin.ts)/1000;event.name=begin.name;}
    } else if (event.ph === 'X') duration=event.dur/1000;
    if (duration !== undefined) {
      if (!durations.has(event.name)) durations.set(event.name, []);
      durations.get(event.name).push(duration);
    }
  }
  const summary = Object.fromEntries([...durations]
    .filter(([name]) => /Frame|Raster|Draw|BUILD|LAYOUT|PAINT|Collect|GC|Pipeline|Vsync/i.test(name))
    .map(([name,values]) => [name, stats(values)]));
  if (frames.length) {
    summary.FlutterFrameBuild = stats(frames.map(f=>f.build/1000));
    summary.FlutterFrameRaster = stats(frames.map(f=>f.raster/1000));
    summary.FlutterFrameVsyncOverhead = stats(frames.map(f=>f.vsyncOverhead/1000));
  }
  fs.writeFileSync(`${output}.summary.json`, JSON.stringify(summary,null,2));
  console.log(JSON.stringify(summary,null,2));
  await rpc('setVMTimelineFlags', {recordedStreams:[]});
  ws.close();
})().catch(error => {console.error(error);process.exit(1);});
