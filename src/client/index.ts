/// <reference types="@citizenfx/client" />
import Config from '@common/config';

// no ox_lib cache needed at runtime for event naming
import type { AnyEncounter, NpcConfig, RootConfig } from '@common/types';
import { ResourceName } from '@common/resource';
import { registerNpc } from './state';
import * as Missions from './missions';
import { notify } from './notify';

// Types and helpers
const Root = Config as RootConfig;
const npcs: Record<string, number> = {}; // npcId -> ped
const npcBlips: number[] = [];
let nuiReady = false;
let pendingEncounter: { npc: NpcConfig; enc: AnyEncounter } | null = null;
let trackerVisible = false;

// Helper function to find NPC by ID from encounters
function findNpcById(npcId: string): { npc: NpcConfig; encounter: AnyEncounter } | null {
  for (const encounter of Root.encounters) {
    if (encounter.npc.id === npcId) {
      return { npc: encounter.npc, encounter };
    }
  }
  return null;
}


// Track whether we are currently eligible to claim for a given encounter at a given NPC
// Track claimable encounters and active encounters per encounterId
const claimableEncounters = new Set<string>();
const activeEncounters = new Map<string, { npcId: string; status: 'in-progress' | 'complete'; type?: AnyEncounter['type'] }>();
const encounterTypes = new Map<string, AnyEncounter['type']>();

// FiveM-compliant NUI callback registration
function registerNui<T = any>(name: string, handler: (data: T, cb: (result: any) => void) => void) {
  try {
    // Ensure the callback type is registered for NUI POST routing
    // @ts-ignore - provided by FiveM runtime
    RegisterNuiCallbackType?.(name);
  } catch {}
  // Listen for the CFX-wrapped NUI event
  // @ts-ignore - provided by FiveM runtime
  on?.(`__cfx_nui:${name}`, (data: T, cb: (result: any) => void) => {
    try {
      handler(data, cb);
    } catch (e) {
      try { console.error(`[missions] NUI handler error for ${name}:`, e); } catch {}
      cb({ ok: false });
    }
  });
}



function openEncounterNui(npc: NpcConfig, enc: AnyEncounter) {
  SetNuiFocus(true, true);
  trackerVisible = true; // Update client state to match
  
  // Always request fresh tracker data first to ensure UI sync
  emitNet(`${ResourceName}:tracker:request`);
  
  if (!nuiReady) {
    // show frame and defer payload until UI reports ready
    const vis = { action: 'setVisible', data: { visible: true } } as const;
    SendNuiMessage(JSON.stringify(vis));
    pendingEncounter = { npc, enc };
    // also send a delayed attempt in case ready event races
    setTimeout(() => {
      const npcWithEncounter = { ...npc, encounterId: enc.id };
      const show = { action: 'encounter:show', data: { npc: npcWithEncounter, encounter: enc } } as const;
      SendNuiMessage(JSON.stringify(vis));
      SendNuiMessage(JSON.stringify(show));
    }, 150);
    setTimeout(() => {
      const npcWithEncounter = { ...npc, encounterId: enc.id };
      const show = { action: 'encounter:show', data: { npc: npcWithEncounter, encounter: enc } } as const;
      SendNuiMessage(JSON.stringify(vis));
      SendNuiMessage(JSON.stringify(show));
    }, 400);
    return;
  }
  
  const vis = { action: 'setVisible', data: { visible: true } } as const;
  const npcWithEncounter = { ...npc, encounterId: enc.id };
  const show = { action: 'encounter:show', data: { npc: npcWithEncounter, encounter: enc } } as const;
  SendNuiMessage(JSON.stringify(vis));
  SendNuiMessage(JSON.stringify(show));
}

function loadModel(model: string) {
  return new Promise<void>((resolve) => {
    const hash = typeof model === 'string' ? GetHashKey(model) : model;
    RequestModel(hash);
    let tries = 0;
    const int = setInterval(() => {
      tries++;
      if (HasModelLoaded(hash) || tries > 100) {
        clearInterval(int);
        resolve();
      }
    }, 50);
  });
}

