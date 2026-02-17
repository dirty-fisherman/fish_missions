import { useEffect } from 'react';
import { isEnvBrowser } from './utils/misc';
import { fetchNui } from './utils/fetchNui';
import { debugMissionData } from './utils/debugData';
import { useMissionStore } from './stores/missionStore';
import { Sidebar } from './components/Sidebar';
import { useKeyboardHandlers } from './hooks/useKeyboardHandlers';
import { useMissionEvents } from './hooks/useMissionEvents';

function App() {
  const { panelVisible, closePanel } = useMissionStore();

  function handleHideModal() {
    closePanel();
    void fetchNui('focus:set', { hasFocus: false, hasCursor: false });
  }

  // Initialize debug data for browser development
  useEffect(() => {
    if (isEnvBrowser()) {
      debugMissionData();
    }
  }, []);

  // Use custom hooks for event handling
  useKeyboardHandlers(panelVisible, handleHideModal);
  useMissionEvents(handleHideModal);

  return (
    <>
      {/* Always-on tiny marker to confirm NUI mounted */}
      <div style={{ position: 'fixed', bottom: 6, right: 8, fontSize: 10, opacity: 0.25, pointerEvents: 'none' }}>
        missions-ui
      </div>

      <Sidebar isVisible={panelVisible} onClose={handleHideModal} />
    </>
  );
}

export default App;
