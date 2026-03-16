# fish_missions

A mission system for FiveM servers running **ox_core**. Players discover missions by interacting with NPCs in the world, complete objectives (delivery, cleanup, assassination), and claim rewards. Includes a built-in admin tool for creating and editing missions in-game.

## Dependencies

- [ox_core](https://github.com/overextended/ox_core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)
- FiveM server build 13068+ with OneSync

## Installation

1. Place `fish_missions` in your resources folder.
2. Add `ensure fish_missions` to your server.cfg (after ox_core, ox_lib, ox_target, oxmysql).
3. The required database tables are created automatically on first start.

## Mission Types

| Type | Description |
|------|-------------|
| **Delivery** | Carry a prop to a destination within a time limit. |
| **Cleanup** | Collect scattered props in a zone. |
| **Assassination** | Eliminate a target NPC. |

Missions are created entirely in-game using the admin tool — no config files needed.

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
│   ├── lifecycle.lua # Character lifecycle and hydration
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
