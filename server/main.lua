-- Server-side mission lifecycle, MySQL persistence, tracker, character lifecycle

local Ox = require '@ox_core.lib.init'

local active = {} -- active[src] = { [missionId] = row }
local playerCharacters = {} -- playerCharacters[src] = charId (number as string)
local missionsCache = {} -- missionId -> mission data (loaded from DB)
local missionsList = {} -- ordered array of missions (loaded from DB)

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

local function seedMissions()
    if not Config.seedMissions then return end
    if not Config.missions then return end
    for i, enc in ipairs(Config.missions) do
        MySQL.query.await([[
            INSERT INTO `fish_missions` (`id`, `label`, `description`, `type`, `cooldown_seconds`, `npc`, `params`, `messages`, `reward`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `label` = VALUES(`label`),
                `description` = VALUES(`description`),
                `type` = VALUES(`type`),
                `cooldown_seconds` = VALUES(`cooldown_seconds`),
                `npc` = VALUES(`npc`),
                `params` = VALUES(`params`),
                `messages` = VALUES(`messages`),
                `reward` = VALUES(`reward`)
        ]], {
            enc.id,
            enc.label or enc.id,
            enc.description or '',
            enc.type,
            enc.cooldownSeconds or 0,
            json.encode(enc.npc),
            json.encode(enc.params),
            enc.messages and json.encode(enc.messages) or nil,
            enc.reward and json.encode(enc.reward) or nil,
        })
    end
end

local function loadMissionsFromDb()
    local rows = MySQL.query.await('SELECT * FROM `fish_missions` WHERE `enabled` = 1 ORDER BY `created_at` DESC')
    missionsCache = {}
    missionsList = {}
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
        missionsCache[enc.id] = enc
        missionsList[#missionsList + 1] = enc
    end
end

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function getActivesFor(src)
    if not active[src] then active[src] = {} end
    return active[src]
end

local function getCharacterId(src)
    if playerCharacters[src] then return playerCharacters[src] end
    local player = Ox.GetPlayer(src)
    if player and player.charId then return tostring(player.charId) end
    return nil
end

local function now()
    return math.floor(os.time())
end

local function findMission(id)
    return missionsCache[id]
end

-- ── DB access helpers ───────────────────────────────────────────────────────

local function dbGetProgress(charId, missionId)
    return MySQL.single.await(
        'SELECT * FROM `fish_mission_progress` WHERE `char_id` = ? AND `mission_id` = ?',
        { charId, missionId }
    )
end

local function dbUpsertProgress(charId, missionId, data)
    MySQL.query.await([[
        INSERT INTO `fish_mission_progress` (`char_id`, `mission_id`, `status`, `npc_id`, `progress`, `cooldown_until`, `times_completed`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `status` = VALUES(`status`),
            `npc_id` = VALUES(`npc_id`),
            `progress` = VALUES(`progress`),
            `cooldown_until` = VALUES(`cooldown_until`),
            `times_completed` = VALUES(`times_completed`)
    ]], {
        charId,
        missionId,
        data.status or 'available',
        data.npcId or nil,
        data.progress and json.encode(data.progress) or nil,
        data.cooldownUntil or 0,
        data.timesCompleted or 0,
    })
end

local function dbUpdateStatus(charId, missionId, status)
    MySQL.query.await(
        'UPDATE `fish_mission_progress` SET `status` = ? WHERE `char_id` = ? AND `mission_id` = ?',
        { status, charId, missionId }
    )
end

local function dbUpdateProgress(charId, missionId, progress)
    MySQL.query.await(
        'UPDATE `fish_mission_progress` SET `progress` = ? WHERE `char_id` = ? AND `mission_id` = ?',
        { progress and json.encode(progress) or nil, charId, missionId }
    )
end

local function dbSetCooldown(charId, missionId, untilTs, timesCompleted)
    MySQL.query.await([[
        INSERT INTO `fish_mission_progress` (`char_id`, `mission_id`, `status`, `cooldown_until`, `times_completed`)
        VALUES (?, ?, 'available', ?, ?)
        ON DUPLICATE KEY UPDATE
            `status` = 'available',
            `cooldown_until` = VALUES(`cooldown_until`),
            `times_completed` = VALUES(`times_completed`),
            `progress` = NULL,
            `npc_id` = NULL
    ]], { charId, missionId, untilTs, timesCompleted or 0 })
end

local function dbSetCancelled(charId, missionId)
    MySQL.query.await([[
        INSERT INTO `fish_mission_progress` (`char_id`, `mission_id`, `status`)
        VALUES (?, ?, 'cancelled')
        ON DUPLICATE KEY UPDATE
            `status` = 'cancelled',
            `progress` = NULL,
            `npc_id` = NULL
    ]], { charId, missionId })
end

local function dbGetAllProgress(charId)
    return MySQL.query.await(
        'SELECT * FROM `fish_mission_progress` WHERE `char_id` = ?',
        { charId }
    ) or {}
end

-- ── XP helpers ──────────────────────────────────────────────────────────────

local function dbGetXp(charId)
    local row = MySQL.single.await('SELECT `xp` FROM `fish_mission_xp` WHERE `char_id` = ?', { charId })
    return row and row.xp or 0
end

local function dbIncrementXp(charId)
    MySQL.query.await([[
        INSERT INTO `fish_mission_xp` (`char_id`, `xp`) VALUES (?, 1)
        ON DUPLICATE KEY UPDATE `xp` = `xp` + 1
    ]], { charId })
end

-- ── Daily completion helpers ────────────────────────────────────────────────

local function todayDate()
    return os.date('%Y-%m-%d')
end

local function dbGetDailyCompletions(charId)
    local row = MySQL.single.await('SELECT `completions`, `reset_date` FROM `fish_mission_daily` WHERE `char_id` = ?', { charId })
    if not row then return 0 end
    if row.reset_date ~= todayDate() then return 0 end
    return row.completions or 0
end

local function dbIncrementDaily(charId)
    local today = todayDate()
    MySQL.query.await([[
        INSERT INTO `fish_mission_daily` (`char_id`, `completions`, `reset_date`) VALUES (?, 1, ?)
        ON DUPLICATE KEY UPDATE
            `completions` = IF(`reset_date` = VALUES(`reset_date`), `completions` + 1, 1),
            `reset_date` = VALUES(`reset_date`)
    ]], { charId, today })
end

-- ── Prerequisite check ──────────────────────────────────────────────────────

local function checkPrerequisites(charId, enc)
    if not enc.prerequisites or #enc.prerequisites == 0 then return true end
    local rows = dbGetAllProgress(charId)
    local completed = {}
    for _, row in ipairs(rows) do
        if row.times_completed and row.times_completed > 0 then
            completed[row.mission_id] = true
        end
    end
    for _, prereqId in ipairs(enc.prerequisites) do
        if not completed[prereqId] then return false end
    end
    return true
end

-- ── Rewards ─────────────────────────────────────────────────────────────────

local function grantReward(src, reward)
    if not reward then return end
    if reward.cash and reward.cash > 0 then
        local ok = pcall(function()
            exports.ox_core:addMoney(src, 'cash', reward.cash, 'mission_reward')
        end)
        if not ok then
            pcall(function()
                exports.ox_inventory:AddItem(src, 'money', reward.cash)
            end)
        end
    end
    if reward.items then
        for _, item in ipairs(reward.items) do
            pcall(function()
                exports.ox_inventory:AddItem(src, item.name, item.count or 1)
            end)
        end
    end
end

-- ── Tracker builder ─────────────────────────────────────────────────────────

local function buildTrackerStatuses(src)
    local charId = getCharacterId(src)
    local actives = getActivesFor(src)
    local nowTs = now()
    local rows = dbGetAllProgress(charId)

    local progressByMission = {}
    for _, row in ipairs(rows) do
        progressByMission[row.mission_id] = row
    end

    local statuses = {}
    for _, enc in ipairs(missionsList) do
        local a = actives[enc.id]
        local row = progressByMission[enc.id]
        local status = 'available'

        if a then
            status = a.status == 'complete' and 'turnin' or 'active'
        elseif row then
            if row.status == 'active' or row.status == 'complete' then
                status = row.status == 'complete' and 'turnin' or 'active'
            elseif row.cooldown_until and row.cooldown_until > nowTs then
                status = 'cooldown'
            elseif row.status == 'cancelled' then
                status = 'cancelled'
            end
        end

        local remaining = 0
        if row and row.cooldown_until and row.cooldown_until > nowTs then
            remaining = row.cooldown_until - nowTs
        end

        local progress = nil
        if a and a.progress then
            progress = a.progress
        elseif row and row.progress then
            local ok, p = pcall(json.decode, row.progress)
            if ok then progress = p end
        end

        statuses[#statuses + 1] = {
            id = enc.id,
            label = enc.label or enc.id,
            type = enc.type,
            status = status,
            cooldownRemaining = remaining,
            reward = enc.reward or nil,
            progress = progress,
        }
    end
    return statuses
end

-- ── Hydrate in-memory actives from DB ───────────────────────────────────────

local function hydrateActives(src)
    local charId = getCharacterId(src)
    local actives = getActivesFor(src)
    local rows = dbGetAllProgress(charId)
    for _, row in ipairs(rows) do
        if not actives[row.mission_id] and (row.status == 'active' or row.status == 'complete') then
            local progress = nil
            if row.progress then
                local ok, p = pcall(json.decode, row.progress)
                if ok then progress = p end
            end
            actives[row.mission_id] = {
                missionId = row.mission_id,
                npcId = row.npc_id,
                status = row.status == 'active' and 'in-progress' or row.status,
                progress = progress,
            }
        end
    end
end

-- ── Character lifecycle ─────────────────────────────────────────────────────

local function handleCharacterSelected(src, charId)
    if not src or not charId then return end
    active[src] = nil
    playerCharacters[src] = tostring(charId)
    hydrateActives(src)

    -- Send mission list to client for NPC spawning
    TriggerClientEvent(ResourceName .. ':missions:load', src, missionsList)
end

local function handleCharacterDeselected(src)
    if not src then return end
    active[src] = nil
    playerCharacters[src] = nil
end

if Config.characterSelectedEvent then
    RegisterNetEvent(Config.characterSelectedEvent)
    AddEventHandler(Config.characterSelectedEvent, function()
        local src = source
        CreateThread(function()
            local charId
            for _ = 1, 20 do
                local player = Ox.GetPlayer(src)
                if player and player.charId then
                    charId = player.charId
                    break
                end
                Wait(250)
            end
            if charId then
                handleCharacterSelected(src, charId)
            end
        end)
    end)
end

if Config.characterDeselectedEvent then
    RegisterNetEvent(Config.characterDeselectedEvent)
    AddEventHandler(Config.characterDeselectedEvent, function()
        local src = source
        handleCharacterDeselected(src)
    end)
end

exports('setCharacter', function(src, charId)
    handleCharacterSelected(src, charId)
end)

exports('clearCharacter', function(src)
    handleCharacterDeselected(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    active[src] = nil
    playerCharacters[src] = nil
end)

-- Dev helpers
if Config.EnableNuiCommand then
    lib.addCommand('openNui', nil, function(src)
        if not src then return end
        TriggerClientEvent(ResourceName .. ':openNui', src)
    end)

    lib.addCommand('missionscd', nil, function(src)
        if not src then return end
        local charId = getCharacterId(src)
        MySQL.query.await('UPDATE `fish_mission_progress` SET `cooldown_until` = 0 WHERE `char_id` = ?', { charId })
    end)
end

-- ── Net event handlers ──────────────────────────────────────────────────────

-- Accept mission
RegisterNetEvent(ResourceName .. ':mission:accept')
AddEventHandler(ResourceName .. ':mission:accept', function(data)
    local src = source
    local enc = findMission(data.missionId)
    if not enc then return end

    local actives = getActivesFor(src)
    local same = actives[enc.id]
    if same and (same.status == 'in-progress' or same.status == 'complete') then
        TriggerClientEvent(ResourceName .. ':mission:busy', src, { missionId = same.missionId, status = same.status })
        return
    end

    local charId = getCharacterId(src)

    -- Level requirement check
    if enc.levelRequired and enc.levelRequired > 0 then
        local xp = dbGetXp(charId)
        if xp < enc.levelRequired then
            TriggerClientEvent(ResourceName .. ':mission:blocked', src, { missionId = enc.id, reason = 'level' })
            return
        end
    end

    -- Daily limit check
    local limit = Config.dailyMissionLimit or 20
    if limit > 0 and dbGetDailyCompletions(charId) >= limit then
        TriggerClientEvent(ResourceName .. ':mission:blocked', src, { missionId = enc.id, reason = 'daily_limit' })
        return
    end

    -- Prerequisite check
    if not checkPrerequisites(charId, enc) then
        TriggerClientEvent(ResourceName .. ':mission:blocked', src, { missionId = enc.id, reason = 'prerequisites' })
        return
    end

    local row = dbGetProgress(charId, enc.id)
    local t = now()

    if row and row.cooldown_until and row.cooldown_until > t then
        local seconds = row.cooldown_until - t
        TriggerClientEvent(ResourceName .. ':mission:cooldown', src, { seconds = seconds, missionId = enc.id })
        return
    end

    local a = { missionId = enc.id, npcId = data.npcId, status = 'in-progress' }
    actives[enc.id] = a

    dbUpsertProgress(charId, enc.id, {
        status = 'active',
        npcId = data.npcId,
        cooldownUntil = row and row.cooldown_until or 0,
        timesCompleted = row and row.times_completed or 0,
    })

    -- Deliveries: give the parcel at accept time
    if enc.type == 'delivery' then
        local item = enc.params and enc.params.item
        if item and item.name then
            pcall(function()
                exports.ox_inventory:AddItem(src, item.name, item.count or 1)
            end)
        end
    end

    TriggerClientEvent(ResourceName .. ':mission:start', src, { mission = enc, npcId = data.npcId, progress = a.progress })
end)

-- Completion from client module
RegisterNetEvent(ResourceName .. ':mission:complete')
AddEventHandler(ResourceName .. ':mission:complete', function(data)
    local src = source
    local actives = getActivesFor(src)
    local a = actives[data.missionId]
    if not a then return end
    local enc = findMission(a.missionId)
    if not enc then return end

    if enc.type == 'delivery' then
        local item = enc.params and enc.params.item
        if item and item.name then
            pcall(function()
                exports.ox_inventory:RemoveItem(src, item.name, item.count or 1)
            end)
        end
    end

    a.status = 'complete'
    actives[a.missionId] = a

    dbUpdateStatus(getCharacterId(src), enc.id, 'complete')
    TriggerClientEvent(ResourceName .. ':mission:return', src, { npcId = a.npcId, missionId = a.missionId })
end)

-- Claim reward at NPC
RegisterNetEvent(ResourceName .. ':mission:claim')
AddEventHandler(ResourceName .. ':mission:claim', function(data)
    local src = source
    local actives = getActivesFor(src)
    local a = actives[data.missionId]
    if not a or a.npcId ~= data.npcId or a.status ~= 'complete' then return end

    local enc = findMission(a.missionId)
    if not enc then return end

    grantReward(src, enc.reward)

    local charId = getCharacterId(src)
    local row = dbGetProgress(charId, enc.id)
    local timesCompleted = (row and row.times_completed or 0) + 1

    -- Track XP and daily completions
    dbIncrementXp(charId)
    dbIncrementDaily(charId)

    actives[enc.id] = nil

    if enc.cooldownSeconds and enc.cooldownSeconds > 0 then
        dbSetCooldown(charId, enc.id, now() + enc.cooldownSeconds, timesCompleted)
    else
        dbUpsertProgress(charId, enc.id, {
            status = 'available',
            cooldownUntil = 0,
            timesCompleted = timesCompleted,
        })
    end

    TriggerClientEvent(ResourceName .. ':mission:claimed', src, { missionId = enc.id })
end)

-- Cancel current mission
RegisterNetEvent(ResourceName .. ':mission:cancel')
AddEventHandler(ResourceName .. ':mission:cancel', function(data)
    local src = source
    local actives = getActivesFor(src)
    local a
    if data and data.missionId then
        a = actives[data.missionId]
    else
        for _, v in pairs(actives) do a = v; break end
    end
    if not a then return end

    local enc = findMission(a.missionId)
    if not enc then actives[a.missionId] = nil; return end

    local charId = getCharacterId(src)
    actives[enc.id] = nil

    local applyCd = enc.cancelIncurCooldown == true
    if applyCd and enc.cooldownSeconds and enc.cooldownSeconds > 0 then
        local row = dbGetProgress(charId, enc.id)
        dbSetCooldown(charId, enc.id, now() + enc.cooldownSeconds, row and row.times_completed or 0)
    else
        dbSetCancelled(charId, enc.id)
    end

    TriggerClientEvent(ResourceName .. ':mission:cancelled', src, { missionId = enc.id, appliedCooldown = applyCd })
end)

-- Tracker: provide mission statuses for the player
RegisterNetEvent(ResourceName .. ':tracker:request')
AddEventHandler(ResourceName .. ':tracker:request', function()
    local src = source
    hydrateActives(src)
    local charId = getCharacterId(src)

    local statuses = buildTrackerStatuses(src)

    local rows = dbGetAllProgress(charId)
    local discoveredIds = {}
    for _, row in ipairs(rows) do
        discoveredIds[row.mission_id] = true
    end

    local discoveredMissions = {}
    for _, enc in ipairs(missionsList) do
        if discoveredIds[enc.id] then
            discoveredMissions[#discoveredMissions + 1] = enc
        end
    end

    TriggerClientEvent(ResourceName .. ':tracker:data', src, {
        statuses = statuses,
        discoveredMissions = discoveredMissions,
        config = { sidebarPosition = Config.sidebarPosition or 'left' },
    })
end)

-- Progress updates from client
RegisterNetEvent(ResourceName .. ':mission:progress')
AddEventHandler(ResourceName .. ':mission:progress', function(data)
    local src = source
    local actives = getActivesFor(src)
    local a = actives[data.missionId]
    if not a then return end

    if data.type == 'cleanup' then
        local prev = (a.progress and a.progress.completed) or 0
        local next_val = math.max(prev, tonumber(data.completed) or 0)
        local total = tonumber(data.total) or (a.progress and a.progress.total) or next_val
        a.progress = { type = 'cleanup', completed = next_val, total = total }
    else
        a.progress = data
    end

    actives[a.missionId] = a
    dbUpdateProgress(getCharacterId(src), a.missionId, a.progress)

    local statuses = buildTrackerStatuses(src)
    TriggerClientEvent(ResourceName .. ':tracker:data', src, { statuses = statuses })
end)

-- Client requests to restore mission state after restart
RegisterNetEvent(ResourceName .. ':restore:request')
AddEventHandler(ResourceName .. ':restore:request', function()
    local src = source
    hydrateActives(src)

    -- Send missions to client (in case this is a /ensure and client needs them)
    TriggerClientEvent(ResourceName .. ':missions:load', src, missionsList)

    local actives = getActivesFor(src)
    for _, a in pairs(actives) do
        local enc = findMission(a.missionId)
        if enc then
            -- Delivery missions cannot be restored (timer-based, no persistence)
            if enc.type == 'delivery' and a.status == 'in-progress' then
                local charId = getCharacterId(src)
                dbSetCancelled(charId, a.missionId)
                actives[a.missionId] = nil
            elseif a.status == 'in-progress' then
                TriggerClientEvent(ResourceName .. ':mission:start', src, { mission = enc, npcId = a.npcId, progress = a.progress })
            elseif a.status == 'complete' then
                TriggerClientEvent(ResourceName .. ':mission:return', src, { npcId = a.npcId, missionId = a.missionId })
            end
        end
    end
end)

-- Unused placeholder from original
RegisterNetEvent(ResourceName .. ':mission:waypoint')
AddEventHandler(ResourceName .. ':mission:waypoint', function() end)

-- ── Assassination ped spawn coordination ────────────────────────────────────

local missionPedData = {}

lib.callback.register(ResourceName .. ':assassination:requestSpawn', function(source, missionId)
    local data = missionPedData[missionId]

    if data then
        if data.status == 'spawning' then
            return { status = 'wait' }
        end

        if data.status == 'ready' and data.netIds and #data.netIds > 0 then
            local anyValid = false
            for _, netId in ipairs(data.netIds) do
                local entity = NetworkGetEntityFromNetworkId(netId)
                if entity and entity ~= 0 and DoesEntityExist(entity) and not IsEntityDead(entity) then
                    anyValid = true
                    break
                end
            end

            if anyValid then
                return { status = 'ready', netIds = data.netIds }
            end

            missionPedData[missionId] = nil
        end
    end

    missionPedData[missionId] = { status = 'spawning', netIds = {}, owner = source }
    return { status = 'spawn' }
end)

RegisterNetEvent(ResourceName .. ':assassination:pedsSpawned')
AddEventHandler(ResourceName .. ':assassination:pedsSpawned', function(missionId, netIds)
    local src = source
    local data = missionPedData[missionId]
    if data and data.owner == src then
        data.status = 'ready'
        data.netIds = netIds
    end
end)

RegisterNetEvent(ResourceName .. ':assassination:pedsCleared')
AddEventHandler(ResourceName .. ':assassination:pedsCleared', function(missionId)
    missionPedData[missionId] = nil
end)

-- ── canAccept callback (used by client before showing NUI) ──────────────────

lib.callback.register(ResourceName .. ':mission:canAccept', function(src, missionId)
    local enc = findMission(missionId)
    if not enc then return { allowed = false, reason = 'not_found' } end

    local charId = getCharacterId(src)
    if not charId then return { allowed = false, reason = 'no_character' } end

    -- Level requirement check
    if enc.levelRequired and enc.levelRequired > 0 then
        local xp = dbGetXp(charId)
        if xp < enc.levelRequired then
            return { allowed = false, reason = 'level' }
        end
    end

    -- Daily limit
    local limit = Config.dailyMissionLimit or 20
    if limit > 0 and dbGetDailyCompletions(charId) >= limit then
        return { allowed = false, reason = 'daily_limit' }
    end

    -- Prerequisites
    if not checkPrerequisites(charId, enc) then
        return { allowed = false, reason = 'prerequisites' }
    end

    return { allowed = true }
end)

-- ── Admin CRUD ──────────────────────────────────────────────────────────────

local function isAdmin(src)
    return IsPlayerAceAllowed(tostring(src), Config.adminPermission or 'command.missionadmin')
end

local function slugify(str)
    return str:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
end

local function generateMissionId(label)
    local base = slugify(label)
    if base == '' then base = 'mission' end
    if not missionsCache[base] then return base end
    for i = 2, 9999 do
        local candidate = base .. '_' .. i
        if not missionsCache[candidate] then return candidate end
    end
    return base .. '_' .. os.time()
end

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
    loadMissionsFromDb()
    TriggerClientEvent(ResourceName .. ':missions:load', -1, missionsList)
end

-- Admin NUI callbacks (server-side via lib.callback)

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
    for playerSrc, actives in pairs(active) do
        if actives[data.id] then
            actives[data.id] = nil
            TriggerClientEvent(ResourceName .. ':mission:cancelled', playerSrc, { missionId = data.id })
        end
    end

    dbDeleteMission(data.id)
    broadcastMissionRefresh()
    return true
end)

-- ── Initialize ──────────────────────────────────────────────────────────────

CreateThread(function()
    runInstallSql()
    seedMissions()
    loadMissionsFromDb()
    print(('[%s] Loaded %d missions from database'):format(ResourceName, #missionsList))
end)
