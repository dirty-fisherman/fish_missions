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
  status: 'available' | 'in-progress' | 'complete' | 'archived' | 'cooldown' | 'turnin';
  reward?: any;
  progress?: any;
  cooldownRemaining?: number;
  cooldownTimestamp?: number; // When the cooldown data was received
}

export interface NpcData {
  id: string;
  encounterId?: string; // Track which encounter this NPC is linked to
  target?: {
    label: string;
    icon: string;
  };
}

interface MissionState {
  // UI State
  panelVisible: boolean;
  offering: boolean;
  openedViaNpc: boolean; // Track if opened via NPC interaction vs F6
  
  // Mission Data
  selectedMission: Mission | null;
  selectedNpc: NpcData | null;
  discoveredMissions: Mission[];
  missionStatuses: MissionStatus[];
  
  // Actions
  setPanelVisible: (visible: boolean) => void;
  setOffering: (offering: boolean) => void;
  setSelectedMission: (mission: Mission | null) => void;
  setSelectedNpc: (npc: NpcData | null) => void;
  addDiscoveredMission: (mission: Mission) => void;
  setDiscoveredMissions: (missions: Mission[]) => void;
  setMissionStatuses: (statuses: MissionStatus[]) => void;
  updateMissionStatus: (id: string, updates: Partial<MissionStatus>) => void;
  
  // Complex Actions
  showEncounter: (npc: NpcData, mission: Mission) => void;
  closePanel: () => void;
  selectMissionFromList: (mission: Mission) => void;
  openPanel: () => void;
  
  // Computed
  getStatusById: (id: string) => MissionStatus | undefined;
}

export const useMissionStore = create<MissionState>()(
  subscribeWithSelector((set, get) => ({
    // Initial State
    panelVisible: false,
    offering: false,
    openedViaNpc: false,
    selectedMission: null,
    selectedNpc: null,
    discoveredMissions: [],
    missionStatuses: [],
    
    // Basic Actions
    setPanelVisible: (visible) => set({ panelVisible: visible }),
    setOffering: (offering) => set({ offering }),
    setSelectedMission: (mission) => set({ selectedMission: mission }),
    setSelectedNpc: (npc) => set({ selectedNpc: npc }),
    
    addDiscoveredMission: (mission) => set((state) => {
      const exists = state.discoveredMissions.find(m => m.id === mission.id);
      if (exists) return state;
      
      // Note: This is mainly for immediate UI feedback. Server manages persistence.
      const newDiscovered = [...state.discoveredMissions, mission];
      return { discoveredMissions: newDiscovered };
    }),
    
    setDiscoveredMissions: (missions) => set({
      discoveredMissions: missions
    }),
    
    setMissionStatuses: (statuses) => set((state) => {
      // Add timestamps to cooldown statuses for dynamic countdown
      const now = Date.now();
      const statusesWithTimestamp = statuses.map(status => ({
        ...status,
        cooldownTimestamp: status.status === 'cooldown' || status.cooldownRemaining ? now : undefined
      }));

      // Opportunistically grow discovered missions from statuses
      const byId = new Set(state.discoveredMissions.map(m => m.id));
      const additions: Mission[] = [];
      
      // Map old status values to new status system
      const mapStatus = (oldStatus: string): 'available' | 'in-progress' | 'complete' | 'archived' => {
        switch (oldStatus) {
          case 'active': return 'in-progress';
          case 'turnin': return 'complete'; 
          case 'cooldown': return 'archived';
          case 'available': return 'available';
          default: return 'available';
        }
      };
      
      const processedStatuses = statusesWithTimestamp.map(status => ({
        ...status,
        status: mapStatus(status.status)
      }));
      
      for (const status of processedStatuses) {
        if ((status.status === 'in-progress' || status.status === 'complete' || status.status === 'available') && !byId.has(status.id)) {
          additions.push({
            id: status.id,
            label: status.label,
            description: '',
            type: status.type as any,
            reward: status.reward
          });
        }
      }
      
      let newDiscovered = state.discoveredMissions;
      if (additions.length > 0) {
        newDiscovered = [...state.discoveredMissions, ...additions];
        
        // Persist to localStorage
        try {
          if (typeof window !== 'undefined' && window.localStorage) {
            localStorage.setItem('missions_discovered', JSON.stringify(newDiscovered));
          }
        } catch {}
      }
      
      // Check if we need to update offering state for currently selected mission
      let newOffering = state.offering;
      if (state.selectedMission && state.offering) {
        const selectedStatus = processedStatuses.find(s => s.id === state.selectedMission!.id);
        if (selectedStatus && selectedStatus.status !== 'available') {
          newOffering = false; // Mission is no longer available, stop offering
        }
      }
      
      return { 
        missionStatuses: processedStatuses,
        discoveredMissions: newDiscovered,
        offering: newOffering
      };
    }),
    
    updateMissionStatus: (id, updates) => set((state) => ({
      missionStatuses: state.missionStatuses.map(status => 
        status.id === id ? { ...status, ...updates } : status
      )
    })),
    
  // Complex Actions
  showEncounter: (npc, mission) => set((state) => {
    // Check mission status to determine if we should show offering UI
    const currentStatus = state.missionStatuses.find(s => s.id === mission.id);
    const isAvailable = !currentStatus || currentStatus.status === 'available';
    
    return {
      selectedNpc: npc,
      selectedMission: mission,
      offering: isAvailable, // Only offer if mission is available
      panelVisible: true,
      openedViaNpc: true // This was opened via NPC interaction
    };
  }),    closePanel: () => set({
      panelVisible: false,
      offering: false,
      openedViaNpc: false // Reset NPC context when closing
    }),
    
  selectMissionFromList: (mission) => set((state) => {
    // If we opened via NPC and selecting the same mission that NPC offers, allow offering again
    const shouldOffer = state.openedViaNpc && 
                       state.selectedNpc?.encounterId === mission.id &&
                       (() => {
                         const currentStatus = state.missionStatuses.find(s => s.id === mission.id);
                         return !currentStatus || currentStatus.status === 'available';
                       })();
    
    return {
      selectedMission: mission,
      selectedNpc: shouldOffer ? state.selectedNpc : null, // Keep NPC context if offering
      offering: shouldOffer
    };
  }),
  
  // New action to open panel (F6 context) - data request handled by client
  openPanel: () => {
    set({ 
      panelVisible: true,
      openedViaNpc: false // This is F6 context, not NPC
    });
  },    // Computed
    getStatusById: (id) => {
      const state = get();
      return state.missionStatuses.find(status => status.id === id);
    }
  }))
);

// Discovered missions are now managed server-side via KVP and sent through tracker:data