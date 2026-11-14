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
          else if(body.action==='zones') result.data={installDistance:4,clients:[{id:1,name:'oscar_vega · oscar',self:true},{id:2,name:'segundo · amigo',self:false}],
            kits:[{id:'os_cctv_kit',name:'Kit CCTV',deviceType:'cctv_camera',count:2},{id:'os_alarm_kit',name:'Kit alarma',deviceType:'alarm_panel',count:0}],
            zones:[{id:'zona_2',place:'Low Power St, Pillbox Hill',client:'segundo · amigo',createdAt:1762700000,surface:'wall',size:1.5,site:'Propiedad 200',distance:2.5,mine:true,status:'free',deletable:true},
              {id:'zona_1',place:'Vespucci Blvd',client:'oscar',createdAt:1762600000,surface:'ceiling',size:1,distance:40,mine:true,status:'installed',deviceId:'osd_0000000001',deletable:false},
              {id:'zona_f2529d2',surface:'wall',size:4,distance:66.5,mine:true,status:'free',deletable:true}]};
          else if(body.action==='requests') result.data={kinds:[{value:'cctv',label:'Instalar camaras'},{value:'repair',label:'Reparar un dispositivo'}],places:[{value:'here',label:'Donde estoy ahora'},{value:'site:property:200',label:'Propiedad 200'}],noteLength:140,maxOpen:3,
            items:[{id:'ot_000002',kind:'repair',status:'billed',note:'Camara sin imagen',place:'Propiedad 200',techName:'oscar_vega',price:1250,createdAt:1762700000},{id:'ot_000001',kind:'cctv',status:'open',note:'Dos camaras',place:'Propiedad 200',createdAt:1762600000}]};
          else if(body.action==='orders') result.data={canWork:true,share:0.6,maxPrice:25000,items:[{id:'ot_000003',kind:'alarm',status:'open',note:'Alarma en el local',place:'Negocio 4',clientName:'segundo · amigo',distance:120,position:{x:1,y:2,z:3},createdAt:1762700000},
            {id:'ot_000002',kind:'repair',status:'accepted',mine:true,note:'Camara sin imagen',place:'Propiedad 200',clientName:'oscar',distance:3,position:{x:4,y:5,z:6},createdAt:1762600000}]};
          else if(body.action==='emergencies') result.data={places:[{value:'here',label:'Donde estoy ahora'},{value:'site:property:200',label:'Propiedad 200'}],noteLength:140,cooldown:0,active:false,
            items:[{id:'av_000002',kind:'panic',status:'assigned',note:'Ruido en el garaje',place:'Propiedad 200',techName:'oscar_vega',count:1,createdAt:1762700000,updatedAt:1762700100},
              {id:'av_000001',kind:'alarm',status:'resolved',place:'Propiedad 200',resolution:'Falsa alarma: el gato',count:2,createdAt:1762600000,updatedAt:1762600100}]};
          else if(body.action==='dispatch') result.data={canTake:window.__mode==='operations'&&window.__role!=='supervisor',canAssign:window.__role==='supervisor',noteLength:140,
            crew:window.__role==='supervisor'?[{id:1,name:'oscar_vega'},{id:3,name:'jefa',self:true}]:[],
            items:[{id:'av_000003',kind:'panic',status:'open',priority:1,note:'Me siguen',place:'Ubicacion del cliente',clientName:'segundo · amigo',distance:340,count:1,position:{x:7,y:8,z:9},createdAt:1762700000,updatedAt:1762700000},
              {id:'av_000001',kind:'alarm',status:'assigned',priority:2,mine:window.__role!=='supervisor',place:'Propiedad 200',clientName:'oscar',techName:'oscar_vega',distance:12,count:3,position:{x:1,y:2,z:3},createdAt:1762600000,updatedAt:1762600000}]};
          else if(body.action==='doors') result.data={items:[{id:'p200_1',site:'Propiedad 200',tier:'Bombin de serie',level:1,locked:true}]};
          else if(body.action==='trackers') result.data={items:[{plate:'OS000012',lock:true,alarm:true,locked:true,sounding:false,position:{x:10.4,y:-20.2,z:30}}]};
          else if(body.action==='home') result.data={counts:{devices:3,ok:2,attention:1,live:1,armed:1,triggered:1,orders:2,ordersOpen:1,ordersMine:1,calls:1,callsMine:0,cars:1,carsAlarm:0},
            attention:[{kind:'device',id:'osd_0000000001',title:'G6-D · osd_0000000001',subtitle:'<img src=x onerror="window.__xss=true">',reason:'triggered'},{kind:'call',id:'av_000003',title:'av_000003',subtitle:'Vinewood',reason:'panic'}],
            points:[{kind:'device',id:'osd_0000000001',x:-620,y:240,label:'G6-D · osd_0000000001',subtitle:'Propiedad 200',state:'triggered'},{kind:'call',id:'av_000003',x:-400,y:1000,label:'av_000003',subtitle:'Vinewood',state:'panic'}]};
          else if(body.action==='search') result.data={query:body.args.query,items:[{kind:'device',id:'osd_0000000001',title:'G6-D · osd_0000000001',subtitle:'Propiedad 200',type:'cctv_camera',state:'active'},{kind:'call',id:'av_000003',title:'av_000003',subtitle:'Vinewood',state:'open'}]};
          else if(body.action==='incidents') result.data={items:[{at:1762700000,kind:'triggered',device:'G6-D · osd_0000000009',deviceId:'osd_0000000009',site:'Propiedad 200'}]};
        }
        return new Response(JSON.stringify(result),{status:200,headers:{'Content-Type':'application/json'}});
      };
      window.__open = (kind, role, module = 'overview') => { window.__mode=kind; window.__role=role||(kind==='operations'?'technician':'client'); window.__device.actions=kind==='operations'?{inspect:true,repair:true,replace:true}:{};
        const supervisor=role==='supervisor';
        window.postMessage({type:'open',session:{kind,role:kind==='operations'?(role||'technician'):'client',profile:kind==='operations'?(supervisor?'Supervisor':'Tecnico'):'Cliente',
          abilities:kind==='operations'?(supervisor?['view','inspect','beginMaintenance']:['view','inspect','repair','replace','provision','install']):[],
          employeeId:kind==='operations'?'G6-E-TEST':null,module:module||undefined,canInstall:kind==='operations'&&!supervisor,expires:Math.floor(Date.now()/1000)+90,brand:window.__brand}},'*'); };
    ` });
    await send('Page.navigate', { url: pathToFileURL(path.join(root, 'web/index.html')).href });
    await until(`document.readyState==='complete' && document.getElementById('app')?.hidden===true && typeof window.__open==='function'`);
    console.log('PASS UI remains hidden before an authorized session message');
    // Pantalla de inicio: widgets, apps, dock, buscador, mapa y avisos en vivo.
    await evaluate(`window.__open('client', null, null)`);
    await until(`!document.getElementById('home').hidden && document.querySelectorAll('.widget-value').length>=4 && document.querySelector('.widget-value').textContent==='3'`);
    assert(await evaluate(`document.getElementById('window').hidden && document.querySelectorAll('#dock .dock-app').length===5 && Array.from(document.querySelectorAll('nav button')).some(b=>b.textContent==='Mapa')`));
    assert(await evaluate(`document.querySelectorAll('.attention-row').length===2 && document.querySelector('.attention-row').textContent.includes('Alarma sonando') && document.querySelector('img')===null && window.__xss!==true`));
    await evaluate(`document.getElementById('search-open').click(); const i=document.getElementById('search-input'); i.value='osd'; i.dispatchEvent(new Event('input'))`);
    await until(`document.querySelectorAll('.search-result').length===2`);
    assert(await evaluate(`window.__calls.some(x=>x.body.action==='search' && x.body.args.query==='osd')`));
    await evaluate(`document.querySelector('.search-result').click()`);
    await until(`document.getElementById('spotlight').hidden && !document.getElementById('window').hidden && window.__calls.some(x=>x.body.action==='device' && x.body.args.deviceId==='osd_0000000001')`);
    console.log('PASS home: widgets and attention from the server, search opens the device found');
    await evaluate(`document.getElementById('home-bar').click()`); await until(`!document.getElementById('home').hidden && document.getElementById('window').hidden`);
    await evaluate(`window.postMessage({type:'notice',text:'<b>Salta la alarma</b>',kind:'error',position:{x:1,y:2}},'*')`);
    await until(`document.querySelector('.toast.kind-error') && !document.getElementById('bell-count').hidden`);
    assert(await evaluate(`document.querySelector('.toast').textContent.includes('<b>Salta la alarma</b>') && !document.querySelector('.toast b')`));
    await evaluate(`document.getElementById('bell').click()`); await until(`!document.getElementById('notice-center').hidden && document.querySelectorAll('.nc-item').length===1 && document.getElementById('bell-count').hidden`);
    await evaluate(`window.__calls.length=0; document.querySelector('.nc-item button').click()`); await until(`window.__calls.some(x=>x.endpoint==='waypoint' && x.body.x===1 && x.body.y===2)`);
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}))`); await until(`document.getElementById('notice-center').hidden && !document.getElementById('app').hidden`);
    console.log('PASS live notices: toast, unread badge, notice center with GPS; Escape closes the overlay first');
    await evaluate(`window.postMessage({type:'status',clock:{h:7,m:5},position:{x:-500,y:300}},'*')`); await until(`document.getElementById('clock').textContent==='07:05'`);
    await evaluate(`window.__calls.length=0; Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent==='Mapa').click()`);
    await until(`window.__calls.some(x=>x.endpoint==='openMap' && x.body.kind==='client' && x.body.points.length===2 && x.body.points[1].kind==='call')`);
    console.log('PASS map: status bar clock; the Map app opens the game map with the summary points');
    await evaluate(`document.getElementById('home-button').click()`); await until(`!document.getElementById('home').hidden && document.getElementById('window').hidden`);
    console.log('PASS the Inicio button in an app returns to the home screen');
    await evaluate(`window.__calls.length=0; Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent==='Configuracion').click()`);
    await until(`document.querySelectorAll('.set-nav').length===5 && document.querySelector('.set-account').textContent.includes('Cliente')`);
    await evaluate(`Array.from(document.querySelectorAll('.set-nav')).find(b=>b.textContent==='Pantalla y brillo').click()`);
    await until(`document.querySelector('.segmented')`);
    await evaluate(`Array.from(document.querySelectorAll('.segmented button')).find(b=>b.textContent==='Oscuro').click()`);
    await until(`document.getElementById('app').classList.contains('dark') && document.getElementById('app').style.getPropertyValue('--background')==='#101a17' && window.__calls.some(x=>x.endpoint==='settings' && x.body.theme==='dark')`);
    await evaluate(`Array.from(document.querySelectorAll('.set-nav')).find(b=>b.textContent==='Fondo de pantalla').click()`); await until(`document.querySelectorAll('.wallpaper-option').length===6`);
    await evaluate(`document.querySelectorAll('.wallpaper-option')[2].click()`); await until(`document.querySelector('.screen.wp-3')`);
    await evaluate(`Array.from(document.querySelectorAll('.set-nav')).find(b=>b.textContent==='Notificaciones').click()`); await until(`document.querySelectorAll('.switch.on').length===2`);
    await evaluate(`document.querySelector('.switch').click()`); await until(`document.querySelectorAll('.switch.on').length===1 && window.__calls.some(x=>x.endpoint==='settings' && x.body.banners===false)`);
    await evaluate(`document.querySelectorAll('.toast').forEach(t=>t.remove()); window.postMessage({type:'notice',text:'Sin banner',kind:'info'},'*')`);
    await until(`!document.getElementById('bell-count').hidden`); assert(await evaluate(`document.querySelectorAll('.toast').length===0`));
    fs.writeFileSync(path.join(output, 'settings.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`Array.from(document.querySelectorAll('.set-nav')).find(b=>b.textContent==='General').click()`); await until(`document.querySelector('.set-row .danger')`);
    await evaluate(`document.querySelector('.set-row .danger').click()`); await until(`!document.getElementById('app').classList.contains('dark') && document.querySelector('.screen.wp-1')`);
    console.log('PASS settings: theme, wallpaper and notice banners are applied, saved per player and reset');
    await evaluate(`window.__open('client')`);
    await until(`document.querySelectorAll('.card').length===1`);
    assert(await evaluate(`document.getElementById('edition').textContent==='G6 Client' && !document.querySelector('.tablet.operations')`));
    assert(await evaluate(`!Array.from(document.querySelectorAll('nav button')).some(b=>b.disabled || b.textContent.includes('Contratos')) && Array.from(document.querySelectorAll('nav button')).some(b=>b.textContent.includes('Cerraduras'))`));
    assert(await evaluate(`document.getElementById('app').textContent.indexOf('Reparar')===-1 && document.querySelector('video')===null`));
    fs.writeFileSync(path.join(output, 'client.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    console.log('PASS Client identity, unimplemented modules hidden and absence of repair/video controls');
    for (const [nav, selector, expected] of [['Cerraduras', '.row', 'Propiedad 200'], ['Localizadores', '.tracker', 'OS000012'], ['Historial', '.incident', 'Salto de alarma']]) {
      await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent.includes(${JSON.stringify(nav)})).click()`);
      await until(`document.querySelector(${JSON.stringify(selector)}) && document.getElementById('content').textContent.includes(${JSON.stringify(expected)})`);
    }
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent.includes('Localizadores')).click()`);
    await until(`document.querySelector('.tracker button')`);
    await evaluate(`document.querySelector('.tracker button').click()`);
    await until(`window.__calls.some(x=>x.endpoint==='waypoint' && x.body.x===10.4)`);
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent.includes('Mis dispositivos')).click()`);
    await until(`document.querySelectorAll('.card').length===1`);
    console.log('PASS Client doors, vehicle trackers with GPS and alarm incident history');
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent.includes('Solicitudes')).click()`);
    await until(`document.querySelectorAll('.order-card').length===2 && document.querySelector('.order-form select')`);
    assert(await evaluate(`document.querySelectorAll('.order-card')[0].textContent.includes('1.250') && Array.from(document.querySelectorAll('.order-card')[0].querySelectorAll('button')).some(b=>b.textContent.includes('Pagar'))`));
    await evaluate(`window.__calls.length=0; document.querySelector('.order-form select').value='repair'; document.querySelectorAll('.order-form select')[1].value='site:property:200'; document.querySelector('.order-form textarea').value='Revisar alarma'; document.querySelector('.order-form button').click()`);
    await until(`window.__calls.some(x=>x.body.action==='request_create' && x.body.args.kind==='repair' && x.body.args.place==='site:property:200' && x.body.args.note==='Revisar alarma')`);
    await evaluate(`Array.from(document.querySelectorAll('.order-card')[0].querySelectorAll('button')).find(b=>b.textContent.includes('Pagar')).click()`);
    await until(`window.__calls.some(x=>x.body.action==='request_pay' && x.body.args.orderId==='ot_000002')`);
    fs.writeFileSync(path.join(output, 'requests.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent.includes('Mis dispositivos')).click()`);
    await until(`document.querySelectorAll('.card').length===1`);
    console.log('PASS Client maintenance requests: form, list with status and pay button');
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent.includes('Emergencias')).click()`);
    await until(`document.querySelector('.panic-button') && document.querySelectorAll('.call-card').length===2`);
    assert(await evaluate(`(() => { const cards=document.querySelectorAll('.call-card'); return cards[0].textContent.includes('En camino') && cards[0].textContent.includes('oscar_vega')
      && cards[1].textContent.includes('el gato') && cards[1].textContent.includes('x2') && !document.querySelector('.panic-button').disabled
      && cards[0].querySelector('button.danger') && !cards[1].querySelector('button'); })()`), 'Emergencies show call status, agent, outcome and cancel only for active panic calls');
    await evaluate(`window.__calls.length=0; document.querySelector('.panic-panel select').value='site:property:200'; document.querySelector('.panic-panel textarea').value='Hay alguien'; document.querySelector('.panic-button').click()`);
    await until(`window.__calls.some(x=>x.body.action==='panic' && x.body.args.place==='site:property:200' && x.body.args.note==='Hay alguien')`);
    await evaluate(`document.querySelector('.call-card button.danger').click()`);
    await until(`window.__calls.some(x=>x.body.action==='panic_cancel' && x.body.args.callId==='av_000002')`);
    fs.writeFileSync(path.join(output, 'emergencies.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent.includes('Mis dispositivos')).click()`);
    await until(`document.querySelectorAll('.card').length===1`);
    console.log('PASS Client emergencies: panic button with place and note, call status and false-alarm cancel');
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
    await evaluate(`window.__device.live=true; window.__calls.length=0; document.getElementById('refresh').click()`);
    await until(`Array.from(document.querySelectorAll('#content button')).some(b=>b.textContent===window.__brand.Text.live.watch)`);
    await evaluate(`Array.from(document.querySelectorAll('#content button')).find(b=>b.textContent===window.__brand.Text.live.watch).click()`);
    await until(`window.__calls.some(x=>x.body.action==='live' && x.body.args.deviceId==='osd_0000000001')`);
    await evaluate(`window.postMessage({type:'live',action:'show',text:window.__brand.Text.live,data:{displayId:'G6-D · osd_0000000001',site:'Propiedad 200',noise:0.45,index:2,total:3}},'*')`);
    await until(`!document.getElementById('live').hidden && document.querySelector('.live-name').textContent.includes('2/3') && document.querySelector('.live-warn') && document.querySelector('.live-static').style.opacity!=='0'`);
    fs.writeFileSync(path.join(output, 'live.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`window.postMessage({type:'live',action:'hide'},'*')`); await until(`document.getElementById('live').hidden`);
    await evaluate(`window.__device.live=false`);
    console.log('PASS live CCTV: watch button on cameras with signal, HUD with camera index, site and degraded-signal warning');
    assert(await evaluate(`Array.from(document.querySelectorAll('nav button')).some(b=>b.textContent==='Instalaciones') && document.querySelector('.profile.role-technician')`));
    await evaluate(`document.querySelector('#content button').click()`); await until(`document.querySelectorAll('.card').length===1`);
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent==='Instalaciones').click()`);
    await until(`document.querySelectorAll('.zone-card').length===3 && document.querySelectorAll('.zone-card .photo').length===3`);
    assert(await evaluate(`document.querySelector('.zone-card .photo-meta').textContent.includes('Pared') && document.querySelectorAll('.zone-new option').length===2`));
    assert(await evaluate(`document.querySelectorAll('.zone-card')[1].textContent.includes('osd_0000000001') && document.querySelectorAll('.zone-card')[0].querySelector('select').options.length===1`));
    assert(await evaluate(`(() => { const cards=document.querySelectorAll('.zone-card'); const far=cards[2].querySelector('.zone-actions button');
      return cards[0].classList.contains('near') && cards[0].querySelector('.badge.here') && !cards[2].classList.contains('near')
        && far.disabled && far.textContent.includes('66.5') && cards[2].querySelector('.zone-place').textContent==='zona_f2529d2'; })()`), 'Far zones cannot be installed from the tablet and say how far they are');
    fs.writeFileSync(path.join(output, 'zones.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`window.__calls.length=0; Array.from(document.querySelectorAll('.zone-card button')).find(b=>b.textContent===window.__brand.Text.zones.install).click()`);
    await until(`window.__calls.some(x=>x.body.action==='zone_install' && x.body.args.anchorId==='zona_2' && x.body.args.kit==='os_cctv_kit')`);
    await evaluate(`document.querySelector('.zone-new select').value='2'; Array.from(document.querySelectorAll('.zone-new button')).find(b=>b.textContent===window.__brand.Text.zones.mark).click()`);
    await until(`window.__calls.some(x=>x.body.action==='zone_begin' && x.body.args.client===2)`);
    await evaluate(`window.postMessage({type:'viewfinder',action:'show',info:{id:'zona_3',client:'segundo · amigo',site:'Propiedad 200'}},'*')`);
    await until(`!document.getElementById('viewfinder').hidden && document.getElementById('vf-title').textContent.includes('zona_3')`);
    await evaluate(`window.postMessage({type:'viewfinder',action:'update',state:{mode:'adjust',size:1.5,x:0.25,y:-0.1,hit:true,surface:'wall'}},'*')`);
    await until(`document.getElementById('vf-data').textContent.includes('1.50 x 1.50 m') && document.getElementById('viewfinder').classList.contains('locked')`);
    fs.writeFileSync(path.join(output, 'viewfinder.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`window.postMessage({type:'viewfinder',action:'shot'},'*')`);
    await until(`document.getElementById('viewfinder').hidden`);
    console.log('PASS Installations: zone photo cards, install from a card, viewfinder marking flow');
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent==='Ordenes de trabajo').click()`);
    await until(`document.querySelectorAll('.order-card').length===2`);
    assert(await evaluate(`document.querySelectorAll('.order-card')[1].querySelector('.badge.here') && document.querySelector('.order-amount')`));
    await evaluate(`window.__calls.length=0; document.querySelector('.order-amount').value='1500'; Array.from(document.querySelectorAll('.order-card')[1].querySelectorAll('button')).find(b=>b.textContent==='Facturar').click()`);
    await until(`window.__calls.some(x=>x.body.action==='order_bill' && x.body.args.price===1500 && x.body.args.orderId==='ot_000002')`);
    await evaluate(`Array.from(document.querySelectorAll('.order-card')[0].querySelectorAll('button')).find(b=>b.textContent==='Aceptar').click()`);
    await until(`window.__calls.some(x=>x.body.action==='order_accept' && x.body.args.orderId==='ot_000003')`);
    fs.writeFileSync(path.join(output, 'orders.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    console.log('PASS Work orders: accept open orders, bill own accepted orders');
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent==='Central de operaciones').click()`);
    await until(`document.querySelectorAll('.call-card').length===2`);
    assert(await evaluate(`(() => { const [panic, mine]=document.querySelectorAll('.call-card'); return panic.classList.contains('call-panic') && panic.textContent.includes('Me siguen')
      && Array.from(panic.querySelectorAll('button')).some(b=>b.textContent==='Me lo asigno') && !panic.querySelector('select')
      && mine.querySelector('.badge.here') && mine.textContent.includes('x3') && mine.querySelector('.call-note'); })()`), 'Technician sees calls by priority, can take open ones and close own ones');
    await evaluate(`window.__calls.length=0; Array.from(document.querySelectorAll('.call-card')[0].querySelectorAll('button')).find(b=>b.textContent==='Me lo asigno').click()`);
    await until(`window.__calls.some(x=>x.body.action==='call_take' && x.body.args.callId==='av_000003') && window.__calls.some(x=>x.endpoint==='waypoint' && x.body.x===7)`);
    await evaluate(`document.querySelector('.call-note').value='Cristal roto, sin intrusos'; Array.from(document.querySelectorAll('.call-card')[1].querySelectorAll('button')).find(b=>b.textContent==='Cerrar aviso').click()`);
    await until(`window.__calls.some(x=>x.body.action==='call_resolve' && x.body.args.callId==='av_000001' && x.body.args.note==='Cristal roto, sin intrusos')`);
    fs.writeFileSync(path.join(output, 'dispatch.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    console.log('PASS Central: take a call with GPS and close own calls with a note');
    await evaluate(`window.__open('operations','supervisor')`);
    await until(`document.querySelector('.profile.role-supervisor') && document.querySelectorAll('.ability').length===3`);
    assert(await evaluate(`!Array.from(document.querySelectorAll('nav button')).some(b=>b.textContent==='Instalaciones') && document.querySelector('.abilities').textContent.includes('Abrir mantenimiento')`));
    fs.writeFileSync(path.join(output, 'supervisor.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    console.log('PASS profile badge, profile functions and modules limited by the session profile');
    await evaluate(`Array.from(document.querySelectorAll('nav button')).find(b=>b.textContent==='Central de operaciones').click()`);
    await until(`document.querySelectorAll('.call-card select').length===2`);
    assert(await evaluate(`!Array.from(document.querySelectorAll('.call-card button')).some(b=>b.textContent==='Me lo asigno') && document.querySelector('.call-card select').options.length===2`), 'Supervisor assigns instead of taking');
    await evaluate(`window.__calls.length=0; document.querySelector('.call-card select').value='1'; Array.from(document.querySelectorAll('.call-card')[0].querySelectorAll('button')).find(b=>b.textContent==='Asignar').click()`);
    await until(`window.__calls.some(x=>x.body.action==='call_assign' && x.body.args.callId==='av_000003' && x.body.args.target===1)`);
    console.log('PASS Central (supervisor): assign a call to an on-duty colleague');
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
    // Minijuego del arco detector: mismos gestos con su dibujo, sus titulos y sus bornes.
    await evaluate(`window.__mgText = Object.assign({}, window.__brand.Text.minigame, window.__brand.Text.checkpoint.minigame);
      window.postMessage({ type: 'minigame', text: window.__mgText, mode: 'install', variant: 'detector' }, '*')`);
    await until(`!document.getElementById('minigame').hidden && document.querySelector('.mg-head h2').textContent === window.__mgText.drillTitle`);
    assert(await evaluate(`document.querySelector('.mg-overline').textContent.startsWith('Montaje del arco detector')
      && document.querySelectorAll('.mg-target').length === 4 && Array.from(document.querySelectorAll('.mg-target')).every(c => Number(c.getAttribute('cy')) > 200)`), 'Detector anchors are drilled on the floor base plates');
    await evaluate(`window.postMessage({ type: 'minigame', text: window.__mgText, mode: 'remove', variant: 'detector' }, '*')`);
    await until(`document.querySelector('.mg-head h2').textContent === window.__mgText.unplugTitle`);
    assert(await evaluate(`Array.from(document.querySelectorAll('.mg-terminal-label')).every(t => ['+12V','GND','SEN I','SEN D','ZUMB'].includes(t.textContent))
      && Array.from(document.querySelectorAll('.mg-terminal-label')).filter(t => ['SEN I','SEN D','ZUMB'].includes(t.textContent)).length >= 2`), 'Detector wiring uses its own terminal names');
    await evaluate(`window.postMessage({ type: 'minigameClose' }, '*')`); await until(`document.getElementById('minigame').hidden`);
    console.log('PASS detector minigame: own titles, floor anchors and control-unit terminals for mounting and unmounting');
    // Control de acceso: permiso de cacheo y panel por zonas.
    await evaluate(`window.__cpText = window.__brand.Text.checkpoint; window.__calls.length = 0;
      window.postMessage({ type: 'friskAsk', text: window.__cpText, data: { from: 'Agente <b>Ruiz</b>', company: 'gruppe6', seconds: 20 } }, '*')`);
    await until(`!document.getElementById('checkpoint').hidden && document.querySelector('.cp-ask')`);
    assert(await evaluate(`document.querySelector('.cp-ask-text').textContent.includes('<b>Ruiz</b>') && document.querySelector('#checkpoint b') === null`), 'Frisk request names render as text');
    await evaluate(`document.querySelector('.cp-ask .cp-yes').click()`);
    await until(`document.getElementById('checkpoint').hidden && window.__calls.some(x => x.endpoint === 'friskConsent' && x.body.accept === true)`);
    await evaluate(`window.postMessage({ type: 'friskOpen', text: window.__cpText, data: { target: 'Jugador5', order: ['chest','back','waist','leftArm','rightArm','leftLeg','rightLeg','ankles'],
      zones: { chest: [], back: [], leftArm: [], rightArm: [], leftLeg: [], ankles: [],
        waist: [{ kind: 'weapon', name: 'weapon_pistol', label: 'Pistola', count: 1, retainable: true, metal: true }, { kind: 'item', name: 'herramienta', label: 'Herramienta', count: 2, retainable: true, metal: true }],
        rightLeg: [{ kind: 'item', name: 'telefono', label: 'Telefono', count: 1, retainable: false, metal: true }] } } }, '*')`);
    await until(`document.querySelectorAll('.cp-zone').length === 8 && document.querySelector('.cp-frisk .cp-yes').disabled`);
    assert(await evaluate(`document.querySelector('.zone-waist .cp-found').children.length === 0`), 'Zones stay hidden until patted');
    await evaluate(`document.querySelector('.zone-waist').dispatchEvent(new MouseEvent('mouseenter'))`);
    await until(`document.querySelector('.zone-waist.done') && document.querySelectorAll('.zone-waist .cp-entry').length === 2`);
    await evaluate(`document.querySelector('.zone-rightLeg').dispatchEvent(new MouseEvent('mouseenter')); document.querySelector('.zone-chest').dispatchEvent(new MouseEvent('mouseenter'));
      setTimeout(() => document.querySelector('.zone-chest').dispatchEvent(new MouseEvent('mouseleave')), 100)`);
    await until(`document.querySelector('.zone-rightLeg.done')`);
    assert(await evaluate(`!document.querySelector('.zone-chest.done') && !document.querySelector('.zone-rightLeg input') && document.querySelector('.cp-status').textContent.includes('6')`), 'Leaving a zone early does not pat it; phones cannot be retained');
    await evaluate(`for (const zone of document.querySelectorAll('.cp-zone:not(.done)')) zone.dispatchEvent(new MouseEvent('mouseenter'))`);
    await until(`document.querySelectorAll('.cp-zone.done').length === 8 && !document.querySelector('.cp-frisk .cp-yes').disabled`);
    await evaluate(`for (const box of document.querySelectorAll('.zone-waist input')) box.click()`);
    fs.writeFileSync(path.join(output, 'frisk.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`document.querySelector('.cp-frisk .cp-yes').click()`);
    await until(`window.__calls.some(x => x.endpoint === 'friskFinish' && x.body.retain.items.herramienta === 2 && x.body.retain.weapons[0] === 'weapon_pistol')`);
    assert(await evaluate(`document.getElementById('checkpoint').hidden`));
    await evaluate(`window.postMessage({ type: 'friskOpen', text: window.__cpText, data: { target: 'X', order: ['chest'], zones: { chest: [] } } }, '*')`);
    await until(`document.querySelector('.cp-frisk')`);
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))`);
    await until(`document.getElementById('checkpoint').hidden && window.__calls.some(x => x.endpoint === 'friskCancel')`);
    console.log('PASS frisk: consent card, zones revealed by patting, retain only allowed finds, Escape cancels');
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
    // Tienda G6: catalogo por categorias, cantidades, total, saldo, pago y resultado.
    await evaluate(`window.__calls.length=0; window.postMessage({type:'shop',text:window.__brand.Text.shop,data:{location:'Gruppe Sechs · Union Depository',staff:false,maxQuantity:10,accounts:['bank','cash'],balance:{bank:3000,cash:50},
      products:[{item:'g6_client_tablet',name:'G6 Client',category:'tablet',price:1500,staff:false,allowed:true},{item:'os_lock_kit',name:'Gruppe Sechs · Bombin de seguridad',category:'kit',price:850,staff:false,allowed:true},
      {item:'os_cctv_kit',name:'Gruppe Sechs · Kit CCTV (exterior)',category:'kit',price:950,staff:true,allowed:false},{item:'os_screwdriver',name:'Gruppe Sechs · Destornillador',category:'tool',price:60,staff:false,allowed:true}]}},'*')`);
    await until(`!document.getElementById('shop').hidden && document.querySelectorAll('.shop-card').length===4 && document.querySelector('.shop-card.locked')`);
    const plus = name => evaluate(`Array.from(document.querySelectorAll('.shop-card')).find(c=>c.textContent.includes(${JSON.stringify(name)})).querySelectorAll('.shop-stepper button')[1].click()`);
    await plus('Bombin'); await plus('Bombin'); await plus('Destornillador');
    await until(`document.querySelector('.shop-total strong').textContent.includes('1760') || document.querySelector('.shop-total strong').textContent.includes('1.760')`);
    assert(await evaluate(`document.querySelector('.shop-card.locked .shop-stepper button:last-child').disabled && !document.querySelector('.shop-buy').disabled`));
    await evaluate(`Array.from(document.querySelectorAll('.shop-account')).find(b=>b.textContent.includes('Efectivo')).click()`);
    await until(`document.querySelector('.shop-warning') && document.querySelector('.shop-buy').disabled`);
    await evaluate(`Array.from(document.querySelectorAll('.shop-account')).find(b=>b.textContent.includes('Banco')).click()`);
    fs.writeFileSync(path.join(output, 'shop.png'), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
    await evaluate(`document.querySelector('.shop-buy').click()`);
    await until(`window.__calls.some(x=>x.endpoint==='shopBuy' && x.body.account==='bank' && x.body.cart.length===2 && x.body.cart.some(l=>l.item==='os_lock_kit' && l.amount===2))`);
    await evaluate(`window.postMessage({type:'shopResult',ok:true,data:{message:'Compra realizada: $1.760.',balance:{bank:1240,cash:50},partial:false}},'*')`);
    await until(`document.querySelector('.shop-message.ok') && document.querySelector('.shop-total strong').textContent==='$0' && document.querySelector('.shop-account').textContent.includes('1.240')`);
    await evaluate(`window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}))`);
    await until(`document.getElementById('shop').hidden && window.__calls.some(x=>x.endpoint==='shopClose')`);
    console.log('PASS shop: categories, staff-only items locked, quantities, balance check, payment request, result and Escape');
    console.log(`UI screenshots: ${path.relative(root, output)}`);
  } finally { socket?.close(); child.kill(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
