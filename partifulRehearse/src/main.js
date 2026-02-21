import * as THREE from 'three';
import { setupControls } from './controls.js';
import { setupInteraction } from './npcInteraction.js';
import { setupUI, showPicker, hidePicker, updateInstructions } from './ui.js';
import { setupAudio } from './audio.js';
import { setProfiles, setApiKey, getApiKey, setPhotoURL } from './customPartyState.js';
import { parseProfiles } from './profileParser.js';

// Location picker
const cards = document.querySelectorAll('.location-card');
const profileInput = document.getElementById('profile-input');
const profileBack = document.getElementById('profile-back');
const profilesTextarea = document.getElementById('profiles-textarea');
const apiKeyInput = document.getElementById('api-key-input');
const startBtn = document.getElementById('start-custom-party');
const parseError = document.getElementById('parse-error');

// Photo assignment
const photoAssign = document.getElementById('photo-assign');
const photoGrid = document.getElementById('photo-grid');
const photoBackLink = document.getElementById('photo-back');
const launchBtn = document.getElementById('launch-party');

// Pre-fill saved API key
apiKeyInput.value = getApiKey();

const JUDGE_PROFILES = [
  {
    name: 'Jonathan Murray',
    headline: 'Building AI Tinkerers in NYC and beyond',
    context: 'NYC GM of AI Tinkerers, Managing Partner at 10by10 Group LLC, Harvard Business School Online. Organizes the best community of founders and builders tinkering on the bleeding edge of LLMs and generative AI.',
    photoURL: '/judges/jonathan.jpg',
  },
  {
    name: 'Jiahe Xiao',
    headline: 'Staff Software Engineer at Anthropic',
    context: 'Member of Technical Staff at Anthropic, previously at Block/Cash App, Robinhood, and Amazon. UVA CS + Biology, Stanford AI & Deep Generative Models certs. Full-stack engineer specializing in distributed systems.',
    photoURL: '/judges/jiahe.jpg',
  },
];

cards.forEach(card => {
  card.addEventListener('click', () => {
    const loc = card.dataset.location;
    if (loc === 'custom') {
      hidePicker();
      profileInput.style.display = 'flex';
      return;
    }
    if (loc === 'judges') {
      hidePicker();
      setProfiles(JUDGE_PROFILES);
      if (getApiKey()) {
        loadLocation('custom');
      } else {
        // Show profile-input with just the API key field
        profilesTextarea.style.display = 'none';
        document.querySelector('#profile-input h2').textContent = 'Meet the Judges';
        document.querySelector('#profile-input .hint').textContent = 'Enter your Claude API key to start.';
        startBtn.textContent = 'Launch';
        startBtn.dataset.judges = 'true';
        profileInput.style.display = 'flex';
      }
      return;
    }
    loadLocation(loc);
  });
});

// Profile input: back button
profileBack.addEventListener('click', () => {
  profileInput.style.display = 'none';
  showPicker();
});

// Start custom party — parse step
startBtn.addEventListener('click', async () => {
  parseError.textContent = '';

  const key = apiKeyInput.value.trim();
  if (!key) {
    parseError.textContent = 'Enter your Claude API key.';
    return;
  }

  setApiKey(key);

  // Judges flow — profiles already set, skip parsing
  if (startBtn.dataset.judges === 'true') {
    profileInput.style.display = 'none';
    // Reset UI state for next time
    startBtn.dataset.judges = '';
    startBtn.textContent = 'Start Party';
    profilesTextarea.style.display = '';
    document.querySelector('#profile-input h2').textContent = "Who's coming to the party?";
    document.querySelector('#profile-input .hint').textContent = 'Paste LinkedIn profiles separated by blank lines. First line = name, second = headline.';
    loadLocation('custom');
    return;
  }

  const raw = profilesTextarea.value.trim();
  if (!raw) {
    parseError.textContent = 'Paste at least one profile.';
    return;
  }

  startBtn.disabled = true;
  startBtn.textContent = 'Reading profiles...';
  parseError.style.color = 'rgba(255,255,255,0.4)';
  parseError.textContent = 'Sending to Claude to extract attendees...';

  try {
    const profiles = await parseProfiles(raw);
    if (profiles.length === 0) {
      throw new Error('No profiles found in the text.');
    }

    setProfiles(profiles);
    profileInput.style.display = 'none';
    showPhotoAssign(profiles);
  } catch (err) {
    parseError.style.color = '#e74c3c';
    parseError.textContent = err.message;
  } finally {
    startBtn.disabled = false;
    startBtn.textContent = 'Start Party';
  }
});

