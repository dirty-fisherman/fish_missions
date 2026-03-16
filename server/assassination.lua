-- Server-side assassination ped spawn coordination

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
