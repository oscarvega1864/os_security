// Browser integration against explicit test doubles. Never connects to FXServer.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { randomUUID } = require('node:crypto');
const { pathToFileURL } = require('node:url');
const { LuaFactory } = require('wasmoon');
const root = path.resolve(__dirname, '..');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function main() {
  const browser = [process.env.G6_BROWSER_PATH, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(file => file && fs.existsSync(file));
  assert(browser, 'Set G6_BROWSER_PATH to Chrome/Edge for the optional UI integration suite');
  const output = path.join(root, '.tools', 'g6-browser', randomUUID()); fs.mkdirSync(output, { recursive: true });
  const factory = new LuaFactory(); const lua = await factory.createEngine({ enableProxy: false });
  let brand;
  try { await lua.doString(fs.readFileSync(path.join(root, 'config/brand.lua'), 'utf8')); brand = lua.global.get('OSSecurity').Brand; }
  finally { lua.global.close(); }
  const child = spawn(browser, ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--disable-background-networking', '--disable-component-update', '--disable-sync', '--disable-breakpad',
    `--crash-dumps-dir=${output}`, `--user-data-dir=${output}`, '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0', 'about:blank'],
  { cwd: root, windowsHide: true, stdio: 'ignore' });
  let socket;
  try {
    const portFile = path.join(output, 'DevToolsActivePort');
    for (let i = 0; i < 100 && !fs.existsSync(portFile); i++) await pause(100);
    assert(fs.existsSync(portFile), 'Browser did not start a local DevTools endpoint');
    const port = Number(fs.readFileSync(portFile, 'utf8').split(/\r?\n/)[0]);
    const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    const target = targets.find(item => item.type === 'page'); assert(target);
    socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true }); socket.addEventListener('error', reject, { once: true }); });
    let next = 0; const waiting = new Map();
    socket.addEventListener('message', event => { const result = JSON.parse(event.data); const pending = waiting.get(result.id); if (pending) { waiting.delete(result.id); result.error ? pending.reject(new Error(result.error.message)) : pending.resolve(result.result); } });
    const send = (method, params = {}) => new Promise((resolve, reject) => {
      const id = ++next; const timeout = setTimeout(() => { waiting.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 10000);
      waiting.set(id, { resolve: value => { clearTimeout(timeout); resolve(value); }, reject: error => { clearTimeout(timeout); reject(error); } });
      socket.send(JSON.stringify({ id, method, params }));
    });
    const evaluate = async expression => { const result = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }); assert(!result.exceptionDetails, result.exceptionDetails?.text); return result.result.value; };
    const until = async expression => { for (let i = 0; i < 100; i++) { if (await evaluate(expression)) return; await pause(50); } throw new Error(`UI condition not reached: ${expression}`); };
    await send('Page.enable'); await send('Runtime.enable');
    await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
    await send('Emulation.setDefaultBackgroundColorOverride', { color: { r: 38, g: 46, b: 41, a: 1 } });
    await send('Page.addScriptToEvaluateOnNewDocument', { source: `
      window.GetParentResourceName = () => 'os_security'; window.__calls = []; window.__mode = 'client'; window.__fail = false;
      window.__brand = ${JSON.stringify(brand)};
      window.__device = { id:'osd_0000000001',displayId:'G6-D · osd_0000000001',type:'cctv_camera',model:'prop_cctv_cam_01a',state:'maintenance',schemaVersion:2,health:79,physical:true,remoteVideo:false,
        components:[{slot:'power',id:'osd_0000000001:power:1',model:'power_standard',health:79,state:'worn',operatingHours:700,lastMaintenanceAt:null}],actions:{} };
      window.fetch = async (url, options) => {
        const endpoint = String(url).split('/').pop(), body = JSON.parse(options.body); window.__calls.push({endpoint,body});
        if (window.__fail && endpoint==='request') throw new Error('Injected NUI failure');
        let result={ok:true};
        if(endpoint==='request') {
          if(body.action==='devices') result.data={items:[window.__device],total:1,offset:0,limit:12};
          else if(body.action==='device') result.data=window.__device;
          else if(body.action==='inventory') result.data={items:[{id:'g6_operations_tablet',name:'G6 Operations',category:'tablet',count:1,usable:true},{id:'os_cctv_kit',name:'Gruppe Sechs · Kit CCTV',category:'kit',count:2,usable:true}]};
          else if(body.action==='maintain') result.data=window.__device;
        }
        return new Response(JSON.stringify(result),{status:200,headers:{'Content-Type':'application/json'}});
      };
      window.__open = (kind, role) => { window.__mode=kind; window.__device.actions=kind==='operations'?{inspect:true,repair:true,replace:true}:{};
        const supervisor=role==='supervisor';
        window.postMessage({type:'open',session:{kind,role:kind==='operations'?(role||'technician'):'client',profile:kind==='operations'?(supervisor?'Supervisor':'Tecnico'):'Cliente',
          abilities:kind==='operations'?(supervisor?['view','inspect','beginMaintenance']:['view','inspect','repair','replace','provision','install']):[],
          employeeId:kind==='operations'?'G6-E-TEST':null,canInstall:kind==='operations'&&!supervisor,expires:Math.floor(Date.now()/1000)+90,brand:window.__brand}},'*'); };
    ` });
    await send('Page.navigate', { url: pathToFileURL(path.join(root, 'web/index.html')).href });
    await until(`document.getElementById('app')?.hidden===true && typeof window.__open==='function'`);
    console.log('PASS UI remains hidden before an authorized session message');
    await evaluate(`window.__open('client')`);
    await until(`document.querySelectorAll('.card').length===1`);
    assert(await evaluate(`document.getElementById('edition').textContent==='G6 Client' && !document.querySelector('.tablet.operations')`));
    assert(await evaluate(`Array.from(document.querySelectorAll('nav button')).some(b=>b.disabled && b.textContent.includes('Cerraduras'))`));
    assert(await evaluate(`document.getElementById('app').textContent.indexOf('Reparar')===-1 && document.querySelector('video')===null`));
    fs.writeFileSync(path.join(output, 'client.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    console.log('PASS Client identity, disabled future modules and absence of repair/video controls');
    await evaluate(`window.__device.displayId='<img src=x onerror="window.__xss=true">'; document.getElementById('refresh').click()`);
    await until(`document.getElementById('content').textContent.includes('<img src=x')`);
    assert(await evaluate(`document.querySelector('img')===null && window.__xss!==true`));
    console.log('PASS untrusted display strings render as text without HTML execution');
    await evaluate(`window.__device.displayId='G6-D · osd_0000000001';window.__device.site='Propiedad 200';window.__open('operations')`);
    await until(`document.querySelector('.tablet.operations') && document.querySelectorAll('.card').length===1`);
    assert(await evaluate(`document.querySelector('.card .site')?.textContent==='Propiedad 200'`));
    assert(await evaluate(`document.getElementById('profile').textContent.includes('G6-E-TEST') && document.getElementById('app').style.getPropertyValue('--background')==='#101a17'`));
    assert(await evaluate(`getComputedStyle(document.getElementById('heading')).color==='rgb(237, 243, 232)'`), 'Operations foreground must resolve inside its own theme');
    fs.writeFileSync(path.join(output, 'operations.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`Array.from(document.querySelectorAll('.card button')).find(b=>b.textContent===window.__brand.Text.details).click()`);
    await until(`document.querySelector('.component')`);
    assert(await evaluate(`Array.from(document.querySelectorAll('#content button')).some(b=>b.textContent===window.__brand.Text.repair && !b.disabled)`));
    assert(await evaluate(`document.getElementById('content').textContent.includes(window.__brand.Text.noSignal)`));
    console.log('PASS Operations theme, professional controls and explicit unavailable signal');
    assert(await evaluate(`Array.from(document.querySelectorAll('nav button')).some(b=>b.textContent==='Instalaciones') && document.querySelector('.profile.role-technician')`));
    await evaluate(`window.__open('operations','supervisor')`);
    await until(`document.querySelector('.profile.role-supervisor') && document.querySelectorAll('.ability').length===3`);
    assert(await evaluate(`!Array.from(document.querySelectorAll('nav button')).some(b=>b.textContent==='Instalaciones') && document.querySelector('.abilities').textContent.includes('Abrir mantenimiento')`));
    fs.writeFileSync(path.join(output, 'supervisor.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    console.log('PASS profile badge, profile functions and modules limited by the session profile');
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}))`);
    await until(`document.getElementById('app').hidden && window.__calls.some(x=>x.endpoint==='close')`);
    console.log('PASS Escape closes the browser view and invokes the native close callback');
    await evaluate(`window.__open('client')`); await until(`!document.getElementById('app').hidden && document.querySelectorAll('.card').length===1`);
    await evaluate(`window.__fail=true;document.getElementById('refresh').click()`);
    await until(`document.getElementById('app').hidden`);
    console.log('PASS failed NUI requests close safely');
    // Minijuego jugado con eventos reales de raton (CDP): taladrar, atornillar y enlazar cables.
    const mouse = (type, x, y, buttons = 0) => send('Input.dispatchMouseEvent', { type, x, y, button: type === 'mouseMoved' && !buttons ? 'none' : 'left', buttons, clickCount: type === 'mouseMoved' ? 0 : 1 });
    const centers = selector => evaluate(`Array.from(document.querySelectorAll(${JSON.stringify(selector)})).map(n => { const r = n.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2, key: n.dataset.key || null }; })`);
    const scale = async () => evaluate(`(() => { const b = document.querySelector('.mg-board'); return b.getBoundingClientRect().width / 400; })()`);
    await evaluate(`window.__calls.length = 0; window.postMessage({type:'minigame',text:window.__brand.Text.minigame},'*')`);
    await until(`!document.getElementById('minigame').hidden && document.querySelectorAll('.mg-hole').length === 4`);
    fs.writeFileSync(path.join(output, 'minigame-drill.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    for (const hole of await centers('.mg-target')) {
      await mouse('mouseMoved', hole.x, hole.y); await mouse('mousePressed', hole.x, hole.y, 1);
      await pause(2700); await mouse('mouseReleased', hole.x, hole.y);
      await pause(2000); // enfriar la broca
    }
    assert(await evaluate(`window.__calls.some(x => x.endpoint === 'minigameFx' && x.body.drilling === true)`), 'Drilling reports the drill sound state');
    await until(`document.querySelectorAll('.mg-screw').length === 4`);
    fs.writeFileSync(path.join(output, 'minigame-screw.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    const radius = 15 * await scale();
    for (const screw of await centers('.mg-screw-head')) {
      await mouse('mouseMoved', screw.x + radius, screw.y); await mouse('mousePressed', screw.x + radius, screw.y, 1);
      for (let degrees = 15; degrees <= 1110; degrees += 15) {
        const r = degrees * Math.PI / 180; await mouse('mouseMoved', screw.x + Math.cos(r) * radius, screw.y + Math.sin(r) * radius, 1); await pause(50);
      }
      await mouse('mouseReleased', screw.x + radius, screw.y); await pause(200);
    }
    await until(`document.querySelectorAll('.mg-plug').length === 4`);
    const plugs = await centers('.mg-plug'), sockets = await centers('.mg-socket');
    const wrong = sockets.find(socket => socket.key !== plugs[0].key);
    await mouse('mouseMoved', plugs[0].x, plugs[0].y); await mouse('mousePressed', plugs[0].x, plugs[0].y, 1);
    await mouse('mouseMoved', wrong.x, wrong.y, 1); await mouse('mouseReleased', wrong.x, wrong.y);
    assert(await evaluate(`document.querySelectorAll('.mg-strike.on').length === 1 && !document.querySelector('.mg-cable')`), 'A wrong terminal counts a short and drops the cable');
    for (const plug of plugs) {
      const socket = sockets.find(item => item.key === plug.key);
      await mouse('mouseMoved', plug.x, plug.y); await mouse('mousePressed', plug.x, plug.y, 1);
      await mouse('mouseMoved', (plug.x + socket.x) / 2, plug.y, 1);
      if (plug === plugs[3]) fs.writeFileSync(path.join(output, 'minigame-cables.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
      await mouse('mouseMoved', socket.x, socket.y, 1); await mouse('mouseReleased', socket.x, socket.y);
    }
    await until(`document.getElementById('minigame').hidden && window.__calls.some(x => x.endpoint === 'minigame' && x.body.ok === true)`);
    console.log('PASS mouse minigame: drill four holes, screw four screws by turning, link the cables');
    await evaluate(`window.__calls.length = 0; window.postMessage({type:'minigame',text:window.__brand.Text.minigame},'*')`);
    await until(`!document.getElementById('minigame').hidden`);
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}))`);
    await until(`document.getElementById('minigame').hidden && window.__calls.some(x=>x.endpoint==='minigame' && x.body.ok===false && x.body.reason==='cancelled')`);
    console.log('PASS Escape cancels the minigame and reports it once');
    // Teclado de alarma (pinpad) y bloque de alarma de la tablet.
    await evaluate(`window.__calls.length = 0; window.postMessage({ type: 'pinpad', data: { deviceId: 'osd_0000000009', label: 'Propiedad 200', mode: 'armed', hasPin: true, tags: true, locked: 0, entry: 22, triggered: false }, text: { pad: window.__brand.Text.alarm.pad, pinFormat: 'formato' } }, '*')`);
    await until(`!document.getElementById('pinpad').hidden && document.querySelector('.pp-status').textContent.includes('22')`);
    for (const key of ['1', '2', '3', '4']) await evaluate(`Array.from(document.querySelectorAll('.pp-key')).find(b => b.textContent === '${key}').click()`);
    assert(await evaluate(`document.querySelector('.pp-screen').textContent === '••••'`));
    fs.writeFileSync(path.join(output, 'pinpad.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`document.querySelector('.pp-mode.disarm').click()`);
    await until(`window.__calls.some(x => x.endpoint === 'pinpad' && x.body.action === 'disarm' && x.body.pin === '1234')`);
    await evaluate(`window.postMessage({ type: 'pinpadResult', ok: false, text: 'Codigo incorrecto (1/3).', data: null }, '*')`);
    await until(`document.querySelector('.pp-message.error')?.textContent === 'Codigo incorrecto (1/3).'`);
    await evaluate(`document.querySelector('.pp-tag').click()`);
    await until(`window.__calls.some(x => x.endpoint === 'pinpad' && x.body.action === 'tag')`);
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))`);
    await until(`document.getElementById('pinpad').hidden && window.__calls.some(x => x.endpoint === 'pinpadClose')`);
    console.log('PASS alarm pinpad: masked code, disarm and tag requests, errors and Escape');
    await evaluate(`window.__fail = false; window.__device.type = 'alarm_panel'; window.__device.alarm = { mode: 'armed', hasPin: true, tags: 2, triggered: true, events: [{ kind: 'triggered', at: 1794100000 }, { kind: 'armed', at: 1794099000, by: '<b>x</b>' }] }; window.__open('client')`);
    await until(`document.querySelectorAll('.card').length === 1`);
    await evaluate(`Array.from(document.querySelectorAll('.card button')).find(b => b.textContent === window.__brand.Text.details).click()`);
    await until(`document.querySelector('.alarm-block.triggered') && document.querySelectorAll('.alarm-events div').length === 2`);
    assert(await evaluate(`document.querySelector('.alarm-mode').textContent === window.__brand.Text.alarm.triggered && !document.querySelector('.alarm-events b')`));
    fs.writeFileSync(path.join(output, 'alarm-tablet.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`window.__calls.length = 0; Array.from(document.querySelectorAll('.alarm-block button')).find(b => b.textContent === window.__brand.Text.alarm.disarm).click()`);
    await until(`window.__calls.some(x => x.endpoint === 'request' && x.body.action === 'alarm' && x.body.args.action === 'disarm')`);
    console.log('PASS tablet alarm block shows mode, alert, history as text and sends remote disarm');
    console.log(`UI screenshots: ${path.relative(root, output)}`);
  } finally { socket?.close(); child.kill(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