function createPedForNpc(n: NpcConfig, encounterId: string) {
  const c = n.coords;
  const heading = c.w ?? n.heading ?? 0;
  return (async () => {
    await loadModel(n.model);
    const ped = CreatePed(4, GetHashKey(n.model), c.x, c.y, c.z, heading, false, true);
    SetEntityInvincible(ped, true);
    SetBlockingOfNonTemporaryEvents(ped, true);
    FreezeEntityPosition(ped, true);
    if (n.scenario) TaskStartScenarioInPlace(ped, n.scenario, 0, true);

    // target entry - force single direct interaction (no dropdown)
    const label = n.target?.label || `Talk to ${n.id}`;
    const target = (globalThis as any).exports?.ox_target;
    
    if (target?.addLocalEntity) {
      const options = {
        name: `${ResourceName}:npc:${n.id}`,
        icon: n.target?.icon || 'fa-solid fa-comments',
        label,
        distance: 2.0,
        onSelect: () => {
          const enc = Root.encounters.find((e) => e.id === encounterId);
          if (!enc) return;
          
          // Play ambient speech for the NPC
          const speechName = n.speech || 'GENERIC_HI';
          PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force');
          openEncounterNui(n, enc);
        },
      };
      
      try {
        target.addLocalEntity(ped, options);
      } catch (e) {
        console.error(`[missions] Failed to add ox_target for NPC ${n.id}:`, e);
      }
    }

    if (Root.npcBlips && n.blip) {
      const blip = AddBlipForEntity(ped);
      SetBlipSprite(blip, n.blip.sprite ?? 280);
      SetBlipColour(blip, n.blip.color ?? 0);
      SetBlipScale(blip, n.blip.scale ?? 0.8);
      BeginTextCommandSetBlipName('STRING');
      AddTextComponentString(n.target?.label || n.id);
      EndTextCommandSetBlipName(blip);
      npcBlips.push(blip);
    }

    return ped;
  })();
}

async function spawnAllNpcs() {
  // prevent duplicates by clearing any tracked references first
  await cleanupAllNpcs();
  
  for (const encounter of Root.encounters) {
    const n = encounter.npc;
    try {
      const ped = await createPedForNpc(n, encounter.id);
      npcs[n.id] = ped;
      registerNpc(n.id, ped);
    } catch (e) {
      console.error(`[missions] Failed to spawn NPC ${n.id}:`, e);
    }
  }
}

async function cleanupAllNpcs() {
  const target = (globalThis as any).exports?.ox_target;
  
  // Remove ox_target interactions first
  for (const id of Object.keys(npcs)) {
    const ped = npcs[id];
    try { 
      if (target?.removeLocalEntity && DoesEntityExist(ped)) {
        target.removeLocalEntity(ped);
      }
    } catch {}
  }
  
  // Delete the actual entities
  for (const id of Object.keys(npcs)) {
    const ped = npcs[id];
    try { 
      if (DoesEntityExist(ped)) {
        DeleteEntity(ped);
      }
    } catch {}
    delete npcs[id];
  }
  
  // Clean up blips
  while (npcBlips.length) {
    const b = npcBlips.pop();
    if (b) { 
      try { 
        RemoveBlip(b);
      } catch {}
    }
  }
  
  // Clear the collections
  Object.keys(npcs).forEach(key => delete npcs[key]);
  npcBlips.length = 0;
}

// Ensure clean restart behavior on /ensure
on('onClientResourceStart', (resName: string) => {
  if (resName === ResourceName) {
    try { SetNuiFocus(false, false); } catch {}
    trackerVisible = false;
    SendNuiMessage(JSON.stringify({ action: 'tracker:toggle', data: { visible: false } }));
    
    // Clean up any existing NPCs first, then spawn after a short delay
    setTimeout(async () => {
      await cleanupAllNpcs();
      await spawnAllNpcs();
    }, 500);
    
    // ask server to restore any active mission state so client can respawn props/blips
    setTimeout(() => emitNet(`${ResourceName}:restore:request`), 750);
  }
});

