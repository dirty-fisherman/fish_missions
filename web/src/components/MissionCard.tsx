import { useState, useEffect } from 'react';
import { fetchNui } from '../utils/fetchNui';
import { formatTimeRemaining, getMissionWaypoint } from '../utils/missionHelpers';
import { useMissionStore } from '../stores/missionStore';

interface MissionCardProps {
  onClose: () => void;
}

export function MissionCard({ onClose }: MissionCardProps) {
  const {
    offering,
    openedViaNpc,
    selectedMission,
    selectedNpc,
    getStatusById,
    addDiscoveredMission,
  } = useMissionStore();

  const [, forceUpdate] = useState({});

  // Update every second for dynamic cooldown
  useEffect(() => {
    const interval = setInterval(() => {
      forceUpdate({});
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  if (!selectedMission) {
    return (
      <div className='selected-card'>
        <div style={{ opacity: 0.65, fontSize: 13 }}>No mission selected</div>
      </div>
    );
  }

  const status = getStatusById(selectedMission.id);

  const handleAccept = () => {
    if (!selectedNpc || !selectedMission) return;
    void fetchNui('encounter:accept', { npcId: selectedNpc.id, encounterId: selectedMission.id });
    
    // Mark as discovered
    addDiscoveredMission(selectedMission);
    
    // Set waypoint to mission location
    const waypoint = getMissionWaypoint(selectedMission);
    if (waypoint) {
      void fetchNui('mission:waypoint', { x: waypoint.x, y: waypoint.y, z: waypoint.z });
    }
    
    onClose();
  };

  const handleReject = () => {
    void fetchNui('encounter:reject', { npcId: selectedNpc?.id });
    onClose();
  };

  const handleClaim = () => {
    void fetchNui('encounter:claim', { 
      encounterId: selectedMission.id,
      npcId: selectedNpc?.id || '' 
    });
    onClose();
  };

  const handleCancel = () => {
    void fetchNui('encounter:cancel', { encounterId: selectedMission.id });
    onClose();
  };

  const handleWaypoint = () => {
    void fetchNui('encounter:waypoint', { encounterId: selectedMission.id });
    onClose();
  };

  const renderActions = () => {
    const isOnCooldown = status?.status === 'cooldown' || (status?.cooldownRemaining && status.cooldownRemaining > 0);
    
    // Show cooldown message for any mission on cooldown (whether offering or not)
    if (isOnCooldown) {
      // Calculate dynamic remaining time
      let remainingSeconds = status?.cooldownRemaining || 0;
      
      if (status?.cooldownTimestamp) {
        const elapsedSinceReceived = Math.floor((Date.now() - status.cooldownTimestamp) / 1000);
        remainingSeconds = Math.max(0, remainingSeconds - elapsedSinceReceived);
      }
      
      return (
        <button 
          type='button' 
          disabled 
          style={{ opacity: 0.6, cursor: 'not-allowed' }}
        >
          Come back in {formatTimeRemaining(remainingSeconds)}
        </button>
      );
    }

    // Show Accept/Reject only when we are looking at an NPC offer
    if (offering) {
      return (
        <>
          <button 
            type='button' 
            onClick={handleAccept} 
            style={{ 
              background: 'linear-gradient(135deg, #4CAF50, #45a049)', 
              border: 'none',
              color: 'white'
            }}
          >
            Accept Mission
          </button>
          <button type='button' className='ghost' onClick={handleReject}>
            Reject
          </button>
        </>
      );
    }
    
    // Claim reward when mission is complete, opened via NPC, and NPC matches mission
    const isComplete = status?.status === 'complete';
    const isCorrectNpc = openedViaNpc && selectedNpc?.encounterId === selectedMission.id;
    
    if (isComplete && isCorrectNpc) {
      return (
        <button
          type='button'
          onClick={handleClaim}
          style={{ 
            background: 'linear-gradient(135deg, #4CAF50, #45a049)', 
            border: 'none',
            color: 'white'
          }}
        >
          Claim Reward
        </button>
      );
    }

    // Allow cancel only when mission is in progress
    if (status?.status === 'in-progress') {
      return (
        <button
          type='button'
          className='ghost'
          onClick={handleCancel}
          title={`Cancel ${selectedMission.label}`}
        >
          Cancel Mission
        </button>
      );
    }

    // Waypoint CTA for available, complete, or cooldown states
    if (status?.status === 'available' || status?.status === 'complete' || status?.status === 'cooldown') {
      return (
        <button
          type='button'
          onClick={handleWaypoint}
          title="Set waypoint to NPC location"
        >
          <svg xmlns="http://www.w3.org/2000/svg" enableBackground="new 0 0 24 24" height="24px" viewBox="0 0 24 24" width="24px" fill="#e3e3e3">
            <g><rect fill="none" height="24" width="24"/></g>
            <g><path d="M12,2c-4.2,0-8,3.22-8,8.2c0,3.18,2.45,6.92,7.34,11.23c0.38,0.33,0.95,0.33,1.33,0C17.55,17.12,20,13.38,20,10.2 C20,5.22,16.2,2,12,2z M12,12c-1.1,0-2-0.9-2-2c0-1.1,0.9-2,2-2c1.1,0,2,0.9,2,2C14,11.1,13.1,12,12,12z"/></g>
          </svg>
        </button>
      );
    }

    return null;
  };

  return (
    <div className='selected-card'>
      <div className='selected-header'>
        <h3 className='selected-title'>{selectedMission.label}</h3>
        {status?.status && (
          <span className={`badge ${status.status}`}>
            {status.status}
          </span>
        )}
      </div>
      
      <p className='selected-description'>{selectedMission.description}</p>
      
      {selectedMission?.reward && (
        <div className='selected-rewards'>
          <h4>Rewards</h4>
          <ul>
            {selectedMission.reward.cash && <li>${selectedMission.reward.cash}</li>}
            {selectedMission.reward.items?.map((it: any, i: number) => (
              <li key={i}>{it.count}x {it.name}</li>
            ))}
          </ul>
        </div>
      )}
      
      <div className='selected-actions'>
        {renderActions()}
      </div>
    </div>
  );
}