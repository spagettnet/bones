import * as THREE from 'three';
import { getProfiles } from '../../customPartyState.js';

const SAFE_POSITIONS = [
  [-4.5, 0, -6.5],
  [-9.5, 0, 0.5],
  [10, 0, 3.5],
  [7, 0, -2],
  [0, 0, 3],
  [5.5, 0, -7.5],
  [-6.5, 0, 7],
  [6, 0, 7.5],
  [-3, 0, -2],
  [3, 0, -5],
  [-8, 0, 5],
  [8, 0, -5],
  [-2, 0, 7],
  [4, 0, 1],
  [-6, 0, -3],
];

const COLOR_POOL = [0xFF69B4, 0x00CED1, 0xDAA520, 0x98FF98, 0x9B59B6, 0xFF6B35, 0x00E5FF, 0xFFD700, 0xE74C3C, 0x2ECC71];
const SKIN_POOL = [0xF5D0C5, 0x8D5524, 0xC68642, 0xE8B88A, 0xFFDBAC, 0xD4A574, 0xF1C27D, 0x6B4423];
const BUILD_POOL = ['slim', 'stocky', 'tall', 'average'];
const ACCESSORY_POOL = ['beret', 'headphones', 'glasses', 'scarf', 'bun', 'cap', 'bowtie'];

function pick(arr, i) { return arr[i % arr.length]; }

function generateNPCData() {
  const profiles = getProfiles();
  return profiles.map((p, i) => {
    const vi = i >= 1 ? i + 1 : i; // skip visual index 1
    return {
    id: `custom-${i}`,
    name: p.name,
    color: pick(COLOR_POOL, vi),
    skinColor: pick(SKIN_POOL, vi + 3),
    position: SAFE_POSITIONS[i % SAFE_POSITIONS.length],
    rotationY: Math.PI * (0.3 + i * 0.4),
    build: pick(BUILD_POOL, vi),
    accessory: pick(ACCESSORY_POOL, vi),
    photoURL: p.photoURL || null,
    isLLM: true,
    systemPrompt: `You are ${p.name} at a house party. Background: ${p.headline}${p.context ? ', ' + p.context : ''}. You're chatting with someone you just met. CRITICAL RULE: Never use asterisks. Never write action descriptions like *smiles* or *nods* or *laughs*. Never use roleplay formatting. Output only spoken words, nothing else. Talk like a normal person — not too eager, not too stiff. Keep it casual — sometimes just a few words, sometimes a sentence or two. Vary your length a lot. Short quips, half-thoughts, trailing off, quick reactions like "hah yeah" or "oh wait really?" are all good. Never monologue. Match the energy of the conversation. Stay in character.`,
  };
  });
}

// Create a circular face texture from an image URL
function loadFaceTexture(url) {
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      // Draw circular crop onto canvas
      const size = 256;
      const canvas = document.createElement('canvas');
      canvas.width = size;
      canvas.height = size;
      const ctx = canvas.getContext('2d');

      // Circular clip
      ctx.beginPath();
      ctx.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2);
      ctx.closePath();
      ctx.clip();

      // Draw image covering the circle
      const scale = Math.max(size / img.width, size / img.height);
      const w = img.width * scale;
      const h = img.height * scale;
      ctx.drawImage(img, (size - w) / 2, (size - h) / 2, w, h);

      // Sample top strip of the circular crop to extract hair color
      const strip = ctx.getImageData(64, 5, 128, 20).data;
      let r = 0, g = 0, b = 0, count = 0;
      for (let i = 0; i < strip.length; i += 4) {
        if (strip[i + 3] > 128) { // only opaque pixels (inside circle clip)
          r += strip[i]; g += strip[i + 1]; b += strip[i + 2]; count++;
        }
      }
      if (count > 0) { r /= count; g /= count; b /= count; }
      const hairColor = (Math.round(r) << 16) | (Math.round(g) << 8) | Math.round(b);

      const texture = new THREE.CanvasTexture(canvas);
      texture.colorSpace = THREE.SRGBColorSpace;
      resolve({ texture, hairColor });
    };
    img.onerror = () => resolve({ texture: null, hairColor: null });
    img.src = url;
  });
}

