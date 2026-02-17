import { type MutableRefObject, useEffect, useRef } from 'react';
import { noop } from '../utils/misc';

interface NuiMessageData<T = unknown> {
  action: string;
  data: T;
}

type NuiHandlerSignature<T> = (data: T) => void;

/**
 * A hook that manage events listeners for receiving data from the client scripts
 * @param action The specific `action` that should be listened for.
 * @param handler The callback function that will handle data relayed by this hook
 *
 * @example
 * useNuiEvent<{visibility: true, wasVisible: 'something'}>('setVisible', (data) => {
 *   // whatever logic you want
 * })
 *
 **/

export const useNuiEvent = <T = unknown>(action: string, handler: (data: T) => void) => {
  const savedHandler: MutableRefObject<NuiHandlerSignature<T>> = useRef(noop);

  // Make sure we handle for a reactive handler
  useEffect(() => {
    savedHandler.current = handler;
  }, [handler]);

  useEffect(() => {
    const eventListener = (event: MessageEvent<NuiMessageData<T> | string>) => {
      try {
        // eslint-disable-next-line no-console
        console.log('[nui] message raw:', event.data);
      } catch {}
      let payload: NuiMessageData<T> | null = null;
      if (typeof event.data === 'string') {
        try { payload = JSON.parse(event.data) as NuiMessageData<T>; } catch { payload = null; }
      } else {
        payload = event.data as NuiMessageData<T>;
      }
      try {
        // eslint-disable-next-line no-console
        console.log('[nui] message parsed:', payload);
      } catch {}
      if (!payload) return;
      const { action: eventAction, data } = payload;

      if (savedHandler.current) {
        if (eventAction === action) {
          savedHandler.current(data);
        }
      }
    };

    window.addEventListener('message', eventListener);
    // Remove Event Listener on component cleanup
    return () => window.removeEventListener('message', eventListener);
  }, [action]);
};
