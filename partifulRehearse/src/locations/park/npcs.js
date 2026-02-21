import * as THREE from 'three';
import { createToonMaterial } from './toonShader.js';

const NPC_DATA = [
  {
    id: 'elena',
    name: 'Elena',
    color: 0xCC6B49,  // Terracotta
    skinColor: 0xE8B88A,
    position: [3, 0, -3],
    rotationY: Math.PI * 0.8,
    build: 'slim',
    accessory: 'guitar',
    messages: [
      "I come here every evening to play. The acoustics off the fountain are surprisingly good.",
      "This song? I wrote it about the arch. Sounds pretentious, I know, but it's actually about pigeons.",
      "Golden hour is the only acceptable time to play guitar outdoors. I don't make the rules."
    ]
  },
  {
    id: 'howard',
    name: 'Howard',
    color: 0x6B8F5E,  // Muted green
    skinColor: 0xF5D0C5,
    position: [-21, 0, 21],
    rotationY: Math.PI * 0.3,
    build: 'stocky',
    accessory: 'glasses',
    messages: [
      "I've been playing chess in this park for thirty years. My rating? Don't worry about it.",
      "The key to chess is patience. Also, I haven't lost to a squirrel yet. They're getting better though.",
      "Want to play? I should warn you, I once drew against a guy who drew against a grandmaster. Basically a grandmaster."
    ]
  },
  {
    id: 'jasmine',
    name: 'Jasmine',
    color: 0xFF69B4,  // Hot pink
    skinColor: 0xC68642,
    position: [-10, 0, 5],
    rotationY: Math.PI * -0.3,
    build: 'average',
    accessory: 'leash',
    messages: [
      "This is Biscuit. He thinks every person in the park exists to pet him. He's not wrong.",
      "We walk three miles a day. Well, I walk three miles. Biscuit walks about half a mile and gets carried the rest.",
      "He just ate something off the ground. I didn't see what it was. I'm choosing peace today."
    ]
  },
  {
    id: 'marco',
    name: 'Marco',
    color: 0x8B5CF6,  // Purple
    skinColor: 0xFFDBAC,
    position: [0, 0, -26],
    rotationY: Math.PI,
    build: 'tall',
    accessory: 'tophat',
    messages: [
      "The arch was built in 1892. I tell this to everyone who stands near it. They love it. Probably.",
      "I'm a walking tour guide. Off duty. But I can't turn it off. Did you know this park was a cemetery?",
      "The top hat? It's historically accurate for the era. Also it holds my snacks. Dual purpose."
    ]
  },
  {
    id: 'carol',
    name: 'Carol',
    color: 0x2DD4BF,  // Teal
    skinColor: 0xF1C27D,
    position: [14, 0, -14],
    rotationY: Math.PI * 0.6,
    build: 'slim',
    accessory: 'book',
    messages: [
      "I'm on page 347. Please don't ask me what the book is about. I lost the plot around page 50.",
      "This bench gets the perfect amount of late afternoon sun. I've tested them all. Peer reviewed.",
      "Reading outdoors is about 40% reading and 60% staring at trees while holding a book. I'm fine with that."
    ]
  },
  {
    id: 'derek',
    name: 'Derek',
    color: 0xF97316,  // Orange
    skinColor: 0x8D5524,
    position: [20, 0, 10],
    rotationY: Math.PI * -0.5,
    build: 'tall',
    accessory: 'headband',
    messages: [
      "Just finished my run. Well, 'run.' I jogged for two blocks and walked the rest. It still counts.",
      "This park loop is exactly 0.4 miles. How do I know? I've measured it on four different apps. They all disagree.",
      "The headband is functional AND fashionable. Mostly fashionable. Okay, entirely fashionable."
    ]
  },
  {
    id: 'rosa',
    name: 'Rosa',
    color: 0xEAB308,  // Gold
    skinColor: 0xD4A574,
    position: [25, 0, -5],
    rotationY: Math.PI * 0.9,
    build: 'stocky',
    accessory: 'apron',
    messages: [
      "Empanadas! Best in the park. Only stand in the park, but still. Best.",
      "My grandmother's recipe. She'd be proud. She'd also say I'm undercharging. She was a businesswoman.",
      "The secret ingredient? I can't tell you. But it's love. And also cumin. Lots of cumin."
    ]
  }
];

