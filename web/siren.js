(() => {
  'use strict';
  // Sirena de alarma generada con Web Audio (sin archivos de sonido externos): ulular clasico
  // (barrido de frecuencia) con volumen segun la distancia que calcula el cliente del juego.
  // Tambien los pitidos del retardo de entrada y del teclado.
  let context = null, siren = null;
  function audio() {
    if (!context) { const Ctor = window.AudioContext || window.webkitAudioContext; if (!Ctor) return null; context = new Ctor(); }
    if (context.state === 'suspended') context.resume().catch(() => {});
    return context;
  }
  function start(volume) {
    const ctx = audio(); if (!ctx) return;
    if (!siren) {
      const gain = ctx.createGain(); gain.gain.value = 0; gain.connect(ctx.destination);
      const filter = ctx.createBiquadFilter(); filter.type = 'lowpass'; filter.frequency.value = 2400; filter.connect(gain);
      const tone = ctx.createOscillator(); tone.type = 'sawtooth'; tone.frequency.value = 900;
      const wobble = ctx.createOscillator(); wobble.type = 'triangle'; wobble.frequency.value = 0.9; // ~1 ciclo por segundo
      const depth = ctx.createGain(); depth.gain.value = 420; // 480-1320 Hz
      wobble.connect(depth); depth.connect(tone.frequency); tone.connect(filter);
      tone.start(); wobble.start();
      siren = { gain, tone, wobble };
    }
    siren.gain.gain.setTargetAtTime(Math.max(0, Math.min(1, volume)) * 0.35, ctx.currentTime, 0.15);
  }
  function stop() {
    if (!siren || !context) return;
    const current = siren; siren = null;
    current.gain.gain.setTargetAtTime(0, context.currentTime, 0.1);
    setTimeout(() => { try { current.tone.stop(); current.wobble.stop(); } catch { /* ya detenido */ } }, 400);
  }
  function beep(frequency = 1800, duration = 0.12, volume = 0.18) {
    const ctx = audio(); if (!ctx) return;
    const gain = ctx.createGain(); gain.gain.value = volume; gain.connect(ctx.destination);
    const tone = ctx.createOscillator(); tone.type = 'square'; tone.frequency.value = frequency; tone.connect(gain);
    tone.start(); gain.gain.setTargetAtTime(0, ctx.currentTime + duration * 0.7, 0.02); tone.stop(ctx.currentTime + duration + 0.05);
  }
  window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.type === 'siren') { if (data.volume > 0) start(data.volume); else stop(); }
    else if (data.type === 'beep') beep(data.frequency, data.duration, data.volume);
  });
  window.__osSiren = { active: () => siren !== null };
})();
