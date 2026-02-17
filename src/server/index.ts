/// <reference types="@citizenfx/server" />
import Config from '@common/config';
import type { AnyEncounter, RootConfig, Reward } from '@common/types';
import { addCommand } from '@communityox/ox_lib/server';
import { ResourceName } from '@common/resource';

const Root = Config as RootConfig;

type Active = { encounterId: string; npcId: string; status: 'in-progress' | 'complete'; progress?: any };
// Allow multiple active missions per player, keyed by encounterId
const active: Map<number, Map<string, Active>> = new Map();

function getActivesFor(src: number) {
  let m = active.get(src);
  if (!m) { m = new Map(); active.set(src, m); }
  return m;
}

function activeKey(identifier: string, encounterId: string) {
  return `${ResourceName}:active:${identifier}:${encounterId}`;
}

function saveActive(identifier: string, data: Active) {
  try { SetResourceKvpNoSync(activeKey(identifier, data.encounterId), JSON.stringify(data)); } catch {}
}

function loadActive(identifier: string, encounterId: string): Active | null {
  try {
    const s = GetResourceKvpString(activeKey(identifier, encounterId));
    return s ? (JSON.parse(s) as Active) : null;
  } catch { return null; }
}

function clearActive(identifier: string, encounterId: string) {
  try { DeleteResourceKvp(activeKey(identifier, encounterId)); } catch {}
}

function getIdentifier(src: number) {
  // Try both FiveM identifier functions depending on environment typings
  const ids = (typeof getPlayerIdentifiers === 'function'
    ? getPlayerIdentifiers(src)
    : (globalThis as any).GetPlayerIdentifiers(src.toString())) as unknown as string[];
  const license = ids.find((i: string) => i.startsWith('license:')) || ids[0];
  return license || `${src}`;
}

function cdKey(identifier: string, encounterId: string, version: number) {
  // Version cooldowns by encounter cooldownSeconds so config changes invalidate old values
  return `${ResourceName}:cooldown:${identifier}:${encounterId}:v${version || 0}`;
}

function getCooldown(identifier: string, enc: AnyEncounter) {
  const ver = enc.cooldownSeconds || 0;
  const key = cdKey(identifier, enc.id, ver);
  let v = GetResourceKvpString(key);
  if (v) {
    const n = Number.parseInt(v, 10);
    return Number.isNaN(n) ? 0 : n;
  }
  // Fallback: old, unversioned key from previous builds; delete to prevent stale lockouts
  try {
    const oldKey = `${ResourceName}:cooldown:${identifier}:${enc.id}`;
    const old = GetResourceKvpString(oldKey);
    if (old) {
      try { DeleteResourceKvp(oldKey); } catch {}
    }
  } catch {}
  return 0;
}

function setCooldown(identifier: string, enc: AnyEncounter, until: number) {
  const ver = enc.cooldownSeconds || 0;
  const key = cdKey(identifier, enc.id, ver);
  SetResourceKvpNoSync(key, String(until));
}

function now() {
  return Math.floor(Date.now() / 1000);
}

// Discovered missions tracking
function discoveredKey(identifier: string) {
  return `${ResourceName}:discovered:${identifier}`;
}

function getDiscoveredMissions(identifier: string): string[] {
  try {
    const s = GetResourceKvpString(discoveredKey(identifier));
    return s ? JSON.parse(s) : [];
  } catch { return []; }
}

function addDiscoveredMission(identifier: string, encounterId: string) {
  try {
    const discovered = getDiscoveredMissions(identifier);
    if (!discovered.includes(encounterId)) {
      discovered.push(encounterId);
      SetResourceKvpNoSync(discoveredKey(identifier), JSON.stringify(discovered));
    }
  } catch {}
}

function grantReward(src: number, reward: Reward) {
  if (!reward) return;
  if (reward.cash && reward.cash > 0) {
    try {
      exports.ox_core?.addMoney?.(src, 'cash', reward.cash, 'mission_reward');
    } catch {
      try {
        exports.ox_inventory?.AddItem?.(src, 'money', reward.cash);
      } catch {}
    }
  }

  if (reward.items && reward.items.length) {
    for (const item of reward.items) {
      try {
        exports.ox_inventory?.AddItem?.(src, item.name, item.count ?? 1);
      } catch {}
    }
  }
}

function findEncounter(id: string): AnyEncounter | undefined {
  return (Root.encounters || []).find((e) => e.id === id);
}

