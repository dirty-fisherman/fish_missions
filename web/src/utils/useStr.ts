import { useMissionStore } from '../stores/missionStore';

const DEFAULTS: Record<string, string> = {
  panel_title: 'Missions',
  tab_available: 'Available',
  tab_archived: 'Archived',
  filter_placeholder: 'Filter missions\u2026',
  empty_available: 'Accept missions to add them here.',
  empty_filter: 'No missions match your filter.',
  empty_detail: 'Select a mission to view details',
  status_active: 'in progress',
  status_complete: 'complete',
  status_cooldown: 'on cooldown',
  status_cancelled: 'cancelled',
  btn_accept: 'Accept',
  btn_reject: 'Reject',
  btn_claim: 'Claim Reward',
  btn_collect: 'Collect Reward',
  btn_cancel: 'Cancel',
  btn_waypoint: 'Set Waypoint',
  btn_admin: 'Mission Admin',
  rewards_label: 'Rewards',
  cooldown_comeback: 'Come back in %s',
  currency_prefix: '$',
};

/** Return a localized string by key, falling back to English default. */
export function useStr(key: string): string {
  const str = useMissionStore((s) => s.strings[key]);
  return str ?? DEFAULTS[key] ?? key;
}

/** Non-hook version for use outside components. */
export function getStr(key: string): string {
  const str = useMissionStore.getState().strings[key];
  return str ?? DEFAULTS[key] ?? key;
}