on('onClientResourceStop', (resName: string) => {
  if (resName === ResourceName) {
    try { SetNuiFocus(false, false); } catch {}
    trackerVisible = false;
    SendNuiMessage(JSON.stringify({ action: 'tracker:toggle', data: { visible: false } }));
    // Cleanup NPCs and mission state
    void cleanupAllNpcs();
    try { Missions.stopAll?.(); } catch {}
  }
});

// NUI callbacks
registerNui('exit', (data: { npcId?: string } | null, cb: (data: unknown) => void) => {
  SetNuiFocus(false, false);
  trackerVisible = false; // Update client state to match
  
  // Play goodbye speech if NPC ID is provided
  if (data?.npcId) {
    const ped = npcs[data.npcId];
    const npcResult = findNpcById(data.npcId);
    if (ped && DoesEntityExist(ped) && npcResult) {
      const speechName = npcResult.npc.speechBye || 'GENERIC_BYE';
      PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force');
    }
  }
  
  cb({});
});

registerNui('ui:ready', (_data: null, cb: (data: unknown) => void) => {
  nuiReady = true;
  if (pendingEncounter) {
    const { npc, enc } = pendingEncounter;
    const npcWithEncounter = { ...npc, encounterId: enc.id };
    SendNuiMessage(JSON.stringify({ action: 'setVisible', data: { visible: true } }));
    SendNuiMessage(JSON.stringify({ action: 'encounter:show', data: { npc: npcWithEncounter, encounter: enc } }));
    pendingEncounter = null;
  }
  cb({ ok: true });
});

registerNui('encounter:accept', (data: { npcId: string; encounterId: string }, cb: (data: any) => void) => {
  SetNuiFocus(false, false);
  trackerVisible = false; // Update client state to match
  
  // Play goodbye speech for the NPC
  const ped = npcs[data.npcId];
  const npcResult = findNpcById(data.npcId);
  if (ped && DoesEntityExist(ped) && npcResult) {
    const speechName = npcResult.npc.speechBye || 'GENERIC_BYE';
    PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force');
  }
  
  if (!ped) return cb({ ok: false, reason: 'npc_missing' });
  emitNet(`${ResourceName}:encounter:accept`, data as any);
  cb({ ok: true });
});

registerNui('encounter:reject', (data: { npcId?: string }, cb: (data: any) => void) => {
  SetNuiFocus(false, false);
  trackerVisible = false; // Update client state to match
  
  // Play goodbye speech for the NPC
  if (data.npcId) {
    const ped = npcs[data.npcId];
    const npcResult = findNpcById(data.npcId);
    if (ped && DoesEntityExist(ped) && npcResult) {
      const speechName = npcResult.npc.speechBye || 'GENERIC_BYE';
      PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force');
    }
  }
  
  cb({ ok: true });
});

// Optional: NUI may post a cancel request (if you have a Cancel button in UI later)
registerNui('encounter:cancel', (data: { encounterId?: string; npcId?: string } | null, cb: (data: any) => void) => {
  SetNuiFocus(false, false);
  trackerVisible = false; // Update client state to match
  
  // Play goodbye speech for the NPC
  if (data?.npcId) {
    const ped = npcs[data.npcId];
    const npcResult = findNpcById(data.npcId);
    if (ped && DoesEntityExist(ped) && npcResult) {
      const speechName = npcResult.npc.speechBye || 'GENERIC_BYE';
      PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force');
    }
  }
  
  if (data?.encounterId) emitNet(`${ResourceName}:encounter:cancel`, { encounterId: data.encounterId });
  cb({ ok: true });
});

// Get current panel visibility state
registerNui('panel:getVisible', (_data: any, cb: (data: any) => void) => {
  cb({ visible: trackerVisible });
});

// Handle focus management from NUI
registerNui('focus:set', (data: { hasFocus?: boolean; hasCursor?: boolean }, cb: (data: any) => void) => {
  try {
    SetNuiFocus(!!data.hasFocus, !!data.hasCursor);
    // Update tracker visibility state
    trackerVisible = !!data.hasFocus;
  } catch {}
  cb({ ok: true });
});

// Handle tracker data request from NUI
registerNui('tracker:request', (_data: any, cb: (data: any) => void) => {
  emitNet(`${ResourceName}:tracker:request`);
  cb({ ok: true });
});

