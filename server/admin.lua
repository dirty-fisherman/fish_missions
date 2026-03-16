-- Server-side admin CRUD operations

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function isAdmin(src)
    return IsPlayerAceAllowed(tostring(src), Config.adminPermission or 'command.missionadmin')
end

local function slugify(str)
    return str:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
end

local function generateMissionId(label)
    local base = slugify(label)
    if base == '' then base = 'mission' end
    if not Server.missionsCache[base] then return base end
    for i = 2, 9999 do
        local candidate = base .. '_' .. i
        if not Server.missionsCache[candidate] then return candidate end
    end
    return base .. '_' .. os.time()
end

-- ── DB operations ───────────────────────────────────────────────────────────

local function dbCreateMission(data)
    MySQL.query.await([[
        INSERT INTO `fish_missions` (`id`, `label`, `description`, `type`, `cooldown_seconds`, `npc`, `params`, `messages`, `reward`, `level_required`, `prerequisites`, `enabled`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.id,
        data.label or data.id,
        data.description or '',
        data.type or 'cleanup',
        data.cooldownSeconds or 0,
        json.encode(data.npc or {}),
        json.encode(data.params or {}),
        data.messages and json.encode(data.messages) or nil,
        data.reward and json.encode(data.reward) or nil,
        data.levelRequired or 0,
        data.prerequisites and json.encode(data.prerequisites) or nil,
        data.enabled ~= false and 1 or 0,
    })
end

local function dbUpdateMission(id, data)
    MySQL.query.await([[
        UPDATE `fish_missions` SET
            `label` = ?, `description` = ?, `type` = ?, `cooldown_seconds` = ?,
            `npc` = ?, `params` = ?, `messages` = ?, `reward` = ?,
            `level_required` = ?, `prerequisites` = ?, `enabled` = ?
        WHERE `id` = ?
    ]], {
        data.label or id,
        data.description or '',
        data.type or 'cleanup',
        data.cooldownSeconds or 0,
        json.encode(data.npc or {}),
        json.encode(data.params or {}),
        data.messages and json.encode(data.messages) or nil,
        data.reward and json.encode(data.reward) or nil,
        data.levelRequired or 0,
        data.prerequisites and json.encode(data.prerequisites) or nil,
        data.enabled ~= false and 1 or 0,
        id,
    })
end

local function dbDeleteMission(id)
    MySQL.query.await('DELETE FROM `fish_mission_progress` WHERE `mission_id` = ?', { id })
    MySQL.query.await('DELETE FROM `fish_missions` WHERE `id` = ?', { id })
end

local function dbGetMissionsPaginated(page, pageSize, search)
    local offset = (page - 1) * pageSize
    local where = ''
    local params = {}
    if search and search ~= '' then
        where = ' WHERE (`label` LIKE ? OR `description` LIKE ? OR `id` LIKE ?)'
        local pattern = '%' .. search .. '%'
        params = { pattern, pattern, pattern }
    end
    local countRow = MySQL.scalar.await('SELECT COUNT(*) FROM `fish_missions`' .. where, params)
    local total = tonumber(countRow) or 0

    local queryParams = {}
    for _, v in ipairs(params) do queryParams[#queryParams + 1] = v end
    queryParams[#queryParams + 1] = pageSize
    queryParams[#queryParams + 1] = offset
    local rows = MySQL.query.await(
        'SELECT * FROM `fish_missions`' .. where .. ' ORDER BY `created_at` DESC LIMIT ? OFFSET ?',
        queryParams
    )

    local missions = {}
    for _, row in ipairs(rows or {}) do
        missions[#missions + 1] = {
            id = row.id,
            label = row.label,
            description = row.description,
            type = row.type,
            cooldownSeconds = row.cooldown_seconds,
            npc = row.npc and json.decode(row.npc) or {},
            params = row.params and json.decode(row.params) or {},
            messages = row.messages and json.decode(row.messages) or nil,
            reward = row.reward and json.decode(row.reward) or nil,
            levelRequired = row.level_required or 0,
            prerequisites = row.prerequisites and json.decode(row.prerequisites) or nil,
            enabled = row.enabled == 1 or row.enabled == true,
        }
    end
    return missions, total
end

local function broadcastMissionRefresh()
    Server.loadMissionsFromDb()
    TriggerClientEvent(ResourceName .. ':missions:load', -1, Server.missionsList)
end

-- ── Admin lib.callback handlers ─────────────────────────────────────────────

lib.callback.register(ResourceName .. ':admin:checkPermission', function(src)
    return isAdmin(src)
end)

lib.callback.register(ResourceName .. ':admin:getMissions', function(src, data)
    if not isAdmin(src) then return { missions = {}, total = 0 } end
    local page = tonumber(data and data.page) or 1
    local pageSize = tonumber(data and data.pageSize) or 25
    local search = data and data.search or ''
    local missions, total = dbGetMissionsPaginated(page, pageSize, search)
    return { missions = missions, total = total, page = page, pageSize = pageSize }
end)

lib.callback.register(ResourceName .. ':admin:saveMission', function(src, data)
    if not isAdmin(src) then return nil end
    if not data or not data.label or data.label == '' then return nil end

    -- Cleanup missions: migrate legacy flat props → propGroups, generate seeds
    if data.type == 'cleanup' and data.params then
        local params = data.params
        -- Auto-migrate legacy flat props into a single propGroup
        if params.props and not params.propGroups then
            params.propGroups = { { label = params.itemLabel or 'Items', mode = 'manual', props = params.props } }
            params.props = nil
        end
        -- Strip legacy zone-fill fields from groups
        if params.propGroups then
            for _, group in ipairs(params.propGroups) do
                group.mode = nil
                group.center = nil
                group.radius = nil
                group.seed = nil
            end
        end
    end

    local id = data.id
    local isNew = not id or id == ''

    if isNew then
        id = generateMissionId(data.label)
        data.id = id
        -- Auto-generate NPC id if not set
        if data.npc and (not data.npc.id or data.npc.id == '') then
            data.npc.id = 'npc_' .. id
        end
        dbCreateMission(data)
    else
        -- Verify mission exists
        local existing = MySQL.scalar.await('SELECT COUNT(*) FROM `fish_missions` WHERE `id` = ?', { id })
        if (tonumber(existing) or 0) == 0 then return nil end
        -- Auto-generate NPC id if not set
        if data.npc and (not data.npc.id or data.npc.id == '') then
            data.npc.id = 'npc_' .. id
        end
        dbUpdateMission(id, data)
    end

    broadcastMissionRefresh()
    return { id = id, isNew = isNew }
end)

lib.callback.register(ResourceName .. ':admin:deleteMission', function(src, data)
    if not isAdmin(src) then return false end
    if not data or not data.id or data.id == '' then return false end

    -- Cancel any active instances across all players
    for playerSrc, actives in pairs(Server.active) do
        if actives[data.id] then
            actives[data.id] = nil
            TriggerClientEvent(ResourceName .. ':mission:cancelled', playerSrc, { missionId = data.id })
        end
    end

    dbDeleteMission(data.id)
    broadcastMissionRefresh()
    return true
end)
