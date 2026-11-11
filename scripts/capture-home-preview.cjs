// Capture the local TV preview in an isolated Chrome launched with CDP on 9223.
const fs = require('node:fs');
const path = require('node:path');
(async () => {
  const tabs = await (await fetch('http://127.0.0.1:9223/json')).json();
  const tab = tabs.find(t => t.type === 'page' && t.url.startsWith('http://127.0.0.1:4174'));
  if (!tab) throw Error('Local preview tab is missing');
  const socket = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise(resolve => socket.addEventListener('open', resolve, {once: true}));
  let id = 0;
  const pending = new Map();
  socket.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.id) { pending.get(message.id)?.(message); pending.delete(message.id); }
  };
  const send = (method, params = {}) => new Promise(resolve => {
    pending.set(++id, resolve); socket.send(JSON.stringify({id, method, params}));
  });
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
  const key = async (key, code, value) => {
    await send('Input.dispatchKeyEvent', {type: 'keyDown', key, code, windowsVirtualKeyCode: value});
    await send('Input.dispatchKeyEvent', {type: 'keyUp', key, code, windowsVirtualKeyCode: value});
    await pause(600);
  };
  const screenshot = async name => {
    const result = await send('Page.captureScreenshot', {format: 'png'});
    fs.writeFileSync(path.resolve(__dirname, '../../artifacts', `${name}.png`), Buffer.from(result.result.data, 'base64'));
  };
  await send('Emulation.setDeviceMetricsOverride', {width: 1600, height: 900, deviceScaleFactor: 1, mobile: false});
  await send('Runtime.evaluate', {expression: `localStorage.setItem('flutter.minimal_background', JSON.stringify('glass'));localStorage.setItem('flutter.home_remember_selection','false');localStorage.setItem('flutter.home_show_watch','true');`});
  await send('Page.reload', {ignoreCache: true});
  await pause(15000);
  await screenshot('luma-clean-home');
  await key('ArrowUp', 'ArrowUp', 38);
  await screenshot('luma-clean-utility-label');
  await key('ArrowDown', 'ArrowDown', 40);
  await key('ArrowDown', 'ArrowDown', 40);
  await screenshot('luma-clean-content');
  for (let i = 0; i < 3; i++) {
    await send('Input.dispatchMouseEvent', {type: 'mouseWheel', x: 1400, y: 750, deltaX: 0, deltaY: 1500});
    await pause(400);
  }
  await screenshot('luma-clean-settings');
  socket.close();
})().catch(error => { console.error(error); process.exit(1); });
