(() => {
  'use strict';
  // Minijuego de ganzua: un pin sube y baja por el bombin; hay que fijarlo (clic o Espacio) cuando pasa
  // por la zona verde. Uno detras de otro, tantos pines como diga el nivel de seguridad. Tres fallos y se
  // deja. Solo interfaz: el resultado lo valida el servidor (tiempo minimo por pin, distancia, objeto).
  const root = document.getElementById('lockpick');
  if (!root) return;
  const resource = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'os_security';
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  let run = null; let runs = 0;
  function post(body) {
    fetch(`https://${resource()}/lockpick`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => {});
  }
  function stop() { if (run?.frame) cancelAnimationFrame(run.frame); clearInterval(run?.clock); run = null; root.hidden = true; root.replaceChildren(); }
  function finish(result) { if (!run) return; stop(); post(result); }

  function start(data, text) {
    stop();
    const id = ++runs;
    run = { id, data, text, index: 0, misses: 0, left: data.seconds || 60 };
    const panel = el('section', null, 'mg-panel lp-panel');
    const head = el('header', null, 'mg-head');
    head.append(el('span', `${text.title} · ${text.kinds[data.kind] || ''} · ${text.tiers[(data.tier || 1) - 1] || ''}`, 'mg-overline'), el('h2', text.heading), el('p', text.help, 'mg-help'));
    const lock = el('div', null, 'lp-lock');
    const pins = [];
    for (let i = 0; i < data.pins; i++) {
      const column = el('div', null, 'lp-column');
      const zone = el('div', null, 'lp-zone'); const pin = el('div', null, 'lp-pin');
      column.append(zone, pin); lock.append(column);
      const size = Math.max(0.06, Math.min(0.5, Number(data.zone) || 0.15));
      const at = 0.15 + Math.random() * (0.7 - size);
      zone.style.bottom = `${at * 100}%`; zone.style.height = `${size * 100}%`;
      pins.push({ column, zone, pin, from: at, to: at + size, phase: Math.random() * Math.PI * 2 });
    }
    const meters = el('div', null, 'mg-meters');
    const misses = el('div', null, 'mg-strikes'); misses.append(el('small', text.misses, 'mg-label'));
    const dots = [0, 1, 2].map(() => el('span', null, 'mg-strike')); misses.append(...dots);
    const timer = el('b', '', 'lp-timer');
    meters.append(misses, timer);
    const foot = el('footer', null, 'mg-foot');
    const status = el('span', '', 'mg-status');
    const cancel = el('button', text.cancel, 'mg-cancel'); cancel.type = 'button'; cancel.addEventListener('click', () => finish({ cancel: true }));
    foot.append(status, cancel);
    panel.append(head, lock, meters, foot); root.append(panel); root.hidden = false;
    run.pins = pins; run.status = status; run.dots = dots;
    timer.textContent = `${run.left}s`;
    run.clock = setInterval(() => { if (!run || run.id !== id) return; run.left -= 1; timer.textContent = `${Math.max(0, run.left)}s`; if (run.left <= 0) finish({ ok: false }); }, 1000);
    const speed = Number(data.speed) || 1;
    let last = performance.now(), t = 0;
    const frame = now => {
      if (!run || run.id !== id) return;
      t += Math.min(0.1, (now - last) / 1000) * speed; last = now;
      pins.forEach((item, index) => {
        if (index < run.index) return;
        item.value = index === run.index ? 0.5 + 0.48 * Math.sin(t * 3.2 + item.phase) : 0.02;
        item.pin.style.bottom = `${item.value * 100}%`;
        item.column.classList.toggle('active', index === run.index);
        item.zone.classList.toggle('hot', index === run.index && item.value >= item.from && item.value <= item.to);
      });
      run.frame = requestAnimationFrame(frame);
    };
    run.frame = requestAnimationFrame(frame);
  }
  // Fijar el pin actual.
  function press() {
    if (!run) return;
    const item = run.pins[run.index];
    if (!item) return;
    if (item.value >= item.from && item.value <= item.to) {
      item.column.classList.remove('active'); item.column.classList.add('set'); item.pin.style.bottom = `${item.to * 100}%`;
      run.index += 1; run.status.textContent = run.text.set;
      if (run.index >= run.pins.length) setTimeout(() => finish({ ok: true }), 250);
    } else {
      run.misses += 1; run.dots.forEach((dot, i) => dot.classList.toggle('on', i < run.misses)); run.status.textContent = run.text.miss;
      if (run.misses >= 3) finish({ ok: false });
    }
  }
  root.addEventListener('pointerdown', event => { if (run && !event.target.closest('button')) press(); });
  window.addEventListener('keydown', event => {
    if (!run) return;
    if (event.key === 'Escape') finish({ cancel: true });
    else if (event.code === 'Space') { event.preventDefault(); press(); }
  });
  window.addEventListener('message', event => {
    if (event.data?.type === 'lockpick' && event.data.data && event.data.text) start(event.data.data, event.data.text);
    else if (event.data?.type === 'lockpickClose') stop();
  });
})();
