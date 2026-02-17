import { useRef, useState, useEffect } from 'react';
import { useMissionStore } from '../stores/missionStore';

interface MissionListProps {
  ITEM_HEIGHT?: number;
  OVERSCAN?: number;
}

export function MissionList({ ITEM_HEIGHT = 62, OVERSCAN = 6 }: MissionListProps) {
  const { discoveredMissions, selectedMission, getStatusById, selectMissionFromList } = useMissionStore();

  const listRef = useRef<HTMLDivElement | null>(null);
  const [scrollTop, setScrollTop] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(0);

  // Manage discovered list scroll + viewport for virtualization
  useEffect(() => {
    const el = listRef.current;
    if (!el) return;
    const update = () => {
      setViewportHeight(el.clientHeight || 0);
    };
    update();
    let ro: ResizeObserver | null = null;
    try {
      ro = new ResizeObserver(update);
      ro.observe(el);
    } catch {}
    return () => { try { ro?.disconnect(); } catch {} };
  }, [listRef.current]);

  useEffect(() => {
    const el = listRef.current;
    if (!el) return;
    let raf = 0;
    const onScroll = () => {
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        setScrollTop(el.scrollTop || 0);
      });
    };
    el.addEventListener('scroll', onScroll, { passive: true });
    return () => { el.removeEventListener('scroll', onScroll as any); if (raf) cancelAnimationFrame(raf); };
  }, [listRef.current]);

  if (discoveredMissions.length === 0) {
    return (
      <div className='list-section'>
        <div className='list-header'>Discovered</div>
        <div style={{ opacity: 0.6, fontSize: 12 }}>Accept missions to add them here.</div>
      </div>
    );
  }

  // Virtualized rendering
  const total = discoveredMissions.length;
  const totalHeight = total * ITEM_HEIGHT;
  const startIdx = Math.max(0, Math.floor(scrollTop / ITEM_HEIGHT) - OVERSCAN);
  const endIdx = Math.min(
    total,
    Math.ceil((scrollTop + viewportHeight) / ITEM_HEIGHT) + OVERSCAN
  );
  const visible = discoveredMissions.slice(startIdx, endIdx);
  const offsetY = startIdx * ITEM_HEIGHT;

  return (
    <div className='list-section' ref={listRef}>
      <div className='list-header'>Discovered</div>
      <div style={{ position: 'relative', height: totalHeight }}>
        <ul className='missions-list' style={{ position: 'absolute', top: offsetY, left: 0, right: 0 }}>
          {visible.map((m) => {
            const status = getStatusById(m.id);
            return (
              <li
                key={m.id}
                className={`list-item ${selectedMission?.id === m.id ? 'active' : ''}`}
                onClick={() => selectMissionFromList(m)}
                style={{ height: 56 }}
              >
                <div>
                  <div className='item-title'>{m.label}</div>
                  {m.type === 'cleanup' && status?.progress && typeof status.progress.completed === 'number' && (
                    <div className='item-sub'>Progress: {status.progress.completed} / {status.progress.total}</div>
                  )}
                </div>
                {status?.status && <span className={`badge ${status.status}`}>{status.status}</span>}
              </li>
            );
          })}
        </ul>
      </div>
    </div>
  );
}