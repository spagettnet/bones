import * as THREE from 'three';

export function setupLighting(scene) {
  // Strong ambient so the big room is never dark
  const ambient = new THREE.AmbientLight(0xffffff, 1.0);
  scene.add(ambient);

  // Warm ceiling lights spread across the room
  const ceilingPositions = [
    [0, 3.3, 0],
    [-6, 3.3, -5],
    [6, 3.3, -5],
    [-6, 3.3, 5],
    [6, 3.3, 5],
  ];
  for (const [x, y, z] of ceilingPositions) {
    const light = new THREE.PointLight(0xFFD4A0, 1.5, 18);
    light.position.set(x, y, z);
    scene.add(light);
  }

  // Floor lamp lights
  const lampLight1 = new THREE.PointLight(0xFFE4B5, 1.2, 10);
  lampLight1.position.set(-8.5, 2.0, -7);
  scene.add(lampLight1);

  const lampLight2 = new THREE.PointLight(0xFFE4B5, 1.2, 10);
  lampLight2.position.set(10.2, 2.0, 3);
  scene.add(lampLight2);

  // Party accent lights — colorful and spread out
  const accents = [
    { color: 0xFF69B4, pos: [-5, 2.5, -6], intensity: 1.2 },   // Pink near lounge
    { color: 0x00CED1, pos: [-10, 2.5, 0], intensity: 1.0 },   // Teal at DJ zone
    { color: 0x9B59B6, pos: [0, 2.5, 3], intensity: 1.0 },     // Purple on dance floor
    { color: 0xFF6B35, pos: [6, 2.5, -8], intensity: 1.0 },     // Orange at bar
    { color: 0x00E5FF, pos: [-7, 2.0, 7], intensity: 0.8 },     // Cyan at chill zone
    { color: 0xFFD700, pos: [6, 2.5, 7], intensity: 0.8 },      // Gold at food table
  ];
  for (const a of accents) {
    const light = new THREE.PointLight(a.color, a.intensity, 14);
    light.position.set(...a.pos);
    scene.add(light);
  }
}
