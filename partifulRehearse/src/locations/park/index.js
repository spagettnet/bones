import { createSky } from './sky.js';
import { createPollen } from './particles.js';

export const config = {
  name: 'Washington Square Park',
  subtitle: 'A golden hour in the Village',
  spawn: [0, 1.6, 30],
  fov: 65,
  far: 500,
  fog: { color: 0xE8D5B7, density: 0.007 },
  background: null,
  toneMappingExposure: 1.1,
  shadows: true,
  boundary: 38,
  music: {
    // Cmaj9 pad — warm, open, peaceful
    padNotes: [130.81, 164.81, 196.00, 293.66],
    oscType: 'sine',
    oscGain: 0.05,
    filterFreq: 1200,
    lfoDepth: 300,
    musicVolume: 0.30,
    // C major pentatonic arpeggio (C4, D4, E4, G4, A4, C5, D5)
    arpNotes: [261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33],
    // Gentle major melodic phrases
    melodyPhrases: [
      [329.63, 293.66, 261.63, 293.66],
      [392.00, 329.63, 293.66, 261.63],
      [293.66, 329.63, 440.00, 392.00],
      [523.25, 440.00, 392.00, 329.63],
    ],
    // Outdoor grass/dirt
    footstep: {
      noiseFreq: 400,
      noiseVol: 0.12,
      thudFreq: 40,
      thudVol: 0.08,
      shuffleFreq: 250,
      shuffleVol: 0.07,
    },
  },
};

export { buildPark as buildEnvironment } from './environment.js';
export { createNPCs, animateNPCs } from './npcs.js';
export { setupLighting } from './lighting.js';

export function extras(scene) {
  createSky(scene);
  const { material: pollenMaterial } = createPollen(scene);
  return {
    update(elapsed) {
      pollenMaterial.uniforms.uTime.value = elapsed;
    }
  };
}
