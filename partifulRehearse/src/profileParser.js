import { getApiKey } from './customPartyState.js';

const SYSTEM = `You extract attendee profiles from raw pasted text (LinkedIn pages, bios, etc).
Return ONLY a JSON array. Each element: { "name": "Full Name", "headline": "Short title/role", "context": "Relevant background details, interests, conversation hooks" }.
Be concise — headline under 10 words, context under 40 words.
If the text contains only one person, return a single-element array.
Never return anything outside the JSON array.`;

export async function parseProfiles(rawText) {
  const res = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      apiKey: getApiKey(),
      system: SYSTEM,
      messages: [{ role: 'user', content: rawText }],
      stream: false,
      max_tokens: 4096,
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(err || `API error ${res.status}`);
  }

  const data = await res.json();
  const text = data.content?.[0]?.text || '';

  // Extract JSON array from response (in case of markdown fences)
  const match = text.match(/\[[\s\S]*\]/);
  if (!match) throw new Error('Could not parse profiles from response');

  const profiles = JSON.parse(match[0]);
  if (!Array.isArray(profiles) || profiles.length === 0) {
    throw new Error('No profiles found');
  }

  return profiles.map(p => ({
    name: p.name || 'Unknown',
    headline: p.headline || '',
    context: p.context || '',
  }));
}
