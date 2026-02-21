import * as THREE from 'three';

export function buildApartment(scene) {
  const wallBounds = [];

  // Materials
  const floorMat = new THREE.MeshStandardMaterial({ color: 0xB5834A, roughness: 0.8 });
  const ceilingMat = new THREE.MeshStandardMaterial({ color: 0xF5F0E8, roughness: 0.9 });
  const wallMat = new THREE.MeshStandardMaterial({ color: 0xEDE8E0, roughness: 0.9 });
  const darkWoodMat = new THREE.MeshStandardMaterial({ color: 0x3E2723, roughness: 0.7 });
  const tealMat = new THREE.MeshStandardMaterial({ color: 0x2A9D8F, roughness: 0.6 });
  const siennaMat = new THREE.MeshStandardMaterial({ color: 0xA0522D, roughness: 0.7 });
  const darkBrownMat = new THREE.MeshStandardMaterial({ color: 0x2C1A0E, roughness: 0.7 });
  const rugMat = new THREE.MeshStandardMaterial({ color: 0x6B3FA0, roughness: 1.0, side: THREE.DoubleSide });
  const lampPoleMat = new THREE.MeshStandardMaterial({ color: 0x888888, metalness: 0.5, roughness: 0.3 });
  const lampShadeMat = new THREE.MeshStandardMaterial({ color: 0xFFF5E0, roughness: 0.5, side: THREE.DoubleSide });
  const speakerMat = new THREE.MeshStandardMaterial({ color: 0x1A1A1A, roughness: 0.5 });
  const brickMat = new THREE.MeshStandardMaterial({ color: 0x8B4513, roughness: 0.95 });
  const concreteMat = new THREE.MeshStandardMaterial({ color: 0x9E9E9E, roughness: 0.9 });
  const velvetMat = new THREE.MeshStandardMaterial({ color: 0x8B0000, roughness: 0.4 });
  const greenMat = new THREE.MeshStandardMaterial({ color: 0x2E7D32, roughness: 0.6 });
  const orangeMat = new THREE.MeshStandardMaterial({ color: 0xE65100, roughness: 0.5 });

  // Room: 24m wide (X), 3.5m tall (Y), 20m deep (Z) — big loft
  const W = 24, H = 3.5, D = 20;
  const halfW = W / 2, halfD = D / 2;
  const wallThickness = 0.2;

  // Floor
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(W, D), floorMat);
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  scene.add(floor);

  // Ceiling
  const ceiling = new THREE.Mesh(new THREE.PlaneGeometry(W, D), ceilingMat);
  ceiling.rotation.x = Math.PI / 2;
  ceiling.position.y = H;
  scene.add(ceiling);

  // Walls
  function addWall(w, h, d, x, y, z, mat) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat || wallMat);
    mesh.position.set(x, y, z);
    scene.add(mesh);
    const box = new THREE.Box3();
    box.setFromCenterAndSize(new THREE.Vector3(x, y, z), new THREE.Vector3(w, h, d));
    wallBounds.push(box);
  }

  addWall(W, H, wallThickness, 0, H / 2, -halfD);           // North
  addWall(W, H, wallThickness, 0, H / 2, halfD);             // South
  addWall(wallThickness, H, D, -halfW, H / 2, 0);            // West
  addWall(wallThickness, H, D, halfW, H / 2, 0);             // East

  // Exposed brick accent wall (north interior face)
  const brickAccent = new THREE.Mesh(new THREE.PlaneGeometry(8, H), brickMat);
  brickAccent.position.set(-4, H / 2, -halfD + 0.12);
  scene.add(brickAccent);

  // --- LOUNGE ZONE (north-west) ---

  // Large L-shaped couch
  function addCouchSection(x, z, w, d) {
    const g = new THREE.Group();
    const seat = new THREE.Mesh(new THREE.BoxGeometry(w, 0.4, d), tealMat);
    seat.position.y = 0.3;
    g.add(seat);
    const back = new THREE.Mesh(new THREE.BoxGeometry(w, 0.5, 0.18), tealMat);
    back.position.set(0, 0.65, -d / 2 + 0.09);
    g.add(back);
    g.position.set(x, 0, z);
    scene.add(g);
    const box = new THREE.Box3();
    box.setFromCenterAndSize(new THREE.Vector3(x, 0.4, z), new THREE.Vector3(w + 0.1, 0.8, d + 0.1));
    wallBounds.push(box);
  }
  addCouchSection(-6, -7.5, 4.0, 1.2);    // Long section
  addCouchSection(-3.2, -6.2, 1.6, 1.4);  // L corner

  // Coffee table (lounge)
  addFurnitureBox(scene, wallBounds, -5, 0.35, -5.8, 1.8, 0.06, 1.0, darkWoodMat);
  addTableLegs(scene, -5, -5.8, 1.8, 1.0, 0.35, darkWoodMat);

  // Floor lamp (lounge)
  addFloorLamp(scene, -8.5, -7);

  // --- BAR AREA (north-east) ---

  // Bar counter
  addFurnitureBox(scene, wallBounds, 6, 0.55, -8, 4.0, 1.1, 0.7, darkBrownMat);

  // Bar stools (3)
  for (let i = 0; i < 3; i++) {
    addBarStool(scene, 4.8 + i * 1.4, -7);
  }

  // --- DJ / SPEAKER ZONE (west wall center) ---

  // DJ table
  addFurnitureBox(scene, wallBounds, -10.5, 0.45, 0, 2.0, 0.9, 0.8, darkBrownMat);

  // Two large speakers
  const speakerL = new THREE.Mesh(new THREE.BoxGeometry(0.6, 1.2, 0.5), speakerMat);
  speakerL.position.set(-10.8, 0.6, -1.5);
  scene.add(speakerL);
  const speakerR = new THREE.Mesh(new THREE.BoxGeometry(0.6, 1.2, 0.5), speakerMat);
  speakerR.position.set(-10.8, 0.6, 1.5);
  scene.add(speakerR);

  // Speaker cones
  for (const sz of [-1.5, 1.5]) {
    const cone = new THREE.Mesh(
      new THREE.CircleGeometry(0.2, 16),
      new THREE.MeshStandardMaterial({ color: 0x333333, roughness: 0.4 })
    );
    cone.position.set(-10.54, 0.7, sz);
    cone.rotation.y = Math.PI / 2;
    scene.add(cone);
  }

  // --- DINING AREA (east side) ---

  // Long dining table
  addFurnitureBox(scene, wallBounds, 8, 0.42, -2, 2.5, 0.06, 1.2, siennaMat);
  addTableLegs(scene, 8, -2, 2.5, 1.2, 0.42, siennaMat);

  // Chairs around dining table
  for (const [cx, cz, ry] of [
    [8, -3.2, 0], [8, -0.8, Math.PI],
    [6.8, -2, Math.PI / 2], [9.2, -2, -Math.PI / 2]
  ]) {
    addChair(scene, cx, cz, ry, siennaMat);
  }

  // --- BOOKSHELF NOOK (east wall, south) ---

  // Two bookshelves
  addBookshelf(scene, wallBounds, 11, 2.5);
  addBookshelf(scene, wallBounds, 11, 5);

  // Reading chair
  const readingChair = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.8, 0.9), velvetMat);
  readingChair.position.set(9.5, 0.4, 3.5);
  scene.add(readingChair);
  const chairBack = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.6, 0.15), velvetMat);
  chairBack.position.set(9.5, 0.9, 3.05);
  scene.add(chairBack);
  const chairBox = new THREE.Box3();
  chairBox.setFromCenterAndSize(new THREE.Vector3(9.5, 0.5, 3.3), new THREE.Vector3(1.0, 1.0, 1.0));
  wallBounds.push(chairBox);

  // Floor lamp by reading chair
  addFloorLamp(scene, 10.2, 3);

  // --- DANCE FLOOR AREA (center-south) ---

  // Large rug / dance floor
  const danceFloor = new THREE.Mesh(
    new THREE.PlaneGeometry(6, 5),
    new THREE.MeshStandardMaterial({ color: 0x2C2C3E, roughness: 0.6, side: THREE.DoubleSide })
  );
  danceFloor.rotation.x = -Math.PI / 2;
  danceFloor.position.set(0, 0.005, 3);
  scene.add(danceFloor);

  // --- CHILL ZONE (south-west) ---

  // Bean bags (rounded boxes)
  for (const [bx, bz, color] of [
    [-7, 6, 0xE65100], [-5.5, 7, 0x6A1B9A], [-8, 8, 0x00695C]
  ]) {
    const bean = new THREE.Mesh(
      new THREE.SphereGeometry(0.5, 12, 8),
      new THREE.MeshStandardMaterial({ color, roughness: 0.7 })
    );
    bean.scale.set(1, 0.6, 1.2);
    bean.position.set(bx, 0.25, bz);
    scene.add(bean);
    const beanBox = new THREE.Box3();
    beanBox.setFromCenterAndSize(new THREE.Vector3(bx, 0.25, bz), new THREE.Vector3(1.0, 0.5, 1.2));
    wallBounds.push(beanBox);
  }

  // Small side table
  addFurnitureBox(scene, wallBounds, -6.5, 0.25, 7, 0.6, 0.04, 0.6, darkWoodMat);

  // --- FOOD TABLE (south-east) ---

  addFurnitureBox(scene, wallBounds, 6, 0.45, 7, 3.0, 0.06, 1.0, darkWoodMat);
  addTableLegs(scene, 6, 7, 3.0, 1.0, 0.45, darkWoodMat);

  // Decorative plants
  for (const [px, pz] of [[-11, -9], [11, -9], [-11, 9], [11, 9], [0, -9.2]]) {
    addPlant(scene, px, pz);
  }

  // Center rug
  const centerRug = new THREE.Mesh(new THREE.PlaneGeometry(4, 3), rugMat);
  centerRug.rotation.x = -Math.PI / 2;
  centerRug.position.set(-5, 0.006, -5.5);
  scene.add(centerRug);

  // Concrete pillars (structural, loft vibes)
  for (const [px, pz] of [[-4, -3], [4, -3], [-4, 5], [4, 5]]) {
    const pillar = new THREE.Mesh(new THREE.BoxGeometry(0.5, H, 0.5), concreteMat);
    pillar.position.set(px, H / 2, pz);
    scene.add(pillar);
    const pBox = new THREE.Box3();
    pBox.setFromCenterAndSize(new THREE.Vector3(px, H / 2, pz), new THREE.Vector3(0.5, H, 0.5));
    wallBounds.push(pBox);
  }

  return wallBounds;
}

