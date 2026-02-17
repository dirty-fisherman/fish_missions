import type { AssassinationEncounter } from '@common/types';
import { ResourceName } from '@common/resource';
import { createMissionBlips, removeMissionBlips, type CreatedBlips } from '../utils/blipHelpers';

let targetPeds: number[] = [];
let missionBlips: CreatedBlips | null = null;
let missionTick: number | undefined;


function loadModel(model: string) {
  return new Promise<void>((resolve, reject) => {
    const hash = GetHashKey(model);
    RequestModel(hash);
    let attempts = 0;
    const maxAttempts = 200; // 5 second timeout (200 * 25ms)
    
    const i = setInterval(() => {
      attempts++;
      if (HasModelLoaded(hash)) {
        clearInterval(i);
        console.log(`[missions] Model ${model} loaded successfully`);
        resolve();
      } else if (attempts >= maxAttempts) {
        clearInterval(i);
        console.error(`[missions] Failed to load model: ${model} after ${maxAttempts * 25}ms`);
        reject(new Error(`Failed to load model: ${model}`));
      }
    }, 25);
  });
}

// Validate targets array
function validateTargets(params: any): Array<{model: string; spawn: any; weapon?: string; heading?: number}> {
  if (!params.targets || !Array.isArray(params.targets)) {
    console.error('[missions] Assassination mission requires targets array');
    return [];
  }
  
  return params.targets.filter((target: any) => {
    if (!target.model || !target.spawn) {
      console.error('[missions] Invalid target config:', target);
      return false;
    }
    return true;
  });
}



export async function start(encounter: AssassinationEncounter) {
  const { blip } = encounter.params;
  
  console.log('[missions] Starting assassination mission:', encounter.id, 'with params:', encounter.params);
  
  const targets = validateTargets(encounter.params);
  console.log('[missions] Validated targets:', targets.length, 'targets found');
  
  if (targets.length === 0) {
    console.error('[missions] No targets defined for assassination mission');
    return;
  }

  // Use defined area from config
  const { area, radius } = encounter.params;
  console.log('[missions] Using defined area:', area, 'with radius:', radius);

  // Load all unique models
  const uniqueModels = [...new Set(targets.map((t: any) => t.model as string))];
  console.log('[missions] Loading models:', uniqueModels);
  
  const loadedModels = new Set<string>();
  for (const model of uniqueModels) {
    try {
      await loadModel(model);
      console.log('[missions] Model loaded successfully:', model, 'hash:', GetHashKey(model));
      loadedModels.add(model);
    } catch (error) {
      console.error('[missions] Failed to load model:', model, 'Error:', error);
      // Continue with other models
    }
  }
  
  // Filter targets to only include those with successfully loaded models
  const validTargets = targets.filter((t: any) => loadedModels.has(t.model));
  console.log('[missions] Valid targets after model loading:', validTargets.length, 'out of', targets.length);

  // Spawn all valid targets
  for (const target of validTargets) {
    console.log('[missions] Spawning target:', target.model, 'at', target.spawn);
    
    // Get proper ground Z coordinate
    let spawnZ = target.spawn.z;
    const [found, groundZ] = GetGroundZFor_3dCoord(target.spawn.x, target.spawn.y, target.spawn.z + 10.0, false);
    if (found && groundZ > 0) {
      spawnZ = groundZ + 1.0; // Spawn slightly above ground
      console.log('[missions] Adjusted Z from', target.spawn.z, 'to', spawnZ);
    }
    
    const ped = CreatePed(
      4, // Ped type (civilian)
      GetHashKey(target.model),
      target.spawn.x,
      target.spawn.y,
      spawnZ,
      target.heading || 0.0,
      true, // isNetwork = true for multiplayer
      true  // bScriptHostPed = true
    );
    
    // Ensure ped is properly networked and won't despawn
    if (DoesEntityExist(ped)) {
      SetEntityAsMissionEntity(ped, true, true);
      SetPedCanBeTargetted(ped, true);
      SetPedCanRagdoll(ped, true);
    }
    
    console.log('[missions] Created ped:', ped, 'exists:', DoesEntityExist(ped));

    // Configure ped behavior - use gang-like relationship
    SetPedCombatAttributes(ped, 46, true); // BF_CanFightArmedPedsWhenNotArmed
    SetPedCombatAttributes(ped, 5, true);  // BF_AlwaysFight
    SetPedFleeAttributes(ped, 0, false);   // Don't flee
    SetEntityHealth(ped, 200); // Set health
    SetPedArmour(ped, 0); // No armor for easier kills
    
    // Use existing gang relationship group for natural hostile-when-attacked behavior
    SetPedRelationshipGroupHash(ped, GetHashKey('GANG_1')); // Built-in gang group with proper defensive behavior
    
    // Give weapon if specified (omit weapon property or set to 'unarmed' for fist fights)
    if (target.weapon && target.weapon !== 'unarmed') {
      console.log('[missions] Giving weapon:', target.weapon, 'to ped:', ped);
      GiveWeaponToPed(ped, GetHashKey(target.weapon), 250, false, true);
      SetCurrentPedWeapon(ped, GetHashKey(target.weapon), true);
    } else {
      console.log('[missions] Ped will fight unarmed (fists):', ped);
      // Ensure they have fists as default weapon
      SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true);
    }

    // Don't start combat immediately - wait for player to attack first
    
    targetPeds.push(ped);
  }

  // Create mission blips using helper
  if (blip && targets.length > 0) {
    missionBlips = createMissionBlips({
      location: area,
      label: encounter.label,
      area,
      radius
    });
    console.log('[missions] Created mission blips at:', area, 'radius:', radius);
  }

  // Start monitoring for mission completion only
  missionTick = setTick(() => {
    // Check if all targets are dead
    let allDead = true;
    for (const ped of targetPeds) {
      if (DoesEntityExist(ped) && !IsEntityDead(ped) && !IsPedFatallyInjured(ped)) {
        allDead = false;
        break;
      }
    }

    if (allDead) {
      // Mission complete
      if (missionTick) {
        clearTick(missionTick as unknown as number);
        missionTick = undefined;
      }
      
      // Remove blips, leave corpses for natural despawn
      removeMissionBlips(missionBlips);
      missionBlips = null;
      
      console.log('[missions] Assassination mission completed - all targets eliminated');
      
      emitNet(`${ResourceName}:encounter:complete`, { encounterId: encounter.id });
    }
  }) as unknown as number;
}

export function stop() {
  // Clear tick
  if (missionTick) {
    clearTick(missionTick as unknown as number);
    missionTick = undefined;
  }
  
  // Remove blips
  removeMissionBlips(missionBlips);
  missionBlips = null;
  
  // Remove peds (for cleanup/cancellation)
  for (const ped of targetPeds) {
    try { 
      if (DoesEntityExist(ped)) {
        DeleteEntity(ped); 
      }
    } catch {}
  }
  targetPeds = [];
}
