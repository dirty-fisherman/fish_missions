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
      if (mission.params?.area) {
        return {
          x: mission.params.area.x,
          y: mission.params.area.y,
          z: mission.params.area.z || 0
        };
      }
      break;
    case 'delivery':
      if (mission.params?.destination) {
        return {
          x: mission.params.destination.x,
          y: mission.params.destination.y,
          z: mission.params.destination.z || 0
        };
      }
      break;
    case 'assassination':
      if (mission.params?.area) {
        // Use defined area center as waypoint
        return {
          x: mission.params.area.x,
          y: mission.params.area.y,
          z: mission.params.area.z || 0
        };
      }
      break;
  }
  
  return null;
}