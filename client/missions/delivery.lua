-- Delivery mission module: destination waypoint, timer, carry prop, completion

Missions = Missions or {}

local running = false
local missionBlips = nil
local startTime = 0
local lastDisplayedTime = -1
local isNearDestination = false
local activeMission = nil
local deliveryProp = nil

-- Props created on this client for other players' carry syncing (ped → obj)
local SyncedDeliveryProps = {}

local function formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return ('%02d:%02d'):format(mins, secs)
end

local function startCarry(propModel, carry, propOffset, propRotation)
    local preset = CARRY_PRESETS[carry or 'both_hands']
    if not propModel or not preset then return end

    local pos = propOffset and vec3(propOffset.x, propOffset.y, propOffset.z) or preset.pos
    local rot = propRotation and vec3(propRotation.x, propRotation.y, propRotation.z) or preset.rot

    CreateThread(function()
        local ped = PlayerPedId()
        local hash = joaat(propModel)

        lib.requestAnimDict(preset.dict)
        lib.requestModel(hash)

        TaskPlayAnim(ped, preset.dict, preset.anim, 5.0, 5.0, -1, 51, 0, false, false, false)
        RemoveAnimDict(preset.dict)

        local coords = GetEntityCoords(ped)
        local obj = CreateObject(hash, coords.x, coords.y, coords.z + 0.2, false, true, false)

        if obj and obj ~= 0 then
            AttachEntityToEntity(obj, ped,
                GetPedBoneIndex(ped, preset.bone),
                pos.x, pos.y, pos.z,
                rot.x, rot.y, rot.z,
                true, true, false, true, 1, true)
            deliveryProp = obj
        end

        SetModelAsNoLongerNeeded(hash)

        -- Broadcast carry state so other clients can create the prop on our ped
        LocalPlayer.state:set('fish_missions:carry', {
            propModel   = propModel,
            carry       = carry or 'both_hands',
            propOffset  = propOffset,
            propRotation = propRotation,
        }, true)
    end)
end

local function stopCarry()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    if deliveryProp then
        if DoesEntityExist(deliveryProp) then
            DetachEntity(deliveryProp, true, true)
            SetEntityAsMissionEntity(deliveryProp, true, true)
            DeleteEntity(deliveryProp)
        end
        deliveryProp = nil
    end
    -- Clear statebag so other clients remove the synced prop
    LocalPlayer.state:set('fish_missions:carry', nil, true)
end

local function cleanup()
    running = false
    activeMission = nil
    lib.hideTextUI()
    Client.RemoveMissionBlips(missionBlips)
    missionBlips = nil
    stopCarry()
    startTime = 0
    lastDisplayedTime = -1
    isNearDestination = false
end

local function stop()
    if activeMission then
        TriggerServerEvent(ResourceName .. ':mission:cancel', { missionId = activeMission.id })
    end
    cleanup()
end

local function start(mission)
    local dest = mission.params.destination
    local destination = vec3(dest.x, dest.y, dest.z)
    local timeSeconds = mission.params.timeSeconds

    activeMission = mission
    startTime = GetGameTimer()

    local blipLocation = mission.params.area or destination
    missionBlips = Client.CreateMissionBlips({
        location = blipLocation,
        label = mission.label,
        area = mission.params.area,
        radius = mission.params.radius,
    })

    startCarry(mission.params.prop, mission.params.carry, mission.params.propOffset, mission.params.propRotation)

    running = true

    CreateThread(function()
        while running do
            Wait(0)
            local elapsed = math.floor((GetGameTimer() - startTime) / 1000)
            local remainingTime = timeSeconds - elapsed

            local playerCoords = GetEntityCoords(cache.ped)
            local dist = #(playerCoords - destination)

            local nearDestination = dist < 5.0
            local stateChanged = nearDestination ~= isNearDestination
            local displayRemaining = math.floor(remainingTime)
            local timeChanged = displayRemaining ~= lastDisplayedTime

            if timeChanged or stateChanged then
                lastDisplayedTime = displayRemaining
                isNearDestination = nearDestination

                local displayTime = math.max(0, displayRemaining)
                local isLowTime = displayRemaining <= 30

                if nearDestination then
                    lib.showTextUI(Config.strings.delivery_near:format(formatTime(displayTime)), {
                        position = 'top-center',
                        icon = 'hand-holding-box',
                        iconColor = '#4CAF50',
                        style = {
                            backgroundColor = 'rgba(76, 175, 80, 0.8)',
                            color = '#ffffff',
                            borderLeft = '4px solid #2E7D32',
                        },
                    })
                else
                    lib.showTextUI(Config.strings.delivery_timer:format(formatTime(displayTime)), {
                        position = 'top-center',
                        icon = 'clock',
                        style = {
                            backgroundColor = 'rgba(0, 0, 0, 0.7)',
                            color = isLowTime and '#ff6b6b' or '#ffffff',
                        },
                    })
                end
            end

            if nearDestination and IsControlJustReleased(0, 38) then
                cleanup()
                TriggerServerEvent(ResourceName .. ':mission:complete', { missionId = mission.id })
                return
            end

            if remainingTime <= 0 then
                lib.notify({
                    title = mission.label or 'Mission Failed',
                    description = Config.strings.delivery_timeout,
                    type = 'error',
                    duration = 10000,
                })
                TriggerServerEvent(ResourceName .. ':mission:cancel', { missionId = mission.id })
                cleanup()
                return
            end
        end
    end)
