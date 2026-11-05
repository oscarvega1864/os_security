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
  function pagination() {
    const enabled = !state.selected && !['inventory', 'installations'].includes(state.module);
    byId('previous').disabled = !enabled || state.offset === 0;
    byId('next').disabled = !enabled || state.offset + state.limit >= state.total;
    byId('page-label').textContent = enabled ? `${text('page')} ${Math.floor(state.offset / state.limit) + 1}` : '';
  }
  function hero(content, count, title) {
    const node = el('section', null, 'hero'); node.append(el('span', state.session.brand.Tagline, 'overline'), el('h2', title));
    node.append(el('p', state.session.kind === 'inventory' ? text('inventoryHero') : text('inspectionNote')));
    if (count != null) { const metric = el('div', count, 'metric'); metric.append(el('small', text('assigned'))); node.append(metric); }
    content.append(node);
  }
  async function showDevice(id) {
    const device = await request('device', { deviceId: id }); if (!device) return;
    state.selected = id;
    const content = byId('content'); content.replaceChildren(button(text('back'), () => { state.selected = null; refresh(); }));
    content.append(el('h2', device.displayId, 'detail-title'), el('div', device.type, 'subtle'));
    const meta = el('div', null, 'detail-meta');
    for (const [title, value] of [[text('state'), labelState(device.state)], [text('model'), device.model], [text('health'), health(device.health)], [text('history'), device.lastIntervention ? `${device.lastIntervention.kind} · ${date(device.lastIntervention.at)}` : text('noHistory')]]) {
      const item = el('div', title, 'subtle'); item.append(el('strong', value)); meta.append(item);
    }
    content.append(meta);
    if (device.type === 'cctv_camera') content.append(el('div', text('noSignal'), 'notice'));
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
      content.append(button(text('installationAction'), () => request('use', { item: 'os_cctv_kit' }), !data.items.some(item => item.id === 'os_cctv_kit' && item.count > 0)));
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
  async function refresh() {
    if (!state.session || state.busy) return;
    if (state.selected) { await showDevice(state.selected); return; }
    const content = byId('content'); content.replaceChildren();
    const module = (state.session.brand.Modules[state.session.kind] || []).find(item => item.id === state.module);
    byId('heading').textContent = module?.name || text('inventory');
    if (state.session.kind === 'inventory' || ['inventory', 'installations'].includes(state.module)) {
      await inventory(content); pagination(); return;
    }
    const data = await request('devices', { offset: state.offset, module: state.module }); if (!data) return;
    state.total = data.total; state.limit = data.limit;
    hero(content, data.total, text(state.session.kind === 'operations' ? 'operationsHero' : 'clientHero'));
    if (state.module === 'cctv') content.append(el('div', text('noSignal'), 'notice'));
    const grid = el('div', null, 'grid');
    for (const device of data.items) {
      const card = el('article', null, 'card'); const head = el('div', null, 'card-head');
      head.append(el('span', null, 'device-symbol'), el('span', labelState(device.state), 'badge'));
      card.append(head, el('h3', device.displayId), el('div', `${device.type} · ${device.model}`, 'subtle'), el('div', text(device.physical ? 'installed' : 'logical'), 'subtle'));
      const bar = el('div', null, 'health-line'); const fill = el('span'); fill.style.width = `${Number.isFinite(device.health) ? Math.min(100, Math.max(0, device.health)) : 0}%`; bar.append(fill); card.append(bar);
      const footer = el('div', null, 'card-footer'); footer.append(el('span', `${text('health')} ${health(device.health)}`, 'subtle'), button(text('details'), () => showDevice(device.id))); card.append(footer); grid.append(card);
    }
    content.append(data.items.length ? grid : el('div', text('empty'), 'empty')); pagination();
  }
  function open(session) {
    if (!session?.brand || !['client', 'operations', 'inventory'].includes(session.kind)) return;
    state.epoch++; state.busy = false; state.session = session; state.offset = 0; state.selected = null; state.module = session.kind === 'inventory' ? 'inventory' : 'overview';
    const brand = session.brand; const theme = brand.Themes[session.kind === 'operations' ? 'operations' : 'client'];
    document.title = `${brand.Name} · ${brand.Tablets[session.kind]?.name || text('inventory')}`;
    for (const [key, value] of Object.entries(theme)) if (/^#[0-9a-f]{6}$/i.test(value)) app.style.setProperty(`--${key}`, value);
    app.className = `tablet ${session.kind}`; app.hidden = false;
    byId('monogram').textContent = brand.Monogram; byId('brand').textContent = brand.Name;
    byId('edition').textContent = brand.Tablets[session.kind]?.name || text('inventory');
    byId('overline').textContent = brand.Tablets[session.kind]?.name || brand.Name;
    byId('profile').textContent = session.employeeId ? `${session.profile} · ${session.employeeId}` : session.profile;
    for (const id of ['refresh', 'close', 'previous', 'next']) byId(id).textContent = text(id);
    byId('session-label').textContent = text('session'); byId('footer-label').textContent = brand.Name;
    byId('expiry').textContent = date(session.expires);
    const navigation = byId('navigation'); navigation.replaceChildren();
    const modules = session.kind === 'inventory' ? [{ id: 'inventory', name: text('inventory'), implemented: true }] : brand.Modules[session.kind];
    for (const module of modules) {
      const nav = button(module.name, () => { state.module = module.id; state.offset = 0; state.selected = null; for (const child of navigation.children) child.classList.remove('selected'); nav.classList.add('selected'); refresh(); }, !module.implemented);
      if (module.id === state.module) nav.classList.add('selected');
      if (!module.implemented) { nav.title = text('unavailable'); nav.append(el('small', '—')); }
      navigation.append(nav);
    }
    refresh();
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
  });
  window.addEventListener('error', () => { if (!app.hidden) close(); });
})();