// ---- Photo assignment screen ----

function showPhotoAssign(profiles) {
  photoGrid.innerHTML = '';

  profiles.forEach((p, i) => {
    const card = document.createElement('div');
    card.className = 'photo-card';

    const name = document.createElement('div');
    name.className = 'pc-name';
    name.textContent = p.name;

    const headline = document.createElement('div');
    headline.className = 'pc-headline';
    headline.textContent = p.headline;

    const drop = document.createElement('div');
    drop.className = 'photo-drop';

    const label = document.createElement('div');
    label.className = 'drop-label';
    label.textContent = 'drop photo';

    const fileInput = document.createElement('input');
    fileInput.type = 'file';
    fileInput.accept = 'image/*';

    drop.appendChild(label);
    drop.appendChild(fileInput);

    // Click to pick
    drop.addEventListener('click', () => fileInput.click());

    // File chosen
    fileInput.addEventListener('change', () => {
      if (fileInput.files[0]) applyPhoto(drop, fileInput.files[0], i);
    });

    // Drag and drop
    drop.addEventListener('dragover', (e) => {
      e.preventDefault();
      drop.classList.add('dragover');
    });
    drop.addEventListener('dragleave', () => drop.classList.remove('dragover'));
    drop.addEventListener('drop', (e) => {
      e.preventDefault();
      drop.classList.remove('dragover');
      const file = e.dataTransfer.files[0];
      if (file && file.type.startsWith('image/')) applyPhoto(drop, file, i);
    });

    card.appendChild(drop);
    card.appendChild(name);
    card.appendChild(headline);
    photoGrid.appendChild(card);
  });

  photoAssign.style.display = 'flex';
}

function applyPhoto(drop, file, index) {
  const url = URL.createObjectURL(file);
  setPhotoURL(index, url);

  // Show preview
  let img = drop.querySelector('img');
  if (!img) {
    img = document.createElement('img');
    drop.appendChild(img);
  }
  img.src = url;

  // Hide label
  const label = drop.querySelector('.drop-label');
  if (label) label.style.display = 'none';
}

photoBackLink.addEventListener('click', () => {
  photoAssign.style.display = 'none';
  profileInput.style.display = 'flex';
});

launchBtn.addEventListener('click', () => {
  photoAssign.style.display = 'none';
  loadLocation('custom');
});

// ---- Location loader ----

function loadLocation(id) {
  const picker = document.getElementById('location-picker');
  picker.style.opacity = '0';
  picker.style.transition = 'opacity 0.3s ease';

  setTimeout(async () => {
    hidePicker();

    const location = await import(`./locations/${id}/index.js`);
    const { config } = location;

    const scene = new THREE.Scene();
    if (config.fog) {
      scene.fog = new THREE.FogExp2(config.fog.color, config.fog.density);
    }
    if (config.background != null) {
      scene.background = new THREE.Color(config.background);
    }

    const camera = new THREE.PerspectiveCamera(
      config.fov,
      window.innerWidth / window.innerHeight,
      0.1,
      config.far
    );
    camera.position.set(...config.spawn);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = config.toneMappingExposure;
    if (config.shadows) {
      renderer.shadowMap.enabled = true;
      renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    }
    document.body.appendChild(renderer.domElement);

    let extrasHandle = null;
    if (location.extras) {
      extrasHandle = location.extras(scene);
    }

    const wallBounds = location.buildEnvironment(scene);
    location.setupLighting(scene);
    const { npcGroups, npcMeshes } = location.createNPCs(scene);

    const playerControls = setupControls(camera, renderer, config.boundary);

    const audio = setupAudio(config.music);
    playerControls.controls.addEventListener('lock', () => audio.resume());

    updateInstructions(config.name, config.subtitle);
    const instructions = document.getElementById('instructions');
    instructions.style.display = 'flex';
    const ui = setupUI(playerControls);

    setupInteraction(camera, npcMeshes, playerControls, ui);

    window.addEventListener('resize', () => {
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(window.innerWidth, window.innerHeight);
    });

    const clock = new THREE.Clock();

    function animate() {
      requestAnimationFrame(animate);
      const delta = clock.getDelta();
      const elapsed = clock.getElapsedTime();

      playerControls.update(delta, wallBounds);
      audio.update(delta, playerControls.isWalking());
      location.animateNPCs(npcGroups, elapsed, camera.position);
      if (extrasHandle) extrasHandle.update(elapsed);

      renderer.render(scene, camera);
    }

    animate();
  }, 300);
}
