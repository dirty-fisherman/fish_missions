import { useMemo, useState } from 'react';
import { Badge, Box, Group, ScrollArea, Stack, Tabs, Text, TextInput } from '@mantine/core';
import { IconSearch } from './icons';
import { useMissionStore, type Mission } from '../stores/missionStore';

const statusBadge: Record<string, { label: string; color: string }> = {
  'in-progress': { label: 'in progress', color: 'blue' },
  complete: { label: 'complete', color: 'green' },
  turnin: { label: 'complete', color: 'green' },
  cooldown: { label: 'on cooldown', color: 'gray' },
  cancelled: { label: 'cancelled', color: 'red' },
};

type TabKey = 'available' | 'archived';

const ARCHIVED_STATUSES = new Set(['cooldown', 'archived', 'cancelled']);

export function MissionList() {
  const { discoveredMissions, selectedMission, getStatusById, selectMissionFromList } = useMissionStore();
  const [tab, setTab] = useState<TabKey>('available');
  const [filter, setFilter] = useState('');

  const buckets = useMemo(() => {
    const available: Mission[] = [];
    const archived: Mission[] = [];
    for (const m of discoveredMissions) {
      const s = getStatusById(m.id)?.status;
      if (ARCHIVED_STATUSES.has(s as string)) archived.push(m);
      else available.push(m);
    }
    return { available, archived };
  }, [discoveredMissions, getStatusById]);

  const filtered = useMemo(() => {
    const list = buckets[tab];
    if (!filter) return list;
    const lower = filter.toLowerCase();
    return list.filter((m) => m.label.toLowerCase().includes(lower));
  }, [buckets, tab, filter]);

  const renderItem = (m: Mission) => {
    const status = getStatusById(m.id);
    const isActive = selectedMission?.id === m.id;
    return (
      <Box
        key={m.id}
        onClick={() => selectMissionFromList(m)}
        style={{
          padding: '6px 10px',
          borderRadius: 4,
          cursor: 'pointer',
          background: isActive ? 'rgba(60, 60, 90, 0.5)' : 'transparent',
          borderBottom: '1px solid rgba(60, 60, 80, 0.25)',
          transition: 'background 120ms ease',
        }}
        onMouseEnter={(e) => { if (!isActive) (e.currentTarget as HTMLElement).style.background = 'rgba(60, 60, 90, 0.25)'; }}
        onMouseLeave={(e) => { if (!isActive) (e.currentTarget as HTMLElement).style.background = 'transparent'; }}
      >
        <Group justify="space-between" wrap="nowrap" gap={6}>
          <Box style={{ minWidth: 0, flex: 1 }}>
            <Text size="sm" fw={500} c="#e0e0e8" truncate>{m.label}</Text>
            {m.type === 'cleanup' && status?.progress && typeof status.progress.completed === 'number' && status.progress.total > 1 && (
              <Text size="xs" c="dimmed" mt={1}>{status.progress.completed} / {status.progress.total}</Text>
            )}
          </Box>
          {status?.status && statusBadge[status.status] && (
            <Badge variant="dot" color={statusBadge[status.status].color} size="xs" style={{ flexShrink: 0 }}>
              {statusBadge[status.status].label}
            </Badge>
          )}
        </Group>
      </Box>
    );
  };

  const tabCount = (key: TabKey) => {
    const n = buckets[key].length;
    return n > 0 ? ` (${n})` : '';
  };

  return (
    <Stack gap={8} style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
      <Tabs
        value={tab}
        onChange={(v) => { setTab((v as TabKey) || 'available'); setFilter(''); }}
        variant="default"
        styles={{
          root: { flexShrink: 0 },
          list: { borderBottomColor: 'rgba(60, 60, 80, 0.4)' },
          tab: { fontSize: 12, fontWeight: 600, padding: '8px 14px' },
        }}
      >
        <Tabs.List grow>
          <Tabs.Tab value="available">Available{tabCount('available')}</Tabs.Tab>
          <Tabs.Tab value="archived">Archived{tabCount('archived')}</Tabs.Tab>
        </Tabs.List>
      </Tabs>

      <TextInput
        placeholder="Filter missions…"
        size="sm"
        leftSection={<IconSearch />}
        value={filter}
        onChange={(e) => setFilter(e.currentTarget.value)}
        styles={{ input: { background: 'rgba(30, 30, 40, 0.6)', borderColor: 'rgba(60, 60, 80, 0.4)', color: '#e0e0e8' } }}
      />

      <ScrollArea style={{ flex: 1 }} scrollbarSize={3} offsetScrollbars>
        {filtered.length === 0 ? (
          <Text size="sm" c="dimmed" ta="center" py="md">
            {discoveredMissions.length === 0
              ? 'Accept missions to add them here.'
              : 'No missions match your filter.'}
          </Text>
        ) : (
          <Stack gap={2}>{filtered.map(renderItem)}</Stack>
        )}
      </ScrollArea>
    </Stack>
  );
}