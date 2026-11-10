(() => {
  'use strict';
  // HUD de la vista en directo de una camara CCTV: esquinas, REC, fecha y hora, camara, sitio, ayuda,
  // lineas de barrido y estatica segun el ruido de la senal. La imagen es la camara del juego (client/live.lua).
  const root = document.getElementById('live');
  if (!root) return;
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  let clock = null;
  const pad = value => String(value).padStart(2, '0');
  const stamp = () => { const d = new Date(); return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}  ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`; };

  function show(data, text) {
    clearInterval(clock);
    root.replaceChildren();
    const noise = Math.max(0, Math.min(1, Number(data.noise) || 0));
    const staticLayer = el('span', null, 'live-static'); staticLayer.style.opacity = String(noise * 0.9);
    root.append(staticLayer);
    for (const corner of ['tl', 'tr', 'bl', 'br']) root.append(el('span', null, `live-corner ${corner}`));
    // Todo centrado: las esquinas quedan libres para los HUD de otros mods (chat, calle, FPS, dinero).
    const top = el('div', null, 'live-top');
    const time = el('span', stamp(), 'live-time');
    const left = el('div'); left.append(el('div', `● ${text.rec || 'REC'}`, 'live-rec'), time);
    const info = el('div', null, 'live-info');
    info.append(el('div', `${text.cam || 'CAM'} ${data.index || 1}/${data.total || 1} · ${data.displayId || ''}`, 'live-name'));
    if (data.site) info.append(el('div', data.site));
    if (noise > 0) info.append(el('div', text.noise || 'Senal degradada', 'live-warn'));
    top.append(left, info);
    const bottom = el('div', null, 'live-bottom');
    bottom.append(el('div', text.help || '', 'live-help'));
    root.append(top, bottom);
    root.hidden = false;
    clock = setInterval(() => { time.textContent = stamp(); }, 1000);
  }
  function hide() { clearInterval(clock); clock = null; root.hidden = true; root.replaceChildren(); }

  window.addEventListener('message', event => {
    const message = event.data;
    if (message?.type !== 'live') return;
    if (message.action === 'show' && message.data) show(message.data, message.text || {});
    else if (message.action === 'hide') hide();
  });
})();
