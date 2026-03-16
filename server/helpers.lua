-- Server-side state and core helpers (loaded first)

local Ox = require '@ox_core.lib.init'

-- Namespace for all cross-file server state and helpers
Server = {}

Server.active = {}              -- active[src] = { [missionId] = row }
Server.playerCharacters = {}    -- playerCharacters[src] = charId (number as string)
Server.missionsCache = {}       -- missionId -> mission data (loaded from DB)
Server.missionsList = {}        -- ordered array of missions (loaded from DB)

-- ── Helpers ─────────────────────────────────────────────────────────────────

function Server.getActivesFor(src)
    if not Server.active[src] then Server.active[src] = {} end
    return Server.active[src]
end

function Server.getCharacterId(src)
    if Server.playerCharacters[src] then return Server.playerCharacters[src] end
    local player = Ox.GetPlayer(src)
    if player and player.charId then return tostring(player.charId) end
    return nil
end

function Server.now()
    return math.floor(os.time())
end

function Server.findMission(id)
    return Server.missionsCache[id]
end
