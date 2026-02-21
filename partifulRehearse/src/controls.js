import * as THREE from 'three';
import { PointerLockControls } from 'three/addons/controls/PointerLockControls.js';

const SPEED = 11.0;
const FRICTION = 20.0;
const PLAYER_RADIUS = 0.3;
const EYE_HEIGHT = 1.6;
const MAX_DELTA = 0.1;
const HEAD_BOB_AMOUNT = 0.03;
const HEAD_BOB_SPEED = 10.0;

export function setupControls(camera, renderer, boundary) {
  const controls = new PointerLockControls(camera, renderer.domElement);

  const keys = { w: false, a: false, s: false, d: false };
  const velocity = new THREE.Vector3();
  let movementPaused = false;
  let headBobPhase = 0;
  let isMoving = false;

  window.addEventListener('keydown', (e) => {
    const k = e.key.toLowerCase();
    if (k in keys) keys[k] = true;
  });

  window.addEventListener('keyup', (e) => {
    const k = e.key.toLowerCase();
    if (k in keys) keys[k] = false;
  });

  function pauseMovement() { movementPaused = true; }
  function resumeMovement() { movementPaused = false; }

  function update(delta, wallBounds) {
    if (!controls.isLocked || movementPaused) return;

    delta = Math.min(delta, MAX_DELTA);

    // Input direction
    const input = new THREE.Vector3();
    if (keys.w) input.z -= 1;
    if (keys.s) input.z += 1;
    if (keys.a) input.x -= 1;
    if (keys.d) input.x += 1;

    isMoving = input.lengthSq() > 0;

    if (isMoving) {
      input.normalize();
      const forward = new THREE.Vector3();
      camera.getWorldDirection(forward);
      forward.y = 0;
      forward.normalize();
      const right = new THREE.Vector3().crossVectors(forward, new THREE.Vector3(0, 1, 0)).normalize();

      const move = new THREE.Vector3();
      move.addScaledVector(forward, -input.z);
      move.addScaledVector(right, input.x);
      move.normalize();

      velocity.x += move.x * SPEED * delta * FRICTION;
      velocity.z += move.z * SPEED * delta * FRICTION;
    }

    // Friction
    velocity.x -= velocity.x * FRICTION * delta;
    velocity.z -= velocity.z * FRICTION * delta;

    // Try X movement
    const pos = camera.position;
    const newX = pos.x + velocity.x * delta;
    if (!collidesAt(newX, pos.z, wallBounds)) {
      pos.x = newX;
    } else {
      velocity.x = 0;
    }

    // Try Z movement
    const newZ = pos.z + velocity.z * delta;
    if (!collidesAt(pos.x, newZ, wallBounds)) {
      pos.z = newZ;
    } else {
      velocity.z = 0;
    }

    // Boundary clamping (if configured)
    if (boundary != null) {
      pos.x = Math.max(-boundary, Math.min(boundary, pos.x));
      pos.z = Math.max(-boundary, Math.min(boundary, pos.z));
    }

    // Head bob
    const speed = Math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    if (isMoving && speed > 0.5) {
      headBobPhase += delta * HEAD_BOB_SPEED;
      pos.y = EYE_HEIGHT + Math.sin(headBobPhase) * HEAD_BOB_AMOUNT;
    } else {
      // Smoothly return to eye height
      pos.y += (EYE_HEIGHT - pos.y) * Math.min(1, delta * 10);
      headBobPhase = 0;
    }
  }

  function collidesAt(x, z, wallBounds) {
    const playerBox = new THREE.Box3(
      new THREE.Vector3(x - PLAYER_RADIUS, 0, z - PLAYER_RADIUS),
      new THREE.Vector3(x + PLAYER_RADIUS, EYE_HEIGHT, z + PLAYER_RADIUS)
    );
    for (const wall of wallBounds) {
      if (playerBox.intersectsBox(wall)) return true;
    }
    return false;
  }

  function isWalking() {
    if (!controls.isLocked || movementPaused) return false;
    const speed = Math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    return isMoving && speed > 0.5;
  }

  return { controls, update, pauseMovement, resumeMovement, isWalking };
}
