-- Delivery mission module: destination waypoint, timer, animation/prop attach, completion

Missions = Missions or {}

local running = false
local missionBlips = nil
local propObjects = {}
local startTime = 0
local lastDisplayedTime = -1
local isNearDestination = false
local activeMission = nil

local function formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return ('%02d:%02d'):format(mins, secs)
end

local function loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do
        Wait(50)
        tries = tries + 1
    end
end

local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local tries = 0
    while not HasAnimDictLoaded(dict) and tries < 100 do
        Wait(50)
        tries = tries + 1
    end
end

local function applyAnimationAndProps(mission)
    local animation = mission.params and mission.params.animation
    if not animation then return end

    local ped = cache.ped
    loadAnimDict(animation.Dictionary)

    for _, prop in ipairs(animation.Options.Props) do
        loadModel(prop.Name)
    end

    ClearPedTasks(ped)

    local flags = animation.Options.Flags
    local animFlags = 0
    if flags.Loop then animFlags = animFlags | 2 end
    if flags.Move then animFlags = animFlags | 49 end
    if animFlags == 0 then animFlags = 1 end

    TaskPlayAnim(ped, animation.Dictionary, animation.Animation, 8.0, 8.0, -1, animFlags, 0.0, false, false, false)
    Wait(100)

    for _, propConfig in ipairs(animation.Options.Props) do
        local propObj = CreateObject(joaat(propConfig.Name), 0.0, 0.0, 0.0, true, true, true)
        local boneIndex = GetPedBoneIndex(ped, propConfig.Bone)

        local offset = propConfig.Placement[1]
        local rotation = propConfig.Placement[2]

        AttachEntityToEntity(propObj, ped, boneIndex,
            offset.x, offset.y, offset.z,
            rotation.x, rotation.y, rotation.z,
            true, true, false, true, 1, true)

        propObjects[#propObjects + 1] = propObj
    end
end

local function removeAnimationAndProps()
    ClearPedTasks(cache.ped)
    for _, propObj in ipairs(propObjects) do
        if DoesEntityExist(propObj) then
            DeleteEntity(propObj)
        end
    end
    propObjects = {}
end

local function cleanup()
    running = false
    activeMission = nil
    lib.hideTextUI()
    RemoveMissionBlips(missionBlips)
    missionBlips = nil
    removeAnimationAndProps()
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
    missionBlips = CreateMissionBlips({
        location = blipLocation,
        label = mission.label,
        area = mission.params.area,
        radius = mission.params.radius,
    })

    applyAnimationAndProps(mission)

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
                    lib.showTextUI(('Press [E] to deliver (%s)'):format(formatTime(displayTime)), {
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
                    lib.showTextUI(('You have %s remaining'):format(formatTime(displayTime)), {
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
                    description = 'You ran out of time.',
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
