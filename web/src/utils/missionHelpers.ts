export function formatTimeRemaining(seconds: number): string {
  if (seconds <= 0) return '';
  
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);
  
  if (days > 0) {
    return `${days}d ${hours}h`;
  }
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  }
  return `${secs}s`;
}

export function getMissionWaypoint(mission: any): { x: number; y: number; z?: number } | null {
  if (!mission) return null;
  
  switch (mission.type) {
    case 'cleanup':
      if (mission.params?.props?.length) {
        const props = mission.params.props;
        let cx = 0, cy = 0, cz = 0;
        for (const p of props) {
          cx += p.coords.x ?? p.coords[1] ?? 0;
          cy += p.coords.y ?? p.coords[2] ?? 0;
          cz += p.coords.z ?? p.coords[3] ?? 0;
        }
        return { x: cx / props.length, y: cy / props.length, z: cz / props.length };
      }
      break;
    case 'delivery':
      if (mission.params?.destination) {
        const d = mission.params.destination;
        return {
          x: d.x ?? d[1] ?? 0,
          y: d.y ?? d[2] ?? 0,
          z: d.z ?? d[3] ?? 0,
        };
      }
      break;
    case 'assassination':
      if (mission.params?.targets?.length) {
        const targets = mission.params.targets;
        let cx = 0, cy = 0, cz = 0;
        for (const t of targets) {
          cx += t.coords.x ?? t.coords[1] ?? 0;
          cy += t.coords.y ?? t.coords[2] ?? 0;
          cz += t.coords.z ?? t.coords[3] ?? 0;
        }
        return { x: cx / targets.length, y: cy / targets.length, z: cz / targets.length };
      }
      break;
  }
  
  return null;
}