export function createNPCs(scene) {
  const npcGroups = [];
  const npcMeshes = [];

  for (const data of NPC_DATA) {
    const group = new THREE.Group();
    group.userData.npcId = data.id;
    group.userData.npcName = data.name;
    group.userData.npcColor = data.color;
    group.userData.messages = data.messages;
    group.userData.messageIndex = 0;

    const bodyMat = createToonMaterial(data.color);
    const skinMat = createToonMaterial(data.skinColor);
    const darkMat = createToonMaterial(0x1a1a1a);

    // Build variation
    let bodyW = 0.24, bodyH = 1.0, headR = 0.18, totalH = 1.38;
    if (data.build === 'stocky') { bodyW = 0.32; bodyH = 0.9; }
    if (data.build === 'tall') { bodyH = 1.15; totalH = 1.52; }
    if (data.build === 'slim') { bodyW = 0.2; }

    // Body
    const body = new THREE.Mesh(new THREE.CylinderGeometry(bodyW - 0.02, bodyW, bodyH, 12), bodyMat);
    body.position.y = bodyH / 2 + 0.2;
    body.castShadow = true;
    group.add(body);

    // Head
    const head = new THREE.Mesh(new THREE.SphereGeometry(headR, 16, 12), skinMat);
    head.position.y = bodyH + 0.2 + headR + 0.04;
    head.castShadow = true;
    group.add(head);

    // Eyes
    const eyeY = head.position.y + 0.02;
    for (const side of [-1, 1]) {
      const eye = new THREE.Mesh(new THREE.SphereGeometry(0.025, 8, 6), darkMat);
      eye.position.set(side * 0.065, eyeY, headR * 0.82);
      group.add(eye);
    }

    // Arms
    for (const side of [-1, 1]) {
      const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.045, 0.55, 8), bodyMat);
      arm.position.set(side * (bodyW + 0.07), bodyH / 2 + 0.15, 0);
      arm.rotation.z = side * 0.15;
      arm.castShadow = true;
      group.add(arm);
      // Hand
      const hand = new THREE.Mesh(new THREE.SphereGeometry(0.05, 8, 6), skinMat);
      hand.position.set(side * (bodyW + 0.09), bodyH / 2 - 0.15, 0);
      group.add(hand);
    }

    // Accessory
    buildAccessory(group, data.accessory, data.color, head.position.y, headR, bodyW, bodyH);

    group.position.set(data.position[0], data.position[1], data.position[2]);
    group.rotation.y = data.rotationY;

    scene.add(group);
    npcGroups.push(group);

    group.traverse((child) => {
      if (child.isMesh) npcMeshes.push(child);
    });
  }

  return { npcGroups, npcMeshes };
}