// Dev helper
if (Config.EnableNuiCommand) {
  addCommand('openNui', async (playerId: number) => {
    if (!playerId) return;
    emitNet(`${ResourceName}:openNui`, playerId);
  });

  // Dev: clear cooldowns
  addCommand('missionscd', async (playerId: number) => {
    if (!playerId) return;
    const identifier = getIdentifier(playerId);
    for (const enc of Root.encounters || []) {
      try {
        const ver = enc.cooldownSeconds || 0;
        const verKey = `${ResourceName}:cooldown:${identifier}:${enc.id}:v${ver}`;
        const oldKey = `${ResourceName}:cooldown:${identifier}:${enc.id}`;
        try { DeleteResourceKvp(verKey); } catch {}
        try { DeleteResourceKvp(oldKey); } catch {}
      } catch {}
    }
  });
}

// Accept encounter
onNet(`${ResourceName}:encounter:accept`, (data: { npcId: string; encounterId: string }) => {
  // eslint-disable-next-line @typescript-eslint/no-this-alias
  const src = (global as any).source as number;
  const enc = findEncounter(data.encounterId);
  if (!enc) return;
  // Prevent starting another instance of the same mission if it's already active/turnin
  const actives = getActivesFor(src);
  const same = actives.get(enc.id);
  if (same && (same.status === 'in-progress' || same.status === 'complete')) {
    emitNet(`${ResourceName}:mission:busy`, src, { encounterId: same.encounterId, status: same.status });
    return;
  }

  const identifier = getIdentifier(src);
  const cd = getCooldown(identifier, enc);
  const t = now();
  if (cd && cd > t) {
    const seconds = cd - t;
    emitNet(`${ResourceName}:mission:cooldown`, src, { seconds, encounterId: enc.id });
    return;
  }

  const a: Active = { encounterId: enc.id, npcId: data.npcId, status: 'in-progress' };
  actives.set(enc.id, a);
  saveActive(identifier, a);
  
  // Add to discovered missions when first accepted
  addDiscoveredMission(identifier, enc.id);
  // Deliveries: give the parcel at accept time
  if (enc.type === 'delivery') {
    // @ts-ignore
    const item = enc.params?.item;
    if (item?.name) {
      try {
        exports.ox_inventory?.AddItem?.(src, item.name, item.count ?? 1);
      } catch {}
    }
  }
  emitNet(`${ResourceName}:mission:start`, src, { encounter: enc, npcId: data.npcId, progress: a.progress || null });
});

// Completion from client module
onNet(`${ResourceName}:encounter:complete`, (data: { encounterId: string }) => {
  const src = (global as any).source as number;
  const actives = getActivesFor(src);
  const a = actives.get(data.encounterId);
  if (!a) return;
  const enc = findEncounter(a.encounterId);
  if (!enc) return;
  if (enc.type === 'delivery') {
    // @ts-ignore
    const item = enc.params?.item;
    if (item?.name) {
      try {
        exports.ox_inventory?.RemoveItem?.(src, item.name, item.count ?? 1);
      } catch {}
    }
  }
  a.status = 'complete';
  actives.set(a.encounterId, a);
  saveActive(getIdentifier(src), a);
  emitNet(`${ResourceName}:mission:return`, src, { npcId: a.npcId, encounterId: a.encounterId });
});

// Claim reward at NPC
onNet(`${ResourceName}:encounter:claim`, (data: { npcId: string; encounterId: string }) => {
  const src = (global as any).source as number;
  const actives = getActivesFor(src);
  const a = actives.get(data.encounterId);
  if (!a || a.npcId !== data.npcId || a.status !== 'complete') return;

  const enc = findEncounter(a.encounterId);
  if (!enc) return;

  grantReward(src, enc.reward);
  const identifier = getIdentifier(src);
  actives.delete(enc.id);
  clearActive(identifier, enc.id);
  const until = now() + (enc.cooldownSeconds || 0);
  if (enc.cooldownSeconds && enc.cooldownSeconds > 0) setCooldown(identifier, enc, until);

  emitNet(`${ResourceName}:mission:claimed`, src, { encounterId: enc.id });
});

// Cancel current mission
onNet(`${ResourceName}:encounter:cancel`, (data?: { encounterId?: string }) => {
  const src = (global as any).source as number;
  const actives = getActivesFor(src);
  let a: Active | undefined;
  if (data?.encounterId) {
    a = actives.get(data.encounterId);
  } else {
    // Back-compat: if no encounterId provided, cancel the first active if any
    a = actives.values().next().value as Active | undefined;
  }
  if (!a) return;
  const enc = findEncounter(a.encounterId);
  if (!enc) { actives.delete(a.encounterId); return; }
  const identifier = getIdentifier(src);
  // Clear active and persisted state for this encounter
  actives.delete(enc.id);
  clearActive(identifier, enc.id);
  // Optionally apply cooldown depending on encounter setting
  const applyCd = !!(enc as any).cancelIncurCooldown;
  if (applyCd && enc.cooldownSeconds && enc.cooldownSeconds > 0) {
    const until = now() + enc.cooldownSeconds;
    setCooldown(identifier, enc, until);
  }
  emitNet(`${ResourceName}:mission:cancelled`, src, { encounterId: enc.id, appliedCooldown: applyCd });
});

