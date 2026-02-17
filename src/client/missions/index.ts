import type { AnyEncounter, EncounterType } from '@common/types';
import * as cleanup from './cleanup';
import * as delivery from './delivery';
import * as assassination from './assassination';

export function start(encounter: AnyEncounter) {
  switch (encounter.type) {
    case 'cleanup':
      return cleanup.start(encounter as any);
    case 'delivery':
      return delivery.start(encounter as any);
    case 'assassination':
      return assassination.start(encounter as any);
  }
}

export function stopAll() {
  try { cleanup.stop?.(); } catch {}
  try { delivery.stop?.(); } catch {}
  try { assassination.stop?.(); } catch {}
}

export function setProgress(encounterId: string, progress: any) {
  // Currently only cleanup uses granular progress
  try { cleanup.setProgress?.(progress); } catch {}
}

export function stopType(type: EncounterType) {
  switch (type) {
    case 'cleanup':
      try { cleanup.stop?.(); } catch {}
      break;
    case 'delivery':
      try { delivery.stop?.(); } catch {}
      break;
    case 'assassination':
      try { assassination.stop?.(); } catch {}
      break;
  }
}