// --- Helper functions ---

function addFurnitureBox(scene, wallBounds, x, y, z, w, h, d, mat) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
  mesh.position.set(x, y, z);
  scene.add(mesh);
  if (wallBounds) {
    const box = new THREE.Box3();
    box.setFromCenterAndSize(new THREE.Vector3(x, y, z), new THREE.Vector3(w + 0.1, h + 0.3, d + 0.1));
    wallBounds.push(box);
  }
}

function addTableLegs(scene, cx, cz, tw, td, th, mat) {
  const hw = tw / 2 - 0.1, hd = td / 2 - 0.1;
  for (const [lx, lz] of [[-hw, -hd], [hw, -hd], [-hw, hd], [hw, hd]]) {
    const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, th), mat);
    leg.position.set(cx + lx, th / 2, cz + lz);
    scene.add(leg);
  }
}

function addChair(scene, x, z, rotY, mat) {
  const g = new THREE.Group();
  const seat = new THREE.Mesh(new THREE.BoxGeometry(0.45, 0.05, 0.45), mat);
  seat.position.y = 0.45;
  g.add(seat);
  const back = new THREE.Mesh(new THREE.BoxGeometry(0.45, 0.5, 0.05), mat);
  back.position.set(0, 0.7, -0.2);
  g.add(back);
  for (const [cx, cz] of [[-0.18, -0.18], [0.18, -0.18], [-0.18, 0.18], [0.18, 0.18]]) {
    const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.02, 0.45), mat);
    leg.position.set(cx, 0.225, cz);
    g.add(leg);
  }
  g.position.set(x, 0, z);
  g.rotation.y = rotY;
  scene.add(g);
}