// NUI: set waypoint to the NPC for this encounter (for available/turnin guidance)
registerNui('encounter:waypoint', (data: { encounterId?: string } | null, cb: (data: any) => void) => {
  try { SetNuiFocus(false, false); } catch {}
  if (data?.encounterId) {
    // Find the encounter and its NPC
    const encounter = Root.encounters.find((e) => e.id === data.encounterId);
    if (encounter && encounter.npc.coords) {
      try {
        const { x, y } = encounter.npc.coords as any;
        SetNewWaypoint(x, y);
        // optional: create a temporary blip to highlight
        const temp = AddBlipForCoord(x, y, (encounter.npc.coords as any).z || 0);
        try {
          SetBlipSprite(temp, 280);
          SetBlipColour(temp, 0);
          SetBlipScale(temp, 0.8);
          BeginTextCommandSetBlipName('STRING');
          AddTextComponentString(encounter.npc.target?.label || encounter.npc.id);
          EndTextCommandSetBlipName(temp);
          // auto remove after a few seconds
          setTimeout(() => { try { RemoveBlip(temp); } catch {} }, 6000);
        } catch {}
      } catch {}
  }
  }
  cb({ ok: true });
});

// NUI: set waypoint to mission location (when accepting a mission)
registerNui('mission:waypoint', (data: { x?: number; y?: number; z?: number } | null, cb: (data: any) => void) => {
  try { SetNuiFocus(false, false); } catch {}
  if (data?.x && data?.y) {
    try {
      SetNewWaypoint(data.x, data.y);
    } catch {}
  }
  cb({ ok: true });
});

// NUI: claim reward for completed mission
registerNui('encounter:claim', (data: { encounterId?: string; npcId?: string } | null, cb: (data: any) => void) => {
  try { SetNuiFocus(false, false); } catch {}
  if (data?.encounterId && data?.npcId) {
    // Play claim reward speech first
    const ped = npcs[data.npcId];
    const npcResult = findNpcById(data.npcId);
    if (ped && DoesEntityExist(ped) && npcResult) {
      const speechName = npcResult.npc.speechClaim || 'GENERIC_THANKS';
      PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force');
      
      // Play goodbye speech after a short delay
      setTimeout(() => {
        const goodbyeSpeech = npcResult.npc.speechBye || 'GENERIC_BYE';
        PlayAmbientSpeech1(ped, goodbyeSpeech, 'Speech_Params_Force');
      }, 1500); // 1.5 second delay between thank you and goodbye
    }
    
    emitNet(`${ResourceName}:encounter:claim`, { encounterId: data.encounterId, npcId: data.npcId });
  }
  cb({ ok: true });
});

// tracker close from NUI
registerNui('tracker:exit', (data: { npcId?: string } | null, cb: (data: unknown) => void) => {
  trackerVisible = false;
  try { SetNuiFocus(false, false); } catch {}
  
  // Play goodbye speech if NPC ID is provided
  if (data?.npcId) {
    const ped = npcs[data.npcId];
    const npcResult = findNpcById(data.npcId);
    if (ped && DoesEntityExist(ped) && npcResult) {
      const speechName = npcResult.npc.speechBye || 'GENERIC_BYE';
      PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force');
    }
  }
  
  SendNuiMessage(JSON.stringify({ action: 'tracker:toggle', data: { visible: false } }));
  cb({ ok: true });
});

// dev command kept
if (Config.EnableNuiCommand) {
  onNet(`${ResourceName}:openNui`, () => {
    SetNuiFocus(true, true);
    const vis = { action: 'setVisible', data: { visible: true } } as const;
    SendNuiMessage(JSON.stringify(vis));
  });

  // Optional: open UI with a test payload for validation
  RegisterCommand('missions_testui', () => {
    const npc = { id: 'test', target: { label: 'Test Giver' } } as any;
    const enc = { id: 'test_enc', label: 'Test Encounter', description: 'Debug modal render', reward: { cash: 1 } } as any;
    openEncounterNui(npc, enc);
  }, false);

}

// Toggle tracker UI (always available)
RegisterCommand('missions', () => {
  // Always send toggle request - let NUI handle the current state determination
  SendNuiMessage(JSON.stringify({ action: 'tracker:toggle', data: {} }));
}, false);

