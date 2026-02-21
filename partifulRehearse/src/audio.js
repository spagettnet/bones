export function setupAudio(musicConfig) {
  const ctx = new (window.AudioContext || window.webkitAudioContext)();

  const master = ctx.createGain();
  master.gain.value = 1.0;
  master.connect(ctx.destination);

  // --- Footsteps ---
  let stepTimer = 0;
  const STEP_INTERVAL = 0.38;

  function playFootstep() {
    const now = ctx.currentTime;
    const foot = musicConfig.footstep || {};

    // Layer 1: Low filtered noise (soft shush)
    const noiseLen = 0.14 + Math.random() * 0.06;
    const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * noiseLen | 0, ctx.sampleRate);
    const noiseData = noiseBuf.getChannelData(0);
    for (let i = 0; i < noiseData.length; i++) {
      const t = i / noiseData.length;
      const env = Math.sin(t * Math.PI) * (1 - t * 0.5);
      noiseData[i] = (Math.random() * 2 - 1) * env;
    }
    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuf;

    const lowpass = ctx.createBiquadFilter();
    lowpass.type = 'lowpass';
    lowpass.frequency.value = (foot.noiseFreq || 500) + Math.random() * 200;
    lowpass.Q.value = 0.3;

    const noiseMaster = ctx.createGain();
    noiseMaster.gain.setValueAtTime(foot.noiseVol || 0.12, now);
    noiseMaster.gain.exponentialRampToValueAtTime(0.001, now + 0.18);

    noise.connect(lowpass);
    lowpass.connect(noiseMaster);
    noiseMaster.connect(master);
    noise.start(now);

    // Layer 2: Deep thud
    const thud = ctx.createOscillator();
    thud.type = 'sine';
    thud.frequency.setValueAtTime((foot.thudFreq || 45) + Math.random() * 15, now);
    thud.frequency.exponentialRampToValueAtTime(20, now + 0.1);

    const thudGain = ctx.createGain();
    thudGain.gain.setValueAtTime(foot.thudVol || 0.08, now);
    thudGain.gain.exponentialRampToValueAtTime(0.001, now + 0.1);

    thud.connect(thudGain);
    thudGain.connect(master);
    thud.start(now);
    thud.stop(now + 0.12);

    // Layer 3: Gentle shuffle
    const shuffleLen = 0.1 + Math.random() * 0.05;
    const shuffleBuf = ctx.createBuffer(1, ctx.sampleRate * shuffleLen | 0, ctx.sampleRate);
    const shuffleData = shuffleBuf.getChannelData(0);
    for (let i = 0; i < shuffleData.length; i++) {
      const t = i / shuffleData.length;
      shuffleData[i] = (Math.random() * 2 - 1) * Math.sin(t * Math.PI);
    }
    const shuffle = ctx.createBufferSource();
    shuffle.buffer = shuffleBuf;

    const shuffleFilter = ctx.createBiquadFilter();
    shuffleFilter.type = 'lowpass';
    shuffleFilter.frequency.value = (foot.shuffleFreq || 300) + Math.random() * 150;

    const shuffleGain = ctx.createGain();
    shuffleGain.gain.setValueAtTime(foot.shuffleVol || 0.07, now);
    shuffleGain.gain.exponentialRampToValueAtTime(0.001, now + 0.12);

    shuffle.connect(shuffleFilter);
    shuffleFilter.connect(shuffleGain);
    shuffleGain.connect(master);
    shuffle.start(now);
  }

  // --- Ambient Music ---
  let musicStarted = false;
  let musicPlaying = false;

  const musicGain = ctx.createGain();
  musicGain.gain.value = 0;
  musicGain.connect(master);

  // Reverb for spaciousness
  const reverbLen = ctx.sampleRate * 2.5;
  const impulse = ctx.createBuffer(2, reverbLen, ctx.sampleRate);
  for (let ch = 0; ch < 2; ch++) {
    const d = impulse.getChannelData(ch);
    for (let i = 0; i < reverbLen; i++) {
      d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / reverbLen, 2.2);
    }
  }
  const reverb = ctx.createConvolver();
  reverb.buffer = impulse;
  const reverbGain = ctx.createGain();
  reverbGain.gain.value = 0.3;
  reverb.connect(reverbGain);
  reverbGain.connect(musicGain);

  const dryBus = ctx.createGain();
  dryBus.gain.value = 0.7;
  dryBus.connect(musicGain);

  const sendBus = ctx.createGain();
  sendBus.gain.value = 0.4;
  sendBus.connect(reverb);

  function toMix(node) {
    node.connect(dryBus);
    node.connect(sendBus);
  }

  // -- Pad layer --
  function startPad() {
    const notes = musicConfig.padNotes || [130.81, 164.81, 196.00];
    const type = musicConfig.oscType || 'sine';

    for (let i = 0; i < notes.length; i++) {
      const freq = notes[i];
      for (const detune of [-6, 6]) {
        const osc = ctx.createOscillator();
        osc.type = type;
        osc.frequency.value = freq;
        osc.detune.value = detune + (Math.random() - 0.5) * 4;

        const filter = ctx.createBiquadFilter();
        filter.type = 'lowpass';
        filter.frequency.value = musicConfig.filterFreq || 800;
        filter.Q.value = 0.5;

        const lfo = ctx.createOscillator();
        lfo.type = 'sine';
        lfo.frequency.value = 0.03 + i * 0.012;
        const lfoG = ctx.createGain();
        lfoG.gain.value = musicConfig.lfoDepth || 200;
        lfo.connect(lfoG);
        lfoG.connect(filter.frequency);
        lfo.start();

        const oscGain = ctx.createGain();
        oscGain.gain.value = musicConfig.oscGain || 0.06;

        osc.connect(filter);
        filter.connect(oscGain);
        toMix(oscGain);
        osc.start();
      }
    }
  }

  // -- Arpeggio layer (music-box / kalimba feel) --
  function startArpeggio() {
    const notes = musicConfig.arpNotes;
    if (!notes || notes.length === 0) return;

    let idx = 0;
    const playNote = () => {
      if (!musicPlaying) return;

      const freq = notes[idx % notes.length];
      idx += 1 + Math.floor(Math.random() * 2);

      const now = ctx.currentTime;

      // Triangle wave — soft bell-like
      const osc = ctx.createOscillator();
      osc.type = 'triangle';
      osc.frequency.value = freq;

      // Soft upper harmonic
      const osc2 = ctx.createOscillator();
      osc2.type = 'sine';
      osc2.frequency.value = freq * 2;

      const gain = ctx.createGain();
      gain.gain.setValueAtTime(0.035 + Math.random() * 0.015, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 2.5);

      const gain2 = ctx.createGain();
      gain2.gain.setValueAtTime(0.012, now);
      gain2.gain.exponentialRampToValueAtTime(0.001, now + 1.5);

      osc.connect(gain);
      osc2.connect(gain2);
      toMix(gain);
      toMix(gain2);

      osc.start(now);
      osc.stop(now + 3);
      osc2.start(now);
      osc2.stop(now + 2);

      const delay = 800 + Math.random() * 2200;
      const actual = Math.random() < 0.2 ? delay + 2000 : delay;
      setTimeout(playNote, actual);
    };

    setTimeout(playNote, 2000);
  }

  // -- Melody layer (slow, sparse, breathy) --
  function startMelody() {
    const phrases = musicConfig.melodyPhrases;
    if (!phrases || phrases.length === 0) return;

    let pi = 0;
    const playPhrase = () => {
      if (!musicPlaying) return;

      const phrase = phrases[pi % phrases.length];
      pi++;

      phrase.forEach((freq, i) => {
        const t0 = ctx.currentTime + i * 1.8;

        // Sine tone
        const osc = ctx.createOscillator();
        osc.type = 'sine';
        osc.frequency.value = freq;

        // Breathy noise layer
        const breathLen = 1.5;
        const breathBuf = ctx.createBuffer(1, ctx.sampleRate * breathLen | 0, ctx.sampleRate);
        const bd = breathBuf.getChannelData(0);
        for (let j = 0; j < bd.length; j++) {
          const t = j / bd.length;
          bd[j] = (Math.random() * 2 - 1) * Math.sin(t * Math.PI) * 0.3;
        }
        const breath = ctx.createBufferSource();
        breath.buffer = breathBuf;

        const breathFilter = ctx.createBiquadFilter();
        breathFilter.type = 'bandpass';
        breathFilter.frequency.value = freq;
        breathFilter.Q.value = 2;

        const gain = ctx.createGain();
        gain.gain.setValueAtTime(0, t0);
        gain.gain.linearRampToValueAtTime(0.025, t0 + 0.3);
        gain.gain.setValueAtTime(0.025, t0 + 1.0);
        gain.gain.linearRampToValueAtTime(0, t0 + 1.6);

        const breathGain = ctx.createGain();
        breathGain.gain.setValueAtTime(0, t0);
        breathGain.gain.linearRampToValueAtTime(0.015, t0 + 0.2);
        breathGain.gain.linearRampToValueAtTime(0, t0 + 1.4);

        osc.connect(gain);
        breath.connect(breathFilter);
        breathFilter.connect(breathGain);
        toMix(gain);
        toMix(breathGain);

        osc.start(t0);
        osc.stop(t0 + 2);
        breath.start(t0);
      });

      setTimeout(playPhrase, 12000 + Math.random() * 8000);
    };

    setTimeout(playPhrase, 5000);
  }

  function startMusic() {
    if (musicStarted) return;
    musicStarted = true;
    musicPlaying = true;

    startPad();
    startArpeggio();
    startMelody();

    // Fade in
    const now = ctx.currentTime;
    musicGain.gain.setValueAtTime(0, now);
    musicGain.gain.linearRampToValueAtTime(musicConfig.musicVolume || 0.4, now + 4);
  }

  // --- Update (call each frame) ---
  function update(delta, walking) {
    if (walking) {
      stepTimer += delta;
      if (stepTimer >= STEP_INTERVAL) {
        stepTimer -= STEP_INTERVAL;
        stepTimer -= (Math.random() - 0.5) * 0.04;
        playFootstep();
      }
    } else {
      // Reset near-ready so first step plays quickly when you start moving
      stepTimer = STEP_INTERVAL * 0.8;
    }
  }

  // Resume context (must be called from user gesture) and start music
  function resume() {
    if (ctx.state === 'suspended') ctx.resume();
    startMusic();
  }

  return { update, resume };
}
