(() => {
  'use strict';
  const state = { session: null, module: 'overview', offset: 0, total: 0, limit: 12, selected: null, epoch: 0, busy: false };
  const byId = id => document.getElementById(id);
  const app = byId('app');
  const text = key => state.session?.brand?.Text?.[key] || key;
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  const labelState = value => state.session?.brand?.Text?.states?.[value] || value;
  const date = value => Number.isFinite(value) ? new Date(value * 1000).toLocaleString('es-ES') : '—';
  const health = value => Number.isFinite(value) ? `${value.toFixed(1)}%` : '—';
  const resource = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'os_security';

  async function post(endpoint, body) {
    const abort = new AbortController(); const timeout = setTimeout(() => abort.abort(), 10000);
    try {
      const response = await fetch(`https://${resource()}/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body), signal: abort.signal });
      if (!response.ok) throw new Error('NUI callback rejected');
      return await response.json();
    } finally { clearTimeout(timeout); }
  }
  function message(value) { byId('message').textContent = value || ''; byId('message').hidden = !value; }
  async function request(action, args = {}) {
    if (state.busy) return null;
    const epoch = state.epoch; state.busy = true; app.setAttribute('aria-busy', 'true'); message('');
    try {
      const response = await post('request', { action, args });
      if (epoch !== state.epoch) return null;
      if (!response.ok) { message(response.error || text('failed')); if (response.close) close(); return null; }
      return response.data || response;
    } catch {
      if (epoch === state.epoch) { message(text('failed')); close(); }
      return null;
    } finally { if (epoch === state.epoch) { state.busy = false; app.setAttribute('aria-busy', 'false'); } }
  }
  function button(title, action, disabled = false, className) {
    const node = el('button', title, className); node.type = 'button'; node.disabled = disabled;
    node.addEventListener('click', () => { if (!state.busy && !node.disabled) action(); }); return node;
  }
  function close() {
    state.epoch++; state.busy = false; app.hidden = true;
    post('close', {}).catch(() => {}); state.session = null;
  }
  // Secciones con vista propia (no son listas paginadas de dispositivos).
  const OWN_VIEWS = ['inventory', 'installations', 'locks', 'trackers', 'incidents'];
  function pagination() {
    const enabled = !state.selected && !OWN_VIEWS.includes(state.module);
    byId('previous').disabled = !enabled || state.offset === 0;
    byId('next').disabled = !enabled || state.offset + state.limit >= state.total;
    byId('page-label').textContent = enabled ? `${text('page')} ${Math.floor(state.offset / state.limit) + 1}` : '';
  }
  function hero(content, count, title) {
    const node = el('section', null, 'hero'); node.append(el('span', state.session.brand.Tagline, 'overline'), el('h2', title));
    node.append(el('p', state.session.kind === 'inventory' ? text('inventoryHero') : text('inspectionNote')));
    if (count != null) { const metric = el('div', count, 'metric'); metric.append(el('small', text('assigned'))); node.append(metric); }
    content.append(node);
    const abilities = Array.isArray(state.session.abilities) ? state.session.abilities : [];
    if (state.session.kind === 'operations' && abilities.length) {
      const strip = el('div', null, 'abilities'); strip.append(el('span', `${state.session.profile} · ${text('profileAbilities')}`, 'overline'));
      const list = el('div', null, 'ability-list');
      for (const ability of abilities) list.append(el('span', state.session.brand.Text?.abilities?.[ability] || ability, 'ability'));
      strip.append(list); content.append(strip);
    }
  }
  // Alarma: estado, armar/desarmar sin codigo (como la app del fabricante), codigo, chapas e historial.
  function alarmBlock(id, alarm) {
    const A = state.session.brand.Text.alarm || {};
    const block = el('section', null, `alarm-block mode-${alarm.mode}${alarm.triggered ? ' triggered' : ''}`);
    const head = el('div', null, 'alarm-head');
    head.append(el('span', A.title || 'Alarma', 'overline'), el('strong', alarm.triggered ? (A.triggered || 'SALTO DE ALARMA') : (A.modes?.[alarm.mode] || alarm.mode), 'alarm-mode'));
    block.append(head);
    const send = async (action, extra = {}) => {
      const result = await request('alarm', { deviceId: id, action, ...extra });
      if (result) { await showDevice(id); if (result.notice) message(result.notice); }
    };
    const modes = el('div', null, 'actions');
    modes.append(button(A.arm || 'Armar total', () => send('arm'), alarm.mode === 'armed'), button(A.partial || 'Armar parcial', () => send('partial'), alarm.mode === 'partial'),
      button(A.disarm || 'Desarmar', () => send('disarm'), alarm.mode === 'disarmed' && !alarm.triggered));
    block.append(modes);
    const pinRow = el('div', null, 'alarm-row');
    const pin = el('input'); pin.type = 'password'; pin.inputMode = 'numeric'; pin.maxLength = 6; pin.placeholder = alarm.hasPin ? (A.newPin || 'Nuevo codigo') : (A.createPin || 'Crear codigo (4-6 cifras)');
    pinRow.append(pin, button(A.savePin || 'Guardar codigo', () => { if (/^\d{4,6}$/.test(pin.value)) send('pin', { pin: pin.value }); else message(A.pinFormat || 'El codigo debe tener entre 4 y 6 cifras.'); }));
    block.append(pinRow);
    const tags = el('div', null, 'alarm-row');
    tags.append(el('span', `${A.tags || 'Chapas'}: ${alarm.tags}`, 'subtle'), button(A.programTag || 'Programar chapa', () => send('tag')), button(A.revokeTags || 'Revocar chapas', () => send('revoke'), alarm.tags === 0));
    block.append(tags);
    if (Array.isArray(alarm.events) && alarm.events.length) {
      const list = el('div', null, 'alarm-events');
      for (const event of alarm.events) list.append(el('div', `${date(event.at)} · ${A.events?.[event.kind] || event.kind}${event.by ? ' · ' + event.by : ''}`, 'subtle'));
      block.append(list);
    }
    return block;
  }
  async function showDevice(id) {
    const device = await request('device', { deviceId: id }); if (!device) return;
    state.selected = id;
    const content = byId('content'); content.replaceChildren(button(text('back'), () => { state.selected = null; refresh(); }));
    content.append(el('h2', device.displayId, 'detail-title'), el('div', device.type, 'subtle'));
    if (typeof device.site === 'string') content.append(el('div', device.site, 'site'));
    const meta = el('div', null, 'detail-meta');
    for (const [title, value] of [[text('state'), labelState(device.state)], [text('model'), device.model], [text('health'), health(device.health)], [text('history'), device.lastIntervention ? `${device.lastIntervention.kind} · ${date(device.lastIntervention.at)}` : text('noHistory')]]) {
      const item = el('div', title, 'subtle'); item.append(el('strong', value)); meta.append(item);
    }
    content.append(meta);
    if (device.type === 'cctv_camera') {
      if (device.live) { const row = el('div', null, 'actions'); row.append(button(state.session.brand.Text.live?.watch || 'Ver en directo', () => request('live', { deviceId: id }), false, 'primary')); content.append(row); }
      else content.append(el('div', device.liveReason || text('noSignal'), 'notice'));
    }
    if (device.alarm) content.append(alarmBlock(id, device.alarm));
    if (device.removable) {
      const remove = el('div', null, 'actions');
      remove.append(button(text('remove'), () => request('remove', { deviceId: id }), false, 'danger'), el('span', text('removeHelp'), 'subtle'));
      content.append(remove);
    }
    const actions = el('div', null, 'actions');
    const act = async (action, slot) => { const result = await request('maintain', { deviceId: id, action, ...(slot ? { slot } : {}) }); if (result) await showDevice(id); };
    if (device.actions?.inspect && device.schemaVersion === 2) actions.append(button(text('inspect'), () => act('inspect')));
    if (device.actions?.provision && device.schemaVersion === 1) actions.append(button(text('provision'), () => act('provision'), !['registered', 'installed', 'maintenance'].includes(device.state)));
    if (device.actions?.beginMaintenance) actions.append(button(text('beginMaintenance'), () => act('beginMaintenance'), !['installed', 'active', 'fault'].includes(device.state)));
    content.append(actions);
    for (const component of device.components || []) {
      const row = el('section', null, 'component'); const identity = el('div');
      identity.append(el('h3', component.slot), el('div', `${component.model} · ${component.id}`, 'subtle'), el('div', `${text('hours')}: ${component.operatingHours.toFixed(2)} · ${text('maintenance')}: ${date(component.lastMaintenanceAt)}`, 'subtle'));
      const values = el('div', health(component.health), 'component-value'); values.append(el('div', labelState(component.state), 'subtle'));
      const buttons = el('div', null, 'actions');
      if (device.actions?.repair) buttons.append(button(text('repair'), () => act('repair', component.slot), device.state !== 'maintenance'));
      if (device.actions?.replace) buttons.append(button(text('replace'), () => act('replace', component.slot), device.state !== 'maintenance'));
      identity.append(buttons); row.append(identity, values); content.append(row);
    }
    pagination();
  }
  async function inventory(content) {
    const data = await request('inventory'); if (!data) return;
    hero(content, null, text('inventoryHero'));
    if (state.module === 'installations' && state.session.canInstall) {
      for (const [kit, label] of [['os_cctv_kit', 'installationAction'], ['os_cctv_kit_mini', 'miniInstallAction'], ['os_cctv_kit_dome', 'domeInstallAction'],
        ['os_alarm_kit', 'alarmInstallAction'], ['os_alarm_kit_panel', 'alarmPanelInstallAction']]) {
        content.append(button(text(label), () => request('use', { item: kit }), !data.items.some(item => item.id === kit && item.count > 0)));
      }
      content.append(el('p', text('placementHelp'), 'subtle'));
    }
    const grid = el('div', null, 'grid');
    for (const item of data.items) {
      const card = el('article', null, 'card'); card.append(el('div', item.category, 'overline'), el('h3', item.name));
      const footer = el('div', null, 'card-footer'); footer.append(el('span', item.count, 'inventory-count'));
      if (item.usable) footer.append(button(text('use'), () => request('use', { item: item.id })));
      card.append(footer); grid.append(card);
    }
    content.append(data.items.length ? grid : el('div', text('noInventory'), 'empty'));
  }
  const group = key => state.session.brand.Text[key] || {};
  const format = (template, ...values) => values.reduce((result, value) => result.replace(/%[sd]/, value), String(template || ''));
  function simpleHero(content, title, help) {
    const node = el('section', null, 'hero'); node.append(el('span', state.session.brand.Tagline, 'overline'), el('h2', title), el('p', help));
    content.append(node);
  }
  // Client: puertas con bombin G6 de sus propiedades.
  async function doorsView(content) {
    const T = group('doors'); const data = await request('doors'); if (!data) return;
    simpleHero(content, T.title, T.help);
    if (!data.items.length) { content.append(el('div', T.empty, 'empty')); return; }
    const list = el('div', null, 'rows');
    for (const door of data.items) {
      const row = el('article', null, `row ${door.locked ? 'is-locked' : 'is-open'}`);
      const identity = el('div'); identity.append(el('strong', door.site), el('div', `${door.id} · ${door.tier}`, 'subtle'));
      row.append(el('span', null, 'row-icon lock-icon'), identity, el('span', door.locked ? T.locked : T.open, 'badge'));
      list.append(row);
    }
    content.append(list);
  }
  // Client: vehiculos con equipo G6, estado y GPS.
  async function trackersView(content) {
    const T = group('trackers'); const data = await request('trackers'); if (!data) return;
    simpleHero(content, T.title, T.help);
    if (!data.items.length) { content.append(el('div', T.empty, 'empty')); return; }
    const grid = el('div', null, 'grid');
    for (const car of data.items) {
      const card = el('article', null, `card tracker${car.sounding ? ' sounding' : ''}`);
      const head = el('div', null, 'card-head'); head.append(el('span', null, 'row-icon car-icon'), el('span', car.sounding ? T.sounding : (car.locked ? T.locked : T.open), 'badge'));
      const kit = [car.lock ? T.lock : null, car.alarm ? T.alarm : null].filter(Boolean).join(' · ');
      card.append(head, el('h3', car.plate), el('div', kit, 'subtle'));
      const footer = el('div', null, 'card-footer');
      if (car.position) {
        footer.append(el('span', `${Math.round(car.position.x)}, ${Math.round(car.position.y)}`, 'subtle'),
          button(T.gps, () => post('waypoint', { x: car.position.x, y: car.position.y }).catch(() => {})));
      } else footer.append(el('span', T.away, 'subtle'));
      card.append(footer); grid.append(card);
    }
    content.append(grid);
  }
  // Client: ultimos sucesos de todas sus alarmas.
  async function incidentsView(content) {
    const T = group('incidents'); const A = group('alarm'); const data = await request('incidents'); if (!data) return;
    simpleHero(content, T.title, T.help);
    if (!data.items.length) { content.append(el('div', T.empty, 'empty')); return; }
    const list = el('div', null, 'rows');
    for (const event of data.items) {
      const row = el('article', null, `row incident kind-${/^[a-z_]+$/.test(event.kind) ? event.kind : 'other'}`);
      const identity = el('div'); identity.append(el('strong', A.events?.[event.kind] || event.kind),
        el('div', [event.site, event.device, event.by].filter(Boolean).join(' · '), 'subtle'));
      row.append(el('span', null, 'row-icon bell-icon'), identity, el('span', date(event.at), 'subtle'));
      list.append(row);
    }
    content.append(list);
  }
  // "Foto" de la zona: encuadre con el cuadrado a escala, superficie, tamano, lugar y fecha.
  function zonePhoto(zone) {
    const T = group('zones'); const V = group('viewfinder');
    const photo = el('div', null, `photo surface-${zone.surface} status-${zone.status}`);
    const frame = el('span', null, 'photo-zone'); const scale = Math.max(18, Math.min(78, zone.size / 4 * 100));
    frame.style.width = `${scale}%`; frame.style.height = zone.surface === 'wall' ? `${scale * 1.6}%` : `${scale}%`;
    photo.append(el('span', null, 'photo-plane'), frame, el('span', null, 'photo-cross'));
    for (const corner of ['tl', 'tr', 'bl', 'br']) photo.append(el('span', null, `photo-corner ${corner}`));
    photo.append(el('span', `● ${V.rec || 'REC'}  ${date(zone.createdAt)}`, 'photo-rec'),
      el('span', `${T.surfaces?.[zone.surface] || zone.surface} · ${format(T.size, zone.size.toFixed(2), zone.size.toFixed(2))}`, 'photo-meta'),
      el('span', zone.id, 'photo-id'));
    return photo;
  }
  // Operations > Instalaciones: nueva zona (cliente + visor) y fichas de zona con su instalacion.
  async function zonesView(content) {
    const T = group('zones'); const data = await request('zones'); if (!data) return;
    simpleHero(content, T.hero, format(T.heroHelp, Math.floor(data.installDistance || 4)));
    const panel = el('section', null, 'zone-new');
    panel.append(el('span', T.newZone, 'overline'));
    const row = el('div', null, 'alarm-row');
    const select = el('select'); select.setAttribute('aria-label', T.client);
    for (const client of data.clients) { const option = el('option', client.self ? `${T.self} · ${client.name}` : `${client.name} (ID ${client.id})`); option.value = String(client.id); select.append(option); }
    row.append(el('span', T.client, 'subtle'), select,
      button(T.mark, () => request('zone_begin', { client: Number(select.value) }), !data.clients.length, 'primary'));
    panel.append(row, el('p', data.clients.length ? T.markHelp : T.noClients, 'subtle'));
    content.append(panel);
    if (!data.zones.length) content.append(el('div', T.empty, 'empty'));
    const grid = el('div', null, 'grid');
    for (const zone of data.zones) {
      // A tu alcance: se puede instalar ya. Las lejanas no ofrecen Instalar (solo dicen a cuanto estan).
      const near = zone.distance != null && zone.distance <= (data.installDistance || 4);
      const card = el('article', null, `card zone-card${near ? ' near' : ''}`);
      const head = el('div', null, 'card-head');
      const badges = el('div', null, 'zone-badges');
      if (near) badges.append(el('span', T.here, 'badge here'));
      badges.append(el('span', T.states?.[zone.status] || zone.status, `badge state-${zone.status}`));
      head.append(el('strong', zone.place || zone.id, 'zone-place'), badges);
      card.append(zonePhoto(zone), head);
      const facts = [zone.client ? `${T.client}: ${zone.client}` : null, zone.distance != null ? format(T.distance, zone.distance) : null].filter(Boolean).join(' · ');
      card.append(el('div', facts, 'subtle'));
      if (zone.site) card.append(el('div', zone.site, 'site'));
      const actions = el('div', null, 'zone-actions');
      if (zone.status === 'installed' && zone.deviceId) {
        actions.append(el('span', `${T.device}: ${zone.deviceId}`, 'subtle'), button(T.viewDevice, () => showDevice(zone.deviceId)));
      } else if (zone.status === 'free' && zone.mine) {
        const kits = data.kits.filter(kit => kit.count > 0);
        const choice = el('select'); choice.setAttribute('aria-label', T.kit);
        for (const kit of kits) { const option = el('option', `${kit.name} (${kit.count})`); option.value = kit.id; choice.append(option); }
        if (!kits.length) { const option = el('option', T.noKits); option.value = ''; choice.append(option); choice.disabled = true; }
        actions.append(choice, button(near ? T.install : format(T.goCloser, zone.distance != null ? zone.distance : '?'),
          () => request('zone_install', { anchorId: zone.id, kit: choice.value }), !kits.length || !near, near ? 'primary' : ''));
      } else if (!zone.mine) actions.append(el('span', T.notMine, 'subtle'));
      if (zone.deletable) actions.append(button(T.delete, async () => { if (await request('zone_delete', { anchorId: zone.id })) refresh(); }, false, 'danger'));
      card.append(actions); grid.append(card);
    }
    content.append(grid);
    const stock = data.kits.filter(kit => kit.count > 0);
    if (stock.length) {
      const strip = el('div', null, 'abilities'); strip.append(el('span', T.materials, 'overline'));
      const list = el('div', null, 'ability-list');
      for (const kit of stock) list.append(el('span', `${kit.name} · ${kit.count}`, 'ability'));
      strip.append(list); content.append(strip);
    }
  }
  const VIEWS = { locks: doorsView, trackers: trackersView, incidents: incidentsView, installations: zonesView };
  async function refresh() {
    if (!state.session || state.busy) return;
    if (state.selected) { await showDevice(state.selected); return; }
    const content = byId('content'); content.replaceChildren();
    const module = (state.session.brand.Modules[state.session.kind] || []).find(item => item.id === state.module);
    byId('heading').textContent = module?.name || text('inventory');
    if (state.session.kind === 'inventory' || state.module === 'inventory') {
      await inventory(content); pagination(); return;
    }
    if (VIEWS[state.module]) { await VIEWS[state.module](content); pagination(); return; }
    const data = await request('devices', { offset: state.offset, module: state.module }); if (!data) return;
    state.total = data.total; state.limit = data.limit;
    hero(content, data.total, text(state.session.kind === 'operations' ? 'operationsHero' : 'clientHero'));

    const grid = el('div', null, 'grid');
    for (const device of data.items) {
      const card = el('article', null, 'card'); const head = el('div', null, 'card-head');
      head.append(el('span', null, 'device-symbol'), el('span', labelState(device.state), 'badge'));
      card.append(head, el('h3', device.displayId), el('div', `${device.type} · ${device.model}`, 'subtle'), el('div', text(device.physical ? 'installed' : 'logical'), 'subtle'));
      if (typeof device.site === 'string') card.append(el('div', device.site, 'site'));
      const bar = el('div', null, 'health-line'); const fill = el('span'); fill.style.width = `${Number.isFinite(device.health) ? Math.min(100, Math.max(0, device.health)) : 0}%`; bar.append(fill); card.append(bar);
      const footer = el('div', null, 'card-footer'); footer.append(el('span', `${text('health')} ${health(device.health)}`, 'subtle'));
      const buttons = el('div', null, 'card-buttons');
      if (device.live) buttons.append(button(state.session.brand.Text.live?.watch || 'Ver en directo', () => request('live', { deviceId: device.id }), false, 'primary'));
      buttons.append(button(text('details'), () => showDevice(device.id)));
      footer.append(buttons); card.append(footer); grid.append(card);
    }
    content.append(data.items.length ? grid : el('div', text('empty'), 'empty')); pagination();
  }
  function open(session) {
    if (!session?.brand || !['client', 'operations', 'inventory'].includes(session.kind)) return;
    state.epoch++; state.busy = false; state.session = session; state.offset = 0; state.selected = null; state.module = session.kind === 'inventory' ? 'inventory' : 'overview';
    viewfinder({ action: 'hide' });
    const brand = session.brand; const theme = brand.Themes[session.kind === 'operations' ? 'operations' : 'client'];
    document.title = `${brand.Name} · ${brand.Tablets[session.kind]?.name || text('inventory')}`;
    for (const [key, value] of Object.entries(theme)) if (/^#[0-9a-f]{6}$/i.test(value)) app.style.setProperty(`--${key}`, value);
    app.className = `tablet ${session.kind}`; app.hidden = false;
    byId('monogram').textContent = brand.Monogram; byId('brand').textContent = brand.Name;
    byId('edition').textContent = brand.Tablets[session.kind]?.name || text('inventory');
    byId('overline').textContent = brand.Tablets[session.kind]?.name || brand.Name;
    const profile = byId('profile'); profile.replaceChildren(el('strong', session.profile, 'role-name'));
    if (session.employeeId) profile.append(el('span', ` · ${session.employeeId}`));
    profile.className = `profile role-${/^[a-z]+$/.test(session.role || '') ? session.role : 'none'}`;
    for (const id of ['refresh', 'close', 'previous', 'next']) byId(id).textContent = text(id);
    byId('session-label').textContent = text('session'); byId('footer-label').textContent = brand.Name;
    byId('expiry').textContent = date(session.expires);
    const navigation = byId('navigation'); navigation.replaceChildren();
    const abilities = new Set(Array.isArray(session.abilities) ? session.abilities : []);
    const modules = session.kind === 'inventory' ? [{ id: 'inventory', name: text('inventory'), implemented: true }]
      : (brand.Modules[session.kind] || []).filter(module => module.implemented && (!module.requires || abilities.has(module.requires)));
    if (typeof session.module === 'string' && modules.some(module => module.id === session.module)) state.module = session.module;
    for (const module of modules) {
      const nav = button(module.name, () => { state.module = module.id; state.offset = 0; state.selected = null; for (const child of navigation.children) child.classList.remove('selected'); nav.classList.add('selected'); refresh(); });
      if (module.id === state.module) nav.classList.add('selected');
      navigation.append(nav);
    }
    refresh();
  }
  // Visor de camara para marcar zonas: encuadre, REC, datos de la zona y destello al hacer la foto.
  let viewfinderTimer = null;
  function viewfinder(message) {
    const node = byId('viewfinder'); if (!node) return;
    const V = state.session?.brand?.Text?.viewfinder || window.__viewfinderText || {};
    const Z = state.session?.brand?.Text?.zones || window.__zonesText || {};
    if (message.action === 'show') {
      clearTimeout(viewfinderTimer); node.className = 'viewfinder'; node.hidden = false;
      const info = message.info || {};
      byId('vf-title').textContent = `${V.zone || 'Zona'} ${info.id || ''}`;
      byId('vf-client').textContent = [info.client ? `${V.client || 'Cliente'}: ${info.client}` : null, info.site].filter(Boolean).join(' · ');
      byId('vf-help').textContent = V.aim || ''; byId('vf-data').textContent = '';
      byId('vf-rec').textContent = `● ${V.rec || 'REC'}`;
    } else if (message.action === 'update' && !node.hidden) {
      const s = message.state || {};
      byId('vf-help').textContent = s.mode === 'adjust' ? (V.adjust || '') : (V.aim || '');
      const surface = s.surface ? (Z.surfaces?.[s.surface] || s.surface) : (V.noSurface || '');
      const size = Number.isFinite(s.size) ? `${s.size.toFixed(2)} x ${s.size.toFixed(2)} m` : '';
      const offset = s.mode === 'adjust' && Number.isFinite(s.x) ? ` · X ${s.x >= 0 ? '+' : ''}${s.x.toFixed(2)} · Y ${s.y >= 0 ? '+' : ''}${s.y.toFixed(2)}` : '';
      byId('vf-data').textContent = `${surface} · ${size}${offset}`;
      node.classList.toggle('locked', s.mode === 'adjust'); node.classList.toggle('nosurface', !s.hit && s.mode !== 'adjust');
    } else if (message.action === 'shot') {
      node.classList.add('shot'); byId('vf-help').textContent = V.shot || '';
      clearTimeout(viewfinderTimer); viewfinderTimer = setTimeout(() => { node.hidden = true; node.className = 'viewfinder'; }, 700);
    } else if (message.action === 'hide') { clearTimeout(viewfinderTimer); node.hidden = true; node.className = 'viewfinder'; }
  }
  byId('close').addEventListener('click', close); byId('refresh').addEventListener('click', refresh);
  byId('previous').addEventListener('click', () => { if (!state.busy && state.offset) { state.offset = Math.max(0, state.offset - state.limit); refresh(); } });
  byId('next').addEventListener('click', () => { if (!state.busy && state.offset + state.limit < state.total) { state.offset += state.limit; refresh(); } });
  window.addEventListener('keydown', event => { if (event.key === 'Escape' && !app.hidden) close(); });
  window.addEventListener('message', event => {
    if (event.data?.type === 'open') open(event.data.session);
    else if (event.data?.type === 'close') { state.epoch++; state.busy = false; state.session = null; app.hidden = true; }
    else if (event.data?.type === 'expiry') byId('expiry').textContent = date(event.data.expires);
    else if (event.data?.type === 'ping') post('alive', { visible: !app.hidden }).catch(() => {});
    else if (event.data?.type === 'viewfinder') viewfinder(event.data);
  });
  window.addEventListener('error', () => { if (!app.hidden) close(); });
})();