function addBarStool(scene, x, z) {
  const mat = new THREE.MeshStandardMaterial({ color: 0x444444, metalness: 0.4, roughness: 0.4 });
  const seat = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 0.05, 16), mat);
  seat.position.set(x, 0.75, z);
  scene.add(seat);
  const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.04, 0.75), mat);
  pole.position.set(x, 0.375, z);
  scene.add(pole);
  const base = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.18, 0.03, 16), mat);
  base.position.set(x, 0.015, z);
  scene.add(base);
}

function addBookshelf(scene, wallBounds, x, z) {
  const mat = new THREE.MeshStandardMaterial({ color: 0x2C1A0E, roughness: 0.7 });
  const shelf = new THREE.Mesh(new THREE.BoxGeometry(1.2, 2.2, 0.4), mat);
  shelf.position.set(x, 1.1, z);
  scene.add(shelf);
  for (let sy = 0.4; sy <= 2.0; sy += 0.4) {
    const s = new THREE.Mesh(new THREE.BoxGeometry(1.1, 0.04, 0.35), mat);
    s.position.set(x, sy, z);
    scene.add(s);
  }
  const box = new THREE.Box3();
  box.setFromCenterAndSize(new THREE.Vector3(x, 1.1, z), new THREE.Vector3(1.3, 2.2, 0.5));
  wallBounds.push(box);
}

function addFloorLamp(scene, x, z) {
  const poleMat = new THREE.MeshStandardMaterial({ color: 0x888888, metalness: 0.5, roughness: 0.3 });
  const shadeMat = new THREE.MeshStandardMaterial({ color: 0xFFF5E0, roughness: 0.5, side: THREE.DoubleSide });
  const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 1.8), poleMat);
  pole.position.set(x, 0.9, z);
  scene.add(pole);
  const shade = new THREE.Mesh(new THREE.ConeGeometry(0.25, 0.3, 16, 1, true), shadeMat);
  shade.position.set(x, 1.9, z);
  shade.rotation.x = Math.PI;
  scene.add(shade);
}

function addPlant(scene, x, z) {
  const potMat = new THREE.MeshStandardMaterial({ color: 0xA0522D, roughness: 0.8 });
  const leafMat = new THREE.MeshStandardMaterial({ color: 0x2E7D32, roughness: 0.6 });
  const pot = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.15, 0.35, 12), potMat);
  pot.position.set(x, 0.175, z);
  scene.add(pot);
  const foliage = new THREE.Mesh(new THREE.SphereGeometry(0.35, 10, 8), leafMat);
  foliage.position.set(x, 0.65, z);
  foliage.scale.set(1, 1.2, 1);
  scene.add(foliage);
}
