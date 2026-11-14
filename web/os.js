// Sistema de la tablet (G6 OS): pantalla de inicio con widgets, iconos de apps, dock, barra de estado,
// buscador, mapa tactico y centro de avisos. app.js lo crea con sus utilidades (peticiones, textos, estado).
window.G6OS = function createOS(api) {
  'use strict';
  const { state, byId, el, button, request, post, text } = api;
  const svgNS = 'http://www.w3.org/2000/svg';
  const H = () => state.session?.brand?.Text?.home || {};
  const W = () => H().widgets || {};
  const os = { notices: [], unread: 0, here: null, data: null, clock: null };

  // Iconos de linea propios (24x24). Sin texto dentro: el nombre de la app va aparte.
  const ICONS = {
    overview: 'M4 5h16v11H4zM9 20h6M12 16v4', cctv: 'M3 8l11-4 2 5-11 4zM9 12l1 4h4M16 7l4-1M20 4v6',
    alarms: 'M6 16V11a6 6 0 0112 0v5l2 2H4zM10 20a2 2 0 004 0', locks: 'M7 11V8a5 5 0 0110 0v3M5 11h14v10H5zM12 15v2',
    trackers: 'M5 16l2-6h10l2 6zM4 16h16v3H4zM7 19v1M17 19v1M12 3v4', emergencies: 'M12 3l9 16H3zM12 10v4M12 17v.5',
    requests: 'M6 3h9l3 3v15H6zM9 10h6M9 14h6M9 18h4', incidents: 'M12 7v5l3 2M3 12a9 9 0 1018 0 9 9 0 00-18 0',
    installations: 'M14 4l6 6-9 9H5v-6zM12 6l6 6', maintenance: 'M15 4a5 5 0 00-5 7L4 17l3 3 6-6a5 5 0 007-5l-3 3-3-1-1-3z',
    inventory: 'M4 8l8-4 8 4v9l-8 4-8-4zM4 8l8 4 8-4M12 12v9', work_orders: 'M9 4h6v3H9zM6 6h12v15H6zM9 12l2 2 4-4',
    dispatch: 'M4 12a8 8 0 0116 0v5h-3v-5M4 17h3v-5M12 4V2', map: 'M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3zM9 3v15M15 6v15',
    search: 'M10 4a6 6 0 110 12 6 6 0 010-12zM15 15l5 5', notices: 'M6 16V11a6 6 0 0112 0v5l2 2H4zM10 20a2 2 0 004 0',
    home: 'M4 11l8-7 8 7M6 10v10h12V10',
    settings: 'M12 9a3 3 0 110 6 3 3 0 010-6zM12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1',
    display: 'M12 4a8 8 0 100 16zM12 4a8 8 0 010 16', wallpaper: 'M4 5h16v14H4zM4 15l5-5 4 4 3-3 4 4M15 9h.5',
    about: 'M12 3a9 9 0 100 18 9 9 0 000-18zM12 11v5M12 8v.5'
  };
  function icon(name) {
    const svg = document.createElementNS(svgNS, 'svg'); svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('aria-hidden', 'true');
    const path = document.createElementNS(svgNS, 'path'); path.setAttribute('d', ICONS[name] || ICONS.overview); svg.append(path); return svg;
  }
  os.icon = icon;
  // Boton de app: icono + nombre. El textContent es solo el nombre (lo usan las pruebas y los lectores).
  os.appButton = (id, name, action, className = 'app') => {
    const node = button('', action, false, className); node.replaceChildren();
    const tile = el('span', null, `app-tile app-${id}`); tile.append(icon(id)); node.append(tile, el('span', name, 'app-label'));
    node.dataset.app = id; return node;
  };

  // ---------- Barra de estado ----------
  function pad(n) { return String(n).padStart(2, '0'); }
  function paintClock() {
    const c = os.clock; const now = new Date();
    byId('clock').textContent = c ? `${pad(c.h)}:${pad(c.m)}` : `${pad(now.getHours())}:${pad(now.getMinutes())}`;
  }
  os.status = message => {
    if (message.clock && Number.isFinite(message.clock.h) && Number.isFinite(message.clock.m)) os.clock = { h: message.clock.h, m: message.clock.m };
    if (message.position && Number.isFinite(message.position.x) && Number.isFinite(message.position.y)) { os.here = { x: message.position.x, y: message.position.y }; }
    paintClock();
    if (state.view === 'home') byId('greeting').textContent = greeting() || '';
  };
  function greeting() {
    const hour = os.clock ? os.clock.h : new Date().getHours(); const G = H().greeting || {};
    return hour >= 6 && hour < 14 ? G.morning : hour >= 14 && hour < 21 ? G.afternoon : G.night;
  }

  // ---------- Avisos en vivo ----------
  function paintBell() { const badge = byId('bell-count'); badge.textContent = os.unread > 9 ? '9+' : String(os.unread); badge.hidden = os.unread === 0; }
  os.notice = message => {
    if (!state.session || typeof message.text !== 'string') return;
    const kind = /^(info|success|warning|error)$/.test(message.kind) ? message.kind : 'info';
    const position = message.position && Number.isFinite(message.position.x) && Number.isFinite(message.position.y) ? { x: message.position.x, y: message.position.y } : null;
    const entry = { text: message.text.slice(0, 240), kind, position, at: Date.now() };
    os.notices.unshift(entry); if (os.notices.length > 30) os.notices.length = 30;
    if (byId('notice-center').hidden) os.unread++; else paintNotices();
    paintBell(); if (os.settings.banners) toast(entry);
    if (os.settings.sounds) window.postMessage({ type: 'beep', frequency: kind === 'error' ? 1500 : 1180, duration: 0.09 }, '*');
    if (state.view === 'home' && !state.busy) os.renderHome();
  };
  function toast(entry) {
    const node = el('div', null, `toast kind-${entry.kind}`); const body = el('div', null, 'toast-body');
    body.append(el('strong', state.session.brand.Name), el('span', entry.text)); node.append(icon('notices'), body);
    node.addEventListener('click', () => { node.remove(); toggleNotices(true); });
    const box = byId('toasts'); box.prepend(node); while (box.children.length > 3) box.lastChild.remove();
    setTimeout(() => { node.classList.add('leaving'); setTimeout(() => node.remove(), 300); }, 5000);
  }
  function timeAgo(at) {
    const seconds = Math.max(0, Math.round((Date.now() - at) / 1000));
    return seconds < 60 ? `${seconds} s` : seconds < 3600 ? `${Math.floor(seconds / 60)} min` : `${Math.floor(seconds / 3600)} h`;
  }
  function paintNotices() {
    const list = byId('notice-list'); list.replaceChildren();
    if (!os.notices.length) { list.append(el('div', H().noNotices, 'nc-empty')); return; }
    for (const entry of os.notices) {
      const row = el('div', null, `nc-item kind-${entry.kind}`); const body = el('div');
      body.append(el('span', entry.text), el('small', timeAgo(entry.at)));
      row.append(body);
      if (entry.position) row.append(button(H().gps, () => gps(entry.position), false, 'mini'));
      list.append(row);
    }
  }
  function toggleNotices(force) {
    const center = byId('notice-center'); const show = force ?? center.hidden;
    center.hidden = !show; if (show) { os.unread = 0; paintBell(); paintNotices(); byId('toasts').replaceChildren(); }
  }
  function gps(position) { post('waypoint', { x: position.x, y: position.y }).catch(() => {}); }

  // ---------- Inicio ----------
  function count(value) { return Number.isFinite(value) ? value : 0; }
  function widget(id, title, value, lines, target, tone) {
    const node = button('', () => target && api.openApp(target), !target, `widget${tone ? ' tone-' + tone : ''}`); node.replaceChildren();
    const head = el('div', null, 'widget-head'); head.append(icon(id), el('span', title)); node.append(head, el('div', value, 'widget-value'));
    const sub = el('div', null, 'widget-lines'); for (const line of lines) if (line) sub.append(el('span', line)); node.append(sub);
    return node;
  }
  function has(id) { return (api.modules() || []).some(module => module.id === id); }
  function widgets(data) {
    const c = data?.counts || {}; const w = W(); const box = byId('widgets'); box.replaceChildren();
    const client = state.session.kind === 'client';
    box.append(widget('overview', w.devices, count(c.devices), [`${count(c.ok)} ${w.ok}`, c.attention ? `${c.attention} ${w.attention}` : null], 'overview', c.attention ? 'warn' : null));
    if (has('alarms')) box.append(widget('alarms', w.alarms, count(c.armed), [w.armed, c.triggered ? `${c.triggered} ${w.triggered}` : null], 'alarms', c.triggered ? 'alert' : null));
    if (client) {
      if (has('requests')) box.append(widget('requests', w.requests, count(c.orders), [w.active], 'requests'));
      if (has('emergencies')) box.append(widget('emergencies', w.emergencies, count(c.calls), [w.active], 'emergencies', c.calls ? 'alert' : null));
      if (has('trackers') && c.cars) box.append(widget('trackers', w.cars, count(c.cars), [c.carsAlarm ? `${c.carsAlarm} ${w.carsAlarm}` : null], 'trackers', c.carsAlarm ? 'alert' : null));
    } else {
      box.append(widget('work_orders', w.orders, count(c.ordersOpen), [w.ordersOpen, c.ordersMine ? `${c.ordersMine} ${w.ordersMine}` : null], has('work_orders') ? 'work_orders' : null));
      if (has('dispatch')) box.append(widget('dispatch', w.calls, count(c.calls), [w.callsActive, c.callsMine ? `${c.callsMine} ${w.callsMine}` : null], 'dispatch', c.calls ? 'alert' : null));
      if (has('cctv')) box.append(widget('cctv', w.cameras, count(c.live), [w.live], 'cctv'));
    }
    const attention = el('section', null, 'widget wide attention'); const title = el('div', null, 'widget-head');
    title.append(icon('notices'), el('span', H().attention)); attention.append(title);
    const items = Array.isArray(data?.attention) ? data.attention : [];
    if (!items.length) attention.append(el('div', H().allGood, 'attention-empty'));
    for (const item of items.slice(0, 5)) {
      const row = button('', () => api.goto(item), false, `attention-row reason-${item.reason}`); row.replaceChildren();
      row.append(el('span', (H().reasons || {})[item.reason] || item.reason, 'attention-reason'), el('span', [item.title, item.subtitle].filter(Boolean).join(' · '), 'attention-title'));
      attention.append(row);
    }
    byId('attention').replaceChildren(attention);
  }
  os.renderHome = async () => {
    const epoch = state.epoch;
    byId('greeting').textContent = `${greeting() || ''}`;
    byId('apps-title').textContent = H().apps || '';
    widgets(os.data);
    const data = await request('home');
    if (epoch !== state.epoch || !state.session || state.view !== 'home') return;
    os.data = data && data.counts ? data : null; widgets(os.data);
  };

  // ---------- Buscador ----------
  let searchTimer = null; let searchToken = 0;
  function openSearch() {
    const box = byId('spotlight'); box.hidden = false; const input = byId('search-input');
    input.placeholder = H().searchPlaceholder || ''; input.value = ''; byId('search-results').replaceChildren(el('div', H().searchHint, 'nc-empty'));
    setTimeout(() => input.focus(), 30);
  }
  function closeSearch() { byId('spotlight').hidden = true; clearTimeout(searchTimer); searchToken++; }
  os.closeOverlays = () => {
    if (!byId('spotlight').hidden) { closeSearch(); return true; }
    if (!byId('notice-center').hidden) { toggleNotices(false); return true; }
    return false;
  };
  async function runSearch(query) {
    const token = ++searchToken; const results = byId('search-results');
    if (query.trim().length < 2) { results.replaceChildren(el('div', H().searchHint, 'nc-empty')); return; }
    if (state.busy) { searchTimer = setTimeout(() => runSearch(query), 250); return; }
    const data = await request('search', { query: query.trim() });
    if (token !== searchToken || byId('spotlight').hidden) return;
    results.replaceChildren();
    const items = Array.isArray(data?.items) ? data.items : [];
    if (!items.length) { results.append(el('div', H().noResults, 'nc-empty')); return; }
    for (const item of items) {
      const row = button('', () => { closeSearch(); api.goto(item); }, false, `search-result kind-${item.kind}`); row.replaceChildren();
      const iconName = { device: item.type === 'alarm_panel' ? 'alarms' : item.type === 'cctv_camera' ? 'cctv' : 'overview', order: 'work_orders', call: 'dispatch', car: 'trackers' }[item.kind];
      const body = el('div'); body.append(el('strong', item.title), el('span', [(H().kinds || {})[item.kind], item.subtitle].filter(Boolean).join(' · ')));
      row.append(icon(iconName), body, el('span', stateLabel(item), 'badge')); results.append(row);
    }
  }
  function stateLabel(item) {
    const T = state.session.brand.Text;
    if (item.kind === 'device') return T.states?.[item.state] || item.state;
    if (item.kind === 'order') return H().orderStatus?.[item.state] || item.state;
    if (item.kind === 'call') return T.dispatch?.status?.[item.state] || item.state;
    return H().carState?.[item.state] || item.state;
  }

  // ---------- Mapa: el mapa real del juego ----------
  // La NUI no dibuja el mapa: pide al cliente que abra el mapa del juego con los puntos del resumen como iconos.
  // Al salir del mapa el cliente vuelve a abrir la tablet en el inicio.
  os.mapView = async content => {
    const data = await request('home'); if (!state.session) return;
    os.data = data && data.counts ? data : os.data;
    const points = Array.isArray(os.data?.points) ? os.data.points : [];
    content.append(el('p', H().mapOpening, 'empty map-opening'));
    post('openMap', { kind: state.session.kind, points }).catch(() => {});
  };

  // ---------- Configuracion (ajustes por jugador) ----------
  const DEFAULTS = { theme: 'auto', wallpaper: 1, textSize: 'normal', sounds: true, banners: true };
  os.settings = { ...DEFAULTS };
  const S = () => H().settings || {};
  function clean(raw) {
    const value = raw && typeof raw === 'object' ? raw : {};
    return { theme: ['auto', 'light', 'dark'].includes(value.theme) ? value.theme : 'auto',
      wallpaper: Number.isInteger(value.wallpaper) && value.wallpaper >= 1 && value.wallpaper <= 6 ? value.wallpaper : 1,
      textSize: value.textSize === 'large' ? 'large' : 'normal', sounds: value.sounds !== false, banners: value.banners !== false };
  }
  os.apply = () => {
    const session = state.session; if (!session) return;
    const app = byId('app'); const set = os.settings;
    const dark = set.theme === 'dark' || (set.theme === 'auto' && session.kind === 'operations');
    const theme = session.brand.Themes[dark ? 'operations' : 'client'];
    for (const [key, value] of Object.entries(theme)) if (/^#[0-9a-f]{6}$/i.test(value)) app.style.setProperty(`--${key}`, value);
    app.classList.toggle('dark', dark); app.classList.toggle('text-large', set.textSize === 'large');
    const screen = app.querySelector('.screen'); screen.className = `screen wp-${set.wallpaper}`;
  };
  async function save(change) {
    os.settings = clean({ ...os.settings, ...change }); os.apply();
    try { const result = await post('settings', os.settings); if (result?.settings) os.settings = clean(result.settings); } catch { /* se aplica igualmente en esta sesion */ }
  }
  function toggle(on, action) {
    const node = button('', () => action(!node.classList.contains('on')), false, `switch${on ? ' on' : ''}`); node.replaceChildren(el('span'));
    node.setAttribute('role', 'switch'); node.setAttribute('aria-checked', String(on)); return node;
  }
  function segmented(options, current, action) {
    const box = el('div', null, 'segmented');
    for (const [value, label] of options) box.append(button(label, () => action(value), false, value === current ? 'active' : null));
    return box;
  }
  function group(title, rows, foot) {
    const node = el('section', null, 'set-group'); if (title) node.append(el('div', title, 'set-title'));
    const list = el('div', null, 'set-list'); for (const row of rows) list.append(row); node.append(list);
    if (foot) node.append(el('div', foot, 'set-foot')); return node;
  }
  function row(iconName, label, control, tone) {
    const node = el('div', null, 'set-row'); const tile = el('span', null, `set-icon tone-${tone || 'grey'}`); tile.append(icon(iconName));
    node.append(tile, el('span', label, 'set-label')); if (control) node.append(control); return node;
  }
  let settingsPage = 'general';
  os.settingsView = content => {
    const T = S(); const session = state.session; const set = os.settings;
    const pages = [['general', T.general, 'settings', 'grey'], ['display', T.display, 'display', 'blue'], ['wallpaper', T.wallpaper, 'wallpaper', 'teal'],
      ['notifications', T.notifications, 'notices', 'red'], ['about', T.about, 'about', 'grey']];
    const shell = el('div', null, 'settings'); const side = el('aside', null, 'set-side'); const pane = el('div', null, 'set-pane');
    const card = el('div', null, 'set-account'); const avatar = el('span', session.brand.Monogram, 'set-avatar');
    const who = el('div'); who.append(el('strong', session.profile || ''), el('span', [session.brand.Tablets[session.kind]?.name, session.employeeId].filter(Boolean).join(' · ')));
    card.append(avatar, who); side.append(card);
    const nav = el('div', null, 'set-list');
    for (const [id, label, iconName, tone] of pages) {
      const item = button('', () => { settingsPage = id; render(); }, false, `set-row set-nav${settingsPage === id ? ' selected' : ''}`); item.replaceChildren();
      const tile = el('span', null, `set-icon tone-${tone}`); tile.append(icon(iconName)); item.append(tile, el('span', label, 'set-label'));
      nav.append(item);
    }
    side.append(nav);
    const render = () => { content.replaceChildren(); os.settingsView(content); };
    pane.append(el('h2', pages.find(page => page[0] === settingsPage)?.[1] || '', 'set-heading'));
    if (settingsPage === 'general') {
      pane.append(group(T.generalGroup, [row('home', T.startScreen, el('span', H().title, 'set-value'), 'blue'), row('search', T.searchScope, el('span', T.searchScopeValue, 'set-value'), 'grey')]),
        group(null, [row('settings', T.reset, button(T.resetButton, () => save({ ...DEFAULTS }).then(render), false, 'danger mini'), 'red')], T.resetHelp));
    } else if (settingsPage === 'display') {
      pane.append(group(T.appearance, [row('display', T.theme, segmented([['auto', T.themeAuto], ['light', T.themeLight], ['dark', T.themeDark]], set.theme, value => save({ theme: value }).then(render)), 'blue')], T.themeHelp),
        group(T.text, [row('display', T.textSize, segmented([['normal', T.textNormal], ['large', T.textLarge]], set.textSize, value => save({ textSize: value }).then(render)), 'grey')]));
    } else if (settingsPage === 'wallpaper') {
      const grid = el('div', null, 'wallpapers');
      for (let index = 1; index <= 6; index++) {
        const option = button('', () => save({ wallpaper: index }).then(render), false, `wallpaper-option wp-${index}${set.wallpaper === index ? ' selected' : ''}`);
        option.replaceChildren(el('span', (T.wallpapers || [])[index - 1] || String(index))); grid.append(option);
      }
      pane.append(group(T.chooseWallpaper, [grid]));
    } else if (settingsPage === 'notifications') {
      pane.append(group(T.notificationsGroup, [row('notices', T.banners, toggle(set.banners, value => save({ banners: value }).then(render)), 'red'),
        row('notices', T.sounds, toggle(set.sounds, value => save({ sounds: value }).then(render)), 'red')], T.notificationsHelp));
    } else {
      const info = [[T.name, session.brand.Tablets[session.kind]?.name], [T.model, T.modelValue], [T.version, session.version], [T.profile, session.profile],
        [T.employee, session.employeeId], [T.sessionUntil, api.date(session.expires)], [T.operator, session.brand.Name]];
      pane.append(group(null, info.filter(([, value]) => value).map(([label, value]) => { const node = el('div', null, 'set-row'); node.append(el('span', label, 'set-label'), el('span', value, 'set-value')); return node; })));
    }
    shell.append(side, pane); content.append(shell);
  };

  // ---------- Montaje ----------
  os.mount = () => {
    byId('bell').addEventListener('click', () => toggleNotices());
    byId('notice-clear').addEventListener('click', () => { os.notices = []; paintNotices(); });
    byId('search-open').addEventListener('click', openSearch);
    byId('search-close').addEventListener('click', closeSearch);
    byId('search-input').addEventListener('input', event => { clearTimeout(searchTimer); const value = event.target.value; searchTimer = setTimeout(() => runSearch(value), 280); });
    byId('home-bar').addEventListener('click', () => { os.closeOverlays(); api.goHome(); });
    byId('home-button').addEventListener('click', () => { os.closeOverlays(); api.goHome(); });
    setInterval(() => { if (!os.clock && state.session) paintClock(); }, 15000);
  };
  os.reset = session => {
    os.notices = []; os.unread = 0; os.data = null; paintBell(); paintClock();
    os.settings = clean(session.settings); os.apply();
    byId('spotlight').hidden = true; byId('notice-center').hidden = true; byId('toasts').replaceChildren();
    byId('notice-title').textContent = H().notices || ''; byId('notice-clear').textContent = H().clear || '';
    byId('search-close').textContent = state.session.brand.Text.close || '';
    byId('search-open').replaceChildren(icon('search'), el('span', H().search || ''));
    const dock = byId('dock'); dock.replaceChildren();
    const first = (api.modules() || [])[0];
    dock.append(os.appButton('search', H().search, openSearch, 'dock-app'), os.appButton('map', H().map, () => api.openApp('map'), 'dock-app'),
      os.appButton('notices', H().notices, () => toggleNotices(), 'dock-app'));
    if (first) dock.append(os.appButton(first.id, first.name, () => api.openApp(first.id), 'dock-app'));
    dock.append(os.appButton('settings', H().settings?.title, () => api.openApp('settings'), 'dock-app'));
  };
  return os;
};
