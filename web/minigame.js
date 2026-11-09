(() => {
  'use strict';
  // Minijuego de instalacion CCTV: taladrar, atornillar y conectar cables. Solo interfaz.
  const root = document.getElementById('minigame');
  const resource = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'os_security';
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  let run = null; // { id, text, phase, frame, ... }
  let runs = 0;

  function report(result) {
    fetch(`https://${resource()}/minigame`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(result) }).catch(() => {});
  }
  function fx(data) {
    fetch(`https://${resource()}/minigameFx`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) }).catch(() => {});
  }
  function stop() { if (run?.frame) cancelAnimationFrame(run.frame); run = null; root.hidden = true; root.replaceChildren(); }
  function finish(ok, reason) { if (!run) return; stop(); report({ ok, reason }); }
  function shell(title, help, step) {
    root.replaceChildren();
    const panel = el('section', null, 'mg-panel');
    const head = el('header', null, 'mg-head');
    head.append(el('span', `${run.text.title} · ${step}/3`, 'mg-overline'), el('h2', title), el('p', help, 'mg-help'));
    const body = el('div', null, 'mg-body');
    const foot = el('footer', null, 'mg-foot');
    const status = el('span', '', 'mg-status');
    const cancel = el('button', run.text.cancel, 'mg-cancel'); cancel.type = 'button'; cancel.addEventListener('click', () => finish(false, 'cancelled'));
    foot.append(status, cancel);
    panel.append(head, body, foot); root.append(panel); root.hidden = false;
    return { body, status };
  }
  function loop(tick) {
    const id = run.id; let last = performance.now();
    const frame = now => { if (!run || run.id !== id) return; const dt = Math.min(0.1, (now - last) / 1000); last = now; if (tick(dt) !== false && run && run.id === id) run.frame = requestAnimationFrame(frame); };
    run.frame = requestAnimationFrame(frame);
  }

  // Fase 1: mantener ESPACIO (o el boton) con la temperatura en la franja verde hasta perforar.
  function drill() {
    run.phase = 'drill'; const t = run.text; fx({ phase: 'drill' });
    const { body, status } = shell(t.drillTitle, t.drillHelp, 1);
    const heatBar = el('div', null, 'mg-meter'); const band = el('span', null, 'mg-band'); const heat = el('span', null, 'mg-fill heat'); heatBar.append(band, heat);
    const progressBar = el('div', null, 'mg-meter'); const progress = el('span', null, 'mg-fill progress'); progressBar.append(progress);
    const hold = el('button', t.drillAction, 'mg-hold'); hold.type = 'button';
    body.append(el('small', t.heat, 'mg-label'), heatBar, el('small', t.progress, 'mg-label'), progressBar, hold);
    const low = 0.55, high = 0.8; band.style.left = `${low * 100}%`; band.style.width = `${(high - low) * 100}%`;
    const state = { heat: 0, done: 0, holding: false };
    run.hold = value => { if (state.holding !== value) fx({ drilling: value }); state.holding = value; hold.classList.toggle('active', value); };
    hold.addEventListener('pointerdown', () => run.hold(true)); hold.addEventListener('pointerup', () => run.hold(false)); hold.addEventListener('pointerleave', () => run.hold(false));
    loop(dt => {
      state.heat = Math.max(0, state.heat + (state.holding ? 0.42 : -0.32) * dt);
      const inBand = state.heat >= low && state.heat <= high;
      if (state.holding && inBand) state.done = Math.min(1, state.done + 0.24 * dt);
      heat.style.width = `${Math.min(1, state.heat) * 100}%`; heat.classList.toggle('hot', state.heat > high);
      progress.style.width = `${state.done * 100}%`;
      status.textContent = state.heat > high ? t.tooHot : inBand && state.holding ? t.drilling : '';
      if (state.heat >= 1) { finish(false, 'overheat'); return false; }
      if (state.done >= 1) { fx({ drilling: false }); run.hold = null; screw(); return false; }
    });
  }

  // Fase 2: pulsar ESPACIO (o el boton) con el cursor dentro de la zona verde. 3 aciertos; 3 fallos cancelan.
  function screw() {
    run.phase = 'screw'; const t = run.text; fx({ phase: 'screw' });
    const { body, status } = shell(t.screwTitle, t.screwHelp, 2);
    const track = el('div', null, 'mg-track'); const zone = el('span', null, 'mg-zone'); const cursor = el('span', null, 'mg-cursor'); track.append(zone, cursor);
    const screws = el('div', null, 'mg-screws');
    const press = el('button', t.screwAction, 'mg-hold'); press.type = 'button';
    body.append(track, screws, press);
    const state = { pos: 0, dir: 1, speed: 0.75, hits: 0, misses: 0, start: 0, width: 0.16 };
    const place = () => { state.start = 0.1 + Math.random() * (0.9 - state.width - 0.1); zone.style.left = `${state.start * 100}%`; zone.style.width = `${state.width * 100}%`; };
    const draw = () => { screws.replaceChildren(...[0, 1, 2].map(i => el('span', null, `mg-screw${i < state.hits ? ' done' : ''}`))); };
    place(); draw();
    run.press = () => {
      if (state.pos >= state.start && state.pos <= state.start + state.width) {
        fx({ cue: 'hit' }); state.hits++; state.speed += 0.2; state.width = Math.max(0.1, state.width - 0.02); status.textContent = t.hit; draw(); place();
        if (state.hits >= 3) { run.press = null; cables(); }
      } else {
        fx({ cue: 'miss' }); state.misses++; status.textContent = `${t.miss} (${state.misses}/3)`;
        if (state.misses >= 3) finish(false, 'stripped');
      }
    };
    press.addEventListener('click', () => run?.press?.());
    loop(dt => {
      state.pos += state.dir * state.speed * dt;
      if (state.pos >= 1) { state.pos = 1; state.dir = -1; } else if (state.pos <= 0) { state.pos = 0; state.dir = 1; }
      cursor.style.left = `${state.pos * 100}%`;
      if (run.phase !== 'screw') return false;
    });
  }

  // Fase 3: unir cada cable con su borne del mismo color. 3 errores cancelan.
  function cables() {
    run.phase = 'cables'; const t = run.text; fx({ phase: 'cables' });
    const { body, status } = shell(t.cablesTitle, t.cablesHelp, 3);
    const colors = t.colors.map((name, i) => ({ name, key: ['red', 'blue', 'yellow', 'green'][i] }));
    const terminals = [...colors].sort(() => Math.random() - 0.5);
    const board = el('div', null, 'mg-board'); const left = el('div', null, 'mg-column'); const right = el('div', null, 'mg-column');
    board.append(left, right); body.append(board);
    let selected = null, connected = 0, errors = 0;
    const leftButtons = colors.map(color => {
      const b = el('button', color.name, `mg-wire ${color.key}`); b.type = 'button';
      b.addEventListener('click', () => { if (b.disabled) return; selected = color; leftButtons.forEach(x => x.classList.remove('selected')); b.classList.add('selected'); });
      left.append(b); return b;
    });
    terminals.forEach(color => {
      const b = el('button', null, 'mg-terminal'); b.type = 'button'; b.append(el('span', null, `mg-dot ${color.key}`));
      b.addEventListener('click', () => {
        if (!selected || b.disabled) return;
        if (selected.key === color.key) {
          b.disabled = true; b.classList.add('done', color.key);
          const source = leftButtons[colors.indexOf(selected)]; source.disabled = true; source.classList.remove('selected'); source.classList.add('done');
          fx({ cue: 'connected' }); selected = null; connected++; status.textContent = t.connected;
          if (connected === colors.length) finish(true);
        } else {
          fx({ cue: 'wrong' }); errors++; status.textContent = `${t.wrongWire} (${errors}/3)`;
          if (errors >= 3) finish(false, 'shorted');
        }
      });
      right.append(b);
    });
  }

  window.addEventListener('keydown', event => {
    if (!run) return;
    if (event.key === 'Escape') { finish(false, 'cancelled'); return; }
    if (event.code === 'Space' && !event.repeat) { event.preventDefault(); if (run.phase === 'drill') run.hold?.(true); else if (run.phase === 'screw') run.press?.(); }
  });
  window.addEventListener('keyup', event => { if (run && event.code === 'Space' && run.phase === 'drill') run.hold?.(false); });
  window.addEventListener('message', event => {
    if (event.data?.type === 'minigame' && event.data.text) { stop(); run = { id: ++runs, text: event.data.text }; drill(); }
    else if (event.data?.type === 'minigameClose') stop();
  });
})();
