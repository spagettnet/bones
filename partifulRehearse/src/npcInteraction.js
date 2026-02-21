import * as THREE from 'three';
import { sendMessage } from './llmChat.js';

const MAX_INTERACT_DISTANCE = 3;
const MAX_HISTORY = 20;

export function setupInteraction(camera, npcMeshes, controls, ui) {
  const raycaster = new THREE.Raycaster();
  const center = new THREE.Vector2(0, 0);

  let activeNPC = null;
  let abortController = null;
  let sending = false;

  async function onChatSend(text) {
    if (!activeNPC || !text.trim() || sending) return;
    const msg = text.trim();
    const input = ui.getChatInput();
    input.value = '';
    sending = true;

    ui.addChatMessage('You', msg, 'user');
    ui.addChatMessage(activeNPC.userData.npcName, '', 'npc');
    ui.setChatStatus('thinking...');

    const history = activeNPC.userData.conversationHistory.slice(-MAX_HISTORY);

    abortController = new AbortController();

    try {
      const full = await sendMessage(
        activeNPC.userData.systemPrompt,
        history,
        msg,
        (chunk) => {
          ui.setChatStatus('');
          ui.appendToLastMessage(chunk);
        },
        abortController.signal,
      );

      activeNPC.userData.conversationHistory.push(
        { role: 'user', content: msg },
        { role: 'assistant', content: full },
      );
      ui.setChatStatus('');
    } catch (err) {
      if (err.name !== 'AbortError') {
        ui.setChatStatus('Error: ' + err.message);
      }
    } finally {
      sending = false;
      abortController = null;
    }
  }

  function onClick() {
    if (!controls.controls.isLocked) return;

    // If canned dialogue is open, close it
    if (ui.isDialogueOpen()) {
      ui.hideDialogue();
      controls.resumeMovement();
      return;
    }

    // If chat is open, ignore clicks (use Escape to close)
    if (ui.isChatOpen()) return;

    // Raycast from screen center
    raycaster.setFromCamera(center, camera);
    const hits = raycaster.intersectObjects(npcMeshes, false);

    if (hits.length === 0) return;

    const hit = hits[0];
    if (hit.distance > MAX_INTERACT_DISTANCE) return;

    // Walk up to find the NPC group
    let obj = hit.object;
    while (obj && !obj.userData.npcId) {
      obj = obj.parent;
    }
    if (!obj) return;

    if (obj.userData.isLLM) {
      // LLM chat mode
      activeNPC = obj;
      const color = '#' + new THREE.Color(obj.userData.npcColor).getHexString();
      ui.showChat(obj.userData.npcName, color);
      controls.pauseMovement();
    } else {
      // Canned message mode
      const { npcName, npcColor, messages } = obj.userData;
      const idx = obj.userData.messageIndex;
      const message = messages[idx];
      obj.userData.messageIndex = (idx + 1) % messages.length;

      ui.showDialogue(npcName, '#' + new THREE.Color(npcColor).getHexString(), message);
      controls.pauseMovement();
    }
  }

  function onKeyDown(e) {
    // Close canned dialogue with E
    if (e.key.toLowerCase() === 'e' && ui.isDialogueOpen()) {
      ui.hideDialogue();
      controls.resumeMovement();
      return;
    }

    // Close chat with Cmd+E / Ctrl+E
    if (e.key.toLowerCase() === 'e' && (e.metaKey || e.ctrlKey) && ui.isChatOpen()) {
      e.preventDefault();
      ui.hideChat();
      controls.resumeMovement();
      return;
    }

    // Send chat message with Enter
    if (e.key === 'Enter' && ui.isChatOpen()) {
      e.preventDefault();
      const input = ui.getChatInput();
      onChatSend(input.value);
    }
  }

  window.addEventListener('click', onClick);
  window.addEventListener('keydown', onKeyDown);
}
