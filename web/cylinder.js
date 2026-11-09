(() => {
  'use strict';
  // Minijuego de cambio de bombin (cerraduras de puertas), con raton:
  //   1. quitar el tornillo de fijacion del canto (giro antihorario sin pasarse de fuerza),
  //   2. sacar el bombin viejo: girar la llave hasta dejar la leva arriba y arrastrarlo fuera,
  //   3. meter el nuevo: alinear su leva y empujarlo dentro,
  //   4. apretar el tornillo (giro horario).
  // Solo interfaz: el resultado se envia al cliente y el servidor valida y cobra.
  const root = document.getElementById('cylinder');
  if (!root) return;
  const NS = 'http://www.w3.org/2000/svg';
  const resource = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'os_security';
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  const svg = (tag, attrs = {}) => { const node = document.createElementNS(NS, tag); for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value)); return node; };
  const W = 400, H = 260, TOTAL = 4;
  const HOLE = { x: 215, y: 112, length: 150, height: 36 }; // canal del bombin en el cuerpo de la cerradura
  const SCREW = { x: 290, y: 190 };
  const ALIGN = 12; // grados de tolerancia de la leva
  let run = null; let runs = 0;

  function post(endpoint, body) {
    fetch(`https://${resource()}/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => {});
  }
  const fx = data => post('cylinderFx', data);
  function stop() { if (run?.frame) cancelAnimationFrame(run.frame); run = null; root.hidden = true; root.replaceChildren(); }
  function finish(ok, reason) { if (!run) return; stop(); post('cylinder', { ok, reason }); }

  function shell(title, help, step) {
    root.replaceChildren();
    const panel = el('section', null, 'mg-panel');
    const head = el('header', null, 'mg-head');
    head.append(el('span', `${run.text.title} · ${run.data.from} → ${run.data.to} · ${step}/${TOTAL}`, 'mg-overline'), el('h2', title), el('p', help, 'mg-help'));
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
  // Puerta vista de canto: hoja, cuerpo de la cerradura y canal del bombin.
  function door(board) {
    board.append(svg('rect', { x: 190, y: 24, width: 196, height: 212, rx: 6, class: 'mg-plate' }));
    board.append(svg('rect', { x: 205, y: 70, width: 170, height: 150, rx: 6, class: 'mg-plate-inner' }));
    board.append(svg('rect', { x: HOLE.x, y: HOLE.y - 4, width: HOLE.length, height: HOLE.height + 8, rx: 4, class: 'cy-channel' }));
  }

  // Tornillo de fijacion: removing = antihorario hasta sacarlo; si no, horario hasta apretarlo.
  function screw(removing, step, then) {
    const t = run.text; fx({ phase: 'screw' });
    const { board, meters, status } = shell(removing ? t.unscrewTitle : t.screwTitle, removing ? t.unscrewHelp : t.screwHelp, step);
    door(board);
    if (!removing) drawCylinder(board, 0, true, 0);
    const TURNS = 2, direction = removing ? -1 : 1;
    const ring = svg('circle', { cx: SCREW.x, cy: SCREW.y, r: 17, class: 'mg-progress', 'stroke-dasharray': '0 999', transform: `rotate(-90 ${SCREW.x} ${SCREW.y})` });
    const head = svg('circle', { cx: SCREW.x, cy: SCREW.y, r: 11, class: 'mg-screw-head' });
    const slot = svg('line', { x1: SCREW.x - 8, y1: SCREW.y, x2: SCREW.x + 8, y2: SCREW.y, class: 'mg-screw-slot' });
    const group = svg('g', { class: 'mg-screw cy-screw' }); group.append(ring, head, slot); board.append(group);
    const torque = meter(meters, t.torque); const showStrips = strikes(meters, t.strips);
    const state = { active: false, last: 0, angle: 0, force: 0, strips: 0, over: 0 };
    const angleOf = p => Math.atan2(p.y - SCREW.y, p.x - SCREW.x) * 180 / Math.PI;
    board.addEventListener('pointerdown', event => {
      const p = point(board, event);
      if (Math.hypot(SCREW.x - p.x, SCREW.y - p.y) > 24) return;
      board.setPointerCapture?.(event.pointerId); state.active = true; state.last = angleOf(p); status.textContent = t.turnHint;
    });
    board.addEventListener('pointermove', event => {
      if (!state.active) return;
      const p = point(board, event);
      if (Math.hypot(SCREW.x - p.x, SCREW.y - p.y) < 6) return;
      const angle = angleOf(p);
      let delta = angle - state.last; if (delta > 180) delta -= 360; if (delta < -180) delta += 360;
      state.last = angle; delta *= direction;
      state.angle = Math.max(0, state.angle + delta);
      if (delta > 0) state.force = Math.min(1.2, state.force + delta / 260);
    });
    const release = () => { state.active = false; };
    board.addEventListener('pointerup', release); board.addEventListener('pointercancel', release);
    loop(dt => {
      state.force = Math.max(0, state.force - 1.1 * dt);
      if (state.force >= 1 && state.active) {
        state.over += dt;
        if (state.over > 0.35) {
          state.strips++; showStrips(state.strips); state.angle = 0; state.active = false; state.force = 0; state.over = 0;
          fx({ cue: 'miss' }); status.textContent = t.stripped;
          if (state.strips >= 3) { finish(false, 'stripped'); return false; }
        } else status.textContent = t.tooStrong;
      } else state.over = 0;
      torque(state.force);
      const ratio = Math.min(1, state.angle / (TURNS * 360));
      ring.setAttribute('stroke-dasharray', `${(ratio * 106.8).toFixed(1)} 999`);
      slot.setAttribute('transform', `rotate(${(direction * state.angle) % 360} ${SCREW.x} ${SCREW.y})`);
      if (ratio >= 1) { fx({ cue: 'hit' }); status.textContent = removing ? t.screwOut : t.done; group.classList.add('done'); setTimeout(() => { if (run) then(); }, 350); return false; }
    });
  }

  // Bombin dibujado con su desplazamiento (0 = dentro) y la leva en 'cam' grados (0 = arriba).
  function drawCylinder(board, offset, fresh, cam) {
    const group = svg('g', { class: `cy-cylinder${fresh ? ' fresh' : ''}` });
    const body = svg('rect', { x: HOLE.x, y: HOLE.y, width: HOLE.length, height: HOLE.height, rx: 8, class: 'cy-body' });
    const keyHead = svg('circle', { cx: HOLE.x - 18, cy: HOLE.y + HOLE.height / 2, r: 16, class: 'cy-key' });
    const keyBlade = svg('rect', { x: HOLE.x - 6, y: HOLE.y + HOLE.height / 2 - 3, width: 40, height: 6, rx: 2, class: 'cy-blade' });
    const camCenter = { x: HOLE.x + HOLE.length / 2, y: HOLE.y + HOLE.height / 2 };
    const lever = svg('line', { x1: camCenter.x, y1: camCenter.y, x2: camCenter.x, y2: camCenter.y - 30, class: 'cy-cam' });
    const hub = svg('circle', { cx: camCenter.x, cy: camCenter.y, r: 7, class: 'cy-hub' });
    group.append(body, keyBlade, keyHead, lever, hub); board.append(group);
    const render = (dx, angle) => {
      group.setAttribute('transform', `translate(${dx} 0)`);
      lever.setAttribute('transform', `rotate(${angle} ${camCenter.x} ${camCenter.y})`);
      lever.classList.toggle('aligned', aligned(angle));
    };
    render(offset, cam);
    return { render, key: { x: HOLE.x - 18, y: HOLE.y + HOLE.height / 2 } };
  }
  const normalize = angle => ((angle % 360) + 540) % 360 - 180;
  const aligned = angle => Math.abs(normalize(angle)) <= ALIGN;

  // Sacar (out) o meter (in) el bombin: la leva debe estar arriba para que pase por el canal.
  function slide(direction, step, then) {
    const t = run.text; fx({ phase: 'cables' });
    const out = direction === 'out';
    const { board, meters, status } = shell(out ? t.outTitle : t.inTitle, out ? t.outHelp : t.inHelp, step);
    door(board);
    const START = out ? 0 : -165, GOAL = out ? -150 : 0;
    const state = { offset: START, cam: 40 + Math.random() * 280, mode: null, last: 0, grab: 0, jams: 0 };
    const cylinder = drawCylinder(board, state.offset, !out, state.cam);
    const showJams = strikes(meters, t.jams);
    const keyAt = () => ({ x: cylinder.key.x + state.offset, y: cylinder.key.y });
    const angleOf = p => { const k = keyAt(); return Math.atan2(p.y - k.y, p.x - k.x) * 180 / Math.PI; };
    board.addEventListener('pointerdown', event => {
      const p = point(board, event); const k = keyAt();
      if (Math.hypot(k.x - p.x, k.y - p.y) <= 26) { state.mode = 'turn'; state.last = angleOf(p); }
      else if (p.x >= HOLE.x + state.offset && p.x <= HOLE.x + HOLE.length + state.offset && Math.abs(p.y - (HOLE.y + HOLE.height / 2)) <= 26) {
        state.mode = 'slide'; state.grab = p.x - state.offset;
      } else return;
      board.setPointerCapture?.(event.pointerId);
    });
    board.addEventListener('pointermove', event => {
      if (!state.mode) return;
      const p = point(board, event);
      if (state.mode === 'turn') {
        const k = keyAt(); if (Math.hypot(k.x - p.x, k.y - p.y) < 6) return;
        const angle = angleOf(p);
        let delta = angle - state.last; if (delta > 180) delta -= 360; if (delta < -180) delta += 360;
        state.last = angle; state.cam += delta;
        status.textContent = aligned(state.cam) ? t.aligned : '';
        return;
      }
      const wanted = Math.max(-165, Math.min(0, p.x - state.grab));
      if (Math.abs(wanted - state.offset) < 0.5) return;
      if (!aligned(state.cam)) {
        state.jams++; showJams(state.jams); state.mode = null; fx({ cue: 'wrong' }); status.textContent = t.jammed;
        if (state.jams >= 3) finish(false, 'jammed');
        return;
      }
      state.offset = wanted;
    });
    const release = () => { state.mode = null; };
    board.addEventListener('pointerup', release); board.addEventListener('pointercancel', release);
    loop(() => {
      cylinder.render(state.offset, state.cam);
      const reached = out ? state.offset <= GOAL + 4 : state.offset >= GOAL - 4;
      if (reached) { fx({ cue: 'connected' }); status.textContent = out ? t.cylinderOut : t.cylinderIn; setTimeout(() => { if (run) then(); }, 350); return false; }
    });
  }

  window.addEventListener('keydown', event => { if (run && event.key === 'Escape') finish(false, 'cancelled'); });
  window.addEventListener('message', event => {
    if (event.data?.type === 'cylinder' && event.data.text && event.data.data) {
      stop(); run = { id: ++runs, text: event.data.text, data: event.data.data };
      screw(true, 1, () => slide('out', 2, () => slide('in', 3, () => screw(false, 4, () => finish(true)))));
    } else if (event.data?.type === 'cylinderClose') stop();
  });
})();
