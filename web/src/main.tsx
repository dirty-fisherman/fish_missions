import React from 'react';
import ReactDOM from 'react-dom/client';
import { MantineProvider, type CSSVariablesResolver } from '@mantine/core';
import '@mantine/core/styles.css';
import './global.css';
import { theme } from './theme';
import App from './App.tsx';
import { isEnvBrowser } from './utils/misc.ts';

const resolver: CSSVariablesResolver = () => ({
  variables: { '--mantine-color-body': 'transparent' },
  light: { '--mantine-color-body': 'transparent' },
  dark: { '--mantine-color-body': 'transparent' },
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <MantineProvider theme={theme} defaultColorScheme="dark" cssVariablesResolver={resolver}>
      <App />
    </MantineProvider>
  </React.StrictMode>,
);

if (isEnvBrowser()) {
  const root = document.getElementById('root');
  root!.style.backgroundImage = 'url("https://i.imgur.com/3pzRj9n.png")';
  root!.style.backgroundSize = 'cover';
  root!.style.backgroundRepeat = 'no-repeat';
  root!.style.backgroundPosition = 'center';
}

// Notify client side that UI is mounted and ready
try {
  const resName = (window as any).GetParentResourceName?.() ?? 'nui-frame-app';
  fetch(`https://${resName}/ui:ready`, {
    method: 'post',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({}),
  });
} catch {}

if (isEnvBrowser()) {
  setTimeout(() => {
    window.postMessage({ action: 'setVisible', data: { visible: true } }, '*');
    window.postMessage({ action: 'mission:show', data: { npc: { id: 'dev' }, mission: { id: 'dev', label: 'Dev Mission', description: 'Local test', reward: { cash: 1 } } } }, '*');
  }, 50);
}
