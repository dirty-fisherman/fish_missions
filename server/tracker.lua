-- Server-side tracker builder and event handlers

-- ── Tracker builder ─────────────────────────────────────────────────────────

function Server.buildTrackerStatuses(src)
    local charId = Server.getCharacterId(src)
    local actives = Server.getActivesFor(src)
    local nowTs = Server.now()
    local rows = Server.dbGetAllProgress(charId)

    local progressByMission = {}
    for _, row in ipairs(rows) do
        progressByMission[row.mission_id] = row
    end

    local statuses = {}
    for _, enc in ipairs(Server.missionsList) do
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

-- ── Tracker request handler ─────────────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':tracker:request')
AddEventHandler(ResourceName .. ':tracker:request', function()
    local src = source
    Server.hydrateActives(src)
    local charId = Server.getCharacterId(src)

    local statuses = Server.buildTrackerStatuses(src)

    local rows = Server.dbGetAllProgress(charId)
    local discoveredIds = {}
    for _, row in ipairs(rows) do
        discoveredIds[row.mission_id] = true
    end

    local discoveredMissions = {}
    for _, enc in ipairs(Server.missionsList) do
        if discoveredIds[enc.id] then
            discoveredMissions[#discoveredMissions + 1] = enc
        end
    end

    TriggerClientEvent(ResourceName .. ':tracker:data', src, {
        statuses = statuses,
        discoveredMissions = discoveredMissions,
        config = { sidebarPosition = Config.sidebarPosition or 'left' },
        strings = Config.strings,
        isAdmin = IsPlayerAceAllowed(tostring(src), Config.adminPermission or 'command.missionadmin'),
    })
end)

-- ── Progress updates from client ────────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':mission:progress')
AddEventHandler(ResourceName .. ':mission:progress', function(data)
    local src = source
    local actives = Server.getActivesFor(src)
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
    Server.dbUpdateProgress(Server.getCharacterId(src), a.missionId, a.progress)

    local statuses = Server.buildTrackerStatuses(src)
    TriggerClientEvent(ResourceName .. ':tracker:data', src, { statuses = statuses })
end)
