import type { DeliveryEncounter } from '@common/types';
import { ResourceName } from '@common/resource';
import { notify } from '../notify';
import { createMissionBlips, removeMissionBlips, type CreatedBlips } from '../utils/blipHelpers';

const lib = exports['ox_lib'];

let interval: number | undefined;
let missionBlips: CreatedBlips | null = null;
let propObjects: number[] = [];
let startTime: number = 0;
let lastDisplayedTime: number = -1;
let isNearDestination: boolean = false;

// Helper function to format time as MM:SS
function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

// Helper function to load model
async function loadModel(model: string): Promise<void> {
  return new Promise((resolve) => {
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

// Helper function to load animation dictionary
async function loadAnimDict(dict: string): Promise<void> {
  return new Promise((resolve) => {
    RequestAnimDict(dict);
    let tries = 0;
    const int = setInterval(() => {
      tries++;
      if (HasAnimDictLoaded(dict) || tries > 100) {
        clearInterval(int);
        resolve();
      }
    }, 50);
  });
}

// Helper function to normalize placement values
function normalizePlacement(placement: { x: number; y: number; z: number } | [number, number, number]): { x: number; y: number; z: number } {
  if (Array.isArray(placement)) {
    return { x: placement[0], y: placement[1], z: placement[2] };
  }
  return placement;
}

// Apply animation and props to player
async function applyAnimationAndProps(encounter: DeliveryEncounter): Promise<void> {
  const animation = encounter.params.animation;
  if (!animation) return;

  try {
    const ped = PlayerPedId();
    
    // Load animation dictionary
    await loadAnimDict(animation.Dictionary);
    
    // Load all prop models
    const propModels = animation.Options.Props.map(prop => prop.Name);
    await Promise.all(propModels.map(model => loadModel(model)));
    
    // Clear any existing animation
    ClearPedTasks(ped);
    
    // Start animation with flags
    const flags = animation.Options.Flags;
    let animFlags = 0;
    
    // FiveM Animation Flags:
    // 1 = ANIM_FLAG_NORMAL
    // 2 = ANIM_FLAG_REPEAT 
    // 16 = ANIM_FLAG_STOP_LAST_FRAME
    // 32 = ANIM_FLAG_UPPERBODY (allows movement)
    // 48 = ANIM_FLAG_ENABLE_PLAYER_CONTROL (allows full player control)
    
    if (flags.Loop) animFlags |= 2;  // ANIM_FLAG_REPEAT
    if (flags.Move) animFlags |= 49; // ANIM_FLAG_ENABLE_PLAYER_CONTROL + ANIM_FLAG_NORMAL
    
    if (animFlags === 0) animFlags = 1; // Default to ANIM_FLAG_NORMAL
    
    TaskPlayAnim(
      ped,
      animation.Dictionary,
      animation.Animation,
      8.0, // blend in speed
      8.0, // blend out speed
      -1,  // duration (-1 = indefinite)
      animFlags,
      0.0, // playback rate
      false,
      false,
      false
    );
    
    // Wait a bit for animation to start
    await new Promise<void>(resolve => setTimeout(resolve, 100));
    
    // Attach props
    for (const propConfig of animation.Options.Props) {
      const propObj = CreateObject(GetHashKey(propConfig.Name), 0, 0, 0, true, true, true);
      const boneIndex = GetPedBoneIndex(ped, propConfig.Bone);
      
      const offset = normalizePlacement(propConfig.Placement[0]);
      const rotation = normalizePlacement(propConfig.Placement[1]);
      
      AttachEntityToEntity(
        propObj,
        ped,
        boneIndex,
        offset.x,
        offset.y,
        offset.z,
        rotation.x,
        rotation.y,
        rotation.z,
        true,
        true,
        false,
        true,
        1,
        true
      );
      
      // Store prop object for cleanup
      propObjects.push(propObj);
    }
  } catch (e) {
    console.error('[missions] Failed to apply animation and props:', e);
  }
}

// Remove animation and props from player
function removeAnimationAndProps(): void {
  const ped = PlayerPedId();
  
  // Clear animation
  ClearPedTasks(ped);
  
  // Remove all props
  for (const propObj of propObjects) {
    if (DoesEntityExist(propObj)) {
      DeleteEntity(propObj);
    }
  }
  propObjects = [];
}

export function start(encounter: DeliveryEncounter) {
  const { destination, timeSeconds, area, radius } = encounter.params;
  startTime = GetGameTimer();

  // Create mission blips using helper
  // Use area if specified, otherwise use destination
  const blipLocation = area || destination;
  missionBlips = createMissionBlips({
    location: blipLocation,
    label: encounter.label,
    area,
    radius
  });

  // Apply animation and props to player
  void applyAnimationAndProps(encounter);

  // Show initial textui
  const initialRemaining = timeSeconds;
  lastDisplayedTime = initialRemaining;
  lib.showTextUI(`⏰ Delivery Time: ${formatTime(initialRemaining)}`, {
    position: 'top-center',
    icon: 'clock',
    style: {
      backgroundColor: 'rgba(0, 0, 0, 0.7)',
      color: '#ffffff'
    }
  });

  interval = setTick(() => {
    const elapsed = Math.floor((GetGameTimer() - startTime) / 1000);
    const remaining = timeSeconds - elapsed;

    const ped = PlayerPedId();
    const coords = GetEntityCoords(ped, true) as unknown as [number, number, number];
    const dx = coords[0] - destination.x;
    const dy = coords[1] - destination.y;
    const dz = coords[2] - destination.z;
    const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);

    // Check if player is near destination (within 5 meters for prompt, 2.5 for completion)
    const nearDestination = dist < 5.0;
    
    // Update textui when time changes OR proximity state changes
    const stateChanged = nearDestination !== isNearDestination;
    const timeChanged = remaining !== lastDisplayedTime;
    
    if (timeChanged || stateChanged) {
      lastDisplayedTime = remaining;
      isNearDestination = nearDestination;
      
      const displayTime = Math.max(0, remaining);
      const isLowTime = remaining <= 30;
      
      if (nearDestination) {
        // Show combined timer + delivery prompt
        lib.showTextUI(`⏰ ${formatTime(displayTime)} | 📦 Press [E] to deliver`, {
          position: 'top-center',
          icon: 'hand-holding-box',
          iconColor: '#4CAF50',
          style: {
            backgroundColor: 'rgba(76, 175, 80, 0.8)',
            color: '#ffffff',
            borderLeft: '4px solid #2E7D32'
          }
        });
      } else {
        // Show just the timer
        lib.showTextUI(`⏰ Delivery Time: ${formatTime(displayTime)}`, {
          position: 'top-center',
          icon: 'clock',
          style: {
            backgroundColor: 'rgba(0, 0, 0, 0.7)',
            color: isLowTime ? '#ff6b6b' : '#ffffff'
          }
        });
      }
    }

    // Check for E key press when near destination
    if (nearDestination && IsControlJustReleased(0, 38)) { // E key
      cleanup();
      emitNet(`${ResourceName}:encounter:complete`, { encounterId: encounter.id });
      return;
    }

    if (remaining <= 0) {
      cleanup();
      notify({ title: encounter.label || 'Mission Failed', description: 'You ran out of time.', type: 'error', duration: 10000 });
      emitNet(`${ResourceName}:encounter:cancel`, { encounterId: encounter.id });
      return;
    }
  }) as unknown as number;
}

function cleanup() {
  // Clear the interval
  if (interval) {
    clearTick(interval as unknown as number);
    interval = undefined;
  }
  
  // Hide textui
  lib.hideTextUI();
  
  // Remove blips
  removeMissionBlips(missionBlips);
  missionBlips = null;
  
  // Remove animation and props
  removeAnimationAndProps();
  
  // Reset timer values
  startTime = 0;
  lastDisplayedTime = -1;
  isNearDestination = false;
}

export function stop() {
  cleanup();
}

// Function to set progress (for restoration after server restart)
export function setProgress(encounterId: string, progress: any) {
  // For delivery missions, we could restore elapsed time
  if (progress?.elapsedSeconds && startTime > 0) {
    startTime = GetGameTimer() - (progress.elapsedSeconds * 1000);
  }
}
