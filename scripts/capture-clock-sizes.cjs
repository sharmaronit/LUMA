const fs = require('node:fs');
const path = require('node:path');
(async () => {
  const tabs = await (await fetch('http://127.0.0.1:9223/json')).json();
  const tab = tabs.find(t => t.type === 'page' && t.url.startsWith('http://127.0.0.1:4174'));
  if (!tab) throw Error('Preview tab missing');
  const socket = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise(r => socket.addEventListener('open', r, {once:true}));
  let id = 0; const pending = new Map();
  socket.onmessage = event => { const m = JSON.parse(event.data); if(m.id){pending.get(m.id)?.(m);pending.delete(m.id);} };
  const send = (method, params={}) => new Promise(r => {pending.set(++id,r);socket.send(JSON.stringify({id,method,params}));});
  await send('Emulation.setDeviceMetricsOverride',{width:960,height:540,deviceScaleFactor:1,mobile:false});
  for(const style of ['digital','analog']) for(const size of ['0','100']) {
    await send('Runtime.evaluate',{expression:`localStorage.setItem('flutter.home_clock_style',${JSON.stringify(JSON.stringify(style))});localStorage.setItem('flutter.home_clock_size',${JSON.stringify(JSON.stringify(size))});localStorage.setItem('flutter.home_remember_selection','false');`});
    await send('Page.reload',{ignoreCache:true});
    await new Promise(r => setTimeout(r,10000));
    const shot=await send('Page.captureScreenshot',{format:'png'});
    fs.writeFileSync(path.resolve(__dirname,'../../artifacts',`luma-clock-${style}-${size}.png`),Buffer.from(shot.result.data,'base64'));
  }
  socket.close();
})().catch(e=>{console.error(e);process.exit(1);});
