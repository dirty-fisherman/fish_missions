-- Server-side bootstrap: SQL install, load, initialize

-- ── Database bootstrap ──────────────────────────────────────────────────────

local function runInstallSql()
    local sql = LoadResourceFile(GetCurrentResourceName(), 'sql/install.sql')
    if not sql then return end
    sql = sql:gsub('%-%-[^\n]*', '')
    for statement in sql:gmatch('([^;]+)') do
        statement = statement:match('^%s*(.-)%s*$')
        if #statement > 0 then
            MySQL.query.await(statement)
        end
    end
end

function Server.loadMissionsFromDb()
    local rows = MySQL.query.await('SELECT * FROM `fish_missions` WHERE `enabled` = 1 ORDER BY `created_at` DESC')
    Server.missionsCache = {}
    Server.missionsList = {}
    for _, row in ipairs(rows or {}) do
        local enc = {
            id = row.id,
            label = row.label,
            description = row.description,
            type = row.type,
            cooldownSeconds = row.cooldown_seconds,
            npc = json.decode(row.npc),
            params = json.decode(row.params),
            messages = row.messages and json.decode(row.messages) or nil,
            reward = row.reward and json.decode(row.reward) or nil,
            levelRequired = row.level_required or 0,
            prerequisites = row.prerequisites and json.decode(row.prerequisites) or nil,
            enabled = row.enabled == 1 or row.enabled == true,
        }
        -- Extract headings into top-level mission fields so they
        -- survive FiveM's msgpack serialisation (which mangles subtables
        -- containing {x,y,z,w} keys).
        if enc.npc and enc.npc.coords then
            enc.npcHeading = enc.npc.coords.w or 0.0
        end
        if enc.params and enc.params.targets then
            enc.targetHeadings = {}
            for i, t in ipairs(enc.params.targets) do
                enc.targetHeadings[i] = (t.coords and t.coords.w) or 0.0
            end
        end
        -- Generate a runtime seed for cleanup missions (deterministic random
        -- prop selection). Rotates on server restart.
        if enc.type == 'cleanup' then
            enc.runtimeSeed = math.random(1, 2147483647)
        end
        Server.missionsCache[enc.id] = enc
        Server.missionsList[#Server.missionsList + 1] = enc
    end
end

-- ── Initialize ──────────────────────────────────────────────────────────────

CreateThread(function()
    runInstallSql()
    Server.loadMissionsFromDb()
    print(('[%s] Loaded %d missions from database'):format(ResourceName, #Server.missionsList))
end)
