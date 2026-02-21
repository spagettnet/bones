let profiles = [];
let apiKey = localStorage.getItem('bones-api-key') || '';

export function setProfiles(p) { profiles = p; }
export function getProfiles() { return profiles; }

export function setPhotoURL(index, url) {
  if (profiles[index]) profiles[index].photoURL = url;
}

export function setApiKey(k) {
  apiKey = k;
  localStorage.setItem('bones-api-key', k);
}
export function getApiKey() { return apiKey; }
