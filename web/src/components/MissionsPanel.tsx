import { ActionIcon, Paper, Title, Transition } from '@mantine/core';
import { IconX } from './icons';
import { MissionCard } from './MissionCard';
import { MissionList } from './MissionList';
import { useMissionStore } from '../stores/missionStore';

interface MissionsPanelProps {
  isVisible: boolean;
  onClose: () => void;
}

export function MissionsPanel({ isVisible, onClose }: MissionsPanelProps) {
  const sidebarPosition = useMissionStore((s) => s.sidebarPosition);
  const isLeft = sidebarPosition === 'left';

  return (
    <>
      <Transition
        mounted={isVisible}
        transition={isLeft ? 'slide-right' : 'slide-left'}
        duration={220}
        timingFunction="ease"
      >
        {(styles) => (
          <Paper
            shadow="xl"
            style={{
              ...styles,
              position: 'fixed',
              top: 0,
              [isLeft ? 'left' : 'right']: 0,
              height: '100vh',
              width: 380,
              zIndex: 1001,
              display: 'flex',
              flexDirection: 'column',
              gap: 12,
              padding: 12,
              pointerEvents: 'auto',
              background: 'rgba(22, 22, 30, 0.95)',
              borderRight: isLeft ? '1px solid rgba(60, 60, 80, 0.5)' : undefined,
              borderLeft: !isLeft ? '1px solid rgba(60, 60, 80, 0.5)' : undefined,
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <Title order={3} c="dimmed" fw={700}>Missions</Title>
              <ActionIcon variant="subtle" color="gray" onClick={onClose} size="sm">
                <IconX />
              </ActionIcon>
            </div>

            <MissionCard onClose={onClose} />
            <MissionList />
          </Paper>
        )}
      </Transition>
    </>
  );
}