// Tracker: provide mission statuses for the player
onNet(`${ResourceName}:tracker:request`, () => {
  const src = (global as any).source as number;
  const identifier = getIdentifier(src);
  // Hydrate in-memory actives from persisted entries
  const actives = getActivesFor(src);
  for (const enc of Root.encounters || []) {
    if (!actives.has(enc.id)) {
      const s = loadActive(identifier, enc.id);
      if (s) actives.set(enc.id, s);
    }
  }
  const nowTs = now();
  const statuses = (Root.encounters || []).map((enc) => {
    const cd = getCooldown(identifier, enc);
    let status: 'available' | 'active' | 'turnin' | 'cooldown' = 'available';
    const a = actives.get(enc.id);
    if (a) {
      status = a.status === 'complete' ? 'turnin' : 'active';
    } else if (cd && cd > nowTs) {
      status = 'cooldown';
    }
    const remaining = cd && cd > nowTs ? cd - nowTs : 0;
    return {
      id: enc.id,
      label: (enc as any).label || enc.id,
      type: enc.type,
      status,
      cooldownRemaining: remaining,
      reward: enc.reward || null,
      progress: a ? a.progress || null : null,
    };
  });
  
  // Get discovered missions for this player
  const discoveredIds = getDiscoveredMissions(identifier);
  const discoveredMissions = (Root.encounters || []).filter(enc => discoveredIds.includes(enc.id));
  
  emitNet(`${ResourceName}:tracker:data`, src, { statuses, discoveredMissions });
});

// Progress updates from client
onNet(`${ResourceName}:encounter:progress`, (data: { encounterId: string; type: string; [k: string]: any }) => {
  const src = (global as any).source as number;
  const actives = getActivesFor(src);
  const a = actives.get(data.encounterId);
  if (!a) return;
  // basic exploit hardening: monotonic progress for cleanup
  if (data?.type === 'cleanup') {
    const prev = a.progress?.completed ?? 0;
    const next = Math.max(prev, Number(data.completed || 0));
    const total = Number(data.total || a.progress?.total || next);
    a.progress = { type: 'cleanup', completed: next, total };
  } else {
    a.progress = data;
  }
  actives.set(a.encounterId, a);
  saveActive(getIdentifier(src), a);
  // push an updated tracker snapshot to this player
  const identifier = getIdentifier(src);
  const nowTs = now();
  const statuses = (Root.encounters || []).map((enc) => {
    const cd = getCooldown(identifier, enc);
    let status: 'available' | 'active' | 'turnin' | 'cooldown' = 'available';
    const aa = actives.get(enc.id);
    if (aa) {
      status = aa.status === 'complete' ? 'turnin' : 'active';
    } else if (cd && cd > nowTs) {
      status = 'cooldown';
    }
    const remaining = cd && cd > nowTs ? cd - nowTs : 0;
    return {
      id: enc.id,
      label: (enc as any).label || enc.id,
      type: enc.type,
      status,
      cooldownRemaining: remaining,
      reward: enc.reward || null,
      progress: aa ? aa.progress || null : null,
    };
  });
  emitNet(`${ResourceName}:tracker:data`, src, { statuses });
});

// Client requests to restore mission state after restart
onNet(`${ResourceName}:restore:request`, () => {
  const src = (global as any).source as number;
  const identifier = getIdentifier(src);
  const actives = getActivesFor(src);
  for (const enc of Root.encounters || []) {
    if (!actives.has(enc.id)) {
      const s = loadActive(identifier, enc.id);
      if (s) actives.set(enc.id, s);
    }
  }
  for (const a of actives.values()) {
    const enc = findEncounter(a.encounterId);
    if (!enc) continue;
    if (a.status === 'in-progress') {
      emitNet(`${ResourceName}:mission:start`, src, { encounter: enc, npcId: a.npcId, progress: a.progress || null });
    } else if (a.status === 'complete') {
      emitNet(`${ResourceName}:mission:return`, src, { npcId: a.npcId, encounterId: a.encounterId });
    }
  }
});

