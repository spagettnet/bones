export function setupUI(controls) {
  const instructions = document.getElementById('instructions');
  const crosshair = document.getElementById('crosshair');
  const dialogue = document.getElementById('dialogue');
  const dialogueName = document.getElementById('dialogue-name');
  const dialogueMessage = document.getElementById('dialogue-message');
  const backLink = document.getElementById('back-to-picker');

  const chatDialogue = document.getElementById('chat-dialogue');
  const chatNpcName = document.getElementById('chat-npc-name');
  const chatMessages = document.getElementById('chat-messages');
  const chatInput = document.getElementById('chat-input');
  const chatStatus = document.getElementById('chat-status');

  let dialogueOpen = false;
  let chatOpen = false;

  // Click instructions to lock pointer
  instructions.addEventListener('click', (e) => {
    if (e.target === backLink) return;
    controls.controls.lock();
  });

  // Back to picker = full reload
  if (backLink) {
    backLink.addEventListener('click', (e) => {
      e.stopPropagation();
      window.location.reload();
    });
  }

  controls.controls.addEventListener('lock', () => {
    instructions.style.display = 'none';
    crosshair.style.display = 'block';
  });

  controls.controls.addEventListener('unlock', () => {
    if (chatOpen) {
      hideChat();
      controls.resumeMovement();
      // Don't show menu — re-lock on next click
      const reLock = () => {
        controls.controls.lock();
        document.removeEventListener('click', reLock);
      };
      document.addEventListener('click', reLock);
      return;
    }
    if (!dialogueOpen) {
      instructions.style.display = 'flex';
      crosshair.style.display = 'none';
    }
  });

  function showDialogue(name, color, message) {
    dialogueName.textContent = name;
    dialogueName.style.color = color;
    dialogueMessage.textContent = message;
    dialogue.style.display = 'block';
    dialogueOpen = true;
  }

  function hideDialogue() {
    dialogue.style.display = 'none';
    dialogueOpen = false;
  }

  function isDialogueOpen() {
    return dialogueOpen;
  }

  // ---- Chat functions ----

  function showChat(name, color) {
    chatNpcName.textContent = name;
    chatNpcName.style.color = color;
    chatMessages.innerHTML = '';
    chatStatus.textContent = '';
    chatDialogue.style.display = 'flex';
    chatOpen = true;
    chatInput.value = '';
    chatInput.focus();
  }

  function hideChat() {
    chatDialogue.style.display = 'none';
    chatOpen = false;
    chatInput.blur();
    chatStatus.textContent = '';
  }

  function isChatOpen() {
    return chatOpen;
  }

  function addChatMessage(label, text, type) {
    const msg = document.createElement('div');
    msg.className = `msg ${type}`;

    const lbl = document.createElement('div');
    lbl.className = 'msg-label';
    lbl.textContent = label;
    msg.appendChild(lbl);

    const txt = document.createElement('div');
    txt.className = 'msg-text';
    txt.textContent = text;
    msg.appendChild(txt);

    chatMessages.appendChild(msg);
    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  function appendToLastMessage(chunk) {
    const last = chatMessages.querySelector('.msg:last-child .msg-text');
    if (last) {
      last.textContent += chunk;
      chatMessages.scrollTop = chatMessages.scrollHeight;
    }
  }

  function setChatStatus(text) {
    chatStatus.textContent = text;
  }

  function getChatInput() {
    return chatInput;
  }

  return {
    showDialogue, hideDialogue, isDialogueOpen,
    showChat, hideChat, isChatOpen,
    addChatMessage, appendToLastMessage, setChatStatus,
    getChatInput,
  };
}

export function showPicker() {
  document.getElementById('location-picker').style.display = 'flex';
}

export function hidePicker() {
  document.getElementById('location-picker').style.display = 'none';
}

export function updateInstructions(name, subtitle) {
  document.getElementById('instructions-title').textContent = name;
  document.getElementById('instructions-subtitle').textContent = subtitle;
}
