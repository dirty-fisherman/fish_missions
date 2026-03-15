import { useState, useEffect } from 'react';
import { Badge, Button, Card, Group, ScrollArea, Stack, Text, Title } from '@mantine/core';
import { IconMapPin } from './icons';
import { fetchNui } from '../utils/fetchNui';
import { formatTimeRemaining, getMissionWaypoint } from '../utils/missionHelpers';
import { useMissionStore } from '../stores/missionStore';

const statusBadge: Record<string, { label: string; color: string }> = {
  complete: { label: 'complete', color: 'green' },
  turnin: { label: 'complete', color: 'green' },
  cooldown: { label: 'on cooldown', color: 'gray' },
};

interface MissionCardProps {
  onClose: () => void;
}

export function MissionCard({ onClose }: MissionCardProps) {
  const { offering, openedViaNpc, selectedMission, selectedNpc, getStatusById, addDiscoveredMission } = useMissionStore();
  const [, forceUpdate] = useState({});

  useEffect(() => {
    const id = setInterval(() => forceUpdate({}), 1000);
    return () => clearInterval(id);
  }, []);

  if (!selectedMission) {
    return (
      <Card
        bg="rgba(30, 30, 40, 0.8)"
        radius="md"
        p="md"
        withBorder
        style={{ borderColor: 'rgba(60, 60, 80, 0.5)', height: 240, flexShrink: 0 }}
      >
        <Stack align="center" justify="center" h="100%">
          <Text size="sm" c="dimmed">Select a mission to view details</Text>
        </Stack>
      </Card>
    );
  }

  const status = getStatusById(selectedMission.id);

  const handleAccept = () => {
    if (!selectedNpc || !selectedMission) return;
    void fetchNui('mission:accept', { npcId: selectedNpc.id, missionId: selectedMission.id });
    addDiscoveredMission(selectedMission);
    const wp = getMissionWaypoint(selectedMission);
    if (wp) void fetchNui('mission:waypoint', { x: wp.x, y: wp.y, z: wp.z });
    onClose();
  };

  const handleReject = () => {
    void fetchNui('mission:reject', { npcId: selectedNpc?.id });
    onClose();
  };

  const handleClaim = () => {
    void fetchNui('mission:claim', { missionId: selectedMission.id, npcId: selectedNpc?.id || '' });
    onClose();
  };

  const handleCancel = () => {
    void fetchNui('mission:cancel', { missionId: selectedMission.id });
    onClose();
  };

  const handleWaypoint = () => {
    void fetchNui('mission:waypoint', { missionId: selectedMission.id });
    onClose();
  };

  // Compute effective cooldown remaining dynamically
  const computeCooldownRemaining = () => {
    if (!status?.cooldownRemaining) return 0;
    let remaining = status.cooldownRemaining;
    if (status.cooldownTimestamp) {
      const elapsed = Math.floor((Date.now() - status.cooldownTimestamp) / 1000);
      remaining = Math.max(0, remaining - elapsed);
    }
    return remaining;
  };

  // Derive effective status — if cooldown has expired, treat as available
  const cooldownRemaining = computeCooldownRemaining();
  const effectiveStatus = (status?.status === 'cooldown' && cooldownRemaining <= 0) ? 'available' : status?.status;

  // Determine if we should show accept/reject based on effective status
  const isAtNpcForMission = openedViaNpc && selectedNpc?.missionId === selectedMission.id;
  const shouldOffer = offering || (isAtNpcForMission && (!effectiveStatus || effectiveStatus === 'available' || effectiveStatus === 'cancelled'));

  const renderActions = () => {
    if (effectiveStatus === 'cooldown' && cooldownRemaining > 0) {
      return (
        <Stack gap={4}>
          <Button variant="light" color="gray" disabled fullWidth size="xs">
            Come back in {formatTimeRemaining(cooldownRemaining)}
          </Button>
          <Button variant="light" color="blue" onClick={handleWaypoint} fullWidth size="xs" leftSection={<IconMapPin />}>
            Set Waypoint
          </Button>
        </Stack>
      );
    }

    if (shouldOffer) {
      return (
        <Group gap="xs" grow>
          <Button variant="filled" color="blue" onClick={handleAccept} size="xs">Accept</Button>
          <Button variant="subtle" color="gray" onClick={handleReject} size="xs">Reject</Button>
        </Group>
      );
    }

    if (effectiveStatus === 'complete' && isAtNpcForMission) {
      return <Button variant="filled" color="green" onClick={handleClaim} fullWidth size="xs">Claim Reward</Button>;
    }

    if (effectiveStatus === 'in-progress') {
      return (
        <Group gap="xs" grow>
          <Button variant="light" color="blue" onClick={handleWaypoint} size="xs" leftSection={<IconMapPin />}>
            Set Waypoint
          </Button>
          <Button variant="light" color="red" onClick={handleCancel} size="xs">
            Cancel
          </Button>
        </Group>
      );
    }

    if (effectiveStatus === 'complete') {
      return (
        <Button variant="light" color="green" onClick={handleWaypoint} fullWidth size="xs" leftSection={<IconMapPin />}>
          Collect Reward
        </Button>
      );
    }

    if (effectiveStatus === 'available' || effectiveStatus === 'cancelled') {
      return (
        <Button variant="light" color="blue" onClick={handleWaypoint} fullWidth size="xs" leftSection={<IconMapPin />}>
          Set Waypoint
        </Button>
      );
    }

    return null;
  };

  return (
    <Card
      bg="rgba(30, 30, 40, 0.8)"
      radius="md"
      p="sm"
      withBorder
      style={{ borderColor: 'rgba(60, 60, 80, 0.5)', height: 240, flexShrink: 0, display: 'flex', flexDirection: 'column' }}
    >
      {/* Header — fixed */}
      <Group justify="space-between" align="flex-start" mb={6} style={{ flexShrink: 0 }}>
        <Title order={6} fw={600} c="#e0e0e8" style={{ flex: 1 }} lineClamp={1}>{selectedMission.label}</Title>
        {effectiveStatus && statusBadge[effectiveStatus] && (
          <Badge variant="light" color={statusBadge[effectiveStatus].color} size="xs">
            {statusBadge[effectiveStatus].label}
          </Badge>
        )}
      </Group>

      {/* Scrollable description */}
      <ScrollArea style={{ flex: 1, minHeight: 0 }} scrollbarSize={3} offsetScrollbars>
        <Text size="xs" c="dimmed" lh={1.5}>{selectedMission.description}</Text>
      </ScrollArea>

      {/* Rewards + Actions — pinned at bottom */}
      <div style={{ flexShrink: 0, paddingTop: 6 }}>
        {selectedMission.reward && (
          <Card bg="rgba(15, 15, 20, 0.6)" radius="sm" p="xs" mb={6}>
            <Text size="xs" fw={600} c="dimmed" mb={2}>Rewards</Text>
            <Group gap={8}>
              {!!selectedMission.reward.cash && (
                <Text size="xs" c="#e0e0e8">${selectedMission.reward.cash.toLocaleString()}</Text>
              )}
              {selectedMission.reward.items?.map((it, i) => (
                <Text size="xs" c="#e0e0e8" key={i}>{it.count}x {it.name}</Text>
              ))}
            </Group>
          </Card>
        )}
        {renderActions()}
      </div>
    </Card>
  );
}