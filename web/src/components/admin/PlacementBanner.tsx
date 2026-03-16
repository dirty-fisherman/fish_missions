import { Paper, Text } from '@mantine/core';
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
    } else if (pos.field.startsWith('prop_')) {
      const idx = parseInt(pos.field.split('_')[1], 10);
      const props = [...(editing.params?.props || [])];
      if (props[idx]) {
        props[idx] = { ...props[idx], coords: { x: pos.x, y: pos.y, z: pos.z } };
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

  if (!capturingField) return null;
  if (capturingField === 'propAdjust') return null;

  const bannerText = `Placing: ${capturingField} — [E] to confirm · [Scroll] to rotate · [Backspace] to cancel`;

  return (
    <Paper
      shadow="lg"
      p="sm"
      style={{
        position: 'fixed',
        top: 16,
        left: '50%',
        transform: 'translateX(-50%)',
        zIndex: 3000,
        background: 'rgba(30, 30, 40, 0.95)',
        border: '1px solid rgba(80, 120, 200, 0.6)',
        pointerEvents: 'none',
      }}
    >
      <Text size="sm" c="white" fw={600} ta="center">
        {bannerText}
      </Text>
    </Paper>
  );
}
