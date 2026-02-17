import { MissionCard } from './MissionCard';
import { MissionList } from './MissionList';

interface SidebarProps {
  isVisible: boolean;
  onClose: () => void;
}

export function Sidebar({ isVisible, onClose }: SidebarProps) {

  return (
    <>
      {/* Backdrop to close on outside click */}
      <div
        className={`backdrop ${isVisible ? 'open' : ''}`}
        onClick={onClose}
      />

      {/* Always render sidebar for smooth animation; use .open to toggle */}
      <div className={`sidebar ${isVisible ? 'open' : ''}`} style={{ pointerEvents: 'auto' }}>
        <div className='sidebar-header'>
          <div style={{ fontWeight: 700 }}></div>
          <button type='button' className='ghost' onClick={onClose}>
            ✕
          </button>
        </div>

        {/* Selected mission section */}
        <MissionCard onClose={onClose} />

        {/* Discovered missions list */}
        <MissionList />
      </div>
    </>
  );
}