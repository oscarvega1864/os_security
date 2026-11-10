(() => {
  'use strict';
  // Minijuego de instalacion en vehiculos (cierre centralizado o alarma), distinto del de pared:
  //   1. soltar las grapas del embellecedor bajo el volante: mantener y soltar con la tension justa,
  //   2. medir los cables del mazo con el multimetro y empalmar cada hilo del modulo en el suyo,
  //   3. probar el mando.
  // Solo interfaz: el resultado se envia al cliente y el servidor valida y cobra.
  const root = document.getElementById('carwire');
  if (!root) return;
  const NS = 'http://www.w3.org/2000/svg';
  const resource = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'os_security';
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  const svg = (tag, attrs = {}) => { const node = document.createElementNS(NS, tag); for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value)); return node; };
  const W = 400, H = 260, TOTAL = 3;
  const COLORS = ['red', 'black', 'green', 'white', 'yellow', 'blue', 'brown', 'purple'];
  // Hilos del modulo: cada uno va al cable del mazo que tiene su mismo nombre. El multimetro dice que es
  // cada cable (lectura y nombre); los demas cables del mazo son de otros sistemas del coche.
  const LEADS = {
    lock: [{ id: '12v', name: '+12V', reading: '12.6 V' }, { id: 'gnd', name: 'Masa', reading: '0 V con continuidad' }, { id: 'can', name: 'CAN', reading: '2.5 V de datos' }],
    alarm: [{ id: '12v', name: '+12V', reading: '12.6 V' }, { id: 'gnd', name: 'Masa', reading: '0 V con continuidad' }, { id: 'door', name: 'Puerta', reading: '12 V, cae al abrir' }],
    // Puente: unir la bateria (+12V) con el cable de la llave (contacto).
    hotwire: [{ id: 'bat', name: '+12V', reading: '12.6 V' }, { id: 'ign', name: 'Llave', reading: '0 V; 12 V al girar la llave' }]
  };
  const DECOYS = [{ name: 'Llave', reading: '12 V solo con contacto' }, { name: 'Sensor', reading: '5 V de referencia' },
    { name: 'Luz', reading: '0 V sin continuidad' }, { name: 'Bocina', reading: '0 V hasta pitar' }];
  let run = null; let runs = 0;

  function post(endpoint, body) {
    fetch(`https://${resource()}/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => {});
  }
  function stop() { if (run?.frame) cancelAnimationFrame(run.frame); run = null; root.hidden = true; root.replaceChildren(); }
  function finish(ok, reason) { if (!run) return; const endpoint = run.data.kind === 'hotwire' ? 'hotwire' : 'carwire'; stop(); post(endpoint, { ok, reason }); }
  const shuffled = list => { const copy = [...list]; for (let i = copy.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [copy[i], copy[j]] = [copy[j], copy[i]]; } return copy; };

  function shell(title, help, step) {
    root.replaceChildren();
    const panel = el('section', null, 'mg-panel');
    const head = el('header', null, 'mg-head');
    const overline = run.data.kind === 'hotwire' ? run.text.hotwireTitle : run.text.title;
    head.append(el('span', `${overline} · ${run.text.kinds[run.data.kind] || ''} · ${run.data.plate} · ${step}/${TOTAL}`, 'mg-overline'), el('h2', title), el('p', help, 'mg-help'));
    const board = svg('svg', { viewBox: `0 0 ${W} ${H}`, class: 'mg-board' });
    const meters = el('div', null, 'mg-meters');
    const foot = el('footer', null, 'mg-foot');
    const status = el('span', '', 'mg-status');
    const cancel = el('button', run.text.cancel, 'mg-cancel'); cancel.type = 'button'; cancel.addEventListener('click', () => finish(false, 'cancelled'));
    foot.append(status, cancel);
    panel.append(head, board, meters, foot); root.append(panel); root.hidden = false;
    return { board, meters, status };
  }
  function meter(container, label) {
    const wrap = el('div', null, 'mg-meter-wrap'); const bar = el('div', null, 'mg-meter'); const fill = el('span', null, 'mg-fill');
    bar.append(fill); wrap.append(el('small', label, 'mg-label'), bar); container.append(wrap);
    return value => { fill.style.width = `${Math.max(0, Math.min(1, value)) * 100}%`; fill.classList.toggle('hot', value > 0.9); };
  }
  function strikes(container, label) {
    const wrap = el('div', null, 'mg-strikes'); wrap.append(el('small', label, 'mg-label'));
    const dots = [0, 1, 2].map(() => el('span', null, 'mg-strike')); wrap.append(...dots); container.append(wrap);
    return count => dots.forEach((dot, index) => dot.classList.toggle('on', index < count));
  }
  function point(board, event) {
    const matrix = board.getScreenCTM(); if (!matrix) return { x: 0, y: 0 };
    const p = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse());
    return { x: p.x, y: p.y };
  }
  function loop(tick) {
    const id = run.id; let last = performance.now();
    const frame = now => { if (!run || run.id !== id) return; const dt = Math.min(0.1, (now - last) / 1000); last = now; if (tick(dt) !== false && run && run.id === id) run.frame = requestAnimationFrame(frame); };
    run.frame = requestAnimationFrame(frame);
  }
  const next = then => setTimeout(() => { if (run) then(); }, 400);

  // Fase 1: embellecedor bajo el volante con cuatro grapas. Mantener pulsado sube la tension; soltar en
  // la franja verde la saca. Pasarse la rompe (fallo); soltar antes no hace nada.
  const BAND = [0.6, 0.88];
  function trim() {
    const t = run.text;
    const hot = run.data.kind === 'hotwire';
    const { board, meters, status } = shell(hot ? t.coverTitle : t.trimTitle, hot ? t.coverHelp : t.trimHelp, 1);
    board.append(svg('path', { d: 'M 60 40 Q 200 10 340 40 L 360 220 Q 200 245 40 220 Z', class: 'cw-trim' }));
    board.append(svg('circle', { cx: 200, cy: 40, r: 34, class: 'cw-column' }));
    const clips = [[85, 80], [315, 80], [80, 195], [320, 195]].map(([x, y]) => {
      const node = svg('rect', { x: x - 14, y: y - 9, width: 28, height: 18, rx: 4, class: 'cw-clip' }); board.append(node);
      return { x, y, node, done: false };
    });
    const tension = meter(meters, t.tension); const showBroken = strikes(meters, t.broken);
    const band = el('div', null, 'cw-band'); band.style.left = `${BAND[0] * 100}%`; band.style.width = `${(BAND[1] - BAND[0]) * 100}%`;
    meters.querySelector('.mg-meter').append(band);
    const state = { active: null, value: 0, broken: 0 };
    board.addEventListener('pointerdown', event => {
      const p = point(board, event);
      state.active = clips.find(clip => !clip.done && Math.abs(clip.x - p.x) <= 20 && Math.abs(clip.y - p.y) <= 16) || null;
      if (state.active) { board.setPointerCapture?.(event.pointerId); state.value = 0; status.textContent = t.pulling; }
    });
    const release = () => {
      const clip = state.active; state.active = null;
      if (!clip) return;
      if (state.value >= BAND[0] && state.value <= BAND[1]) { clip.done = true; clip.node.classList.add('done'); status.textContent = t.clipOut; }
      else status.textContent = t.notEnough;
      state.value = 0;
    };
    board.addEventListener('pointerup', release); board.addEventListener('pointercancel', release);
    loop(dt => {
      if (state.active) {
        state.value += 0.75 * dt;
        if (state.value > 1) {
          const clip = state.active; state.active = null; state.value = 0;
          clip.done = true; clip.node.classList.add('broken'); state.broken++; showBroken(state.broken); status.textContent = t.clipBroken;
          if (state.broken >= 3) { finish(false, 'broken'); return false; }
        }
      }
      tension(state.value);
      if (clips.every(clip => clip.done)) { next(wiring); return false; }
    });
  }

  // Fase 2: mazo de seis cables. Pulsar un cable lo mide (lectura en el multimetro y bajo el cable);
  // arrastrar cada hilo del modulo hasta el cable cuya lectura corresponde. Equivocarse es un fallo.
  function wiring() {
    const t = run.text;
    const { board, meters, status } = shell(t.wireTitle, t.wireHelp, 2);
    const leads = LEADS[run.data.kind] || LEADS.lock;
    const names = new Set(leads.map(lead => lead.name));
    const decoys = Number.isInteger(run.data.decoys) ? run.data.decoys : 3;
    const readings = shuffled([...leads.map(lead => ({ name: lead.name, reading: lead.reading, lead: lead.id })),
      ...shuffled(DECOYS.filter(decoy => !names.has(decoy.name))).slice(0, decoys).map(decoy => ({ name: decoy.name, reading: decoy.reading, lead: null }))]);
    const colors = shuffled(COLORS);
    board.append(svg('rect', { x: 150, y: 14, width: 240, height: 34, rx: 6, class: 'cw-meter' }));
    const display = svg('text', { x: 270, y: 37, class: 'cw-display', 'text-anchor': 'middle' }); display.textContent = '--.- V'; board.append(display);
    const wires = readings.map((entry, i) => {
      const x = 170 + i * 38;
      const line = svg('line', { x1: x, y1: 60, x2: x, y2: 230, class: `cw-wire ${colors[i]}` }); board.append(line);
      const label = svg('text', { x, y: 248, class: 'cw-reading', 'text-anchor': 'middle' }); board.append(label);
      return { ...entry, x, line, label, probed: false, used: false };
    });
    board.append(svg('rect', { x: 14, y: 60, width: 110, height: 170, rx: 8, class: 'cw-module' }));
    const plugs = leads.map((lead, i) => {
      const y = 95 + i * 50;
      const node = svg('circle', { cx: 100, cy: y, r: 10, class: 'cw-lead' }); board.append(node);
      const name = svg('text', { x: 26, y: y + 4, class: 'cw-lead-label' }); name.textContent = lead.name; board.append(name);
      const cable = svg('path', { d: '', class: 'cw-lead-cable' }); board.insertBefore(cable, node);
      return { ...lead, x: 100, y, node, cable, done: false };
    });
    const showErrors = strikes(meters, t.shorts);
    let dragging = null, errors = 0;
    const nearWire = p => wires.find(wire => Math.abs(wire.x - p.x) <= 12 && p.y >= 60 && p.y <= 230);
    board.addEventListener('pointerdown', event => {
      const p = point(board, event);
      const plug = plugs.find(item => !item.done && Math.hypot(item.x - p.x, item.y - p.y) <= 16);
      if (plug) { board.setPointerCapture?.(event.pointerId); dragging = plug; return; }
      const wire = nearWire(p);
      if (wire) {
        wire.probed = true; display.textContent = `${wire.reading} → ${wire.name}`; wire.label.textContent = wire.name;
        status.textContent = `${t.probe}: ${wire.name} (${wire.reading})`;
      }
    });
    board.addEventListener('pointermove', event => {
      if (!dragging) return;
      const p = point(board, event);
      dragging.cable.setAttribute('d', `M ${dragging.x} ${dragging.y} C ${dragging.x + 40} ${dragging.y + 30}, ${p.x - 40} ${p.y + 30}, ${p.x} ${p.y}`);
    });
    board.addEventListener('pointerup', event => {
      if (!dragging) return;
      const plug = dragging; dragging = null;
      const p = point(board, event); const wire = nearWire(p);
      if (!wire || wire.used) { plug.cable.setAttribute('d', ''); return; }
      if (wire.lead === plug.id) {
        plug.done = wire.used = true; plug.node.classList.add('done'); wire.line.classList.add('spliced');
        plug.cable.setAttribute('d', `M ${plug.x} ${plug.y} C ${plug.x + 40} ${plug.y + 30}, ${wire.x - 40} ${p.y + 30}, ${wire.x} ${p.y}`);
        status.textContent = `${t.spliced}: ${plug.name}`;
        if (plugs.every(item => item.done)) next(run.data.kind === 'hotwire' ? starter : test);
      } else {
        plug.cable.setAttribute('d', ''); errors++; showErrors(errors); status.textContent = t.wrongWire;
        if (errors >= 3) finish(false, 'shorted');
      }
    });
  }

  // Fase 3: probar el mando; el LED del modulo parpadea y termina.
  // Puente, fase 3: dar al motor de arranque. Mantener pulsado sube la carga; soltar en la franja verde
  // arranca. Soltar antes no arranca; pasarse quema el fusible (fallo). La franja depende del nivel.
  function starter() {
    const t = run.text;
    const { board, meters, status } = shell(t.starterTitle, t.starterHelp, 3);
    const width = Math.max(0.08, Math.min(0.4, Number(run.data.band) || 0.2));
    const from = 0.5 + Math.random() * (0.38 - width);
    board.append(svg('rect', { x: 120, y: 70, width: 160, height: 120, rx: 14, class: 'cw-fob' }));
    const button = svg('circle', { cx: 200, cy: 130, r: 38, class: 'cw-button cw-start' }); board.append(button);
    const label = svg('text', { x: 200, y: 135, class: 'cw-start-label', 'text-anchor': 'middle' }); label.textContent = t.start; board.append(label);
    const charge = meter(meters, t.charge); const showFuses = strikes(meters, t.fuses);
    const band = el('div', null, 'cw-band'); band.style.left = `${from * 100}%`; band.style.width = `${width * 100}%`;
    meters.querySelector('.mg-meter').append(band);
    const state = { holding: false, value: 0, fuses: 0 };
    button.addEventListener('pointerdown', event => { board.setPointerCapture?.(event.pointerId); state.holding = true; state.value = 0; status.textContent = t.cranking; });
    const release = () => {
      if (!state.holding) return;
      state.holding = false;
      if (state.value >= from && state.value <= from + width) { status.textContent = t.started; charge(state.value); setTimeout(() => finish(true), 450); state.done = true; return; }
      status.textContent = t.noStart; state.value = 0;
    };
    board.addEventListener('pointerup', release); board.addEventListener('pointercancel', release);
    loop(dt => {
      if (state.done) return false;
      if (state.holding) {
        state.value += 0.62 * dt;
        if (state.value > 1) {
          state.holding = false; state.value = 0; state.fuses++; showFuses(state.fuses); status.textContent = t.fuse;
          if (state.fuses >= 3) { finish(false, 'fuse'); return false; }
        }
      }
      charge(state.value);
    });
  }

  function test() {
    const t = run.text;
    const { board, status } = shell(t.testTitle, t.testHelp, 3);
    board.append(svg('rect', { x: 150, y: 50, width: 100, height: 160, rx: 40, class: 'cw-fob' }));
    const led = svg('circle', { cx: 200, cy: 80, r: 7, class: 'cw-led' }); board.append(led);
    const button = svg('circle', { cx: 200, cy: 140, r: 24, class: 'cw-button' }); board.append(button);
    button.addEventListener('click', () => {
      led.classList.add('on'); status.textContent = t.works;
      setTimeout(() => finish(true), 600);
    }, { once: true });
  }

  window.addEventListener('keydown', event => { if (run && event.key === 'Escape') finish(false, 'cancelled'); });
  window.addEventListener('message', event => {
    if (event.data?.type === 'carwire' && event.data.text && event.data.data) {
      stop(); run = { id: ++runs, text: event.data.text, data: event.data.data };
      trim();
    } else if (event.data?.type === 'carwireClose') stop();
  });
})();
