import { useNuiEvent } from './useNuiEvent';
import { fetchNui } from '../utils/fetchNui';
import { useMissionStore } from '../stores/missionStore';

export function useMissionEvents(onClose: () => void) {
  const {
    setPanelVisible,
    showEncounter,
    setDiscoveredMissions,
    setMissionStatuses,
    openPanel,
  } = useMissionStore();

  useNuiEvent('setVisible', (data: { visible?: boolean }) => {
    setPanelVisible(!!data.visible);
  });

  useNuiEvent('encounter:show', (data: { npc: any; encounter: any }) => {
    showEncounter(data.npc, data.encounter);
  });

  // Tracker events
  useNuiEvent('tracker:toggle', (data: { visible?: boolean }) => {
    // Use explicit visibility if provided, otherwise toggle current state
    const { panelVisible } = useMissionStore.getState();
    const shouldShow = data.visible !== undefined ? data.visible : !panelVisible;
    console.log('[missions] tracker:toggle received, shouldShow:', shouldShow, 'current panelVisible:', panelVisible);
    
    if (shouldShow) {
      // Opening: Request fresh data, set focus, and show panel
      void fetchNui('tracker:request', {});
      void fetchNui('focus:set', { hasFocus: true, hasCursor: true });
      openPanel();
    } else {
      // Closing: Hide panel and remove focus
      onClose();
    }
  });
  
  useNuiEvent('tracker:data', (data: { statuses: any[], discoveredMissions?: any[] }) => {
    setMissionStatuses(data.statuses || []);
    // Update discovered missions from server instead of localStorage
    if (data.discoveredMissions) {
      setDiscoveredMissions(data.discoveredMissions);
    }
  });
}