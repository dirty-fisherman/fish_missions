-- Server-side assassination ped spawn coordination and multi-player participation

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
                -- GetEntityHealth is the server-safe equivalent of IsEntityDead
                if entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityHealth(entity) > 0 then
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

    missionPedData[missionId] = { status = 'spawning', netIds = {}, owner = source, participants = { [source] = true } }
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

-- ── Zone presence tracking ──────────────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':assassination:enteredZone')
AddEventHandler(ResourceName .. ':assassination:enteredZone', function(missionId)
    local src = source
    local actives = Server.getActivesFor(src)
    if not actives[missionId] or actives[missionId].status ~= 'in-progress' then return end

    local data = missionPedData[missionId]
    if data then
        if not data.participants then data.participants = {} end
        data.participants[src] = true
    end
end)

RegisterNetEvent(ResourceName .. ':assassination:exitedZone')
AddEventHandler(ResourceName .. ':assassination:exitedZone', function(missionId)
    local src = source
    local data = missionPedData[missionId]
    if data and data.participants then
        data.participants[src] = nil
    end
end)

-- ── Broadcast completion to all zone participants ───────────────────────────

function Server.completeAssassinationForParticipants(missionId, triggerSrc)
    local data = missionPedData[missionId]
    if not data or not data.participants then
        missionPedData[missionId] = nil
        return
    end

    for participantSrc, _ in pairs(data.participants) do
        if participantSrc ~= triggerSrc then
            local actives = Server.getActivesFor(participantSrc)
            local a = actives[missionId]
            if a and a.status == 'in-progress' then
                a.status = 'complete'
                actives[missionId] = a

                local charId = Server.getCharacterId(participantSrc)
                if charId then
                    Server.dbUpdateStatus(charId, missionId, 'complete')
                end

                TriggerClientEvent(ResourceName .. ':assassination:allDead', participantSrc, { missionId = missionId, npcId = a.npcId })
                TriggerClientEvent(ResourceName .. ':mission:return', participantSrc, { npcId = a.npcId, missionId = missionId })
            end
        end
    end

    missionPedData[missionId] = nil
end
