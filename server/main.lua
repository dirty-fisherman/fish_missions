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
    if not Config.missions then return end
    for i, enc in ipairs(Config.missions) do
        MySQL.query.await([[
            INSERT IGNORE INTO `fish_missions` (`id`, `label`, `description`, `type`, `cooldown_seconds`, `npc`, `params`, `messages`, `reward`, `sort_order`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            i,
        })
    end
end

local function loadMissionsFromDb()
    local rows = MySQL.query.await('SELECT * FROM `fish_missions` WHERE `enabled` = 1 ORDER BY `sort_order`, `id`')
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
            enabled = row.enabled == 1,
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
                if entity and entity ~= 0 and DoesEntityExist(entity) then
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

-- ── Initialize ──────────────────────────────────────────────────────────────

CreateThread(function()
    runInstallSql()
    seedMissions()
    loadMissionsFromDb()
    print(('[%s] Loaded %d missions from database'):format(ResourceName, #missionsList))
end)
