(() => {
  'use strict';
  // Teclado de alarma en pantalla (pinpad y lector de chapa). Solo interfaz: el servidor valida
  // la distancia al teclado, el codigo, la chapa y los bloqueos.
  const root = document.getElementById('pinpad');
  const resource = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'os_security';
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  const post = (endpoint, body) => fetch(`https://${resource()}/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => {});
  let pad = null; // { data, text, code, screen, status, busy }

  function close(notify = true) { if (!pad) return; pad = null; root.hidden = true; root.replaceChildren(); if (notify) post('pinpadClose', {}); }
  // Segundos restantes descontados localmente desde el ultimo dato del servidor (se actualiza solo).
  const remaining = value => value == null ? null : Math.max(0, Math.ceil(value - (performance.now() - pad.receivedAt) / 1000));
  function render() {
    const { data, text } = pad;
    let status = text.pad[data.mode] || data.mode;
    const entry = remaining(data.entry), locked = remaining(data.locked);
    if (data.triggered) status = text.pad.triggered;
    else if (entry != null && entry > 0) status = `${text.pad.entry} · ${entry}s`;
    if (locked > 0) status = `${text.pad.locked} · ${locked}s`;
    pad.status.textContent = status;
    pad.status.className = `pp-status ${data.triggered ? 'alert' : data.mode}`;
    pad.screen.textContent = pad.code.length ? '•'.repeat(pad.code.length) : '----';
  }
  function press(key) {
    if (!pad || pad.busy) return;
    if (/^\d$/.test(key) && pad.code.length < 6) pad.code += key;
    else if (key === 'clear') pad.code = '';
    else if (key === 'back') pad.code = pad.code.slice(0, -1);
    window.postMessage({ type: 'beep', frequency: 1500, duration: 0.05, volume: 0.12 }, '*'); render();
  }
  function send(action) {
    if (!pad || pad.busy) return;
    if (action !== 'tag' && pad.code.length < 4) { pad.message.textContent = pad.text.pinFormat; return; }
    pad.busy = true; pad.message.textContent = '…';
    post('pinpad', { action, pin: action === 'tag' ? null : pad.code });
    pad.code = ''; render();
  }
  function open(data, text) {
    root.replaceChildren();
    const panel = el('section', null, 'pp-panel');
    const brand = el('div', null, 'pp-brand'); brand.append(el('strong', 'G6'), el('span', data.label || ''));
    const status = el('div', '', 'pp-status'); const screen = el('div', '----', 'pp-screen'); const messageLine = el('div', '', 'pp-message');
    const keys = el('div', null, 'pp-keys');
    for (const key of ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'clear', '0', 'back']) {
      const button = el('button', key === 'clear' ? 'C' : key === 'back' ? '⌫' : key, `pp-key${/\d/.test(key) ? '' : ' fn'}`); button.type = 'button';
      button.addEventListener('click', () => press(key)); keys.append(button);
    }
    const modes = el('div', null, 'pp-modes');
    for (const [action, label, className] of [['arm', text.pad.arm, 'arm'], ['partial', text.pad.partial, 'partial'], ['disarm', text.pad.disarm, 'disarm']]) {
      const button = el('button', label, `pp-mode ${className}`); button.type = 'button'; button.addEventListener('click', () => send(action)); modes.append(button);
    }
    const footer = el('div', null, 'pp-footer');
    if (data.tags) { const tag = el('button', text.pad.tag, 'pp-tag'); tag.type = 'button'; tag.addEventListener('click', () => send('tag')); footer.append(tag); }
    const exit = el('button', text.pad.close, 'pp-exit'); exit.type = 'button'; exit.addEventListener('click', () => close()); footer.append(exit);
    panel.append(brand, status, screen, keys, modes, messageLine, footer); root.append(panel); root.hidden = false;
    pad = { data, text, code: '', screen, status, message: messageLine, busy: false, receivedAt: performance.now() };
    render();
  }
  setInterval(() => { if (pad) render(); }, 250);

  window.addEventListener('keydown', event => {
    if (!pad) return;
    if (event.key === 'Escape') { event.preventDefault(); close(); }
    else if (/^\d$/.test(event.key)) press(event.key);
    else if (event.key === 'Backspace') press('back');
    else if (event.key === 'Enter') send(pad.data.mode === 'disarmed' ? 'arm' : 'disarm');
  });
  window.addEventListener('message', event => {
    const message = event.data || {};
    if (message.type === 'pinpad' && message.data && message.text) open(message.data, message.text);
    else if (message.type === 'pinpadResult' && pad) {
      pad.busy = false;
      if (message.data) { pad.data = message.data; pad.receivedAt = performance.now(); }
      pad.message.textContent = message.text || '';
      pad.message.className = `pp-message ${message.ok ? 'ok' : 'error'}`;
      render();
    } else if (message.type === 'pinpadUpdate' && pad && message.data) { pad.data = message.data; pad.receivedAt = performance.now(); render(); }
    else if (message.type === 'pinpadClose') close(false);
  });
})();
