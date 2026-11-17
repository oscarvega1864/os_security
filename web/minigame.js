(() => {
  'use strict';
  // Minijuego de instalacion CCTV con raton: taladrar agujeros, atornillar girando y enlazar cables.
  // Solo interfaz: decide si el cliente confirma o cancela la colocacion; el servidor valida el resto.
  const root = document.getElementById('minigame');
  const NS = 'http://www.w3.org/2000/svg';
  const resource = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'os_security';
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  const svg = (tag, attrs = {}) => { const node = document.createElementNS(NS, tag); for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value)); return node; };
  const W = 400, H = 260;
  let run = null; let runs = 0;

  function post(endpoint, body) {
    fetch(`https://${resource()}/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => {});
  }
  const fx = data => post('minigameFx', data);
  function stop() { if (run?.frame) cancelAnimationFrame(run.frame); run = null; root.hidden = true; root.replaceChildren(); }
  function finish(ok, reason) { if (!run) return; fx({ drilling: false }); stop(); post('minigame', { ok, reason }); }

  // Estructura comun: cabecera, superficie SVG, medidores y pie con estado y cancelar.
  function shell(title, help, step, total = 3) {
    root.replaceChildren();
    const panel = el('section', null, 'mg-panel');
    const head = el('header', null, 'mg-head');
    head.append(el('span', `${run.mode === 'remove' ? run.text.removeTitle : run.text.title} · ${step}/${total}`, 'mg-overline'), el('h2', title), el('p', help, 'mg-help'));
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
    return value => { fill.style.width = `${Math.max(0, Math.min(1, value)) * 100}%`; fill.classList.toggle('hot', value > 0.8); };
  }
  function strikes(container, label) {
    const wrap = el('div', null, 'mg-strikes'); wrap.append(el('small', label, 'mg-label'));
    const dots = [0, 1, 2].map(() => el('span', null, 'mg-strike')); wrap.append(...dots); container.append(wrap);
    return count => dots.forEach((dot, index) => dot.classList.toggle('on', index < count));
  }
  // Coordenadas del puntero dentro del SVG.
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
  // Variante 'detector' (arco detector de metales): dos postes con su placa de anclaje al suelo y el travesano.
  function plate(board) {
    if (run.variant === 'detector') {
      board.append(svg('rect', { x: 80, y: 30, width: 240, height: 22, rx: 6, class: 'mg-plate-inner' }));
      for (const x of [95, 285]) {
        board.append(svg('rect', { x, y: 40, width: 20, height: 160, rx: 4, class: 'mg-plate-inner' }));
        board.append(svg('rect', { x: x - 35, y: 195, width: 90, height: 40, rx: 8, class: 'mg-plate' }));
      }
      return;
    }
    board.append(svg('rect', { x: 70, y: 40, width: 260, height: 180, rx: 14, class: 'mg-plate' }));
    board.append(svg('rect', { x: 150, y: 95, width: 100, height: 70, rx: 8, class: 'mg-plate-inner' }));
  }
  function holes() {
    const base = run.variant === 'detector' ? [[75, 215], [135, 215], [265, 215], [325, 215]] : [[105, 75], [295, 75], [105, 185], [295, 185]];
    const jitter = run.variant === 'detector' ? 6 : 16;
    return base.map(([x, y]) => ({ x: x + (Math.random() * jitter - jitter / 2), y: y + (Math.random() * 8 - 4) }));
  }
  // Etiqueta del borne: la variante puede llamarlos de otra forma (sensores y zumbador del arco).
  const terminalOf = wire => run.text.terminals?.[wire.key] || wire.terminal;

  // Fase 1: mantener pulsado sobre cada marca hasta perforarla. La broca se calienta mientras
  // taladras y se enfria al soltar; si llega al maximo se rompe. Salirse de la marca es un resbalon.
  function drill() {
    run.phase = 'drill'; const t = run.text; fx({ phase: 'drill' });
    const { board, meters, status } = shell(t.drillTitle, t.drillHelp, 1);
    plate(board);
    const list = holes().map(hole => {
      const group = svg('g', { class: 'mg-hole' });
      const ring = svg('circle', { cx: hole.x, cy: hole.y, r: 15, class: 'mg-target' });
      const progress = svg('circle', { cx: hole.x, cy: hole.y, r: 15, class: 'mg-progress', 'stroke-dasharray': '0 999', transform: `rotate(-90 ${hole.x} ${hole.y})` });
      const bore = svg('circle', { cx: hole.x, cy: hole.y, r: 0, class: 'mg-bore' });
      group.append(ring, progress, bore); board.append(group);
      return { ...hole, done: 0, group, progress, bore };
    });
    const bit = svg('g', { class: 'mg-bit', visibility: 'hidden' });
    bit.append(svg('circle', { cx: 0, cy: 0, r: 6 }), svg('line', { x1: -12, y1: 0, x2: 12, y2: 0 }), svg('line', { x1: 0, y1: -12, x2: 0, y2: 12 }));
    board.append(bit);
    const heat = meter(meters, t.heat); const showSlips = strikes(meters, t.slips);
    const state = { heat: 0, slips: 0, active: null, pointer: null, holding: false };
    const setHolding = value => { if (state.holding !== value) fx({ drilling: value }); state.holding = value; };
    board.addEventListener('pointermove', event => {
      state.pointer = point(board, event);
      bit.setAttribute('visibility', 'visible'); bit.setAttribute('transform', `translate(${state.pointer.x} ${state.pointer.y})`);
    });
    board.addEventListener('pointerleave', () => bit.setAttribute('visibility', 'hidden'));
    board.addEventListener('pointerdown', event => {
      board.setPointerCapture?.(event.pointerId); state.pointer = point(board, event);
      state.active = list.find(hole => hole.done < 1 && Math.hypot(hole.x - state.pointer.x, hole.y - state.pointer.y) <= 13) || null;
      if (state.active) setHolding(true);
    });
    const release = () => { state.active = null; setHolding(false); };
    board.addEventListener('pointerup', release); board.addEventListener('pointercancel', release);
    loop(dt => {
      if (state.holding && state.active && state.pointer) {
        if (Math.hypot(state.active.x - state.pointer.x, state.active.y - state.pointer.y) > 13) {
          state.slips++; showSlips(state.slips); state.active.done = Math.max(0, state.active.done - 0.35); release();
          fx({ cue: 'miss' }); status.textContent = t.slip;
          if (state.slips >= 3) { finish(false, 'slipped'); return false; }
        } else {
          state.active.done = Math.min(1, state.active.done + 0.42 * dt);
          state.heat += 0.34 * dt; status.textContent = state.heat > 0.8 ? t.tooHot : t.drilling;
          if (state.heat > 0.8 && !state.hot) { state.hot = true; fx({ cue: 'hot' }); } // chispas: la broca se calienta
          if (state.active.done >= 1) { fx({ cue: 'hit' }); release(); status.textContent = t.holeDone; }
        }
      } else state.heat = Math.max(0, state.heat - 0.45 * dt);
      if (state.heat < 0.6) state.hot = false;
      heat(state.heat);
      for (const hole of list) {
        hole.progress.setAttribute('stroke-dasharray', `${(hole.done * 94.2).toFixed(1)} 999`);
        hole.bore.setAttribute('r', (hole.done * 7).toFixed(1)); hole.group.classList.toggle('done', hole.done >= 1);
      }
      if (state.heat >= 1) { finish(false, 'overheat'); return false; }
      if (list.every(hole => hole.done >= 1)) { setHolding(false); screw(list); return false; }
    });
  }

  // Fase 2: pulsar sobre un tornillo y girar el raton alrededor en sentido horario hasta apretarlo.
  // Girar demasiado deprisa sube la fuerza; mantenerla al maximo pasa la rosca.
  function screw(previous, mode) {
    run.phase = 'screw'; const t = run.text; fx({ phase: 'screw' });
    const removing = mode === 'remove', direction = removing ? -1 : 1;
    const { board, meters, status } = shell(removing ? t.unscrewTitle : t.screwTitle, removing ? t.unscrewHelp : t.screwHelp, removing ? 2 : 2, removing ? 2 : 3);
    plate(board);
    const TURNS = 3;
    const list = (previous || holes()).map(hole => {
      const group = svg('g', { class: 'mg-screw' });
      const ring = svg('circle', { cx: hole.x, cy: hole.y, r: 17, class: 'mg-progress', 'stroke-dasharray': '0 999', transform: `rotate(-90 ${hole.x} ${hole.y})` });
      const head = svg('circle', { cx: hole.x, cy: hole.y, r: 11, class: 'mg-screw-head' });
      const slot = svg('line', { x1: hole.x - 8, y1: hole.y, x2: hole.x + 8, y2: hole.y, class: 'mg-screw-slot' });
      group.append(ring, head, slot); board.append(group);
      return { x: hole.x, y: hole.y, angle: 0, group, ring, slot };
    });
    const torque = meter(meters, t.torque); const showStrips = strikes(meters, t.strips);
    const state = { active: null, last: null, force: 0, strips: 0, over: 0 };
    const angleOf = (hole, p) => Math.atan2(p.y - hole.y, p.x - hole.x) * 180 / Math.PI;
    board.addEventListener('pointerdown', event => {
      board.setPointerCapture?.(event.pointerId); const p = point(board, event);
      state.active = list.find(hole => hole.angle < TURNS * 360 && Math.hypot(hole.x - p.x, hole.y - p.y) <= 22) || null;
      state.last = state.active ? angleOf(state.active, p) : null;
      if (state.active) { status.textContent = t.turnHint; fx({ screwing: true }); }
    });
    board.addEventListener('pointermove', event => {
      if (!state.active) return;
      const p = point(board, event);
      if (Math.hypot(state.active.x - p.x, state.active.y - p.y) < 6) return; // demasiado cerca del centro: angulo inestable
      const angle = angleOf(state.active, p);
      let delta = angle - state.last; if (delta > 180) delta -= 360; if (delta < -180) delta += 360;
      state.last = angle;
      delta *= direction; // al desmontar cuenta el giro antihorario
      state.active.angle = Math.max(0, state.active.angle + delta);
      if (delta > 0) state.force = Math.min(1.2, state.force + delta / 260);
      if (state.active.angle >= TURNS * 360) { state.active.angle = TURNS * 360; fx({ cue: 'hit', screwing: false }); status.textContent = removing ? t.unscrewed : t.hit; state.active = null; }
    });
    const release = () => { if (state.active) fx({ screwing: false }); state.active = null; };
    board.addEventListener('pointerup', release); board.addEventListener('pointercancel', release);
    loop(dt => {
      state.force = Math.max(0, state.force - 1.1 * dt);
      if (state.force >= 1 && state.active) {
        state.over += dt;
        if (state.over > 0.35) {
          state.strips++; showStrips(state.strips); state.active.angle = 0; state.active = null; state.force = 0; state.over = 0;
          fx({ cue: 'miss', screwing: false }); status.textContent = t.stripped;
          if (state.strips >= 3) { finish(false, 'stripped'); return false; }
        } else status.textContent = t.tooStrong;
      } else state.over = 0;
      torque(state.force);
      for (const hole of list) {
        const ratio = hole.angle / (TURNS * 360);
        hole.ring.setAttribute('stroke-dasharray', `${(ratio * 106.8).toFixed(1)} 999`);
        hole.slot.setAttribute('transform', `rotate(${(direction * hole.angle) % 360} ${hole.x} ${hole.y})`);
        hole.group.classList.toggle('done', ratio >= 1);
      }
      if (list.every(hole => hole.angle >= TURNS * 360)) { if (removing) finish(true); else cables(); return false; }
    });
  }

  // Fase 3: arrastrar cada cable desde su conector hasta el borne del mismo color.
  // Cableado real de baja tension (alarmas y CCTV): cada color va a la senal de su borne segun el codigo
  // (rojo +12V, negro GND, verde A+, blanco B-, amarillo TAMPER). Como en la vida real los bornes no
  // tienen color, solo la etiqueta. Cuatro de los cinco cables, en orden y alturas aleatorias, y
  // cables que cuelgan (curvos), no en lineas rectas.
  const WIRES = [{ key: 'red', terminal: '+12V' }, { key: 'black', terminal: 'GND' }, { key: 'green', terminal: 'A+' },
    { key: 'white', terminal: 'B-' }, { key: 'yellow', terminal: 'TAMP' }];
  const shuffled = list => { const copy = [...list]; for (let i = copy.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [copy[i], copy[j]] = [copy[j], copy[i]]; } return copy; };
  // Alturas aleatorias sin solaparse: 4 de 5 franjas, con un pequeno desplazamiento dentro de cada una.
  const rowsFor = count => shuffled([0, 1, 2, 3, 4]).slice(0, count).sort((a, b) => a - b).map(i => 50 + i * 42 + (Math.random() * 14 - 7));
  const sagging = (a, b, sag) => `M ${a.x} ${a.y} C ${a.x + 70} ${a.y + sag}, ${b.x - 70} ${b.y + sag}, ${b.x} ${b.y}`;
  function cables() {
    run.phase = 'cables'; const t = run.text; fx({ phase: 'cables' });
    const { board, meters, status } = shell(t.cablesTitle, t.cablesHelp, 3);
    const wires = shuffled(WIRES).slice(0, 4);
    board.append(svg('rect', { x: 20, y: 20, width: 90, height: H - 40, rx: 10, class: 'mg-panel-box' }), svg('rect', { x: W - 110, y: 20, width: 90, height: H - 40, rx: 10, class: 'mg-panel-box' }));
    board.append(Object.assign(svg('text', { x: W / 2, y: 14, class: 'mg-wire-code', 'text-anchor': 'middle' }), { textContent: t.wireCode }));
    const layer = svg('g'); board.append(layer);
    const leftRows = rowsFor(wires.length), rightRows = rowsFor(wires.length);
    const sources = shuffled(wires).map((wire, i) => {
      const node = { ...wire, x: 70 + Math.random() * 25, y: leftRows[i], linked: false, sag: 25 + Math.random() * 45 };
      board.append(svg('path', { d: `M 20 ${node.y + 12} Q 45 ${node.y + 18} ${node.x} ${node.y}`, class: `mg-loose ${wire.key}` }));
      node.plug = svg('circle', { cx: node.x, cy: node.y, r: 9, class: `mg-plug ${wire.key}`, 'data-key': wire.key }); board.append(node.plug);
      return node;
    });
    const targets = shuffled(wires).map((wire, i) => {
      const node = { ...wire, x: W - 80, y: rightRows[i], linked: false };
      board.append(svg('rect', { x: W - 72, y: node.y - 10, width: 50, height: 20, rx: 3, class: 'mg-terminal' }));
      board.append(Object.assign(svg('text', { x: W - 47, y: node.y + 4, class: 'mg-terminal-label', 'text-anchor': 'middle' }), { textContent: terminalOf(wire) }));
      node.socket = svg('circle', { cx: node.x, cy: node.y, r: 10, class: 'mg-socket', 'data-key': wire.key }); board.append(node.socket);
      return node;
    });
    const showErrors = strikes(meters, t.shorts);
    let dragging = null, errors = 0, linked = 0;
    board.addEventListener('pointerdown', event => {
      const p = point(board, event);
      const source = sources.find(node => !node.linked && Math.hypot(node.x - p.x, node.y - p.y) <= 16);
      if (!source) return;
      board.setPointerCapture?.(event.pointerId);
      dragging = { source, path: svg('path', { d: sagging(source, p, source.sag), class: `mg-cable ${source.key}` }) };
      layer.append(dragging.path);
    });
    board.addEventListener('pointermove', event => { if (dragging) dragging.path.setAttribute('d', sagging(dragging.source, point(board, event), dragging.source.sag)); });
    board.addEventListener('pointerup', event => {
      if (!dragging) return;
      const p = point(board, event); const current = dragging; dragging = null;
      const target = targets.find(node => !node.linked && Math.hypot(node.x - p.x, node.y - p.y) <= 20);
      if (target && target.key === current.source.key) {
        current.path.setAttribute('d', sagging(current.source, target, current.source.sag)); current.path.classList.add('linked');
        current.source.linked = target.linked = true; target.socket.classList.add('linked', target.key); current.source.plug.classList.add('linked');
        linked++; fx({ cue: 'connected' }); status.textContent = `${t.connected}: ${terminalOf(target)}`;
        if (linked === wires.length) finish(true);
      } else {
        current.path.remove();
        if (target) {
          errors++; showErrors(errors); fx({ cue: 'wrong' }); status.textContent = t.wrongWire;
          if (errors >= 3) finish(false, 'shorted');
        }
      }
    });
  }

  // Desmontaje, fase 1: los cables estan conectados; arrastra cada uno desde su borne hasta la bandeja.
  function unplug() {
    run.phase = 'cables'; const t = run.text; fx({ phase: 'cables' });
    const { board, meters, status } = shell(t.unplugTitle, t.unplugHelp, 1, 2);
    board.append(svg('rect', { x: 20, y: 20, width: 90, height: H - 40, rx: 10, class: 'mg-tray' }), svg('rect', { x: W - 110, y: 20, width: 90, height: H - 40, rx: 10, class: 'mg-panel-box' }));
    board.append(Object.assign(svg('text', { x: 65, y: H / 2, class: 'mg-tray-label', 'text-anchor': 'middle' }), { textContent: '⇠' }));
    const layer = svg('g'); board.append(layer);
    const wires = shuffled(WIRES).slice(0, 4);
    const leftRows = rowsFor(wires.length), rightRows = rowsFor(wires.length);
    const curve = (a, b) => sagging(a, b, 40);
    const cables = wires.map((wire, i) => {
      const key = wire.key;
      const socket = { x: W - 80, y: rightRows[i] };
      const anchor = { x: 140, y: leftRows[i] };
      board.append(svg('rect', { x: W - 72, y: socket.y - 10, width: 50, height: 20, rx: 3, class: 'mg-terminal' }));
      board.append(Object.assign(svg('text', { x: W - 47, y: socket.y + 4, class: 'mg-terminal-label', 'text-anchor': 'middle' }), { textContent: terminalOf(wire) }));
      const path = svg('path', { d: curve(anchor, socket), class: `mg-cable linked ${key}` }); layer.append(path);
      const plug = svg('circle', { cx: socket.x, cy: socket.y, r: 10, class: `mg-plug ${key}`, 'data-key': key }); board.append(plug);
      return { key, socket, anchor, path, plug, out: false };
    });
    const showErrors = strikes(meters, t.shorts);
    let dragging = null, errors = 0, removed = 0;
    board.addEventListener('pointerdown', event => {
      const p = point(board, event);
      const cable = cables.find(item => !item.out && Math.hypot(item.socket.x - p.x, item.socket.y - p.y) <= 16);
      if (!cable) return;
      board.setPointerCapture?.(event.pointerId); dragging = cable;
    });
    board.addEventListener('pointermove', event => {
      if (!dragging) return;
      const p = point(board, event);
      dragging.path.setAttribute('d', curve(dragging.anchor, p)); dragging.plug.setAttribute('cx', p.x); dragging.plug.setAttribute('cy', p.y);
    });
    board.addEventListener('pointerup', event => {
      if (!dragging) return;
      const cable = dragging; dragging = null; const p = point(board, event);
      if (p.x <= 110) {
        cable.out = true; removed++; cable.path.remove(); cable.plug.remove(); fx({ cue: 'connected' }); status.textContent = t.unplugged;
        if (removed === cables.length) screw(null, 'remove');
        return;
      }
      cable.path.setAttribute('d', curve(cable.anchor, cable.socket)); cable.plug.setAttribute('cx', cable.socket.x); cable.plug.setAttribute('cy', cable.socket.y);
      if (cables.some(other => other !== cable && !other.out && Math.hypot(other.socket.x - p.x, other.socket.y - p.y) <= 16)) {
        errors++; showErrors(errors); fx({ cue: 'wrong' }); status.textContent = t.wrongWire;
        if (errors >= 3) finish(false, 'shorted');
      }
    });
  }

  // ---------------------------------------------------------------------------------------------------
  // Sustitucion en el sitio (variante 'swap'), distinta del montaje: 1) diagnosticar con el polimetro y marcar
  // lo averiado, 2) abrir el pestillo y sacar el modulo sin doblar los pines, 3) encajar el nuevo con la muesca
  // bien orientada y 4) repetir la secuencia del autotest de arranque. Tres errores en una fase: falla.
  const SW_STEPS = 4;
  const swapText = () => run.text.swap || {};
  const swapTitle = () => swapText().title || run.text.title;
  function swapShell(title, help, step) {
    const parts = shell(title, help, step, SW_STEPS);
    parts.board.parentElement.querySelector('.mg-overline').textContent = `${swapTitle()} · ${step}/${SW_STEPS}`;
    return parts;
  }
  function swapModules() {
    const list = Array.isArray(run.data?.modules) ? run.data.modules : [];
    const modules = list.slice(0, 4).map(m => ({ key: String(m.key || ''), label: String(m.label || m.key || ''), bad: m.bad === true }));
    if (!modules.length) modules.push({ key: 'power', label: 'alimentación', bad: true });
    if (!modules.some(m => m.bad)) modules[0].bad = true;
    return modules;
  }
  const BAD_READINGS = ['0,0 V', '3,1 V', '17,8 V', 'ERR', '0,4 V'];

  // Fase 1: medir cada modulo manteniendo el polimetro en su toma y marcar los que estan fuera de rango.
  function diagnose() {
    run.phase = 'diagnose'; const t = swapText(); fx({ phase: 'cables' });
    const { board, meters, status } = swapShell(t.diagnoseTitle, t.diagnoseHelp, 1);
    const modules = swapModules(); run.modules = modules;
    board.append(svg('rect', { x: 26, y: 24, width: W - 52, height: H - 48, rx: 14, class: 'mg-plate' }));
    const gap = 12, width = (W - 100 - gap * (modules.length - 1)) / modules.length;
    const cards = modules.map((module, index) => {
      const x = 50 + index * (width + gap), cx = x + width / 2;
      const group = svg('g', { class: 'sw-card' });
      const box = svg('rect', { x, y: 44, width, height: 170, rx: 10, class: 'sw-module' });
      const led = svg('circle', { cx, cy: 64, r: 6, class: 'sw-led' });
      const name = Object.assign(svg('text', { x: cx, y: 96, class: 'sw-name', 'text-anchor': 'middle' }), { textContent: module.label });
      const reading = Object.assign(svg('text', { x: cx, y: 130, class: 'sw-reading', 'text-anchor': 'middle' }), { textContent: '— V' });
      const pad = svg('circle', { cx, cy: 178, r: 13, class: 'sw-pad' });
      group.append(box, led, name, reading, pad); board.append(group);
      return { module, x, cx, width, group, box, reading, pad, measured: false, flagged: false, value: module.bad ? BAD_READINGS[Math.floor(Math.random() * BAD_READINGS.length)] : `${(11.8 + Math.random() * 0.4).toFixed(1).replace('.', ',')} V` };
    });
    const progress = meter(meters, t.progress); const showErrors = strikes(meters, t.mistakes);
    let holding = null, held = 0, errors = 0;
    const mistake = message => { errors++; showErrors(errors); fx({ cue: 'wrong' }); status.textContent = message; if (errors >= 3) finish(false, 'misdiagnosed'); };
    board.addEventListener('pointerdown', event => {
      const p = point(board, event);
      const onPad = cards.find(card => Math.hypot(card.cx - p.x, 178 - p.y) <= 16);
      if (onPad && !onPad.measured) { holding = onPad; held = 0; board.setPointerCapture?.(event.pointerId); status.textContent = t.measuring; return; }
      const card = cards.find(c => p.x >= c.x && p.x <= c.x + c.width && p.y >= 44 && p.y <= 160);
      if (!card || card.flagged) return;
      if (!card.measured) { status.textContent = t.measureFirst; return; }
      if (!card.module.bad) { mistake(t.wrongMark); return; }
      card.flagged = true; card.group.classList.add('flagged'); fx({ cue: 'connected' }); status.textContent = `${t.marked}: ${card.module.label}`;
      if (cards.filter(c => c.module.bad).every(c => c.flagged)) setTimeout(() => { if (run && run.phase === 'diagnose') extract(); }, 450);
    });
    const release = () => { if (holding && !holding.measured) { status.textContent = ''; progress(0); } holding = null; };
    board.addEventListener('pointerup', release); board.addEventListener('pointercancel', release);
    board.addEventListener('pointermove', event => {
      if (!holding) return; const p = point(board, event);
      if (Math.hypot(holding.cx - p.x, 178 - p.y) > 22) release();
    });
    loop(dt => {
      if (run.phase !== 'diagnose') return false;
      if (!holding) return;
      held += dt; progress(held / 0.9);
      if (held >= 0.9) {
        const card = holding; holding = null; card.measured = true; progress(0);
        card.reading.textContent = card.value; card.group.classList.add(card.module.bad ? 'bad' : 'good');
        status.textContent = card.module.bad ? t.outOfRange : t.inRange;
      }
    });
  }

  // Fase 2: abrir el pestillo y tirar del modulo hacia abajo; tirar rapido sube la tension y dobla los pines.
  function extract() {
    run.phase = 'extract'; const t = swapText(); fx({ phase: 'screw' });
    const { board, meters, status } = swapShell(t.extractTitle, t.extractHelp, 2);
    const bad = run.modules.filter(m => m.bad);
    const label = bad.length === run.modules.length && run.modules.length > 1 ? t.whole : bad[0].label;
    board.append(svg('rect', { x: 150, y: 16, width: 100, height: 232, rx: 10, class: 'mg-panel-box' }));
    board.append(svg('rect', { x: 165, y: 30, width: 70, height: 100, rx: 6, class: 'sw-slot' }));
    for (let i = 0; i < 5; i++) board.append(svg('line', { x1: 175 + i * 12, y1: 30, x2: 175 + i * 12, y2: 40, class: 'sw-pin' }));
    const START = 36, OUT = 120;
    const group = svg('g');
    const body = svg('rect', { x: 170, y: 0, width: 60, height: 88, rx: 6, class: 'sw-module sw-moving' });
    const name = Object.assign(svg('text', { x: 200, y: 50, class: 'sw-name', 'text-anchor': 'middle' }), { textContent: label });
    group.append(body, name); board.append(group);
    const latch = svg('rect', { x: 236, y: 52, width: 26, height: 14, rx: 3, class: 'sw-latch' }); board.append(latch);
    const tension = meter(meters, t.tension); const showErrors = strikes(meters, t.mistakes);
    let latchX = 0, offset = 0, drag = null, pressure = 0, over = 0, errors = 0, done = false;
    const place = () => { group.setAttribute('transform', `translate(0 ${START + offset})`); latch.setAttribute('x', 236 + latchX); };
    place();
    board.addEventListener('pointerdown', event => {
      const p = point(board, event);
      if (Math.abs(p.x - (249 + latchX)) <= 18 && Math.abs(p.y - 59) <= 14 && latchX < 30) { drag = { kind: 'latch', x: p.x, base: latchX }; }
      else if (p.x >= 165 && p.x <= 235 && p.y >= START + offset && p.y <= START + offset + 88) {
        if (latchX < 30) { status.textContent = t.latchFirst; return; }
        drag = { kind: 'module', y: p.y, base: offset, last: performance.now(), lastY: p.y };
      } else return;
      board.setPointerCapture?.(event.pointerId);
    });
    board.addEventListener('pointermove', event => {
      if (!drag || done) return; const p = point(board, event);
      if (drag.kind === 'latch') {
        latchX = Math.max(0, Math.min(30, drag.base + p.x - drag.x)); place();
        if (latchX >= 30) { drag = null; fx({ cue: 'connected' }); status.textContent = t.latchOpen; }
        return;
      }
      const now = performance.now(); const dt = Math.max(0.008, (now - drag.last) / 1000);
      const speed = Math.max(0, (p.y - drag.lastY) / dt); drag.last = now; drag.lastY = p.y;
      pressure = Math.max(pressure, Math.min(1, speed / 420));
      if (speed > 1400) { over = 1; return; } // tiron brusco: dobla los pines al momento (lo cuenta el bucle)
      offset = Math.max(0, Math.min(OUT, drag.base + p.y - drag.y)); place();
      if (offset >= OUT) { done = true; drag = null; fx({ cue: 'connected' }); status.textContent = t.extracted; setTimeout(() => { if (run && run.phase === 'extract') insert(); }, 450); }
    });
    const release = () => { drag = null; };
    board.addEventListener('pointerup', release); board.addEventListener('pointercancel', release);
    loop(dt => {
      if (run.phase !== 'extract') return false;
      if (done) return;
      pressure = Math.max(0, pressure - dt * 1.6); tension(pressure);
      over = over >= 1 ? over : (pressure > 0.85 && drag?.kind === 'module' ? over + dt : 0);
      if (over > 0.18) {
        errors++; showErrors(errors); fx({ cue: 'wrong' }); status.textContent = t.bent;
        drag = null; offset = 0; pressure = 0; over = 0; place();
        if (errors >= 3) { finish(false, 'bent'); return false; }
      }
    });
  }

  // Fase 3: el modulo nuevo llega girado; la rueda (o el boton) lo gira 90 grados y solo entra con la muesca arriba.
  function insert() {
    run.phase = 'insert'; const t = swapText(); fx({ phase: 'cables' });
    const { board, meters, status } = swapShell(t.insertTitle, t.insertHelp, 3);
    board.append(svg('rect', { x: 230, y: 16, width: 120, height: 232, rx: 10, class: 'mg-panel-box' }));
    const slot = svg('rect', { x: 255, y: 70, width: 70, height: 100, rx: 6, class: 'sw-slot' }); board.append(slot);
    board.append(svg('path', { d: 'M 282 70 L 290 80 L 298 70 Z', class: 'sw-notch-slot' }));
    board.append(svg('rect', { x: 30, y: 50, width: 150, height: 160, rx: 12, class: 'mg-tray' }));
    const HOME = { x: 105, y: 125 };
    let angle = 90 * (1 + Math.floor(Math.random() * 3)), pos = { ...HOME }, drag = null, errors = 0, done = false;
    const group = svg('g');
    group.append(svg('rect', { x: -32, y: -46, width: 64, height: 92, rx: 6, class: 'sw-module sw-new' }), svg('path', { d: 'M -8 -46 L 0 -36 L 8 -46 Z', class: 'sw-notch' }));
    board.append(group);
    const turn = svg('g', { class: 'sw-rotate' });
    turn.append(svg('circle', { cx: 105, cy: 232, r: 13 }), Object.assign(svg('text', { x: 105, y: 237, 'text-anchor': 'middle' }), { textContent: t.rotate || '⟳' }));
    board.append(turn);
    const showErrors = strikes(meters, t.mistakes);
    const place = () => group.setAttribute('transform', `translate(${pos.x} ${pos.y}) rotate(${angle})`);
    const rotate = step => { if (done || drag) return; angle = (angle + step + 360) % 360; place(); fx({ cue: 'connected' }); };
    place();
    board.addEventListener('wheel', event => { event.preventDefault(); rotate(event.deltaY > 0 ? 90 : -90); }, { passive: false });
    board.addEventListener('pointerdown', event => {
      if (done) return; const p = point(board, event);
      if (Math.hypot(p.x - 105, p.y - 232) <= 15) { rotate(90); return; }
      if (Math.abs(p.x - pos.x) <= 40 && Math.abs(p.y - pos.y) <= 50) { drag = { dx: p.x - pos.x, dy: p.y - pos.y }; board.setPointerCapture?.(event.pointerId); }
    });
    board.addEventListener('pointermove', event => { if (!drag) return; const p = point(board, event); pos = { x: p.x - drag.dx, y: p.y - drag.dy }; place(); });
    board.addEventListener('pointerup', () => {
      if (!drag) return; drag = null;
      const inSlot = Math.abs(pos.x - 290) <= 30 && Math.abs(pos.y - 120) <= 40;
      if (!inSlot) return;
      if (angle % 360 !== 0) {
        errors++; showErrors(errors); fx({ cue: 'wrong' }); status.textContent = t.notch; pos = { ...HOME }; place();
        if (errors >= 3) finish(false, 'notch');
        return;
      }
      done = true; pos = { x: 290, y: 120 }; place(); slot.classList.add('filled'); fx({ cue: 'connected' }); status.textContent = t.inserted;
      setTimeout(() => { if (run && run.phase === 'insert') selftest(); }, 450);
    });
  }

  // Fase 4 (accesible): se enciende un piloto y se queda encendido hasta pulsarlo; despues el siguiente.
  // Sin memoria, sin tiempo y sin errores: pulsar otro solo recuerda cual es. Cada piloto lleva numero y color.
  function selftest() {
    run.phase = 'selftest'; const t = swapText(); fx({ phase: 'cables' });
    const { board, meters, status } = swapShell(t.testTitle, t.testHelp, 4);
    const id = run.id;
    board.append(svg('rect', { x: 40, y: 50, width: W - 80, height: 170, rx: 14, class: 'mg-plate' }));
    const colors = ['red', 'green', 'blue', 'yellow'];
    const names = Array.isArray(t.colorNames) ? t.colorNames : ['Rojo', 'Verde', 'Azul', 'Amarillo'];
    const leds = colors.map((color, index) => {
      const cx = 100 + index * 67;
      const node = svg('circle', { cx, cy: 120, r: 27, class: `sw-test ${color}` });
      board.append(node, Object.assign(svg('text', { x: cx, y: 127, class: 'sw-test-number', 'text-anchor': 'middle' }), { textContent: String(index + 1) }),
        Object.assign(svg('text', { x: cx, y: 175, class: 'sw-test-name', 'text-anchor': 'middle' }), { textContent: names[index] || '' }));
      return node;
    });
    const total = run.modules.filter(m => m.bad).length > 1 ? 4 : 3;
    const progress = meter(meters, t.progressTest || t.progress);
    let step = 0, current = -1;
    const next = () => {
      leds.forEach(led => led.classList.remove('lit'));
      let index; do { index = Math.floor(Math.random() * leds.length); } while (index === current);
      current = index; leds[index].classList.add('lit');
      status.textContent = `${t.pressLit} ${index + 1} (${names[index] || ''})`;
    };
    board.addEventListener('pointerdown', event => {
      if (current < 0) return; const p = point(board, event);
      const index = leds.findIndex((_, i) => Math.hypot(100 + i * 67 - p.x, 120 - p.y) <= 32);
      if (index < 0) return;
      if (index !== current) { status.textContent = `${t.wrongLed} ${current + 1} (${names[current] || ''})`; return; }
      step++; progress(step / total); fx({ cue: 'connected' });
      if (step >= total) {
        leds.forEach(led => led.classList.add('lit')); current = -1; status.textContent = t.passed;
        setTimeout(() => { if (run && run.id === id) finish(true); }, 700);
      } else next();
    });
    next();
  }

  window.addEventListener('keydown', event => { if (run && event.key === 'Escape') finish(false, 'cancelled'); });
  window.addEventListener('message', event => {
    if (event.data?.type === 'minigame' && event.data.text) {
      const variant = ['detector', 'swap'].includes(event.data.variant) ? event.data.variant : 'cctv';
      stop(); run = { id: ++runs, text: event.data.text, mode: event.data.mode === 'remove' ? 'remove' : 'install', variant, data: event.data.data || null };
      if (variant === 'swap') diagnose(); else if (run.mode === 'remove') unplug(); else drill();
    }
    else if (event.data?.type === 'minigameClose') stop();
  });
})();
