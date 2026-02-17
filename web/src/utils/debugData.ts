import { isEnvBrowser } from './misc';

interface DebugEvent<T = unknown> {
  action: string;
  data: T;
}

/**
 * Emulates dispatching an event using SendNuiMessage.
 * This is used when developing in browser.
 *
 * @param events - The event you want to cover
 * @param timer - How long until it should trigger (ms)
 */
export const debugData = <P>(events: DebugEvent<P>[], timer = 1000): void => {
  if (process.env.NODE_ENV === 'development' && isEnvBrowser()) {
    for (const event of events) {
      setTimeout(() => {
        window.dispatchEvent(
          new MessageEvent('message', {
            data: {
              action: event.action,
              data: event.data,
            },
          }),
        );
      }, timer);
    }
  }
};

// Sample mission data based on actual config for browser development
const sampleMissions = [
  {
    id: "cleanup_beach",
    label: "Beach Cleanup",
    description: "Help clean up trash along the beach and keep our shores pristine.",
    type: "cleanup",
    reward: { cash: 2500, items: [{ name: "water", count: 2 }] }
  },
  {
    id: "delivery_quickdrop", 
    label: "Express Delivery",
    description: "Deliver this package across town before the timer runs out.",
    type: "delivery",
    reward: { cash: 1500, items: [] }
  },
  {
    id: "assassination_parksuspect",
    label: "Deal with the Threat", 
    description: "A hostile target has been spotted. Neutralize them.",
    type: "assassination",
    reward: { cash: 3000, items: [] }
  },
  {
    id: "cleanup_downtown",
    label: "Downtown Cleanup",
    description: "The city center needs attention. Clear the debris and litter.",
    type: "cleanup", 
    reward: { cash: 1800, items: [{ name: "sandwich", count: 1 }] }
  },
  {
    id: "delivery_medical",
    label: "Medical Supply Run",
    description: "Rush medical supplies to the hospital. Lives depend on it.",
    type: "delivery",
    reward: { cash: 2200, items: [{ name: "first_aid", count: 1 }] }
  }
];

const sampleNpcs = [
  {
    id: "beach_keeper",
    target: { label: "Beach Cleanup Worker", icon: "fa-solid fa-recycle" }
  },
  {
    id: "courier_bob", 
    target: { label: "Express Courier", icon: "fa-solid fa-box" }
  },
  {
    id: "fixer_joe",
    target: { label: "Underground Contact", icon: "fa-solid fa-skull" }
  }
];

// Enhanced debug data with realistic mission scenarios
export const debugMissionData = () => {
  if (!isEnvBrowser()) return;

  // Simulate showing the panel with tracker data
  debugData([
    {
      action: 'tracker:toggle',
      data: { visible: true }
    }
  ], 500);

  // Simulate tracker data with various mission states
  debugData([
    {
      action: 'tracker:data', 
      data: {
        statuses: [
          {
            id: "cleanup_beach",
            label: "Beach Cleanup",
            type: "cleanup", 
            status: "in-progress",
            reward: { cash: 2500, items: [{ name: "water", count: 2 }] },
            progress: { type: "cleanup", completed: 3, total: 10 }
          },
          {
            id: "delivery_quickdrop",
            label: "Express Delivery",
            type: "delivery",
            status: "complete", 
            reward: { cash: 1500, items: [] },
            progress: null
          },
          {
            id: "assassination_parksuspect",
            label: "Deal with the Threat",
            type: "assassination",
            status: "complete",
            reward: { cash: 3000, items: [] },
            cooldownRemaining: 125
          },
          {
            id: "cleanup_downtown", 
            label: "Downtown Cleanup",
            type: "cleanup",
            status: "available",
            reward: { cash: 1800, items: [{ name: "sandwich", count: 1 }] }
          },
          {
            id: "delivery_medical",
            label: "Medical Supply Run", 
            type: "delivery",
            status: "available",
            reward: { cash: 2200, items: [{ name: "first_aid", count: 1 }] }
          }
        ]
      }
    }
  ], 1000);

  // Simulate an NPC encounter after 3 seconds
  setTimeout(() => {
    debugData([
      {
        action: 'encounter:show',
        data: {
          npc: sampleNpcs[1], // courier_bob
          encounter: sampleMissions[1] // delivery_quickdrop
        }
      }
    ], 100);
  }, 3000);
};
