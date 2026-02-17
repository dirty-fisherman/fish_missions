import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.tsx';
import './index.css';
import { isEnvBrowser } from './utils/misc.ts';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);

if (isEnvBrowser()) {
  const root = document.getElementById('root');

  // https://i.imgur.com/iPTAdYV.png - Night time img
  // https://i.imgur.com/3pzRj9n.png - Day time img
  root!.style.backgroundImage = 'url("https://i.imgur.com/3pzRj9n.png")';
  root!.style.backgroundSize = 'cover';
  root!.style.backgroundRepeat = 'no-repeat';
  root!.style.backgroundPosition = 'center';
}

// Notify client side that UI is mounted and ready to receive messages
// This runs both in CEF and browser; client script listens for 'ui:ready'
try {
  const resName = (window as any).GetParentResourceName?.() ?? 'nui-frame-app';
  fetch(`https://${resName}/ui:ready`, {
    method: 'post',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({}),
  });
} catch {}

// In dev browser, echo messages to our hook (helps verify rendering outside FiveM)
if (isEnvBrowser()) {
  setTimeout(() => {
    window.postMessage({ action: 'setVisible', data: { visible: true } }, '*');
    window.postMessage({ action: 'encounter:show', data: { npc: { id: 'dev' }, encounter: { id: 'dev', label: 'Dev Encounter', description: 'Local test', reward: { cash: 1 } } } }, '*');
  }, 50);
}
