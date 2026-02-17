import { useEffect } from 'react';

export function useKeyboardHandlers(panelVisible: boolean, onClose: () => void) {
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && panelVisible) {
        onClose();
      }
      // Handle F6 to close when NUI has focus
      if (event.key === 'F6' && panelVisible) {
        console.log('[missions] F6 pressed in NUI, closing panel');
        event.preventDefault();
        onClose();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [panelVisible, onClose]);
}