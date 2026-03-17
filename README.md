# fish_missions

![FiveM_b3751_GTAProcess_zEtjDPlZjr](https://github.com/user-attachments/assets/731fe40b-e5ae-4b80-a962-d93c5955e2f7)

A mission system for FiveM servers running **ox_core**. Players discover missions by interacting with NPCs in the world, complete objectives (delivery, cleanup, assassination), and claim rewards. Includes a built-in admin tool for creating and editing missions entirely in-game.

## Dependencies

- [ox_core](https://github.com/overextended/ox_core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)

## Installation

1. Place `fish_missions` in your resources folder.
2. Add `ensure fish_missions` to your server.cfg (after ox_core, ox_lib, ox_target, oxmysql).
3. The required database tables are created automatically on first start.

Make sure to hook into the correct character login/logout events for your server:

In **`shared/config.lua`**:

```
characterSelectedEvent = 'ox:setActiveCharacter',
characterDeselectedEvent = 'ox:playerLogout',
```

## Mission Types

### Delivery

Carry a prop to a destination within a time limit. The player carries a visible prop with an animation (box carry or bag carry). Configurable carry style, prop model, prop offset/rotation, and time limit.

### Cleanup

Collect scattered props in a zone. Props are organized into **prop groups** — each group has its own label, set of placed props, and optional **random selection** (e.g. spawn 5 of 12 placed props per run, deterministic across all clients via seeded PRNG). Each prop stores position and rotation, and props snap to the ground on spawn. Players pick up props via ox_target interaction.

### Assassination

Eliminate target NPCs. Targets spawn in a zone when the player enters, configured with model, position, heading, optional weapon, and idle scenario. Supports aggressive mode (targets attack the player) and optional target blips. Networked ped spawning with server-side coordination prevents duplicate spawns.

## Admin Tool

Open with `/missionadmin` (requires configurable permission). All mission creation and editing happens in-game through a React-based NUI panel.

### Features

- **Create / Edit / Delete** missions with paginated list and search
- **In-world placement tool** — position NPCs, props, and targets by pointing at the ground. Scroll wheel rotates in 15° increments. Other placed entities are shown as context during placement for spatial reference.
- **Prop groups** — organize cleanup props into named groups with optional random selection
- **Prop rotation** — scroll wheel heading is saved per prop and applied at spawn
- **Assassination targets** — place multiple targets with weapon and scenario configuration
- **Delivery setup** — place destination, configure carry style, and fine-tune prop offset/rotation in-world
- **NPC configuration** — model, position, idle scenario, blip, target label/icon, and ambient speech (greet, claim, bye)
- **Rewards** — cash amount and item list with count and optional JSON metadata per item
- **Prerequisites** — require completion of other missions before a mission becomes available
- **Level requirement** — gate missions behind an XP level
- **Enable/disable** missions without deleting them
- **Cancel active instances** across all players from the admin panel

## Progression

- **XP tracking** — players earn XP for completing missions, stored per-character in the database
- **Daily completion limit** — configurable cap on missions completed per character per day (resets at midnight)
- **Mission prerequisites** — missions can require prior missions to be completed first
- **Cooldowns** — configurable cooldown per mission, with optional cooldown on cancel

## Persistence

Active missions survive server restarts and player reconnects. On character load, the server restores in-progress missions to the client. Delivery missions (which are time-limited) are automatically cancelled on restore rather than resumed.

Mission progress (e.g. cleanup collected count) is stored in the database and synced in real-time.

## Mission Tracker

Players toggle the mission tracker panel with a configurable keybind (default F6). The tracker shows discovered missions with their current status: available, active, ready to turn in, on cooldown, or cancelled. Missions only appear in the tracker after the player has interacted with them at least once.

## Commands & Keybinds

| Command | Default Key | Description |
|---------|-------------|-------------|
| `/missions` | F6 | Toggle the missions tracker panel |
| `/missionadmin` | — | Open the admin mission editor (requires permission) |

Commands, keybind, and the required admin permission are all configurable in `shared/config.lua`.

## Configuration

All settings live in `shared/config.lua`:

```lua
Config = {
    EnableNuiCommand = false,        -- Dev: allow /nui to toggle the panel
    npcBlips = true,                 -- Show blips for mission NPCs
    npcBlipSprite = 280,             -- Blip sprite ID
    npcBlipColor = 29,               -- Blip color ID
    npcBlipScale = 0.7,              -- Blip scale
    maxNpcBlips = 10,                -- Max NPC blips on the map
    dailyMissionLimit = 20,          -- Max completions per character per day
    sidebarPosition = 'left',        -- NUI panel position: 'left' or 'right'
    adminPermission = 'command.missionadmin',

    commands = {
        missions = 'missions',       -- Player command name
        missionadmin = 'missionadmin', -- Admin command name
    },
    keybind = 'F6',
    keybindDescription = 'Toggle Missions Tracker',

    strings = { ... },               -- All player-facing strings (override to localize)
}
```

### Localization

Every player-facing string (notifications, HUD text, NUI labels, button text) is defined in `Config.strings`. Override any value to translate or rebrand.

## Building the NUI

The NUI is a React app built with Vite. You only need to rebuild if you modify files under `web/`.

```bash
pnpm install
pnpm build        # Production build → dist/web/
pnpm web:dev      # Dev server with hot reload
```

Requires Node.js 18+ and pnpm.

## Project Structure

```
fish_missions/
├── shared/           # Config and shared helpers
├── client/
│   ├── helpers.lua   # Client namespace (Client = {})
│   ├── lifecycle.lua # State management, commands, keybinds
│   ├── npc.lua       # NPC spawning, ox_target, blips
│   ├── nui.lua       # NUI callbacks and server event handlers
│   ├── admin/        # Admin tool (placement, prop adjustment)
│   └── missions/     # Mission type handlers (cleanup, delivery, assassination)
├── server/
│   ├── helpers.lua   # Server namespace (Server = {})
│   ├── db.lua        # Database queries
│   ├── rewards.lua   # XP, daily tracking, reward granting
│   ├── tracker.lua   # Mission tracker state builder
│   ├── missions.lua  # Accept/complete/claim/cancel handlers
│   ├── lifecycle.lua # Character lifecycle, hydration, and mission restore
│   ├── admin.lua     # Admin CRUD operations
│   └── init.lua      # SQL setup and mission loading
├── web/              # React NUI (Vite + Mantine v8)
├── dist/web/         # Built NUI output
└── fxmanifest.lua
```

## Releases

Tag a commit (e.g. `v1.0.0`) and push — GitHub Actions will build the NUI and create a release zip automatically.

## License

MIT
