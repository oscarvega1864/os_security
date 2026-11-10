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
    await until(`document.readyState==='complete' && document.getElementById('app')?.hidden===true && typeof window.__open==='function'`);
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
    // Desmontaje: desconectar los cables arrastrandolos a la bandeja y desatornillar en sentido antihorario.
    await evaluate(`window.__calls.length = 0; window.postMessage({type:'minigame',text:window.__brand.Text.minigame,mode:'remove'},'*')`);
    await until(`document.querySelectorAll('.mg-plug').length === 4 && document.querySelector('.mg-tray')`);
    const tray = await evaluate(`(() => { const r = document.querySelector('.mg-tray').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()`);
    fs.writeFileSync(path.join(output, 'minigame-unplug.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    for (const plug of await centers('.mg-plug')) {
      await mouse('mouseMoved', plug.x, plug.y); await mouse('mousePressed', plug.x, plug.y, 1);
      await mouse('mouseMoved', (plug.x + tray.x) / 2, plug.y, 1); await mouse('mouseMoved', tray.x, tray.y, 1); await mouse('mouseReleased', tray.x, tray.y);
    }
    await until(`document.querySelectorAll('.mg-screw').length === 4`);
    const unscrewRadius = 15 * await scale();
    for (const screw of await centers('.mg-screw-head')) {
      await mouse('mouseMoved', screw.x + unscrewRadius, screw.y); await mouse('mousePressed', screw.x + unscrewRadius, screw.y, 1);
      for (let degrees = 15; degrees <= 1110; degrees += 15) {
        const r = -degrees * Math.PI / 180; await mouse('mouseMoved', screw.x + Math.cos(r) * unscrewRadius, screw.y + Math.sin(r) * unscrewRadius, 1); await pause(50);
      }
      await mouse('mouseReleased', screw.x + unscrewRadius, screw.y); await pause(200);
    }
    await until(`document.getElementById('minigame').hidden && window.__calls.some(x => x.endpoint === 'minigame' && x.body.ok === true)`);
    console.log('PASS removal minigame: unplug cables to the tray and unscrew counter-clockwise');
    await evaluate(`window.__calls.length = 0; window.postMessage({type:'minigame',text:window.__brand.Text.minigame},'*')`);
    await until(`!document.getElementById('minigame').hidden`);
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}))`);
    await until(`document.getElementById('minigame').hidden && window.__calls.some(x=>x.endpoint==='minigame' && x.body.ok===false && x.body.reason==='cancelled')`);
    console.log('PASS Escape cancels the minigame and reports it once');
    // Cambio de bombin: quitar el tornillo, sacar el viejo con la leva alineada, meter el nuevo y apretar.
    const cylinderScale = async () => evaluate(`(() => { const b = document.querySelector('#cylinder .mg-board'); return b.getBoundingClientRect().width / 400; })()`);
    const turn = async (center, radius, from, degrees) => {
      const step = degrees > 0 ? 10 : -10;
      await mouse('mouseMoved', center.x + Math.cos(from) * radius, center.y + Math.sin(from) * radius);
      await mouse('mousePressed', center.x + Math.cos(from) * radius, center.y + Math.sin(from) * radius, 1);
      for (let d = step; Math.abs(d) <= Math.abs(degrees); d += step) {
        const r = from + d * Math.PI / 180; await mouse('mouseMoved', center.x + Math.cos(r) * radius, center.y + Math.sin(r) * radius, 1); await pause(40);
      }
      const end = from + degrees * Math.PI / 180; await mouse('mouseReleased', center.x + Math.cos(end) * radius, center.y + Math.sin(end) * radius); await pause(150);
    };
    const camAngle = () => evaluate(`Number((document.querySelector('.cy-cam').getAttribute('transform') || 'rotate(0').match(/rotate\\(([-0-9.e]+)/)[1])`);
    const align = async () => {
      const key = (await centers('.cy-key'))[0]; const s = await cylinderScale();
      const angle = await camAngle(); const delta = -(((angle % 360) + 540) % 360 - 180);
      await turn(key, 22 * s, Math.PI / 2, delta);
      assert(await evaluate(`document.querySelector('.cy-cam').classList.contains('aligned')`), 'The cam must end aligned');
    };
    const drag = async dx => {
      const body = (await centers('.cy-body'))[0]; const s = await cylinderScale();
      await mouse('mouseMoved', body.x, body.y); await mouse('mousePressed', body.x, body.y, 1);
      for (let i = 1; i <= 10; i++) { await mouse('mouseMoved', body.x + dx * s * i / 10, body.y, 1); await pause(30); }
      await mouse('mouseReleased', body.x + dx * s, body.y); await pause(500);
    };
    await evaluate(`window.__calls.length = 0; window.postMessage({type:'cylinder',text:window.__brand.Text.locks.minigame,data:{from:'Bombin de serie',to:'Bombin de seguridad',tier:2}},'*')`);
    await until(`!document.getElementById('cylinder').hidden && document.querySelector('.cy-screw')`);
    fs.writeFileSync(path.join(output, 'cylinder-unscrew.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await turn((await centers('.cy-screw .mg-screw-head'))[0], 15 * await cylinderScale(), 0, -760);
    await until(`document.querySelector('.cy-body') && !document.querySelector('.cy-screw')`);
    await drag(-60); // leva sin alinear: atasco
    assert(await evaluate(`document.querySelectorAll('#cylinder .mg-strike.on').length === 1`), 'Moving a misaligned cylinder jams');
    await align();
    fs.writeFileSync(path.join(output, 'cylinder-out.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await drag(-160);
    await until(`document.querySelector('.cy-cylinder.fresh')`);
    await align(); await drag(170);
    await until(`document.querySelector('.cy-screw')`);
    fs.writeFileSync(path.join(output, 'cylinder-screw.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await turn((await centers('.cy-screw .mg-screw-head'))[0], 15 * await cylinderScale(), 0, 760);
    await until(`document.getElementById('cylinder').hidden && window.__calls.some(x => x.endpoint === 'cylinder' && x.body.ok === true)`);
    assert(await evaluate(`window.__calls.some(x => x.endpoint === 'cylinderFx' && x.body.phase === 'screw')`));
    console.log('PASS cylinder change: unscrew, jam on a misaligned cam, swap the cylinder and tighten');
    await evaluate(`window.__calls.length = 0; window.postMessage({type:'cylinder',text:window.__brand.Text.locks.minigame,data:{from:'a',to:'b',tier:3}},'*')`);
    await until(`!document.getElementById('cylinder').hidden`);
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}))`);
    await until(`document.getElementById('cylinder').hidden && window.__calls.some(x=>x.endpoint==='cylinder' && x.body.ok===false && x.body.reason==='cancelled')`);
    console.log('PASS Escape cancels the cylinder change');
    // Vehiculo: grapas del embellecedor con la tension justa, medir y empalmar, y probar el mando.
    await evaluate(`window.__calls.length = 0; window.postMessage({type:'carwire',text:window.__brand.Text.cars.minigame,data:{kind:'lock',plate:'OS000012'}},'*')`);
    await until(`!document.getElementById('carwire').hidden && document.querySelectorAll('.cw-clip').length === 4`);
    fs.writeFileSync(path.join(output, 'car-trim.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    const clips = await centers('.cw-clip');
    await mouse('mouseMoved', clips[0].x, clips[0].y); await mouse('mousePressed', clips[0].x, clips[0].y, 1); await pause(1500);
    await mouse('mouseReleased', clips[0].x, clips[0].y); await pause(100);
    assert(await evaluate(`document.querySelectorAll('#carwire .mg-strike.on').length === 1 && document.querySelector('.cw-clip.broken')`), 'Pulling too long breaks the clip');
    for (const clip of clips.slice(1)) {
      await mouse('mouseMoved', clip.x, clip.y); await mouse('mousePressed', clip.x, clip.y, 1); await pause(990);
      await mouse('mouseReleased', clip.x, clip.y); await pause(120);
    }
    await until(`document.querySelectorAll('.cw-wire').length === 6`);
    const expected = { '+12V': 0, 'Masa': 1, 'CAN': 2 };
    const wiresAt = await centers('.cw-wire');
    const byLead = [];
    for (const wire of wiresAt) {
      await mouse('mouseMoved', wire.x, wire.y); await mouse('mousePressed', wire.x, wire.y, 1); await mouse('mouseReleased', wire.x, wire.y); await pause(60);
      const reading = await evaluate(`document.querySelector('#carwire .mg-status').textContent.split(': ').slice(1).join(': ').split(' (')[0]`);
      if (reading in expected) byLead[expected[reading]] = wire; else byLead.decoy = wire;
    }
    assert(byLead[0] && byLead[1] && byLead[2] && byLead.decoy, 'Probing reveals what every wire is');
    assert(await evaluate(`Array.from(document.querySelectorAll('.cw-reading')).every(n => n.textContent.length > 0) && Array.from(document.querySelectorAll('.cw-lead-label')).map(n => n.textContent).join() === '+12V,Masa,CAN'`), 'Wire names under each wire match the module leads');
    fs.writeFileSync(path.join(output, 'car-wiring.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    const leadsAt = await centers('.cw-lead');
    await mouse('mouseMoved', leadsAt[0].x, leadsAt[0].y); await mouse('mousePressed', leadsAt[0].x, leadsAt[0].y, 1);
    await mouse('mouseMoved', byLead.decoy.x, byLead.decoy.y, 1); await mouse('mouseReleased', byLead.decoy.x, byLead.decoy.y); await pause(60);
    assert(await evaluate(`document.querySelectorAll('#carwire .mg-strike.on').length === 1`), 'A wrong wire counts a fault');
    for (let i = 0; i < 3; i++) {
      await mouse('mouseMoved', leadsAt[i].x, leadsAt[i].y); await mouse('mousePressed', leadsAt[i].x, leadsAt[i].y, 1);
      await mouse('mouseMoved', byLead[i].x, byLead[i].y + 20, 1); await mouse('mouseReleased', byLead[i].x, byLead[i].y + 20); await pause(60);
    }
    await until(`document.querySelector('.cw-button')`);
    await evaluate(`document.querySelector('.cw-button').dispatchEvent(new MouseEvent('click', { bubbles: true }))`);
    await until(`document.getElementById('carwire').hidden && window.__calls.some(x => x.endpoint === 'carwire' && x.body.ok === true)`);
    console.log('PASS vehicle install: trim clips with the right tension, probe and splice the module, test the key fob');
    // Ganzua: fijar cada pin con Espacio cuando pasa por la zona verde; fallar suma un fallo.
    await evaluate(`window.__calls.length = 0; window.postMessage({type:'lockpick',text:window.__brand.Text.lockpick,data:{kind:'door',tier:2,pins:3,zone:0.3,speed:0.5,seconds:60}},'*')`);
    await until(`!document.getElementById('lockpick').hidden && document.querySelectorAll('.lp-column').length === 3`);
    await until(`document.querySelector('.lp-column.active .lp-zone:not(.hot)')`);
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown', { code: 'Space', key: ' ' }))`);
    assert(await evaluate(`document.querySelectorAll('#lockpick .mg-strike.on').length === 1`), 'Pressing outside the green zone is a miss');
    fs.writeFileSync(path.join(output, 'lockpick.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    for (let pin = 0; pin < 3; pin++) {
      await until(`document.querySelector('.lp-column.active .lp-zone.hot')`);
      await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown', { code: 'Space', key: ' ' }))`);
    }
    await until(`document.getElementById('lockpick').hidden && window.__calls.some(x => x.endpoint === 'lockpick' && x.body.ok === true)`);
    await evaluate(`window.postMessage({type:'lockpick',text:window.__brand.Text.lockpick,data:{kind:'vehicle',tier:1,pins:3,zone:0.2,speed:1,seconds:60}},'*')`);
    await until(`!document.getElementById('lockpick').hidden`);
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))`);
    await until(`document.getElementById('lockpick').hidden && window.__calls.some(x => x.endpoint === 'lockpick' && x.body.cancel === true)`);
    console.log('PASS lockpick: miss outside the zone, set every pin in the green zone, Escape gives up');
    // Puente: tapa de la columna, unir +12V con Llave y arrancar soltando en la franja verde.
    await evaluate(`window.__calls.length = 0; window.postMessage({type:'carwire',text:window.__brand.Text.cars.minigame,data:{kind:'hotwire',plate:'OS000012',decoys:2,band:0.3}},'*')`);
    await until(`!document.getElementById('carwire').hidden && document.querySelectorAll('.cw-clip').length === 4`);
    for (const clip of await centers('.cw-clip')) {
      await mouse('mouseMoved', clip.x, clip.y); await mouse('mousePressed', clip.x, clip.y, 1); await pause(990);
      await mouse('mouseReleased', clip.x, clip.y); await pause(120);
    }
    await until(`document.querySelectorAll('.cw-wire').length === 4 && document.querySelectorAll('.cw-lead').length === 2`);
    const hotNames = { '+12V': 0, 'Llave': 1 }; const hotWires = [];
    for (const wire of await centers('.cw-wire')) {
      await mouse('mouseMoved', wire.x, wire.y); await mouse('mousePressed', wire.x, wire.y, 1); await mouse('mouseReleased', wire.x, wire.y); await pause(60);
      const name = await evaluate(`document.querySelector('#carwire .mg-status').textContent.split(': ').slice(1).join(': ').split(' (')[0]`);
      if (name in hotNames) hotWires[hotNames[name]] = wire;
    }
    const hotLeads = await centers('.cw-lead');
    for (let i = 0; i < 2; i++) {
      await mouse('mouseMoved', hotLeads[i].x, hotLeads[i].y); await mouse('mousePressed', hotLeads[i].x, hotLeads[i].y, 1);
      await mouse('mouseMoved', hotWires[i].x, hotWires[i].y + 20, 1); await mouse('mouseReleased', hotWires[i].x, hotWires[i].y + 20); await pause(60);
    }
    await until(`document.querySelector('.cw-start')`);
    fs.writeFileSync(path.join(output, 'hotwire-start.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    const band = await evaluate(`(() => { const b = document.querySelector('#carwire .cw-band'); return { from: parseFloat(b.style.left) / 100, width: parseFloat(b.style.width) / 100 }; })()`);
    const start = (await centers('.cw-start'))[0];
    await mouse('mouseMoved', start.x, start.y); await mouse('mousePressed', start.x, start.y, 1); await pause(200);
    await mouse('mouseReleased', start.x, start.y); await pause(100);
    assert(await evaluate(`document.querySelector('#carwire .mg-status').textContent.includes('No arranca')`), 'Releasing too early does not start');
    const hold = Math.round(((band.from + band.width / 2) / 0.62) * 1000);
    await mouse('mousePressed', start.x, start.y, 1); await pause(hold); await mouse('mouseReleased', start.x, start.y);
    await until(`document.getElementById('carwire').hidden && window.__calls.some(x => x.endpoint === 'hotwire' && x.body.ok === true)`);
    console.log('PASS hotwire: column cover, join +12V with the key wire, crank and release in the green band');
    // Teclado de alarma (pinpad) y bloque de alarma de la tablet.
    await evaluate(`window.__calls.length = 0; window.postMessage({ type: 'pinpad', data: { deviceId: 'osd_0000000009', label: 'Propiedad 200', mode: 'armed', hasPin: true, tags: true, locked: 0, entry: 22, triggered: false }, text: { pad: window.__brand.Text.alarm.pad, pinFormat: 'formato' } }, '*')`);
    await until(`!document.getElementById('pinpad').hidden && document.querySelector('.pp-status').textContent.includes('22')`);
    await until(`document.querySelector('.pp-status').textContent.includes('20')`); // la cuenta atras baja sola
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
    await evaluate(`window.postMessage({ type: 'siren', volume: 0.6 }, '*')`); await until(`window.__osSiren.active()`);
    await evaluate(`window.postMessage({ type: 'siren', volume: 0 }, '*')`); await until(`!window.__osSiren.active()`);
    console.log('PASS generated siren starts with a volume and stops at zero');
    await evaluate(`window.__fail = false; window.__device.type = 'alarm_panel'; window.__device.alarm = { mode: 'armed', hasPin: true, tags: 2, triggered: true, events: [{ kind: 'triggered', at: 1794100000 }, { kind: 'armed', at: 1794099000, by: '<b>x</b>' }] }; window.__open('client')`);
    await until(`document.querySelectorAll('.card').length === 1`);
    await evaluate(`Array.from(document.querySelectorAll('.card button')).find(b => b.textContent === window.__brand.Text.details).click()`);
    await until(`document.querySelector('.alarm-block.triggered') && document.querySelectorAll('.alarm-events div').length === 2`);
    assert(await evaluate(`document.querySelector('.alarm-mode').textContent === window.__brand.Text.alarm.triggered && !document.querySelector('.alarm-events b')`));
    fs.writeFileSync(path.join(output, 'alarm-tablet.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`window.__calls.length = 0; Array.from(document.querySelectorAll('.alarm-block button')).find(b => b.textContent === window.__brand.Text.alarm.disarm).click()`);
    await until(`window.__calls.some(x => x.endpoint === 'request' && x.body.action === 'alarm' && x.body.args.action === 'disarm')`);
    console.log('PASS tablet alarm block shows mode, alert, history as text and sends remote disarm');
    await evaluate(`window.__device.removable = true; window.__calls.length = 0; document.getElementById('refresh').click()`);
    await until(`Array.from(document.querySelectorAll('#content button')).some(b => b.textContent === window.__brand.Text.remove)`);
    await evaluate(`Array.from(document.querySelectorAll('#content button')).find(b => b.textContent === window.__brand.Text.remove).click()`);
    await until(`window.__calls.some(x => x.endpoint === 'request' && x.body.action === 'remove' && x.body.args.deviceId)`);
    console.log('PASS removable devices offer an uninstall button that requests the removal');
    console.log(`UI screenshots: ${path.relative(root, output)}`);
  } finally { socket?.close(); child.kill(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
