import { create } from 'zustand';

export interface MissionNpc {
  id?: string;
  model?: string;
  coords?: { x: number; y: number; z: number; w: number };
  scenario?: string;
  target?: { icon?: string; label?: string };
  blip?: Record<string, never> | false;
  speech?: string;
  speechClaim?: string;
  speechBye?: string;
}

export interface MissionReward {
  cash?: number;
  items?: Array<{ name: string; count: number; metadata?: Record<string, any> }>;
}

export interface MissionDefinition {
  id?: string;
  label: string;
  description: string;
  type: 'cleanup' | 'delivery' | 'assassination';
  cooldownSeconds: number;
  npc: MissionNpc;
  params: Record<string, any>;
  messages?: Record<string, string>;
  reward: MissionReward;
  levelRequired?: number;
  prerequisites?: string[];
  enabled: boolean;
}

interface AdminState {
  mode: 'hidden' | 'admin';
  missions: MissionDefinition[];
  total: number;
  page: number;
  pageSize: number;
  search: string;
  selectedId: string | null;
  editing: MissionDefinition | null;
  saving: boolean;
  capturingField: string | null;

  setMode: (mode: 'hidden' | 'admin') => void;
  setMissions: (missions: MissionDefinition[], total: number) => void;
  setPage: (page: number) => void;
  setSearch: (search: string) => void;
  setSelectedId: (id: string | null) => void;
  setEditing: (editing: MissionDefinition | null) => void;
  updateEditing: (partial: Partial<MissionDefinition>) => void;
  updateNpc: (partial: Partial<MissionNpc>) => void;
  updateReward: (partial: Partial<MissionReward>) => void;
  updateParams: (partial: Record<string, any>) => void;
  setSaving: (saving: boolean) => void;
  setCapturingField: (field: string | null) => void;
  newMission: () => void;
  reset: () => void;
}

const DEFAULT_MISSION: MissionDefinition = {
  label: '',
  description: '',
  type: 'cleanup',
  cooldownSeconds: 3600,
  npc: {
    model: 's_m_y_dealer_01',
    coords: { x: 0, y: 0, z: 0, w: 0 },
    target: { icon: 'fa-solid fa-clipboard', label: 'Help Stranger' },
    blip: {},
    scenario: '',
    speech: 'GENERIC_HI',
    speechClaim: 'GENERIC_THANKS',
    speechBye: 'GENERIC_BYE',
  },
  params: {},
  reward: { cash: 0, items: [] },
  enabled: true,
};

export const useAdminStore = create<AdminState>()((set) => ({
  mode: 'hidden',
  missions: [],
  total: 0,
  page: 1,
  pageSize: 25,
  search: '',
  selectedId: null,
  editing: null,
  saving: false,
  capturingField: null,

  setMode: (mode) => set({ mode }),
  setMissions: (missions, total) => set({ missions, total }),
  setPage: (page) => set({ page }),
  setSearch: (search) => set({ search, page: 1 }),
  setSelectedId: (id) => set({ selectedId: id }),
  setEditing: (editing) => set({ editing }),

  updateEditing: (partial) => set((s) => {
    if (!s.editing) return s;
    return { editing: { ...s.editing, ...partial } };
  }),

  updateNpc: (partial) => set((s) => {
    if (!s.editing) return s;
    return { editing: { ...s.editing, npc: { ...s.editing.npc, ...partial } } };
  }),

  updateReward: (partial) => set((s) => {
    if (!s.editing) return s;
    return { editing: { ...s.editing, reward: { ...s.editing.reward, ...partial } } };
  }),

  updateParams: (partial) => set((s) => {
    if (!s.editing) return s;
    return { editing: { ...s.editing, params: { ...s.editing.params, ...partial } } };
  }),

  setSaving: (saving) => set({ saving }),
  setCapturingField: (field) => set({ capturingField: field }),

  newMission: () => set({
    selectedId: null,
    editing: JSON.parse(JSON.stringify(DEFAULT_MISSION)),
  }),

  reset: () => set({
    mode: 'hidden',
    missions: [],
    total: 0,
    page: 1,
    search: '',
    selectedId: null,
    editing: null,
    saving: false,
    capturingField: null,
  }),
}));