// Default keybind to toggle missions tracker (customizable in settings)
try {
  // Users can rebind this in GTA V keybinds (FiveM Settings -> Key Bindings)
  RegisterKeyMapping('missions', 'Toggle Missions Tracker', 'keyboard', 'F6');
} catch {}

// Mission lifecycle events forwarded by server
onNet(`${ResourceName}:mission:start`, (data: { encounter: AnyEncounter; npcId: string; progress?: any }) => {
  // If server provided progress snapshot (e.g., after restore), send it to the module first
  try {
    if (data.progress && typeof Missions.setProgress === 'function') {
      Missions.setProgress(data.encounter.id, data.progress);
    }
  } catch {}
  // Track this encounter as in progress for this NPC
  activeEncounters.set(data.encounter.id, { npcId: data.npcId, status: 'in-progress', type: data.encounter.type });
  encounterTypes.set(data.encounter.id, data.encounter.type);
  Missions.start(data.encounter);
});

onNet(`${ResourceName}:mission:return`, (data: { npcId: string; encounterId: string }) => {
  // Track mission as complete and ready for claim (claim rewards handled via NUI now)
  claimableEncounters.add(data.encounterId);
  const t = encounterTypes.get(data.encounterId);
  activeEncounters.set(data.encounterId, { npcId: data.npcId, status: 'complete', type: t });
  
  // Get mission title from encounter data
  const encounter = Root.encounters.find((e) => e.id === data.encounterId);
  const missionTitle = encounter?.label || 'Mission';
  
  notify({ title: missionTitle, description: 'You did it! Return to claim your reward.', type: 'success', duration: 10000 });
  // Set waypoint to the NPC
  if (encounter && encounter.npc.coords) {
    try {
      const { x, y } = encounter.npc.coords as any;
      SetNewWaypoint(x, y);
    } catch {}
  }
});

onNet(`${ResourceName}:mission:claimed`, (_data: { encounterId: string }) => {
  // Clear claimable and active state for this encounter
  claimableEncounters.delete(_data.encounterId);
  activeEncounters.delete(_data.encounterId);
  if (trackerVisible) emitNet(`${ResourceName}:tracker:request`);
});

onNet(`${ResourceName}:mission:cooldown`, (data: { seconds: number; encounterId: string }) => {
  const mins = Math.ceil(data.seconds / 60);
  notify({ title: 'Encounter', description: `On cooldown (${mins} min)`, type: 'error' });
  if (trackerVisible) emitNet(`${ResourceName}:tracker:request`);
});

// Server refused accept because we already have a mission
onNet(`${ResourceName}:mission:busy`, (data: { encounterId: string; status: 'in-progress' | 'complete' }) => {
  const status = data.status === 'complete' ? 'ready to turn in' : 'in progress';
  notify({ title: 'Encounter', description: `You already have a mission ${status}.`, type: 'error', duration: 10000 });
});

// Mission was cancelled from client
onNet(`${ResourceName}:mission:cancelled`, (data: { encounterId: string; appliedCooldown: boolean }) => {
  // Stop only the cancelled mission's module to avoid clearing other missions' blips/props
  const t = encounterTypes.get(data.encounterId);
  if (t) {
    try { Missions.stopType?.(t as any); } catch {}
  } else {
    try { Missions.stopAll?.(); } catch {}
  }
  // Clear sets for this encounter
  claimableEncounters.delete(data.encounterId);
  activeEncounters.delete(data.encounterId);
  encounterTypes.delete(data.encounterId);
  const msg = data.appliedCooldown ? 'You cancelled the mission.' : 'Mission cancelled.';
  notify({ title: 'Encounter', description: msg, type: 'warning', duration: 10000 });
  if (trackerVisible) emitNet(`${ResourceName}:tracker:request`);
});

// Receive tracker data from server and forward to NUI
onNet(`${ResourceName}:tracker:data`, (data: { statuses: any[], discoveredMissions?: any[] }) => {
  SendNuiMessage(JSON.stringify({ action: 'tracker:data', data }));
});
