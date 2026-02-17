export type NotifyPayload = {
  title?: string;
  description?: string;
  type?: 'inform' | 'success' | 'error' | 'warning';
  duration?: number;
};

export function notify(payload: NotifyPayload) {
  try {
    (globalThis as any).exports?.ox_lib?.notify?.(payload);
  } catch {}
}
