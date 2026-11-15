(() => {
  'use strict';
  // HUD de la vista en directo de una camara CCTV con la plantilla de camaras G6: logo arriba a la izquierda,
  // REC arriba a la derecha y el nombre de la camara abajo. Sin senal, pantalla NO VIDEO (gris, opaca) con el
  // motivo. La imagen es la camara del juego (client/live.lua); aqui solo se pinta lo de encima.
  const root = document.getElementById('live');
  if (!root) return;
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  const img = (src, className) => { const node = document.createElement('img'); node.src = src; node.alt = ''; node.className = className; return node; };
  let clock = null, helpTimer = null;
  const pad = value => String(value).padStart(2, '0');
  const stamp = () => { const d = new Date(); return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}  ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`; };

  function show(data, text) {
    clearInterval(clock); clearTimeout(helpTimer);
    root.replaceChildren();
    const noSignal = typeof data.noSignal === 'string' && data.noSignal !== '';
    root.classList.toggle('no-video', noSignal);
    const name = (typeof data.title === 'string' && data.title ? data.title : `${text.cam || 'CAMARA'} ${data.index || 1}${data.site ? ` - ${data.site}` : ''}`).toUpperCase();
    if (noSignal) {
      const center = el('div', null, 'live-novideo');
      center.append(img('live/novideo.png', 'live-novideo-img'), el('div', data.noSignal, 'live-reason'));
      root.append(center);
    } else {
      const noise = Math.max(0, Math.min(1, Number(data.noise) || 0));
      const staticLayer = el('span', null, 'live-static'); staticLayer.style.opacity = String(noise * 0.9);
      root.append(staticLayer);
      if (text.logo !== false) root.append(img('live/logo.png', 'live-logo'));
      const rec = el('div', null, 'live-rec'); rec.append(el('span', null, 'live-rec-dot'), el('span', text.rec || 'REC'));
      root.append(rec);
      if (noise > 0) root.append(el('div', text.noise || 'Senal degradada', 'live-warn'));
    }
    const label = el('div', null, 'live-label');
    label.append(el('div', name, 'live-name'));
    const time = el('div', stamp(), 'live-time');
    label.append(el('div', `${data.total > 1 ? `${data.index || 1}/${data.total} · ` : ''}${data.displayId || ''}`, 'live-id'));
    root.append(label, time);
    const help = el('div', data.help || text.help || '', 'live-help');
    root.append(help);
    helpTimer = setTimeout(() => help.classList.add('faded'), 7000);
    root.hidden = false;
    clock = setInterval(() => { time.textContent = stamp(); }, 1000);
  }
  function hide() { clearInterval(clock); clearTimeout(helpTimer); clock = helpTimer = null; root.hidden = true; root.classList.remove('no-video'); root.replaceChildren(); }

  window.addEventListener('message', event => {
    const message = event.data;
    if (message?.type !== 'live') return;
    if (message.action === 'show' && message.data) show(message.data, message.text || {});
    else if (message.action === 'hide') hide();
  });
})();
