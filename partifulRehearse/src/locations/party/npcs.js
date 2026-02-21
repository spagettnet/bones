import * as THREE from 'three';

const NPC_DATA = [
  {
    id: 'luna',
    name: 'Luna',
    color: 0xFF69B4,
    skinColor: 0xF5D0C5,
    position: [-4.5, 0, -6.5],
    rotationY: Math.PI * 0.6,
    build: 'slim',
    accessory: 'beret',
    messages: [
      "Have you tried the dip? I made it from scratch. Well, I opened the container from scratch.",
      "I made the playlist! It's called 'Songs That Slap At Moderate Volume'. You're welcome.",
      "I love your shoes! Are they new? They look like they've never seen a dance floor. Let's fix that."
    ]
  },
  {
    id: 'marcus',
    name: 'Marcus',
    color: 0x00CED1,
    skinColor: 0x8D5524,
    position: [-9.5, 0, 0.5],
    rotationY: Math.PI * 0.3,
    build: 'stocky',
    accessory: 'headphones',
    messages: [
      "This couch? It's my couch now. I've been here since 8. Territorial rights apply.",
      "The bass on these speakers is wild. I can feel it in my teeth. Is that normal?",
      "Wait, what time is it? I came here at 8 and I genuinely don't know what day it is anymore."
    ]
  },
  {
    id: 'priya',
    name: 'Priya',
    color: 0xDAA520,
    skinColor: 0xC68642,
    position: [10, 0, 3.5],
    rotationY: Math.PI * -0.2,
    build: 'average',
    accessory: 'glasses',
    messages: [
      "I've been alphabetizing these books for twenty minutes. Nobody asked me to. I just... started.",
      "The invite said 'casual.' I brought a blazer, a backup blazer, and a cardigan. You know, casual.",
      "Did you notice there are zero plants in this— oh wait, there are plants. Five of them. I take it back."
    ]
  },
  {
    id: 'diego',
    name: 'Diego',
    color: 0x98FF98,
    skinColor: 0xE8B88A,
    position: [7, 0, -2],
    rotationY: Math.PI * 1.2,
    build: 'tall',
    accessory: 'scarf',
    messages: [
      "I brought three board games and zero people want to play. This is my villain origin story.",
      "The cheese-to-cracker ratio at this party is criminal. I'm writing a formal complaint.",
      "That lamp in the corner? I've been staring at it for five minutes. It's either really cool or I need water."
    ]
  },
  {
    id: 'zara',
    name: 'Zara',
    color: 0x9B59B6,
    skinColor: 0xFFDBAC,
    position: [0, 0, 3],
    rotationY: Math.PI * 0.5,
    build: 'slim',
    accessory: 'bun',
    messages: [
      "This playlist goes hard. Like, unreasonably hard for a Tuesday.",
      "I'd rate this party a solid 8. Points lost for no disco ball. Points gained for vibes.",
      "Do you ever think about how we're all just standing in a room together? Like, on purpose? Wild."
    ]
  },
  {
    id: 'kai',
    name: 'Kai',
    color: 0xFF6B35,
    skinColor: 0xD4A574,
    position: [5.5, 0, -7.5],
    rotationY: Math.PI * -0.5,
    build: 'stocky',
    accessory: 'cap',
    messages: [
      "I've been standing by this bar for 20 minutes pretending I know how to mix drinks.",
      "Someone told me there's a secret room. I've checked every wall. There's no secret room.",
      "My uber is 7 minutes away. It's been 7 minutes away for 45 minutes."
    ]
  },
  {
    id: 'nina',
    name: 'Nina',
    color: 0x00E5FF,
    skinColor: 0xF1C27D,
    position: [-6.5, 0, 7],
    rotationY: Math.PI * 0.9,
    build: 'tall',
    accessory: 'jacket',
    messages: [
      "These bean bags are dangerously comfortable. I may never stand again.",
      "I brought a card game but honestly I'm too comfy to explain the rules right now.",
      "The vibes in this corner are immaculate. I'm claiming it. This is Nina's Corner now."
    ]
  },
  {
    id: 'felix',
    name: 'Felix',
    color: 0xFFD700,
    skinColor: 0x6B4423,
    position: [6, 0, 7.5],
    rotationY: Math.PI * 1.4,
    build: 'average',
    accessory: 'bowtie',
    messages: [
      "I arranged the food table by color. Nobody asked. Everyone benefits.",
      "Is it gauche to take a plate home? Asking for myself. I'm the friend.",
      "I've been to 47 parties this year. This one cracks the top 10. Easily."
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

    const bodyMat = new THREE.MeshStandardMaterial({ color: data.color, roughness: 0.5 });
    const skinMat = new THREE.MeshStandardMaterial({ color: data.skinColor, roughness: 0.6 });
    const darkMat = new THREE.MeshStandardMaterial({ color: 0x1a1a1a });

    // Build variation
    let bodyW = 0.24, bodyH = 1.0, headR = 0.18, totalH = 1.38;
    if (data.build === 'stocky') { bodyW = 0.32; bodyH = 0.9; }
    if (data.build === 'tall') { bodyH = 1.15; totalH = 1.52; }
    if (data.build === 'slim') { bodyW = 0.2; }

    // Body
    const body = new THREE.Mesh(new THREE.CylinderGeometry(bodyW - 0.02, bodyW, bodyH, 12), bodyMat);
    body.position.y = bodyH / 2 + 0.2;
    group.add(body);

    // Head
    const head = new THREE.Mesh(new THREE.SphereGeometry(headR, 16, 12), skinMat);
    head.position.y = bodyH + 0.2 + headR + 0.04;
    group.add(head);

    // Eyes
    const eyeY = head.position.y + 0.02;
    for (const side of [-1, 1]) {
      const eye = new THREE.Mesh(new THREE.SphereGeometry(0.025, 8, 6), darkMat);
      eye.position.set(side * 0.065, eyeY, headR * 0.82);
      group.add(eye);
    }

    // Arms
    const armMat = data.accessory === 'jacket' ? new THREE.MeshStandardMaterial({ color: 0x333333, roughness: 0.5 }) : bodyMat;
    for (const side of [-1, 1]) {
      const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.045, 0.55, 8), armMat);
      arm.position.set(side * (bodyW + 0.07), bodyH / 2 + 0.15, 0);
      arm.rotation.z = side * 0.15;
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
    case 'beret': {
      const beret = new THREE.Mesh(
        new THREE.SphereGeometry(0.16, 12, 6, 0, Math.PI * 2, 0, Math.PI / 2),
        new THREE.MeshStandardMaterial({ color: 0x8B0000, roughness: 0.5 })
      );
      beret.position.set(0.03, headY + headR - 0.02, 0);
      beret.scale.set(1, 0.4, 1);
      group.add(beret);
      break;
    }
    case 'headphones': {
      const hpMat = new THREE.MeshStandardMaterial({ color: 0x222222, roughness: 0.3, metalness: 0.5 });
      // Band
      const band = new THREE.Mesh(new THREE.TorusGeometry(headR + 0.04, 0.02, 8, 16, Math.PI), hpMat);
      band.position.set(0, headY + headR * 0.3, 0);
      band.rotation.z = Math.PI;
      band.rotation.y = Math.PI / 2;
      group.add(band);
      // Ear cups
      for (const side of [-1, 1]) {
        const cup = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.04, 12), hpMat);
        cup.position.set(side * (headR + 0.03), headY, 0);
        cup.rotation.z = Math.PI / 2;
        group.add(cup);
      }
      break;
    }
    case 'glasses': {
      const glassMat = new THREE.MeshStandardMaterial({ color: 0x333333, metalness: 0.3, roughness: 0.3 });
      // Frames
      for (const side of [-1, 1]) {
        const lens = new THREE.Mesh(new THREE.TorusGeometry(0.045, 0.008, 6, 12), glassMat);
        lens.position.set(side * 0.06, headY + 0.02, headR * 0.85);
        group.add(lens);
      }
      // Bridge
      const bridge = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.008, 0.008), glassMat);
      bridge.position.set(0, headY + 0.02, headR * 0.85);
      group.add(bridge);
      break;
    }
    case 'scarf': {
      const scarfMat = new THREE.MeshStandardMaterial({ color: 0xC62828, roughness: 0.6 });
      const scarf = new THREE.Mesh(new THREE.TorusGeometry(bodyW + 0.02, 0.05, 8, 16), scarfMat);
      scarf.position.y = bodyH + 0.15;
      scarf.rotation.x = Math.PI / 2;
      group.add(scarf);
      // Hanging end
      const tail = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.3, 0.03), scarfMat);
      tail.position.set(bodyW * 0.5, bodyH, 0.1);
      tail.rotation.z = 0.2;
      group.add(tail);
      break;
    }
    case 'bun': {
      const bunMat = new THREE.MeshStandardMaterial({ color: 0x2C1A0E, roughness: 0.6 });
      // Hair bun on top
      const bun = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 8), bunMat);
      bun.position.set(0, headY + headR + 0.04, -0.03);
      group.add(bun);
      // Hair base
      const hair = new THREE.Mesh(
        new THREE.SphereGeometry(headR + 0.02, 12, 8, 0, Math.PI * 2, 0, Math.PI * 0.6),
        bunMat
      );
      hair.position.set(0, headY + 0.02, -0.01);
      group.add(hair);
      break;
    }
    case 'cap': {
      const capMat = new THREE.MeshStandardMaterial({ color: 0x1B5E20, roughness: 0.5 });
      // Cap dome
      const dome = new THREE.Mesh(
        new THREE.SphereGeometry(headR + 0.03, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2),
        capMat
      );
      dome.position.set(0, headY + headR * 0.15, 0);
      dome.scale.set(1, 0.5, 1);
      group.add(dome);
      // Brim
      const brim = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 0.02, 16, 1, false, 0, Math.PI), capMat);
      brim.position.set(0, headY + headR * 0.15, 0.08);
      brim.rotation.x = -0.1;
      group.add(brim);
      break;
    }
    case 'jacket': {
      const jacketMat = new THREE.MeshStandardMaterial({ color: 0x333333, roughness: 0.5 });
      // Jacket overlay (slightly larger than body)
      const jacket = new THREE.Mesh(new THREE.CylinderGeometry(bodyW + 0.03, bodyW + 0.04, bodyH * 0.7, 12), jacketMat);
      jacket.position.y = bodyH / 2 + 0.2;
      group.add(jacket);
      // Collar
      const collar = new THREE.Mesh(new THREE.TorusGeometry(bodyW - 0.02, 0.03, 6, 12), jacketMat);
      collar.position.y = bodyH + 0.12;
      collar.rotation.x = Math.PI / 2;
      group.add(collar);
      break;
    }
    case 'bowtie': {
      const bowMat = new THREE.MeshStandardMaterial({ color: 0xB71C1C, roughness: 0.4 });
      // Two triangles for the bow
      for (const side of [-1, 1]) {
        const wing = new THREE.Mesh(new THREE.ConeGeometry(0.04, 0.07, 4), bowMat);
        wing.position.set(side * 0.04, bodyH + 0.16, bodyW * 0.8);
        wing.rotation.z = side * Math.PI / 2;
        group.add(wing);
      }
      // Center knot
      const knot = new THREE.Mesh(new THREE.SphereGeometry(0.02, 8, 6), bowMat);
      knot.position.set(0, bodyH + 0.16, bodyW * 0.8);
      group.add(knot);
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
      // Smooth rotation toward player
      let diff = targetAngle - group.rotation.y;
      // Normalize to [-PI, PI]
      while (diff > Math.PI) diff -= Math.PI * 2;
      while (diff < -Math.PI) diff += Math.PI * 2;
      group.rotation.y += diff * Math.min(1, FACE_SPEED * (1 / 60));
    }
  }
}
