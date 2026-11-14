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
    home: 'M4 11l8-7 8 7M6 10v10h12V10'
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
    if (message.position && Number.isFinite(message.position.x) && Number.isFinite(message.position.y)) { os.here = { x: message.position.x, y: message.position.y }; moveYou(); }
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
    paintBell(); toast(entry);
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

  // ---------- Mapa tactico (esquematico, coordenadas del mundo) ----------
  // Contorno aproximado dibujado a mano: solo orienta, la posicion exacta la marca el GPS.
  const WORLD = { minX: -4200, maxX: 4600, minY: -4200, maxY: 8200 };
  const COAST = [[1350, -3350], [300, -3300], [-900, -3600], [-1900, -3300], [-1600, -2000], [-1900, -1250], [-2100, -500], [-3000, 200], [-3250, 1100],
    [-3100, 1900], [-2800, 2500], [-2650, 3100], [-2300, 3800], [-2000, 4500], [-1600, 5300], [-900, 6000], [-300, 6600], [150, 7450], [700, 7150],
    [1500, 6700], [2400, 6100], [3300, 5400], [3850, 4500], [3700, 3500], [3200, 2400], [2950, 1300], [2750, 100], [2550, -1200], [1900, -2400]];
  const PLACES = [['Los Santos', 150, -900], ['Vinewood', 300, 600], ['Sandy Shores', 1800, 3600], ['Grapeseed', 1900, 4950], ['Paleto Bay', -250, 6350],
    ['Fort Zancudo', -2250, 3150], ['Chumash', -2900, 900], ['Monte Chiliad', 500, 5550], ['Alamo Sea', 1300, 4050]];
  const toSvg = (x, y) => [x - WORLD.minX, WORLD.maxY - y];
  let view = null; let mapNodes = null;
  function moveYou() {
    if (!mapNodes?.you || !os.here) return;
    const [x, y] = toSvg(os.here.x, os.here.y); mapNodes.you.setAttribute('transform', `translate(${x} ${y})`); mapNodes.you.style.display = '';
  }
  // Proporcion alto/ancho del marco: la vista siempre tiene la forma del marco y el mapa lo llena.
  const ratio = () => { const svg = mapNodes?.svg; return svg && svg.clientWidth ? svg.clientHeight / svg.clientWidth : 0.6; };
  function setView(v) {
    const width = WORLD.maxX - WORLD.minX, height = WORLD.maxY - WORLD.minY;
    v.w = Math.min(Math.max(width, height / ratio()), Math.max(500, v.w)); v.h = v.w * ratio();
    v.x = Math.min(width - v.w * 0.2, Math.max(-v.w * 0.8, v.x)); v.y = Math.min(height - v.h * 0.2, Math.max(-v.h * 0.8, v.y));
    view = v; mapNodes.svg.setAttribute('viewBox', `${v.x} ${v.y} ${v.w} ${v.h}`);
    // Con 'slice' el mapa llena el marco: unidades del mundo por pixel en pantalla (tamano fijo de puntos y textos).
    mapNodes.svg.style.setProperty('--u', String(v.w / (mapNodes.svg.clientWidth || 800)));
  }
  os.mapView = async content => {
    const data = await request('home'); if (!state.session) return;
    os.data = data && data.counts ? data : os.data;
    const points = Array.isArray(os.data?.points) ? os.data.points : [];
    const wrap = el('div', null, 'map-wrap'); const svg = document.createElementNS(svgNS, 'svg'); svg.classList.add('map');
    const make = (tag, attrs, parent = svg) => { const node = document.createElementNS(svgNS, tag); for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v); parent.append(node); return node; };
    const width = WORLD.maxX - WORLD.minX, height = WORLD.maxY - WORLD.minY;
    make('rect', { x: -width, y: -height, width: width * 3, height: height * 3, class: 'map-sea' });
    const grid = make('g', { class: 'map-grid' });
    for (let x = 0; x <= width; x += 1000) make('line', { x1: x, y1: 0, x2: x, y2: height }, grid);
    for (let y = 0; y <= height; y += 1000) make('line', { x1: 0, y1: y, x2: width, y2: y }, grid);
    make('polygon', { points: COAST.map(([x, y]) => toSvg(x, y).join(',')).join(' '), class: 'map-land' });
    const [lx, ly] = toSvg(1300, 4050); make('ellipse', { cx: lx, cy: ly, rx: 900, ry: 330, transform: `rotate(-12 ${lx} ${ly})`, class: 'map-lake' });
    for (const [name, x, y] of PLACES) { const [px, py] = toSvg(x, y); const label = make('text', { x: px, y: py, class: 'map-place' }); label.textContent = name; }
    const layer = make('g', { class: 'map-points' });
    const popup = el('div', null, 'map-popup'); popup.hidden = true;
    for (const point of points) {
      if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) continue;
      const [px, py] = toSvg(point.x, point.y);
      const g = make('g', { class: `map-point kind-${point.kind} state-${point.state}`, transform: `translate(${px} ${py})` }, layer);
      make('circle', { r: 1, class: 'map-dot' }, g);
      g.addEventListener('click', event => {
        event.stopPropagation(); popup.hidden = false; popup.replaceChildren();
        popup.append(el('span', (H().kinds || {})[point.kind], 'overline'), el('strong', point.label), el('div', [point.subtitle, stateLabel({ kind: point.kind, state: point.state })].filter(Boolean).join(' · '), 'subtle'));
        const actions = el('div', null, 'map-actions');
        actions.append(button(H().gps, () => gps(point), false, 'primary'), button(H().open, () => api.goto({ kind: point.kind, id: point.id })));
        popup.append(actions);
      });
    }
    const you = make('g', { class: 'map-you' }); make('circle', { r: 1, class: 'map-you-pulse' }, you); make('circle', { r: 1, class: 'map-you-dot' }, you); you.style.display = 'none';
    svg.addEventListener('click', () => { popup.hidden = true; });
    mapNodes = { svg, you };
    const tools = el('div', null, 'map-tools'); const legend = el('div', null, 'map-legend');
    wrap.append(svg, tools, legend, popup);
    content.append(el('p', points.length ? H().mapHelp : H().noPoints, 'subtle map-help'), wrap);
    // Encuadre inicial: la zona con puntos (o el jugador, o Los Santos).
    const xs = points.map(p => p.x), ys = points.map(p => p.y);
    if (os.here) { xs.push(os.here.x); ys.push(os.here.y); }
    if (!xs.length) { xs.push(-1500, 1500); ys.push(-2500, 1000); }
    const pad = 600, minX = Math.min(...xs) - pad, maxX = Math.max(...xs) + pad, maxY = Math.max(...ys) + pad, minY = Math.min(...ys) - pad;
    const w = Math.max(maxX - minX, (maxY - minY) / ratio(), 2500); const [cx, cy] = toSvg((minX + maxX) / 2, (minY + maxY) / 2);
    setView({ x: cx - w / 2, y: cy - (w * ratio()) / 2, w });
    moveYou();
    // Rueda: zoom hacia el cursor. Arrastrar: mover.
    svg.addEventListener('wheel', event => {
      event.preventDefault(); const box = svg.getBoundingClientRect(); const factor = event.deltaY > 0 ? 1.18 : 1 / 1.18;
      const fx = (event.clientX - box.left) / box.width, fy = (event.clientY - box.top) / box.height; const nw = view.w * factor;
      setView({ x: view.x + (view.w - nw) * fx, y: view.y + (view.h - nw * view.h / view.w) * fy, w: nw });
    }, { passive: false });
    let drag = null;
    svg.addEventListener('pointerdown', event => { drag = { x: event.clientX, y: event.clientY, view: { ...view }, moved: false }; });
    svg.addEventListener('pointermove', event => {
      if (!drag) return; const box = svg.getBoundingClientRect(); const dx = event.clientX - drag.x, dy = event.clientY - drag.y;
      if (Math.abs(dx) + Math.abs(dy) > 4) drag.moved = true;
      if (drag.moved) setView({ x: drag.view.x - dx * drag.view.w / box.width, y: drag.view.y - dy * drag.view.h / box.height, w: drag.view.w });
    });
    svg.addEventListener('pointerup', () => { drag = null; }); svg.addEventListener('pointerleave', () => { drag = null; });
    tools.append(button('+', () => setView({ x: view.x + view.w * 0.15, y: view.y + view.h * 0.15, w: view.w * 0.7 })),
      button('−', () => setView({ x: view.x - view.w * 0.2, y: view.y - view.h * 0.2, w: view.w * 1.4 })),
      button(H().you, () => { if (!os.here) return; const [x, y] = toSvg(os.here.x, os.here.y); setView({ x: x - 1250, y: y - 1250 * ratio(), w: 2500 }); }, false, 'you'));
    for (const kind of ['device', 'order', 'call', 'car']) if (points.some(p => p.kind === kind)) { const item = el('span', (H().legend || {})[kind], `legend kind-${kind}`); legend.append(item); }
  };

  // ---------- Montaje ----------
  os.mount = () => {
    byId('bell').addEventListener('click', () => toggleNotices());
    byId('notice-clear').addEventListener('click', () => { os.notices = []; paintNotices(); });
    byId('search-open').addEventListener('click', openSearch);
    byId('search-close').addEventListener('click', closeSearch);
    byId('search-input').addEventListener('input', event => { clearTimeout(searchTimer); const value = event.target.value; searchTimer = setTimeout(() => runSearch(value), 280); });
    byId('home-bar').addEventListener('click', () => { os.closeOverlays(); api.goHome(); });
    setInterval(() => { if (!os.clock && state.session) paintClock(); }, 15000);
  };
  os.reset = session => {
    os.notices = []; os.unread = 0; os.data = null; mapNodes = null; paintBell(); paintClock();
    byId('spotlight').hidden = true; byId('notice-center').hidden = true; byId('toasts').replaceChildren();
    byId('notice-title').textContent = H().notices || ''; byId('notice-clear').textContent = H().clear || '';
    byId('search-close').textContent = state.session.brand.Text.close || '';
    byId('search-open').replaceChildren(icon('search'), el('span', H().search || ''));
    const dock = byId('dock'); dock.replaceChildren();
    const first = (api.modules() || [])[0];
    dock.append(os.appButton('search', H().search, openSearch, 'dock-app'), os.appButton('map', H().map, () => api.openApp('map'), 'dock-app'),
      os.appButton('notices', H().notices, () => toggleNotices(), 'dock-app'));
    if (first) dock.append(os.appButton(first.id, first.name, () => api.openApp(first.id), 'dock-app'));
    void session;
  };
  return os;
};
