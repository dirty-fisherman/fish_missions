export type Vector3 = { x: number; y: number; z: number };
export type Vector4 = Vector3 & { w?: number };

export type RewardItem = { name: string; count: number };
export type Reward = {
  cash?: number;
  items?: RewardItem[];
};

export type EncounterType = 'cleanup' | 'delivery' | 'assassination';

export interface EncounterBase<T extends EncounterType = EncounterType, P = any> {
  id: string;
  label: string;
  description: string;
  type: T;
  cooldownSeconds?: number;
  npc: NpcConfig;
  params: P;
  reward: Reward;
  // Optional UI messages
  messages?: {
    pickup?: string;   // shown on per-item pickup (where applicable)
    complete?: string; // shown when objectives are completed
  };
  // Cancel behavior: when true, cancelling applies cooldown; default false
  cancelIncurCooldown?: boolean;
}

export type CleanupParams = {
  // Existing random-in-radius spawn config
  area: Vector3;
  radius: number;
  props: string[];
  count: number;
  // Explicit spawn mode selection (default 'random')
  spawnMode?: 'random' | 'positions' | 'preset';
  // New: display label for picked-up item (e.g., "trash bag")
  itemLabel?: string;
  // New: manual placement options
  positions?: Vector3[]; // exact positions to spawn props
  // New: multiple preset groups; one preset is chosen at random each mission
  presets?: { positions: Vector3[] }[];
  // New: environmental guards
  preventUnderground?: boolean; // ensure z is at ground level
  preventWater?: boolean; // avoid water areas
  // Performance knobs for water checks
  waterCheckStrategy?: 'none' | 'fast' | 'strict'; // default 'fast' if preventWater
  waterCheckAttempts?: number; // default 3, max 10
};

export type DeliveryParams = {
  destination: Vector3;
  timeSeconds: number;
  item: RewardItem;
  // Optional area marker around destination
  area?: Vector3; // If specified, creates area blip at this location instead of destination
  radius?: number; // If specified with area, creates area radius marker
  animation?: {
    Animation: string;
    Dictionary: string;
    Options: {
      Flags: {
        Loop?: boolean;
        Move?: boolean;
      };
      Props: Array<{
        Bone: number;
        Name: string;
        Placement: [
          { x: number; y: number; z: number } | [number, number, number],
          { x: number; y: number; z: number } | [number, number, number]
        ];
      }>;
    };
  };
};

export type AssassinationParams = {
  area: Vector3; // Center point of the mission area
  radius: number; // Radius of the mission area for blip display
  targets: Array<{
    model: string;
    spawn: Vector3;
    weapon?: string; // Optional: weapon name, 'unarmed', or omit for fist fights
    heading?: number; // Default to 0.0 if not specified
  }>;
  weaponWhitelist?: string[];
  blip?: boolean; // Creates single area blip and waypoint at defined area center
};export type CleanupEncounter = EncounterBase<'cleanup', CleanupParams>;
export type DeliveryEncounter = EncounterBase<'delivery', DeliveryParams>;
export type AssassinationEncounter = EncounterBase<'assassination', AssassinationParams>;
export type AnyEncounter = CleanupEncounter | DeliveryEncounter | AssassinationEncounter;

export type NpcConfig = {
  id: string;
  model: string;
  coords: Vector4;
  scenario?: string;
  heading?: number; // alias for w
  blip?: { sprite?: number; color?: number; scale?: number };
  target?: { icon?: string; label?: string };
  speech?: string; // Ambient speech to play on interaction (default: 'GENERIC_HI')
  speechClaim?: string; // Speech to play when claiming reward (default: 'GENERIC_THANKS')
  speechBye?: string; // Speech to play when dismissing UI (default: 'GENERIC_BYE')
};

export type RootConfig = {
  EnableNuiCommand?: boolean;
  npcBlips?: boolean;
  encounters: AnyEncounter[];
};

export type ActiveMissionState = {
  id: string; // encounter id
  giverNpcId: string;
  acceptedAt: number; // game timer unix
  data?: Record<string, any>;
  status: 'active' | 'completed' | 'failed' | 'turnin';
};

export type MissionAcceptPayload = {
  npcId: string;
  encounterId: string;
};
