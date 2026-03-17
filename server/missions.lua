-- Server-side mission accept/complete/claim/cancel handlers

-- ── Accept mission ──────────────────────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':mission:accept')
AddEventHandler(ResourceName .. ':mission:accept', function(data)
    local src = source
    local enc = Server.findMission(data.missionId)
    if not enc then return end

    local actives = Server.getActivesFor(src)
    local same = actives[enc.id]
    if same and (same.status == 'in-progress' or same.status == 'complete') then
        TriggerClientEvent(ResourceName .. ':mission:busy', src, { missionId = same.missionId, status = same.status })
        return
    end

    local charId = Server.getCharacterId(src)

    -- Level requirement check
    if enc.levelRequired and enc.levelRequired > 0 then
        local xp = Server.dbGetXp(charId)
        if xp < enc.levelRequired then
            TriggerClientEvent(ResourceName .. ':mission:blocked', src, { missionId = enc.id, reason = 'level' })
            return
        end
    end

    -- Daily limit check
    local limit = Config.dailyMissionLimit or 20
    if limit > 0 and Server.dbGetDailyCompletions(charId) >= limit then
        TriggerClientEvent(ResourceName .. ':mission:blocked', src, { missionId = enc.id, reason = 'daily_limit' })
        return
    end

    -- Prerequisite check
    if not Server.checkPrerequisites(charId, enc) then
        TriggerClientEvent(ResourceName .. ':mission:blocked', src, { missionId = enc.id, reason = 'prerequisites' })
        return
    end

    local row = Server.dbGetProgress(charId, enc.id)
    local t = Server.now()

    if row and row.cooldown_until and row.cooldown_until > t then
        local seconds = row.cooldown_until - t
        TriggerClientEvent(ResourceName .. ':mission:cooldown', src, { seconds = seconds, missionId = enc.id })
        return
    end

    local a = { missionId = enc.id, npcId = data.npcId, status = 'in-progress' }
    actives[enc.id] = a

    Server.dbUpsertProgress(charId, enc.id, {
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

-- ── Completion from client module ───────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':mission:complete')
AddEventHandler(ResourceName .. ':mission:complete', function(data)
    local src = source
    local actives = Server.getActivesFor(src)
    local a = actives[data.missionId]
    if not a then return end
    local enc = Server.findMission(a.missionId)
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

    Server.dbUpdateStatus(Server.getCharacterId(src), enc.id, 'complete')
    TriggerClientEvent(ResourceName .. ':mission:return', src, { npcId = a.npcId, missionId = a.missionId })

    -- Broadcast completion to all other zone participants for assassination missions
    if enc.type == 'assassination' and Server.completeAssassinationForParticipants then
        Server.completeAssassinationForParticipants(enc.id, src)
    end
end)

-- ── Claim reward at NPC ─────────────────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':mission:claim')
AddEventHandler(ResourceName .. ':mission:claim', function(data)
    local src = source
    local actives = Server.getActivesFor(src)
    local a = actives[data.missionId]
    if not a or a.npcId ~= data.npcId or a.status ~= 'complete' then return end

    local enc = Server.findMission(a.missionId)
    if not enc then return end

    Server.grantReward(src, enc.reward)

    local charId = Server.getCharacterId(src)
    local row = Server.dbGetProgress(charId, enc.id)
    local timesCompleted = (row and row.times_completed or 0) + 1

    -- Track XP and daily completions
    Server.dbIncrementXp(charId)
    Server.dbIncrementDaily(charId)

    actives[enc.id] = nil

    if enc.cooldownSeconds and enc.cooldownSeconds > 0 then
        Server.dbSetCooldown(charId, enc.id, Server.now() + enc.cooldownSeconds, timesCompleted)
    else
        Server.dbUpsertProgress(charId, enc.id, {
            status = 'available',
            cooldownUntil = 0,
            timesCompleted = timesCompleted,
        })
    end

    TriggerClientEvent(ResourceName .. ':mission:claimed', src, { missionId = enc.id })
end)

-- ── Cancel current mission ──────────────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':mission:cancel')
AddEventHandler(ResourceName .. ':mission:cancel', function(data)
    local src = source
    local actives = Server.getActivesFor(src)
    local a
    if data and data.missionId then
        a = actives[data.missionId]
    else
        for _, v in pairs(actives) do a = v; break end
    end
    if not a then return end

    local enc = Server.findMission(a.missionId)
    if not enc then actives[a.missionId] = nil; return end

    local charId = Server.getCharacterId(src)
    actives[enc.id] = nil

    local applyCd = enc.cancelIncurCooldown == true
    if applyCd and enc.cooldownSeconds and enc.cooldownSeconds > 0 then
        local row = Server.dbGetProgress(charId, enc.id)
        Server.dbSetCooldown(charId, enc.id, Server.now() + enc.cooldownSeconds, row and row.times_completed or 0)
    else
        Server.dbSetCancelled(charId, enc.id)
    end

    TriggerClientEvent(ResourceName .. ':mission:cancelled', src, { missionId = enc.id, appliedCooldown = applyCd })
end)

-- ── canAccept callback ──────────────────────────────────────────────────────

lib.callback.register(ResourceName .. ':mission:canAccept', function(src, missionId)
    local enc = Server.findMission(missionId)
    if not enc then return { allowed = false, reason = 'not_found' } end

    local charId = Server.getCharacterId(src)
    if not charId then return { allowed = false, reason = 'no_character' } end

    -- Level requirement check
    if enc.levelRequired and enc.levelRequired > 0 then
        local xp = Server.dbGetXp(charId)
        if xp < enc.levelRequired then
            return { allowed = false, reason = 'level' }
        end
    end

    -- Daily limit
    local limit = Config.dailyMissionLimit or 20
    if limit > 0 and Server.dbGetDailyCompletions(charId) >= limit then
        return { allowed = false, reason = 'daily_limit' }
    end

    -- Prerequisites
    if not Server.checkPrerequisites(charId, enc) then
        return { allowed = false, reason = 'prerequisites' }
    end

    return { allowed = true }
end)

-- Unused placeholder from original
RegisterNetEvent(ResourceName .. ':mission:waypoint')
AddEventHandler(ResourceName .. ':mission:waypoint', function() end)
