import { useEffect } from 'react';
import { isEnvBrowser } from './utils/misc';
import { fetchNui } from './utils/fetchNui';
import { debugMissionData } from './utils/debugData';
import { useMissionStore } from './stores/missionStore';
import { useAdminStore } from './stores/adminStore';
import { MissionsPanel } from './components/MissionsPanel';
import { AdminPanel } from './components/admin/AdminPanel';
import { useKeyboardHandlers } from './hooks/useKeyboardHandlers';
import { useMissionEvents } from './hooks/useMissionEvents';
import { useNuiEvent } from './hooks/useNuiEvent';

function App() {
  const { panelVisible, closePanel } = useMissionStore();
  const adminMode = useAdminStore((s) => s.mode);
  const setAdminMode = useAdminStore((s) => s.setMode);
  const resetAdmin = useAdminStore((s) => s.reset);

  function handleClose() {
    if (adminMode === 'admin') {
      void fetchNui('admin:close', {});
      resetAdmin();
    }
    closePanel();
    void fetchNui('focus:set', { hasFocus: false, hasCursor: false });
  }

  useEffect(() => {
    if (isEnvBrowser()) {
      debugMissionData();
    }
  }, []);

  // Admin NUI events
  useNuiEvent('admin:open', () => {
    setAdminMode('admin');
  });

  useNuiEvent('admin:closed', () => {
    resetAdmin();
    closePanel();
  });

  useKeyboardHandlers(panelVisible || adminMode === 'admin', handleClose);
  useMissionEvents(handleClose);

  if (adminMode === 'admin') {
    return <AdminPanel />;
  }

  return <MissionsPanel isVisible={panelVisible} onClose={handleClose} />;
}

export default App;
