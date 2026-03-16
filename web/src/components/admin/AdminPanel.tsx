import { useCallback, useEffect, useState } from 'react';
import {
  ActionIcon,
  Badge,
  Box,
  Button,
  Group,
  Pagination,
  Paper,
  ScrollArea,
  Stack,
  Text,
  TextInput,
  Title,
} from '@mantine/core';
import { IconX, IconSearch } from '../icons';
import { fetchNui } from '../../utils/fetchNui';
import { useAdminStore, type MissionDefinition } from '../../stores/adminStore';
import { useNuiEvent } from '../../hooks/useNuiEvent';
import { MissionEditor } from './MissionEditor';
import { PlacementBanner } from './PlacementBanner';

const TYPE_COLORS: Record<string, string> = {
  cleanup: 'green',
  delivery: 'blue',
  assassination: 'red',
};

export function AdminPanel() {
  const {
    missions,
    total,
    page,
    pageSize,
    search,
    selectedId,
    editing,
    capturingField,
    setMissions,
    setPage,
    setSearch,
    setSelectedId,
    setEditing,
    newMission,
    reset,
  } = useAdminStore();

  const totalPages = Math.max(1, Math.ceil(total / pageSize));

  const fetchMissions = useCallback(async () => {
    const result = await fetchNui<{ missions: MissionDefinition[]; total: number }>(
      'admin:getMissions',
      { page, pageSize, search },
    );
    if (result) {
      setMissions(result.missions || [], result.total || 0);
    }
  }, [page, pageSize, search, setMissions]);

  useEffect(() => {
    void fetchMissions();
  }, [fetchMissions]);

  // Listen for position capture events
  useNuiEvent('admin:positionCaptured', () => {
    // Handled by PlacementBanner / MissionEditor
  });

  useNuiEvent('admin:placementCancelled', () => {
    useAdminStore.getState().setCapturingField(null);
  });

  // Hide admin panel UI during gizmo prop adjustment (keeps PlacementBanner mounted)
  const [gizmoActive, setGizmoActive] = useState(false);
  useNuiEvent<{ active: boolean }>('admin:gizmoMode', (data) => setGizmoActive(data.active));

  const handleClose = () => {
    void fetchNui('admin:close', {});
    reset();
  };

  const handleSelect = (mission: MissionDefinition) => {
    setSelectedId(mission.id || null);
    setEditing(JSON.parse(JSON.stringify(mission)));
  };

  const handleNew = () => {
    newMission();
  };

  const handleSaved = () => {
    void fetchMissions();
  };

  const handleDeleted = () => {
    setSelectedId(null);
    setEditing(null);
    void fetchMissions();
  };

  const isPlacing = !!capturingField;

  return (
    <div className={`admin-root`}>
      {isPlacing && <PlacementBanner />}
      <div className={`admin-tablet${isPlacing ? ' placing' : ''}`} style={gizmoActive ? { display: 'none' } : { position: 'relative' }}>
        {/* Close button - top-right of tablet */}
        {!isPlacing && (
          <ActionIcon
            variant="subtle"
            color="gray"
            onClick={handleClose}
            size="sm"
            style={{ position: 'absolute', top: 8, right: 8, zIndex: 10 }}
          >
            <IconX />
          </ActionIcon>
        )}
        {/* Left panel: mission list */}
        <Paper
          shadow="xl"
          style={{
            width: 340,
            height: '100%',
            display: isPlacing ? 'none' : 'flex',
            flexDirection: 'column',
            background: 'rgba(22, 22, 30, 0.97)',
            borderRight: '1px solid rgba(60, 60, 80, 0.5)',
          }}
          p="md"
        >
        <Group justify="space-between" mb="sm">
          <Title order={4} c="dimmed" fw={700}>Mission Admin</Title>
        </Group>

        <TextInput
          placeholder="Search missions..."
          leftSection={<IconSearch />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          mb="sm"
          size="xs"
        />

        <ScrollArea style={{ flex: 1 }} offsetScrollbars>
          <Stack gap={2}>
            {missions.length === 0 && (
              <Text size="sm" c="dimmed" ta="center" py="lg">
                No missions found
              </Text>
            )}
            {missions.map((m) => (
              <Box
                key={m.id}
                onClick={() => handleSelect(m)}
                style={{
                  padding: '8px 10px',
                  borderRadius: 4,
                  cursor: 'pointer',
                  background: selectedId === m.id ? 'rgba(60, 60, 90, 0.5)' : 'transparent',
                  borderBottom: '1px solid rgba(60, 60, 80, 0.25)',
                  transition: 'background 120ms ease',
                }}
                onMouseEnter={(e) => {
                  if (selectedId !== m.id) (e.currentTarget as HTMLElement).style.background = 'rgba(60, 60, 90, 0.25)';
                }}
                onMouseLeave={(e) => {
                  if (selectedId !== m.id) (e.currentTarget as HTMLElement).style.background = 'transparent';
                }}
              >
                <Group justify="space-between" wrap="nowrap" gap={6}>
                  <Box style={{ minWidth: 0, flex: 1 }}>
                    <Text size="sm" fw={500} truncate>{m.label || m.id || '(untitled)'}</Text>
                    <Text size="xs" c="dimmed" truncate>{m.id}</Text>
                  </Box>
                  <Group gap={4} wrap="nowrap">
                    <Badge size="xs" color={TYPE_COLORS[m.type] || 'gray'} variant="light">
                      {m.type}
                    </Badge>
                    {!m.enabled && (
                      <Badge size="xs" color="red" variant="outline">off</Badge>
                    )}
                  </Group>
                </Group>
              </Box>
            ))}
          </Stack>
        </ScrollArea>

        <Button size="xs" variant="light" fullWidth mt="sm" onClick={handleNew}>
          + New Mission
        </Button>

        {totalPages > 1 && (
          <Group justify="center" mt="sm">
            <Pagination
              size="xs"
              total={totalPages}
              value={page}
              onChange={setPage}
            />
          </Group>
        )}
      </Paper>

      {/* Right panel: editor */}
      <Box style={{ flex: 1, height: '100%', overflow: 'hidden', background: 'rgba(16, 16, 20, 0.95)', display: isPlacing ? 'none' : 'flex', flexDirection: 'column' }} p="md">
        {editing ? (
          <MissionEditor onSaved={handleSaved} onDeleted={handleDeleted} />
        ) : (
          <Stack align="center" justify="center" h="100%">
            <Text size="lg" c="dimmed">Select a mission or create a new one</Text>
          </Stack>
        )}
      </Box>
      </div>
    </div>
  );
}
