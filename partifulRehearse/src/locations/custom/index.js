export const config = {
  name: 'Your Custom Party',
  subtitle: 'A loft full of people you know',
  spawn: [0, 1.6, 8],
  fov: 75,
  far: 100,
  fog: null,
  background: 0x1a1a2e,
  toneMappingExposure: 1.3,
  shadows: false,
  boundary: null,
  music: {
    padNotes: [65.41, 155.56, 196.00, 233.08],
    oscType: 'sawtooth',
    oscGain: 0.025,
    filterFreq: 350,
    lfoDepth: 120,
    musicVolume: 0.35,
    arpNotes: [261.63, 311.13, 349.23, 392.00, 466.16, 523.25],
    melodyPhrases: [
      [311.13, 261.63, 233.08, 261.63],
      [392.00, 349.23, 311.13, 261.63],
      [349.23, 392.00, 466.16, 392.00],
      [261.63, 233.08, 196.00, 233.08],
    ],
    footstep: {
      noiseFreq: 600,
      noiseVol: 0.10,
      thudFreq: 50,
      thudVol: 0.06,
      shuffleFreq: 350,
      shuffleVol: 0.05,
    },
  },
};

export { buildApartment as buildEnvironment } from '../party/environment.js';
export { setupLighting } from '../party/lighting.js';
export { createNPCs, animateNPCs } from './npcs.js';
