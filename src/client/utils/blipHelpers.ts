import type { Vector3 } from '@common/types';

export interface BlipConfig {
  location: Vector3;
  label: string;
  area?: Vector3;
  radius?: number;
  sprite?: number;
  color?: number;
  scale?: number;
}

export interface CreatedBlips {
  missionBlip: number;
  areaBlip?: number;
}

/**
 * Creates mission blips with optional area marker
 * @param config - Blip configuration
 * @returns Object containing created blip IDs for cleanup
 */
export function createMissionBlips(config: BlipConfig): CreatedBlips {
  const {
    location,
    label,
    area,
    radius,
    sprite = 1,
    color = 5, // Yellow
    scale = 1.0
  } = config;

  // Use area if specified, otherwise use main location
  const blipLocation = area || location;

  // Create main mission blip
  const missionBlip = AddBlipForCoord(blipLocation.x, blipLocation.y, blipLocation.z);
  SetBlipSprite(missionBlip, sprite);
  SetBlipColour(missionBlip, color);
  SetBlipScale(missionBlip, scale);
  SetBlipAsShortRange(missionBlip, false); // Never use short range
  BeginTextCommandSetBlipName('STRING');
  AddTextComponentString(`Encounter: ${label}`);
  EndTextCommandSetBlipName(missionBlip);

  const result: CreatedBlips = { missionBlip };

  // Create area marker if area and radius are specified
  if (area && radius && radius > 0) {
    const areaBlip = AddBlipForRadius(area.x, area.y, area.z, radius);
    SetBlipColour(areaBlip, color); // Match mission blip color
    SetBlipAlpha(areaBlip, 64); // Semi-transparent area boundary
    result.areaBlip = areaBlip;
  }

  return result;
}

/**
 * Removes mission blips safely
 * @param blips - Blips object returned from createMissionBlips
 */
export function removeMissionBlips(blips: CreatedBlips | null): void {
  if (!blips) return;

  try {
    if (blips.missionBlip && DoesBlipExist(blips.missionBlip)) {
      RemoveBlip(blips.missionBlip);
    }
  } catch (e) {
    console.warn('[blipHelpers] Failed to remove mission blip:', e);
  }

  try {
    if (blips.areaBlip && DoesBlipExist(blips.areaBlip)) {
      RemoveBlip(blips.areaBlip);
    }
  } catch (e) {
    console.warn('[blipHelpers] Failed to remove area blip:', e);
  }
}