function buildAccessory(group, type, color, headY, headR, bodyW, bodyH) {
  switch (type) {
    case 'guitar': {
      const woodMat = createToonMaterial('#6B4F3A');
      const darkMat = createToonMaterial('#1a1a1a');

      // Guitar body (flattened sphere)
      const guitarBody = new THREE.Mesh(new THREE.SphereGeometry(0.2, 10, 8), woodMat);
      guitarBody.scale.set(1, 0.3, 1.4);
      guitarBody.position.set(-(bodyW + 0.25), bodyH / 2 + 0.1, 0.1);
      guitarBody.rotation.z = 0.3;
      group.add(guitarBody);

      // Neck
      const neck = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.5, 0.04), woodMat);
      neck.position.set(-(bodyW + 0.25), bodyH / 2 + 0.45, 0.1);
      neck.rotation.z = 0.3;
      group.add(neck);

      // Sound hole
      const hole = new THREE.Mesh(new THREE.CircleGeometry(0.06, 8), darkMat);
      hole.position.set(-(bodyW + 0.26), bodyH / 2 + 0.1, 0.24);
      group.add(hole);

      // Strap
      const strapMat = createToonMaterial('#4A3728');
      const strap = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.7, 0.02), strapMat);
      strap.position.set(-(bodyW + 0.05), bodyH / 2 + 0.3, 0);
      strap.rotation.z = -0.2;
      group.add(strap);
      break;
    }

    case 'glasses': {
      const glassMat = createToonMaterial('#333333', { glossiness: 48 });
      for (const side of [-1, 1]) {
        const lens = new THREE.Mesh(new THREE.TorusGeometry(0.045, 0.008, 6, 12), glassMat);
        lens.position.set(side * 0.06, headY + 0.02, headR * 0.85);
        group.add(lens);
      }
      const bridge = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.008, 0.008), glassMat);
      bridge.position.set(0, headY + 0.02, headR * 0.85);
      group.add(bridge);
      break;
    }

    case 'leash': {
      const leashMat = createToonMaterial('#8B4513');
      const dogMat = createToonMaterial('#D4A574');
      const darkMat = createToonMaterial('#1a1a1a');

      // Leash line
      const leash = new THREE.Mesh(new THREE.CylinderGeometry(0.01, 0.01, 1.5, 4), leashMat);
      leash.position.set(bodyW + 0.5, 0.3, 0.5);
      leash.rotation.z = Math.PI / 4;
      leash.rotation.x = -0.3;
      group.add(leash);

      // Dog body
      const dogBody = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.14, 0.5, 8), dogMat);
      dogBody.position.set(bodyW + 1.2, 0.3, 0.8);
      dogBody.rotation.z = Math.PI / 2;
      dogBody.castShadow = true;
      group.add(dogBody);

      // Dog head
      const dogHead = new THREE.Mesh(new THREE.SphereGeometry(0.12, 8, 6), dogMat);
      dogHead.position.set(bodyW + 1.5, 0.35, 0.8);
      group.add(dogHead);

      // Dog snout
      const snout = new THREE.Mesh(new THREE.SphereGeometry(0.06, 6, 4), dogMat);
      snout.position.set(bodyW + 1.62, 0.33, 0.8);
      snout.scale.set(1.3, 0.8, 1);
      group.add(snout);

      // Dog nose
      const nose = new THREE.Mesh(new THREE.SphereGeometry(0.025, 6, 4), darkMat);
      nose.position.set(bodyW + 1.67, 0.34, 0.8);
      group.add(nose);

      // Dog eyes
      for (const side of [-1, 1]) {
        const eye = new THREE.Mesh(new THREE.SphereGeometry(0.02, 6, 4), darkMat);
        eye.position.set(bodyW + 1.56, 0.39, 0.8 + side * 0.06);
        group.add(eye);
      }

      // Dog legs (4)
      for (const sx of [-0.12, 0.12]) {
        for (const sz of [-0.06, 0.06]) {
          const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.025, 0.25, 4), dogMat);
          leg.position.set(bodyW + 1.2 + sx, 0.1, 0.8 + sz);
          group.add(leg);
        }
      }

      // Dog tail
      const tail = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.01, 0.2, 4), dogMat);
      tail.position.set(bodyW + 0.9, 0.42, 0.8);
      tail.rotation.z = -0.8;
      group.add(tail);
      break;
    }

    case 'tophat': {
      const hatMat = createToonMaterial('#1a1a1a', { glossiness: 48 });

      // Brim
      const brim = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.25, 0.03, 16), hatMat);
      brim.position.set(0, headY + headR + 0.01, 0);
      group.add(brim);

      // Crown
      const crown = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.16, 0.25, 12), hatMat);
      crown.position.set(0, headY + headR + 0.14, 0);
      group.add(crown);

      // Hat band
      const bandMat = createToonMaterial('#8B5CF6');
      const band = new THREE.Mesh(new THREE.CylinderGeometry(0.162, 0.162, 0.03, 12), bandMat);
      band.position.set(0, headY + headR + 0.05, 0);
      group.add(band);
      break;
    }

    case 'book': {
      const coverMat = createToonMaterial('#8B0000');
      const pageMat = createToonMaterial('#F5F5DC');

      // Book cover
      const cover = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.2, 0.04), coverMat);
      cover.position.set(bodyW + 0.15, bodyH / 2 + 0.2, 0.1);
      cover.rotation.z = -0.1;
      cover.rotation.y = -0.3;
      group.add(cover);

      // Pages (slightly inset)
      const pages = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.18, 0.03), pageMat);
      pages.position.set(bodyW + 0.15, bodyH / 2 + 0.2, 0.12);
      pages.rotation.z = -0.1;
      pages.rotation.y = -0.3;
      group.add(pages);
      break;
    }

    case 'headband': {
      const bandMat = createToonMaterial('#F97316');

      // Headband (torus around head)
      const band = new THREE.Mesh(new THREE.TorusGeometry(headR + 0.02, 0.025, 8, 16), bandMat);
      band.position.set(0, headY + headR * 0.3, 0);
      band.rotation.x = Math.PI / 2;
      group.add(band);
      break;
    }

    case 'apron': {
      const apronMat = createToonMaterial('#F5F5DC');
      const strapMat = createToonMaterial('#D4A574');

      // Apron body (front of torso)
      const apron = new THREE.Mesh(new THREE.BoxGeometry(bodyW * 1.6, bodyH * 0.6, 0.02), apronMat);
      apron.position.set(0, bodyH / 2 + 0.1, bodyW + 0.02);
      group.add(apron);

      // Apron pocket
      const pocket = new THREE.Mesh(new THREE.BoxGeometry(bodyW * 0.8, bodyH * 0.2, 0.025), strapMat);
      pocket.position.set(0, bodyH / 2 - 0.05, bodyW + 0.03);
      group.add(pocket);

      // Neck strap
      const neckStrap = new THREE.Mesh(new THREE.TorusGeometry(0.12, 0.015, 6, 12, Math.PI), strapMat);
      neckStrap.position.set(0, bodyH + 0.1, bodyW * 0.5);
      neckStrap.rotation.x = Math.PI / 2;
      group.add(neckStrap);
      break;
    }
  }
}

const FACE_RANGE = 5.0;
const FACE_SPEED = 3.0;

export function animateNPCs(npcGroups, time, cameraPosition) {
  for (let i = 0; i < npcGroups.length; i++) {
    const group = npcGroups[i];

    // Idle bob
    group.position.y = Math.sin(time * 2 + i * 1.3) * 0.03;

    // Face player when within range
    const dx = cameraPosition.x - group.position.x;
    const dz = cameraPosition.z - group.position.z;
    const dist = Math.sqrt(dx * dx + dz * dz);

    if (dist < FACE_RANGE) {
      const targetAngle = Math.atan2(dx, dz);
      let diff = targetAngle - group.rotation.y;
      while (diff > Math.PI) diff -= Math.PI * 2;
      while (diff < -Math.PI) diff += Math.PI * 2;
      group.rotation.y += diff * Math.min(1, FACE_SPEED * (1 / 60));
    }
  }
}
