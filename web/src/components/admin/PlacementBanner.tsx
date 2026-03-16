import { useAdminStore } from '../../stores/adminStore';
import { useNuiEvent } from '../../hooks/useNuiEvent';

interface CapturedPosition {
  field: string;
  entityType: string;
  x: number;
  y: number;
  z: number;
  heading: number;
}

interface PropAdjustResult {
  propOffset: { x: number; y: number; z: number };
  propRotation: { x: number; y: number; z: number };
}

export function PlacementBanner() {
  const capturingField = useAdminStore((s) => s.capturingField);

  useNuiEvent<CapturedPosition>('admin:positionCaptured', (pos) => {
    const { editing, updateNpc, updateParams, setCapturingField } = useAdminStore.getState();
    if (!editing || !pos.field) return;

    if (pos.field === 'npc') {
      updateNpc({
        coords: { x: pos.x, y: pos.y, z: pos.z, w: pos.heading },
      });
    } else if (pos.field === 'destination') {
      updateParams({
        destination: { x: pos.x, y: pos.y, z: pos.z },
      });
    } else if (pos.field.startsWith('gprop_')) {
      // Group-aware prop: gprop_{groupIdx}_{propIdx}
      const parts = pos.field.split('_');
      const gi = parseInt(parts[1], 10);
      const pi = parseInt(parts[2], 10);
      const propGroups = [...(editing.params?.propGroups || [])];
      if (propGroups[gi]?.props?.[pi]) {
        const props = [...propGroups[gi].props];
        props[pi] = { ...props[pi], coords: { x: pos.x, y: pos.y, z: pos.z }, heading: pos.heading };
        propGroups[gi] = { ...propGroups[gi], props };
        updateParams({ propGroups });
      }
    } else if (pos.field.startsWith('prop_')) {
      // Legacy flat prop: prop_{idx}
      const idx = parseInt(pos.field.split('_')[1], 10);
      const props = [...(editing.params?.props || [])];
      if (props[idx]) {
        props[idx] = { ...props[idx], coords: { x: pos.x, y: pos.y, z: pos.z }, heading: pos.heading };
        updateParams({ props });
      }
    } else if (pos.field.startsWith('target_')) {
      const idx = parseInt(pos.field.split('_')[1], 10);
      const targets = [...(editing.params?.targets || [])];
      if (targets[idx]) {
        targets[idx] = { ...targets[idx], coords: { x: pos.x, y: pos.y, z: pos.z, w: pos.heading } };
        updateParams({ targets });
      }
    }

    setCapturingField(null);
  });

  useNuiEvent('admin:placementCancelled', () => {
    useAdminStore.getState().setCapturingField(null);
  });

  useNuiEvent<PropAdjustResult>('admin:propAdjusted', (result) => {
    const { updateParams, setCapturingField } = useAdminStore.getState();
    updateParams({
      propOffset: result.propOffset,
      propRotation: result.propRotation,
    });
    setCapturingField(null);
  });

  useNuiEvent('admin:propAdjustCancelled', () => {
    useAdminStore.getState().setCapturingField(null);
  });

  // Visual banner removed — ox lib.showTextUI handles placement instructions
  return null;
}
