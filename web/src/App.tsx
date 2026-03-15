import { useEffect } from 'react';
import { isEnvBrowser } from './utils/misc';
import { fetchNui } from './utils/fetchNui';
import { debugMissionData } from './utils/debugData';
import { useMissionStore } from './stores/missionStore';
import { MissionsPanel } from './components/MissionsPanel';
import { useKeyboardHandlers } from './hooks/useKeyboardHandlers';
import { useMissionEvents } from './hooks/useMissionEvents';

function App() {
  const { panelVisible, closePanel } = useMissionStore();

  function handleClose() {
    closePanel();
    void fetchNui('focus:set', { hasFocus: false, hasCursor: false });
  }

  useEffect(() => {
    if (isEnvBrowser()) {
      debugMissionData();
    }
  }, []);

  useKeyboardHandlers(panelVisible, handleClose);
  useMissionEvents(handleClose);

  return <MissionsPanel isVisible={panelVisible} onClose={handleClose} />;
}

export default App;
