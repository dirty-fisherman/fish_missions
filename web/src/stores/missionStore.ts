import { create } from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';

export interface Mission {
  id: string;
  label: string;
  description: string;
  type: 'cleanup' | 'delivery' | 'assassination';
  reward?: {
    cash?: number;
    items?: Array<{ name: string; count: number }>;
  };
}

export interface MissionStatus {
  id: string;
  label: string;
  type: string;
  status: 'available' | 'in-progress' | 'complete' | 'archived' | 'cooldown' | 'turnin' | 'cancelled';
  reward?: any;
  progress?: any;
  cooldownRemaining?: number;
  cooldownTimestamp?: number;
}

export interface NpcData {
  id: string;
  missionId?: string;
  target?: {
    label: string;
    icon: string;
  };
}

interface MissionState {
  panelVisible: boolean;
  offering: boolean;
  openedViaNpc: boolean;
  sidebarPosition: 'left' | 'right';

  selectedMission: Mission | null;
  selectedNpc: NpcData | null;
  discoveredMissions: Mission[];
  missionStatuses: MissionStatus[];

  setSidebarPosition: (pos: 'left' | 'right') => void;
  setPanelVisible: (visible: boolean) => void;
  setOffering: (offering: boolean) => void;
  setSelectedMission: (mission: Mission | null) => void;
  setSelectedNpc: (npc: NpcData | null) => void;
  addDiscoveredMission: (mission: Mission) => void;
  setDiscoveredMissions: (missions: Mission[]) => void;
  setMissionStatuses: (statuses: MissionStatus[]) => void;
  updateMissionStatus: (id: string, updates: Partial<MissionStatus>) => void;

  showMission: (npc: NpcData, mission: Mission) => void;
  closePanel: () => void;
  selectMissionFromList: (mission: Mission) => void;
  openPanel: () => void;

  getStatusById: (id: string) => MissionStatus | undefined;
}

const mapStatus = (s: string): MissionStatus['status'] => {
  switch (s) {
    case 'active': return 'in-progress';
    case 'turnin': return 'complete';
    case 'cooldown': return 'cooldown';
    case 'cancelled': return 'cancelled';
    case 'available': return 'available';
    default: return 'available';
  }
};

export const useMissionStore = create<MissionState>()(
  subscribeWithSelector((set, get) => ({
    panelVisible: false,
    offering: false,
    openedViaNpc: false,
    sidebarPosition: 'left',
    selectedMission: null,
    selectedNpc: null,
    discoveredMissions: [],
    missionStatuses: [],

    setSidebarPosition: (pos) => set({ sidebarPosition: pos }),
    setPanelVisible: (visible) => set({ panelVisible: visible }),
    setOffering: (offering) => set({ offering }),
    setSelectedMission: (mission) => set({ selectedMission: mission }),
    setSelectedNpc: (npc) => set({ selectedNpc: npc }),

    addDiscoveredMission: (mission) => set((state) => {
      if (state.discoveredMissions.find(m => m.id === mission.id)) return state;
      return { discoveredMissions: [...state.discoveredMissions, mission] };
    }),

    setDiscoveredMissions: (missions) => set({ discoveredMissions: missions }),

    setMissionStatuses: (statuses) => set((state) => {
      const now = Date.now();
      const processed = statuses.map(s => ({
        ...s,
        status: mapStatus(s.status),
        cooldownTimestamp: s.status === 'cooldown' || s.cooldownRemaining ? now : undefined,
      }));

      const byId = new Set(state.discoveredMissions.map(m => m.id));
      const additions: Mission[] = [];
      for (const s of processed) {
        if (!byId.has(s.id) && (s.status === 'in-progress' || s.status === 'complete' || s.status === 'available')) {
          additions.push({ id: s.id, label: s.label, description: '', type: s.type as any, reward: s.reward });
        }
      }

      let newDiscovered = state.discoveredMissions;
      if (additions.length > 0) {
        newDiscovered = [...state.discoveredMissions, ...additions];
      }

      // Re-evaluate offering based on fresh data
      let newOffering = state.offering;
      if (state.selectedMission && state.openedViaNpc && state.selectedNpc?.missionId === state.selectedMission.id) {
        const sel = processed.find(s => s.id === state.selectedMission!.id);
        // If no status entry or status is available, we should be offering
        newOffering = !sel || sel.status === 'available';
      } else if (state.selectedMission && state.offering) {
        const sel = processed.find(s => s.id === state.selectedMission!.id);
        if (sel && sel.status !== 'available') newOffering = false;
      }

      return { missionStatuses: processed, discoveredMissions: newDiscovered, offering: newOffering };
    }),

    updateMissionStatus: (id, updates) => set((state) => ({
      missionStatuses: state.missionStatuses.map(s => s.id === id ? { ...s, ...updates } : s),
    })),

    showMission: (npc, mission) => set((state) => {
      const cur = state.missionStatuses.find(s => s.id === mission.id);
      const isAvailable = !cur || cur.status === 'available' || cur.status === 'cancelled';
      return { selectedNpc: npc, selectedMission: mission, offering: isAvailable, panelVisible: true, openedViaNpc: true };
    }),

    closePanel: () => set({ panelVisible: false, offering: false, openedViaNpc: false }),

    selectMissionFromList: (mission) => set((state) => {
      const shouldOffer = state.openedViaNpc &&
        state.selectedNpc?.missionId === mission.id &&
        (() => {
          const cur = state.missionStatuses.find(s => s.id === mission.id);
          return !cur || cur.status === 'available' || cur.status === 'cancelled';
        })();
      return {
        selectedMission: mission,
        selectedNpc: shouldOffer ? state.selectedNpc : null,
        offering: shouldOffer,
      };
    }),

    openPanel: () => set({ panelVisible: true, openedViaNpc: false }),

    getStatusById: (id) => get().missionStatuses.find(s => s.id === id),
  })),
);