// Run against an isolated Chrome instance with CDP on port 9223.
const fs = require('node:fs');
const path = require('node:path');
(async () => {
  const tabs = await (await fetch('http://127.0.0.1:9223/json')).json();
  const tab = tabs.find(t => t.type === 'page' && t.url.startsWith('http://127.0.0.1:4174'));
  if (!tab) throw Error('Local preview tab missing');
  const socket = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise(r => socket.addEventListener('open', r, {once: true}));
  let id = 0; const pending = new Map();
  socket.onmessage = event => { const m = JSON.parse(event.data); if (m.id) { pending.get(m.id)?.(m); pending.delete(m.id); } };
  const send = (method, params = {}) => new Promise(r => { pending.set(++id, r); socket.send(JSON.stringify({id, method, params})); });
  const pause = ms => new Promise(r => setTimeout(r, ms));
  const shot = async name => { const r = await send('Page.captureScreenshot', {format: 'png'}); fs.writeFileSync(path.resolve(__dirname, '../../artifacts', `${name}.png`), Buffer.from(r.result.data, 'base64')); };
  const key = async (key, code, value) => {
    for (const type of ['keyDown', 'keyUp']) await send('Input.dispatchKeyEvent', {type, key, code, windowsVirtualKeyCode: value});
    await pause(400);
  };
  await send('Emulation.setDeviceMetricsOverride', {width: 960, height: 540, deviceScaleFactor: 1, mobile: false});
  await send('Page.reload', {ignoreCache: true}); await pause(6500);
  for (const type of ['mousePressed', 'mouseReleased']) await send('Input.dispatchMouseEvent', {type, x: 178, y: 38, button: 'left', clickCount: 1});
  await pause(1800); await shot('luma-all-apps-design');
  await key('ArrowRight', 'ArrowRight', 39);
  await key('ArrowDown', 'ArrowDown', 40);
  await shot('luma-all-apps-grid-focus');
  socket.close();
})().catch(error => { console.error(error); process.exit(1); });
