import { useState, useEffect } from 'react';
import { Badge, Button, Card, Group, ScrollArea, Stack, Text, Title } from '@mantine/core';
import { IconMapPin } from './icons';
import { fetchNui } from '../utils/fetchNui';
import { formatTimeRemaining, getMissionWaypoint } from '../utils/missionHelpers';
import { useMissionStore } from '../stores/missionStore';
import { useStr } from '../utils/useStr';

const statusColors: Record<string, string> = {
  complete: 'green',
  turnin: 'green',
  cooldown: 'gray',
};

const statusStringKey: Record<string, string> = {
  complete: 'status_complete',
  turnin: 'status_complete',
  cooldown: 'status_cooldown',
};

interface MissionCardProps {
  onClose: () => void;
}

export function MissionCard({ onClose }: MissionCardProps) {
  const { offering, openedViaNpc, selectedMission, selectedNpc, getStatusById, addDiscoveredMission } = useMissionStore();
  const [, forceUpdate] = useState({});
  const emptyDetail = useStr('empty_detail');
  const btnAccept = useStr('btn_accept');
  const btnReject = useStr('btn_reject');
  const btnClaim = useStr('btn_claim');
  const btnCollect = useStr('btn_collect');
  const btnCancel = useStr('btn_cancel');
  const btnWaypoint = useStr('btn_waypoint');
  const rewardsLabel = useStr('rewards_label');
  const cooldownComeback = useStr('cooldown_comeback');
  const currencyPrefix = useStr('currency_prefix');
  const strStatusComplete = useStr('status_complete');
  const strStatusCooldown = useStr('status_cooldown');
  const statusLabels: Record<string, string> = {
    status_complete: strStatusComplete,
    status_cooldown: strStatusCooldown,
  };

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
          <Text size="sm" c="dimmed">{emptyDetail}</Text>
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
        <Group gap="xs" grow>
          <Button variant="light" color="gray" disabled size="xs">
            {cooldownComeback.replace('%s', formatTimeRemaining(cooldownRemaining))}
          </Button>
          <Button variant="light" color="blue" onClick={handleWaypoint} size="xs" leftSection={<IconMapPin />}>
            {btnWaypoint}
          </Button>
        </Group>
      );
    }

    if (shouldOffer) {
      return (
        <Group gap="xs" grow>
          <Button variant="filled" color="blue" onClick={handleAccept} size="xs">{btnAccept}</Button>
          <Button variant="subtle" color="gray" onClick={handleReject} size="xs">{btnReject}</Button>
        </Group>
      );
    }

    if (effectiveStatus === 'complete' && isAtNpcForMission) {
      return <Button variant="filled" color="green" onClick={handleClaim} fullWidth size="xs">{btnClaim}</Button>;
    }

    if (effectiveStatus === 'in-progress') {
      return (
        <Group gap="xs" grow>
          <Button variant="light" color="blue" onClick={handleWaypoint} size="xs" leftSection={<IconMapPin />}>
            {btnWaypoint}
          </Button>
          <Button variant="light" color="red" onClick={handleCancel} size="xs">
            {btnCancel}
          </Button>
        </Group>
      );
    }

    if (effectiveStatus === 'complete') {
      return (
        <Button variant="light" color="green" onClick={handleWaypoint} fullWidth size="xs" leftSection={<IconMapPin />}>
          {btnCollect}
        </Button>
      );
    }

    if (effectiveStatus === 'available' || effectiveStatus === 'cancelled') {
      return (
        <Button variant="light" color="blue" onClick={handleWaypoint} fullWidth size="xs" leftSection={<IconMapPin />}>
          {btnWaypoint}
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
        {effectiveStatus && statusColors[effectiveStatus] && (
          <Badge variant="light" color={statusColors[effectiveStatus]} size="xs">
            {statusLabels[statusStringKey[effectiveStatus]] ?? effectiveStatus}
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
            <Text size="xs" fw={600} c="dimmed" mb={2}>{rewardsLabel}</Text>
            <Group gap={8}>
              {!!selectedMission.reward.cash && (
                <Text size="xs" c="#e0e0e8">{currencyPrefix}{selectedMission.reward.cash.toLocaleString()}</Text>
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