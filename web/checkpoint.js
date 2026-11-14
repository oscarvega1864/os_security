(() => {
  'use strict';
  // Control de acceso: tarjeta de permiso para el cacheado y panel de cacheo por zonas para el vigilante.
  // El vigilante "palpa" cada zona manteniendo el raton encima; al terminar marca lo que retiene. El servidor
  // vuelve a comprobar que lo marcado se encontro y se puede retener.
  const resource = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'os_security';
  const post = (endpoint, body) => fetch(`https://${resource()}/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => {});
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  const format = (template, ...values) => values.reduce((result, value) => result.replace(/%[sd]/, value), String(template || ''));
  const root = document.getElementById('checkpoint');
  const PAT_MS = 700;
  let mode = null; // 'ask' | 'frisk'
  let frisk = null; // { zones, done:Set, retain:{items:{}, weapons:Set}, text }

  function hide() { mode = null; frisk = null; root.hidden = true; root.replaceChildren(); }
  function consent(accept) { if (mode !== 'ask') return; hide(); post('friskConsent', { accept }); }
  function ask(data, text) {
    hide(); mode = 'ask';
    const card = el('section', null, 'cp-ask');
    card.append(el('span', text.askTitle, 'cp-overline'), el('p', format(text.ask, data.from || '', data.company || ''), 'cp-ask-text'));
    const timer = el('div', '', 'cp-timer'); card.append(timer);
    const row = el('div', null, 'cp-row');
    const yes = el('button', text.accept, 'cp-yes'); yes.type = 'button'; yes.addEventListener('click', () => consent(true));
    const no = el('button', text.refuse, 'cp-no'); no.type = 'button'; no.addEventListener('click', () => consent(false));
    row.append(yes, no); card.append(row); root.append(card); root.hidden = false;
    let left = Math.max(1, Number(data.seconds) || 20);
    timer.textContent = `${left}s`;
    const tick = setInterval(() => { if (mode !== 'ask') { clearInterval(tick); return; } left -= 1; timer.textContent = `${Math.max(0, left)}s`; if (left <= 0) { clearInterval(tick); consent(false); } }, 1000);
  }
  function renderStatus() {
    const missing = frisk.order.filter(zone => !frisk.done.has(zone)).length;
    frisk.status.textContent = missing ? format(frisk.text.pending, missing) : '';
    frisk.finish.disabled = missing > 0;
  }
  function reveal(zone, tile) {
    if (frisk.done.has(zone)) return;
    frisk.done.add(zone); tile.classList.add('done'); tile.classList.remove('patting');
    const list = tile.querySelector('.cp-found');
    const entries = Array.isArray(frisk.zones[zone]) ? frisk.zones[zone] : [];
    if (!entries.length) list.append(el('div', frisk.text.nothing, 'cp-empty'));
    for (const entry of entries) {
      const row = el('label', null, `cp-entry kind-${entry.kind === 'weapon' ? 'weapon' : 'item'}${entry.metal ? ' metal' : ''}`);
      row.append(el('span', entry.count > 1 ? `${entry.label} x${entry.count}` : entry.label, 'cp-entry-name'));
      if (entry.retainable) {
        const box = el('input'); box.type = 'checkbox'; box.title = frisk.text.retain;
        box.addEventListener('change', () => {
          if (entry.kind === 'weapon') { if (box.checked) frisk.retain.weapons.add(entry.name); else frisk.retain.weapons.delete(entry.name); }
          else if (box.checked) frisk.retain.items[entry.name] = entry.count; else delete frisk.retain.items[entry.name];
        });
        row.append(box, el('small', frisk.text.retain, 'cp-retain'));
      }
      list.append(row);
    }
    window.postMessage({ type: 'beep', frequency: entries.length ? 520 : 1200, duration: 0.05, volume: 0.05 }, '*');
    renderStatus();
  }
  function open(data, text) {
    hide(); mode = 'frisk';
    const panel = el('section', null, 'cp-frisk');
    panel.append(el('span', format(text.friskTitle, data.target || ''), 'cp-overline'), el('p', text.friskHelp, 'cp-help'));
    const body = el('div', null, 'cp-body');
    const order = Array.isArray(data.order) ? data.order.filter(zone => /^[a-zA-Z]+$/.test(zone)) : [];
    frisk = { zones: data.zones || {}, order, done: new Set(), retain: { items: {}, weapons: new Set() }, text };
    for (const zone of order) {
      const tile = el('div', null, `cp-zone zone-${zone}`);
      tile.dataset.zone = zone;
      tile.append(el('strong', text.zones?.[zone] || zone), el('span', null, 'cp-progress'), el('div', null, 'cp-found'));
      let timer = null;
      tile.addEventListener('mouseenter', () => { if (frisk.done.has(zone)) return; tile.classList.add('patting'); timer = setTimeout(() => reveal(zone, tile), PAT_MS); });
      tile.addEventListener('mouseleave', () => { clearTimeout(timer); tile.classList.remove('patting'); });
      body.append(tile);
    }
    const status = el('div', '', 'cp-status');
    const row = el('div', null, 'cp-row');
    const finish = el('button', text.finish, 'cp-yes'); finish.type = 'button';
    finish.addEventListener('click', () => {
      if (!frisk || finish.disabled) return;
      const retain = { items: { ...frisk.retain.items }, weapons: Array.from(frisk.retain.weapons) };
      hide(); post('friskFinish', { retain });
    });
    const cancel = el('button', text.cancel, 'cp-no'); cancel.type = 'button'; cancel.addEventListener('click', () => { hide(); post('friskCancel', {}); });
    row.append(finish, cancel);
    panel.append(body, status, row); root.append(panel); root.hidden = false;
    frisk.status = status; frisk.finish = finish; renderStatus();
  }
  window.addEventListener('keydown', event => {
    if (event.key !== 'Escape' || !mode) return;
    event.preventDefault();
    if (mode === 'ask') consent(false); else { hide(); post('friskCancel', {}); }
  });
  window.addEventListener('message', event => {
    const message = event.data || {};
    if (message.type === 'friskAsk' && message.data && message.text) ask(message.data, message.text);
    else if (message.type === 'friskOpen' && message.data && message.text) open(message.data, message.text);
    else if (message.type === 'friskClose') hide();
  });
})();