export function createNPCs(scene) {
  const npcGroups = [];
  const npcMeshes = [];

  for (const data of generateNPCData()) {
    const group = new THREE.Group();
    group.userData.npcId = data.id;
    group.userData.npcName = data.name;
    group.userData.npcColor = data.color;
    group.userData.messages = [`Hey! I'm ${data.name}. Come chat with me.`];
    group.userData.messageIndex = 0;
    group.userData.isLLM = true;
    group.userData.systemPrompt = data.systemPrompt;
    group.userData.conversationHistory = [];

    const bodyMat = new THREE.MeshStandardMaterial({ color: data.color, roughness: 0.5 });
    const skinMat = new THREE.MeshStandardMaterial({ color: data.skinColor, roughness: 0.6 });
    const darkMat = new THREE.MeshStandardMaterial({ color: 0x1a1a1a });

    let bodyW = 0.24, bodyH = 1.0, headR = 0.18;
    if (data.build === 'stocky') { bodyW = 0.32; bodyH = 0.9; }
    if (data.build === 'tall') { bodyH = 1.15; }
    if (data.build === 'slim') { bodyW = 0.2; }

    // Body
    const body = new THREE.Mesh(new THREE.CylinderGeometry(bodyW - 0.02, bodyW, bodyH, 12), bodyMat);
    body.position.y = bodyH / 2 + 0.2;
    group.add(body);

    // Head
    const head = new THREE.Mesh(new THREE.SphereGeometry(headR, 16, 12), skinMat);
    head.position.y = bodyH + 0.2 + headR + 0.04;
    group.add(head);

    // Eyes (only if no photo — photo replaces the face)
    if (!data.photoURL) {
      const eyeY = head.position.y + 0.02;
      for (const side of [-1, 1]) {
        const eye = new THREE.Mesh(new THREE.SphereGeometry(0.025, 8, 6), darkMat);
        eye.position.set(side * 0.065, eyeY, headR * 0.82);
        group.add(eye);
      }
    }

    // Face photo — circular plane in front of head
    if (data.photoURL) {
      const faceR = headR * 0.85;
      const faceGeo = new THREE.CircleGeometry(faceR, 32);
      // Placeholder material — texture loaded async
      const faceMat = new THREE.MeshBasicMaterial({
        color: 0xffffff,
        transparent: true,
        opacity: 0,
      });
      const faceMesh = new THREE.Mesh(faceGeo, faceMat);
      faceMesh.position.set(0, head.position.y, headR + 0.01);
      group.add(faceMesh);

      // Load texture async, apply face photo, and add hair mesh
      const headY = head.position.y;
      loadFaceTexture(data.photoURL).then(({ texture: tex, hairColor }) => {
        if (tex) {
          faceMat.map = tex;
          faceMat.opacity = 1;
          faceMat.needsUpdate = true;
        }
        if (hairColor != null) {
          const hairGeo = new THREE.SphereGeometry(headR + 0.02, 16, 12, 0, Math.PI * 2, 0, Math.PI * 0.5);
          const hairMat = new THREE.MeshStandardMaterial({ color: hairColor, roughness: 0.7 });
          const hairMesh = new THREE.Mesh(hairGeo, hairMat);
          hairMesh.position.set(0, headY + 0.02, -0.04);
          group.add(hairMesh);
        }
      });
    }

    // Arms
    const armMat = data.accessory === 'jacket' ? new THREE.MeshStandardMaterial({ color: 0x333333, roughness: 0.5 }) : bodyMat;
    for (const side of [-1, 1]) {
      const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.045, 0.55, 8), armMat);
      arm.position.set(side * (bodyW + 0.07), bodyH / 2 + 0.15, 0);
      arm.rotation.z = side * 0.15;
      group.add(arm);
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
      const band = new THREE.Mesh(new THREE.TorusGeometry(headR + 0.04, 0.02, 8, 16, Math.PI), hpMat);
      band.position.set(0, headY + headR * 0.3, 0);
      band.rotation.z = Math.PI;
      band.rotation.y = Math.PI / 2;
      group.add(band);
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
    case 'scarf': {
      const scarfMat = new THREE.MeshStandardMaterial({ color: 0xC62828, roughness: 0.6 });
      const scarf = new THREE.Mesh(new THREE.TorusGeometry(bodyW + 0.02, 0.05, 8, 16), scarfMat);
      scarf.position.y = bodyH + 0.15;
      scarf.rotation.x = Math.PI / 2;
      group.add(scarf);
      const tail = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.3, 0.03), scarfMat);
      tail.position.set(bodyW * 0.5, bodyH, 0.1);
      tail.rotation.z = 0.2;
      group.add(tail);
      break;
    }
    case 'bun': {
      const bunMat = new THREE.MeshStandardMaterial({ color: 0x2C1A0E, roughness: 0.6 });
      const bun = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 8), bunMat);
      bun.position.set(0, headY + headR + 0.04, -0.03);
      group.add(bun);
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
      const dome = new THREE.Mesh(
        new THREE.SphereGeometry(headR + 0.03, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2),
        capMat
      );
      dome.position.set(0, headY + headR * 0.15, 0);
      dome.scale.set(1, 0.5, 1);
      group.add(dome);
      const brim = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 0.02, 16, 1, false, 0, Math.PI), capMat);
      brim.position.set(0, headY + headR * 0.15, 0.08);
      brim.rotation.x = -0.1;
      group.add(brim);
      break;
    }
    case 'jacket': {
      const jacketMat = new THREE.MeshStandardMaterial({ color: 0x333333, roughness: 0.5 });
      const jacket = new THREE.Mesh(new THREE.CylinderGeometry(bodyW + 0.03, bodyW + 0.04, bodyH * 0.7, 12), jacketMat);
      jacket.position.y = bodyH / 2 + 0.2;
      group.add(jacket);
      const collar = new THREE.Mesh(new THREE.TorusGeometry(bodyW - 0.02, 0.03, 6, 12), jacketMat);
      collar.position.y = bodyH + 0.12;
      collar.rotation.x = Math.PI / 2;
      group.add(collar);
      break;
    }
    case 'bowtie': {
      const bowMat = new THREE.MeshStandardMaterial({ color: 0xB71C1C, roughness: 0.4 });
      for (const side of [-1, 1]) {
        const wing = new THREE.Mesh(new THREE.ConeGeometry(0.04, 0.07, 4), bowMat);
        wing.position.set(side * 0.04, bodyH + 0.16, bodyW * 0.8);
        wing.rotation.z = side * Math.PI / 2;
        group.add(wing);
      }
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
    group.position.y = Math.sin(time * 2 + i * 1.3) * 0.03;

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
