import type { CleanupEncounter } from '@common/types';
import { ResourceName } from '@common/resource';
import { notify } from '../notify';
import { createMissionBlips, removeMissionBlips, type CreatedBlips } from '../utils/blipHelpers';
// no ox_lib cache needed here

const spawned: number[] = [];
let remaining = 0;
let total = 0;
let missionBlips: CreatedBlips | null = null;


function randomInCircle(radius: number) {
  const t = Math.random() * 2 * Math.PI;
  const r = radius * Math.sqrt(Math.random());
  return { x: Math.cos(t) * r, y: Math.sin(t) * r };
}

async function loadModel(model: string) {
  return new Promise<void>((resolve) => {
    const hash = GetHashKey(model);
    RequestModel(hash);
    const i = setInterval(() => {
      if (HasModelLoaded(hash)) {
        clearInterval(i);
        resolve();
      }
    }, 25);
  });
}

function groundZAt(x: number, y: number, zHint: number) {
  try {
    const [ok, gz] = GetGroundZFor_3dCoord(x, y, zHint, true);
    if (ok) return gz;
  } catch {}
  return zHint;
}

export async function start(encounter: CleanupEncounter) {
  const { area, radius, props, count, positions, presets, preventUnderground, spawnMode } = encounter.params as any;
  // If progress was restored earlier via setProgress, honor it; otherwise initialize
  if (!(total > 0)) total = count;
  if (!(remaining > 0) || remaining > total) remaining = total;

  // Create mission blips using helper
  if (area) {
    missionBlips = createMissionBlips({
      location: area,
      label: encounter.label,
      area,
      radius
    });
  }

  // Determine spawn list by explicit spawnMode or fallback
  let spawnPoints: { x: number; y: number; z: number }[] = [];
  const mode = (spawnMode as string) || (Array.isArray(positions) && positions.length ? 'positions' : (Array.isArray(presets) && presets.length ? 'preset' : 'random'));
  if (mode === 'positions' && Array.isArray(positions) && positions.length) {
    spawnPoints = positions.slice(0, count);
  } else if (mode === 'preset' && Array.isArray(presets) && presets.length) {
    const choice = presets[Math.floor(Math.random() * presets.length)];
    if (choice?.positions?.length) spawnPoints = choice.positions.slice(0, count);
  }

  for (let i = 0; i < count; i++) {
    const model = props[Math.floor(Math.random() * props.length)];
    await loadModel(model);
    let x: number, y: number, z: number;
    if (spawnPoints[i]) {
      x = spawnPoints[i].x; y = spawnPoints[i].y; z = spawnPoints[i].z;
    } else {
      x = area.x; y = area.y; z = area.z + 20;
      // choose a random point in the circle
      const off = randomInCircle(radius);
      x += off.x; y += off.y;
    }
    if (preventUnderground) z = groundZAt(x, y, z);

    const obj = CreateObject(GetHashKey(model), x, y, z, false, true, false);
    PlaceObjectOnGroundProperly(obj);
    FreezeEntityPosition(obj, true);
    spawned.push(obj);

    const target = (globalThis as any).exports?.ox_target;
    target?.addLocalEntity?.(obj, [
      { name: `${encounter.id}:pickup:${i}`,
        icon: 'fa-solid fa-hand',
        label: 'Pick up',
        onSelect: () => collect(obj, encounter) },
    ]);
  }
}

export function stop() {
  // delete any spawned objects and blips if resource is stopping
  for (const o of spawned) {
    try { DeleteObject(o); } catch {}
  }
  spawned.length = 0;
  remaining = 0;
  total = 0;
  removeMissionBlips(missionBlips);
  missionBlips = null;
}

export function setProgress(progress: { completed?: number; total?: number } | null) {
  if (!progress) return;
  try {
    const fallbackTotal = total > 0 ? total : (typeof progress.total === 'number' && progress.total > 0 ? progress.total : 0);
    const t = fallbackTotal > 0 ? fallbackTotal : 0;
    const c = Math.max(0, Math.min(t || Number(progress.total || 0), Number(progress.completed ?? 0)));
    if (t > 0) {
      total = t;
      remaining = Math.max(0, t - c);
    }
  } catch {}
}
function collect(obj: number, encounter: CleanupEncounter) {
  try { SetEntityAsMissionEntity(obj, true, true); } catch {}
  try { DeleteObject(obj); } catch {}
  const idx = spawned.indexOf(obj);
  if (idx >= 0) spawned.splice(idx, 1);
  remaining--;

  // progress update
  try {
    const completed = Math.max(0, total - remaining);
    emitNet(`${ResourceName}:encounter:progress`, { encounterId: encounter.id, type: 'cleanup', completed, total });
    const label = encounter.params.itemLabel || 'item';
    const msg = encounter.messages?.pickup
      ? encounter.messages.pickup
      : `Collected ${completed}/${total} ${label}`;
    notify({ title: encounter.label || 'Cleanup', description: msg, type: 'inform' });
  } catch {}

  if (remaining <= 0) {
    // Cleanup leftovers and blips
    for (const o of spawned) {
      try { DeleteObject(o); } catch {}
    }
    removeMissionBlips(missionBlips);
    missionBlips = null;
    emitNet(`${ResourceName}:encounter:complete`, { encounterId: encounter.id });
  }
}
