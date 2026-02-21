import { getApiKey } from './customPartyState.js';

export async function sendMessage(systemPrompt, history, userMessage, onChunk, signal) {
  const messages = [
    ...history,
    { role: 'user', content: userMessage }
  ];

  const res = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      apiKey: getApiKey(),
      system: systemPrompt,
      messages,
    }),
    signal,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `API error ${res.status}`);
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let full = '';
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop(); // keep incomplete line

    for (const line of lines) {
      if (!line.startsWith('data: ')) continue;
      const payload = line.slice(6);
      if (payload === '[DONE]') continue;

      try {
        const evt = JSON.parse(payload);
        if (evt.type === 'content_block_delta' && evt.delta?.text) {
          full += evt.delta.text;
          onChunk(evt.delta.text);
        }
      } catch {
        // skip malformed JSON
      }
    }
  }

  return full;
}