end

local function setProgress(progress)
    -- Delivery does not restore progress; mission is cancelled on any interruption
end

Missions.delivery = {
    start = start,
    stop = stop,
    setProgress = setProgress,
}

-- ── Statebag handler: create/remove props on remote players' peds ───────────

AddStateBagChangeHandler('fish_missions:carry', nil, function(bagName, key, value, reserved, replicated)
    -- `replicated = true` means this is the local player's own state change;
    -- they already created their prop in startCarry(), so skip.
    if replicated then return end

    local ply = GetPlayerFromStateBagName(bagName)
    -- 0 = not a player bag, PlayerId() = our own (extra safety guard)
    if ply == 0 or ply == PlayerId() then return end

    local ped = GetPlayerPed(ply)

    -- Clean up any previously synced prop for this player
    if SyncedDeliveryProps[ped] then
        if DoesEntityExist(SyncedDeliveryProps[ped]) then
            SetEntityAsMissionEntity(SyncedDeliveryProps[ped], false, false)
            DeleteEntity(SyncedDeliveryProps[ped])
        end
        SyncedDeliveryProps[ped] = nil
    end

    if type(value) ~= 'table' or not value.propModel then return end

    local preset = CARRY_PRESETS[value.carry or 'both_hands']
    if not preset then return end

    local pos = value.propOffset   and vec3(value.propOffset.x,   value.propOffset.y,   value.propOffset.z)   or preset.pos
    local rot = value.propRotation and vec3(value.propRotation.x, value.propRotation.y, value.propRotation.z) or preset.rot

    -- Wait until the ped is streamed in before trying to attach
    while not DoesEntityExist(ped) do
        ped = GetPlayerPed(ply)
        Wait(0)
    end

    local hash = joaat(value.propModel)
    lib.requestModel(hash)

    local coords = GetEntityCoords(ped)
    local obj = CreateObject(hash, coords.x, coords.y, coords.z + 0.2, false, false, false)
    if obj and obj ~= 0 then
        AttachEntityToEntity(obj, ped,
            GetPedBoneIndex(ped, preset.bone),
            pos.x, pos.y, pos.z,
            rot.x, rot.y, rot.z,
            true, true, false, true, 1, true)
        SyncedDeliveryProps[ped] = obj
    end

    SetModelAsNoLongerNeeded(hash)
end)

-- Periodically clean up props whose owning ped has left / streamed out
CreateThread(function()
    while true do
        Wait(1000)
        for ped, prop in pairs(SyncedDeliveryProps) do
            if not DoesEntityExist(ped) then
                if DoesEntityExist(prop) then
                    SetEntityAsMissionEntity(prop, false, false)
                    DeleteEntity(prop)
                end
                SyncedDeliveryProps[ped] = nil
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resName)
    if resName ~= ResourceName then return end
    for _, prop in pairs(SyncedDeliveryProps) do
        if DoesEntityExist(prop) then
            SetEntityAsMissionEntity(prop, false, false)
            DeleteEntity(prop)
        end
    end
    SyncedDeliveryProps = {}
end)
