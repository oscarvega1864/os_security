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
  function plate(board) {
    board.append(svg('rect', { x: 70, y: 40, width: 260, height: 180, rx: 14, class: 'mg-plate' }));
    board.append(svg('rect', { x: 150, y: 95, width: 100, height: 70, rx: 8, class: 'mg-plate-inner' }));
  }
  function holes() {
    const base = [[105, 75], [295, 75], [105, 185], [295, 185]];
    return base.map(([x, y]) => ({ x: x + (Math.random() * 16 - 8), y: y + (Math.random() * 12 - 6) }));
  }

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
          if (state.active.done >= 1) { fx({ cue: 'hit' }); release(); status.textContent = t.holeDone; }
        }
      } else state.heat = Math.max(0, state.heat - 0.45 * dt);
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
      if (state.active) status.textContent = t.turnHint;
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
      if (state.active.angle >= TURNS * 360) { state.active.angle = TURNS * 360; fx({ cue: 'hit' }); status.textContent = removing ? t.unscrewed : t.hit; state.active = null; }
    });
    const release = () => { state.active = null; };
    board.addEventListener('pointerup', release); board.addEventListener('pointercancel', release);
    loop(dt => {
      state.force = Math.max(0, state.force - 1.1 * dt);
      if (state.force >= 1 && state.active) {
        state.over += dt;
        if (state.over > 0.35) {
          state.strips++; showStrips(state.strips); state.active.angle = 0; state.active = null; state.force = 0; state.over = 0;
          fx({ cue: 'miss' }); status.textContent = t.stripped;
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
      board.append(Object.assign(svg('text', { x: W - 47, y: node.y + 4, class: 'mg-terminal-label', 'text-anchor': 'middle' }), { textContent: wire.terminal }));
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
        linked++; fx({ cue: 'connected' }); status.textContent = `${t.connected}: ${target.terminal}`;
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
      board.append(Object.assign(svg('text', { x: W - 47, y: socket.y + 4, class: 'mg-terminal-label', 'text-anchor': 'middle' }), { textContent: wire.terminal }));
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

  window.addEventListener('keydown', event => { if (run && event.key === 'Escape') finish(false, 'cancelled'); });
  window.addEventListener('message', event => {
    if (event.data?.type === 'minigame' && event.data.text) {
      stop(); run = { id: ++runs, text: event.data.text, mode: event.data.mode === 'remove' ? 'remove' : 'install' };
      if (run.mode === 'remove') unplug(); else drill();
    }
    else if (event.data?.type === 'minigameClose') stop();
  });
})();
