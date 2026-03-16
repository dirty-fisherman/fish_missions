-- Client-side: NUI bridge, NPC spawning, ox_target interactions, mission orchestration

local npcs = {} -- npcId -> ped handle
local npcBlips = {}
local nuiReady = false
local pendingMission = nil -- { npc, enc }
local trackerVisible = false

-- Track claimable/active missions
local claimableMissions = {}
local activeMissions = {} -- missionId -> { npcId, status, type }
local missionTypes = {} -- missionId -> type

-- Server-provided mission data (loaded from DB)
local missionsList = {}
local missionsById = {}

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function findNpcById(npcId)
    for _, mission in ipairs(missionsList) do
        if mission.npc and mission.npc.id == npcId then
            return mission.npc, mission
        end
    end
    return nil, nil
end

local function findMissionById(missionId)
    return missionsById[missionId]
end

local function notify(payload)
    pcall(function()
        lib.notify(payload)
    end)
end

local function sendNui(action, data)
    SendNUIMessage(json.encode({ action = action, data = data or {} }))
end

-- ── NPC management ──────────────────────────────────────────────────────────

local function loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do
        Wait(50)
        tries = tries + 1
    end
    return HasModelLoaded(hash)
end

local function openMissionNui(npc, enc)
    SetNuiFocus(true, true)
    trackerVisible = true

    -- Request fresh tracker data
    TriggerServerEvent(ResourceName .. ':tracker:request')

    local npcWithMission = {}
    for k, v in pairs(npc) do npcWithMission[k] = v end
    npcWithMission.missionId = enc.id

    local showPayload = { npc = npcWithMission, mission = enc }

    if not nuiReady then
        sendNui('setVisible', { visible = true })
        pendingMission = { npc = npc, enc = enc }
        -- Delayed attempts in case ready event races
        SetTimeout(150, function()
            sendNui('setVisible', { visible = true })
            sendNui('mission:show', showPayload)
        end)
        SetTimeout(400, function()
            sendNui('setVisible', { visible = true })
            sendNui('mission:show', showPayload)
        end)
        return
    end

    sendNui('setVisible', { visible = true })
    sendNui('mission:show', showPayload)
end

local function createPedForNpc(n, missionId)
    local c = n.coords
    local heading = c.w or n.heading or 0.0
    loadModel(n.model)

    local ped = CreatePed(4, joaat(n.model), c.x, c.y, c.z, heading, false, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    if n.scenario then
        TaskStartScenarioInPlace(ped, n.scenario, 0, true)
    end

    -- ox_target interaction
    local label = (n.target and n.target.label) or ('Talk to ' .. n.id)
    local target = exports.ox_target

    if target then
        pcall(function()
            target:addLocalEntity(ped, {
                {
                    name = ('%s:npc:%s'):format(ResourceName, n.id),
                    icon = (n.target and n.target.icon) or 'fa-solid fa-comments',
                    label = label,
                    distance = 2.0,
                    onSelect = function()
                        local enc = findMissionById(missionId)
                        if not enc then return end

                        -- Check daily limit + prerequisites before opening NUI
                        local result = lib.callback.await(ResourceName .. ':mission:canAccept', false, missionId)
                        if result and not result.allowed then
                            local msg = Config.blockedNpcMessage or "I'm not interested in talking to you."
                            local speechName = n.speech or 'GENERIC_HI'
                            PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force')
                            notify({ title = enc.label or 'Mission', description = msg, type = 'error' })
                            return
                        end

                        local speechName = n.speech or 'GENERIC_HI'
                        PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force')
                        openMissionNui(n, enc)
                    end,
                }
            })
        end)
    end

    -- NPC blip (unified style from config)
    if Config.npcBlips and n.blip ~= false then
        local blip = AddBlipForEntity(ped)
        SetBlipSprite(blip, Config.npcBlipSprite or 280)
        SetBlipColour(blip, Config.npcBlipColor or 29)
        SetBlipScale(blip, Config.npcBlipScale or 0.7)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(label)
        EndTextCommandSetBlipName(blip)
        npcBlips[#npcBlips + 1] = blip
    end

    return ped
end

local function cleanupAllNpcs()
    local target = exports.ox_target

    for id, ped in pairs(npcs) do
        pcall(function()
            if target and DoesEntityExist(ped) then
                target:removeLocalEntity(ped)
            end
        end)
        pcall(function()
            if DoesEntityExist(ped) then
                DeleteEntity(ped)
            end
        end)
        npcs[id] = nil
    end

    for _, b in ipairs(npcBlips) do
        pcall(RemoveBlip, b)
    end
    npcBlips = {}
end

local function spawnAllNpcs()
    cleanupAllNpcs()
    local maxBlips = Config.maxNpcBlips or 10
    local blipCount = 0
    for _, mission in ipairs(missionsList) do
        local n = mission.npc
        if n then
            -- Cap blips: only the first N missions (by sort order) get blips
            local origBlip = n.blip
            if blipCount >= maxBlips then
                n.blip = false
            end
            local ok, ped = pcall(createPedForNpc, n, mission.id)
            n.blip = origBlip -- restore original value
            if ok and ped then
                npcs[n.id] = ped
                if origBlip ~= false and blipCount < maxBlips then
                    blipCount = blipCount + 1
                end
            end
        end
    end
end

-- ── NPC speech helpers ──────────────────────────────────────────────────────

local function playNpcSpeech(npcId, speechType)
    local ped = npcs[npcId]
    if not ped or not DoesEntityExist(ped) then return end
    local npc = findNpcById(npcId)
    if not npc then return end

    local speech
    if speechType == 'bye' then
        speech = npc.speechBye or 'GENERIC_BYE'
    elseif speechType == 'claim' then
        speech = npc.speechClaim or 'GENERIC_THANKS'
    else
        speech = npc.speech or 'GENERIC_HI'
    end
    PlayAmbientSpeech1(ped, speech, 'Speech_Params_Force')
end

-- ── Blip helpers ────────────────────────────────────────────────────────────

local function createMissionBlips(config)
    local location = config.area or config.location
    local label = config.label or 'Mission'
    local sprite = config.sprite or 1
    local color = config.color or 5
    local scale = config.scale or 1.0

    local missionBlip = AddBlipForCoord(location.x, location.y, location.z)
    SetBlipSprite(missionBlip, sprite)
    SetBlipColour(missionBlip, color)
    SetBlipScale(missionBlip, scale)
    SetBlipAsShortRange(missionBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Mission: ' .. label)
    EndTextCommandSetBlipName(missionBlip)

    local result = { missionBlip = missionBlip }

    if config.area and config.radius and config.radius > 0 then
        local areaBlip = AddBlipForRadius(config.area.x, config.area.y, config.area.z, config.radius)
        SetBlipColour(areaBlip, color)
        SetBlipAlpha(areaBlip, 64)
        result.areaBlip = areaBlip
    end

    return result
end

local function removeMissionBlips(blips)
    if not blips then return end
    pcall(function()
        if blips.missionBlip and DoesBlipExist(blips.missionBlip) then
            RemoveBlip(blips.missionBlip)
        end
    end)
    pcall(function()
        if blips.areaBlip and DoesBlipExist(blips.areaBlip) then
            RemoveBlip(blips.areaBlip)
        end
    end)
end

-- Make blip helpers available to mission modules
_G.CreateMissionBlips = createMissionBlips
_G.RemoveMissionBlips = removeMissionBlips

-- ── Mission module orchestration ────────────────────────────────────────────
-- Mission modules are loaded from client/missions/*.lua and register themselves
-- in the global Missions table.

Missions = Missions or {}

local function startMission(missionData)
    local mod = Missions[missionData.type]
    if mod and mod.start then
        mod.start(missionData)
    end
end

local function stopMission(mtype)
    local mod = Missions[mtype]
    if mod and mod.stop then
        pcall(mod.stop)
    end
end

local function stopAllMissions()
    for _, mod in pairs(Missions) do
        if mod.stop then pcall(mod.stop) end
    end
end

local function setMissionProgress(missionId, progress)
    if not progress or not progress.type then return end
    local mod = Missions[progress.type]
    if mod and mod.setProgress then
        pcall(mod.setProgress, progress)
    end
end

-- ── Resource lifecycle ──────────────────────────────────────────────────────

AddEventHandler('onClientResourceStart', function(resName)
    if resName ~= ResourceName then return end
    pcall(SetNuiFocus, false, false)
    trackerVisible = false
    sendNui('tracker:toggle', { visible = false })

    -- Clean up leftovers from a previous session (e.g. /ensure)
    pcall(lib.hideTextUI)

    -- Delete any objects attached to the player ped before clearing tasks
    local ped = cache.ped
    for _, obj in ipairs(GetGamePool('CObject')) do
        if IsEntityAttachedToEntity(obj, ped) then
            DetachEntity(obj, true, true)
            SetEntityAsMissionEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end

    ClearPedTasksImmediately(ped)

    -- Clean up any leftover NPCs; new ones will spawn when server sends missions
    cleanupAllNpcs()

    -- Ask server to restore state + send missions
    SetTimeout(500, function()
        TriggerServerEvent(ResourceName .. ':restore:request')
    end)
end)

AddEventHandler('onClientResourceStop', function(resName)
    if resName ~= ResourceName then return end
    pcall(SetNuiFocus, false, false)
    trackerVisible = false
    sendNui('tracker:toggle', { visible = false })
    cleanupAllNpcs()
    stopAllMissions()
end)

-- Clean up missions on character deselect / logout
if Config.characterDeselectedEvent then
    AddEventHandler(Config.characterDeselectedEvent, function()
        stopAllMissions()
    end)
end

-- ── NUI Callbacks ───────────────────────────────────────────────────────────

RegisterNUICallback('exit', function(data, cb)
    SetNuiFocus(false, false)
    trackerVisible = false
    if data and data.npcId then
        playNpcSpeech(data.npcId, 'bye')
    end
    cb({})
end)

RegisterNUICallback('ui:ready', function(_, cb)
    nuiReady = true
    if pendingMission then
        local npc = pendingMission.npc
        local enc = pendingMission.enc
        local npcWithMission = {}
        for k, v in pairs(npc) do npcWithMission[k] = v end
        npcWithMission.missionId = enc.id
        sendNui('setVisible', { visible = true })
        sendNui('mission:show', { npc = npcWithMission, mission = enc })
        pendingMission = nil
    end
    cb({ ok = true })
end)

RegisterNUICallback('mission:accept', function(data, cb)
    SetNuiFocus(false, false)
    trackerVisible = false
    if data.npcId then playNpcSpeech(data.npcId, 'bye') end
    if not npcs[data.npcId] then return cb({ ok = false, reason = 'npc_missing' }) end
    TriggerServerEvent(ResourceName .. ':mission:accept', data)
    cb({ ok = true })
end)

RegisterNUICallback('mission:reject', function(data, cb)
    SetNuiFocus(false, false)
    trackerVisible = false
    if data and data.npcId then playNpcSpeech(data.npcId, 'bye') end
    cb({ ok = true })
end)

RegisterNUICallback('mission:cancel', function(data, cb)
    SetNuiFocus(false, false)
    trackerVisible = false
    if data and data.npcId then playNpcSpeech(data.npcId, 'bye') end
    if data and data.missionId then
        TriggerServerEvent(ResourceName .. ':mission:cancel', { missionId = data.missionId })
    end
    cb({ ok = true })
end)

RegisterNUICallback('panel:getVisible', function(_, cb)
    cb({ visible = trackerVisible })
end)

RegisterNUICallback('focus:set', function(data, cb)
    pcall(SetNuiFocus, not not data.hasFocus, not not data.hasCursor)
    trackerVisible = not not data.hasFocus
    cb({ ok = true })
end)

RegisterNUICallback('tracker:request', function(_, cb)
    TriggerServerEvent(ResourceName .. ':tracker:request')
    cb({ ok = true })
end)

RegisterNUICallback('mission:waypoint', function(data, cb)
    pcall(SetNuiFocus, false, false)
    if data and data.missionId then
        local mission = findMissionById(data.missionId)
        if mission and mission.npc and mission.npc.coords then
            local x, y = mission.npc.coords.x, mission.npc.coords.y
            pcall(SetNewWaypoint, x, y)
            -- Temporary blip
            pcall(function()
                local temp = AddBlipForCoord(x, y, mission.npc.coords.z or 0.0)
                SetBlipSprite(temp, 280)
                SetBlipColour(temp, 0)
                SetBlipScale(temp, 0.8)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString((mission.npc.target and mission.npc.target.label) or mission.npc.id)
                EndTextCommandSetBlipName(temp)
                SetTimeout(6000, function()
                    pcall(RemoveBlip, temp)
                end)
            end)
        end
    elseif data and data.x and data.y then
        pcall(SetNewWaypoint, data.x, data.y)
    end
    cb({ ok = true })
end)

RegisterNUICallback('mission:claim', function(data, cb)
    pcall(SetNuiFocus, false, false)
    if data and data.missionId and data.npcId then
        playNpcSpeech(data.npcId, 'claim')
        SetTimeout(1500, function()
            playNpcSpeech(data.npcId, 'bye')
        end)
        TriggerServerEvent(ResourceName .. ':mission:claim', { missionId = data.missionId, npcId = data.npcId })
    end
    cb({ ok = true })
end)

RegisterNUICallback('tracker:exit', function(data, cb)
    trackerVisible = false
    pcall(SetNuiFocus, false, false)
    if data and data.npcId then playNpcSpeech(data.npcId, 'bye') end
    sendNui('tracker:toggle', { visible = false })
    cb({ ok = true })
end)

-- ── Dev command ─────────────────────────────────────────────────────────────

if Config.EnableNuiCommand then
    RegisterNetEvent(ResourceName .. ':openNui')
    AddEventHandler(ResourceName .. ':openNui', function()
        SetNuiFocus(true, true)
        sendNui('setVisible', { visible = true })
    end)

    RegisterCommand('missions_testui', function()
        local npc = { id = 'test', target = { label = 'Test Giver' } }
        local enc = { id = 'test_enc', label = 'Test Mission', description = 'Debug modal render', reward = { cash = 1 } }
        openMissionNui(npc, enc)
    end, false)
end

-- Toggle tracker UI (always available)
RegisterCommand('missions', function()
    sendNui('tracker:toggle', {})
end, false)

-- Default keybind
pcall(RegisterKeyMapping, 'missions', 'Toggle Missions Tracker', 'keyboard', 'F6')

-- ── Server event handlers ───────────────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':mission:start')
AddEventHandler(ResourceName .. ':mission:start', function(data)
    -- Restore progress if provided
    if data.progress then
        pcall(setMissionProgress, data.mission.id, data.progress)
    end
    activeMissions[data.mission.id] = { npcId = data.npcId, status = 'in-progress', type = data.mission.type }
    missionTypes[data.mission.id] = data.mission.type
    startMission(data.mission)
end)

RegisterNetEvent(ResourceName .. ':mission:return')
AddEventHandler(ResourceName .. ':mission:return', function(data)
    claimableMissions[data.missionId] = true
    local t = missionTypes[data.missionId]
    activeMissions[data.missionId] = { npcId = data.npcId, status = 'complete', type = t }

    local mission = findMissionById(data.missionId)
    local missionTitle = mission and mission.label or 'Mission'

    notify({ title = missionTitle, description = 'You did it! Return to claim your reward.', type = 'success', duration = 10000 })

    if mission and mission.npc and mission.npc.coords then
        pcall(SetNewWaypoint, mission.npc.coords.x, mission.npc.coords.y)
    end
end)

RegisterNetEvent(ResourceName .. ':mission:claimed')
AddEventHandler(ResourceName .. ':mission:claimed', function(data)
    claimableMissions[data.missionId] = nil
    activeMissions[data.missionId] = nil
    if trackerVisible then
        TriggerServerEvent(ResourceName .. ':tracker:request')
    end
end)

RegisterNetEvent(ResourceName .. ':mission:cooldown')
AddEventHandler(ResourceName .. ':mission:cooldown', function(data)
    local mins = math.ceil(data.seconds / 60)
    notify({ title = 'Mission', description = ('On cooldown (%d min)'):format(mins), type = 'error' })
    if trackerVisible then
        TriggerServerEvent(ResourceName .. ':tracker:request')
    end
end)

RegisterNetEvent(ResourceName .. ':mission:busy')
AddEventHandler(ResourceName .. ':mission:busy', function(data)
    local status = data.status == 'complete' and 'ready to turn in' or 'in progress'
    notify({ title = 'Mission', description = ('You already have a mission %s.'):format(status), type = 'error', duration = 10000 })
end)

RegisterNetEvent(ResourceName .. ':mission:blocked')
AddEventHandler(ResourceName .. ':mission:blocked', function(data)
    local msg = Config.blockedNpcMessage or "I'm not interested in talking to you."
    notify({ title = 'Mission', description = msg, type = 'error' })
end)

RegisterNetEvent(ResourceName .. ':mission:cancelled')
AddEventHandler(ResourceName .. ':mission:cancelled', function(data)
    local t = missionTypes[data.missionId]
    if t then
        stopMission(t)
    else
        stopAllMissions()
    end

    claimableMissions[data.missionId] = nil
    activeMissions[data.missionId] = nil
    missionTypes[data.missionId] = nil

    local msg = data.appliedCooldown and 'You cancelled the mission.' or 'Mission cancelled.'
    notify({ title = 'Mission', description = msg, type = 'warning', duration = 10000 })

    if trackerVisible then
        TriggerServerEvent(ResourceName .. ':tracker:request')
    end
end)

RegisterNetEvent(ResourceName .. ':tracker:data')
AddEventHandler(ResourceName .. ':tracker:data', function(data)
    sendNui('tracker:data', data)
end)

-- Receive mission definitions from server (loaded from DB)
RegisterNetEvent(ResourceName .. ':missions:load')
AddEventHandler(ResourceName .. ':missions:load', function(data)
    missionsList = data or {}
    missionsById = {}
    for _, enc in ipairs(missionsList) do
        missionsById[enc.id] = enc
    end
    spawnAllNpcs()
end)

-- ── Admin: mission creator ──────────────────────────────────────────────────

local adminMode = false
local placingEntity = nil
local placingField = nil
local placingHeading = 0.0
local placingType = nil -- 'ped' or 'prop'

RegisterCommand('missionadmin', function()
    lib.callback(ResourceName .. ':admin:checkPermission', false, function(allowed)
        if not allowed then
            notify({ title = 'Mission Admin', description = 'You do not have permission.', type = 'error' })
            return
        end
        adminMode = true
        SetNuiFocus(true, true)
        sendNui('admin:open', {})
    end)
end, false)

RegisterNUICallback('admin:close', function(_, cb)
    adminMode = false
    SetNuiFocus(false, false)
    sendNui('admin:closed', {})
    cb({ ok = true })
end)

local speechPreviewPed = nil

RegisterNUICallback('admin:previewSpeech', function(data, cb)
    cb({ ok = true })
    local speech = data.speech
    local model = data.model
    if not speech or speech == '' or not model or model == '' then return end

    -- Immediately clean up any existing preview ped
    if speechPreviewPed and DoesEntityExist(speechPreviewPed) then
        DeleteEntity(speechPreviewPed)
        speechPreviewPed = nil
    end

    CreateThread(function()
        local hash = joaat(model)
        if not IsModelInCdimage(hash) then
            notify({ type = 'error', description = 'Invalid NPC model: ' .. model })
            return
        end

        lib.requestModel(hash)
        local playerPos = GetEntityCoords(cache.ped)
        local camRot = GetGameplayCamRot(2)
        local rad = math.rad(camRot.z)
        local fwd = vector3(-math.sin(rad), math.cos(rad), 0.0)
        local spawnPos = playerPos + fwd * 1.5
        local heading = (camRot.z + 180.0) % 360.0
        local ped = CreatePed(4, hash, spawnPos.x, spawnPos.y, spawnPos.z, heading, false, false)
        SetModelAsNoLongerNeeded(hash)

        if not ped or ped == 0 then return end

        speechPreviewPed = ped
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityCollision(ped, false, false)

        Wait(100)
        PlayAmbientSpeech1(ped, speech, 'Speech_Params_Force')
        Wait(3000)

        if speechPreviewPed == ped and DoesEntityExist(ped) then
            DeleteEntity(ped)
            speechPreviewPed = nil
        end
    end)
end)

RegisterNUICallback('admin:getMissions', function(data, cb)
    lib.callback(ResourceName .. ':admin:getMissions', false, function(result)
        cb(result or { missions = {}, total = 0 })
    end, data)
end)

RegisterNUICallback('admin:saveMission', function(data, cb)
    lib.callback(ResourceName .. ':admin:saveMission', false, function(result)
        cb(result or { ok = false })
    end, data)
end)

RegisterNUICallback('admin:deleteMission', function(data, cb)
    lib.callback(ResourceName .. ':admin:deleteMission', false, function(result)
        cb({ ok = result == true })
    end, data)
end)

-- ── Placement tool: camera raycast with preview entity ──────────────────────

local function cleanupPlacement()
    pcall(lib.hideTextUI)
    if placingEntity and DoesEntityExist(placingEntity) then
        DeleteEntity(placingEntity)
    end
    placingEntity = nil
    placingField = nil
    placingType = nil
    placingHeading = 0.0
end

local function screenToWorld(distance)
    local camRot = GetGameplayCamRot(2)
    local camPos = GetGameplayCamCoord()

    local rX = math.rad(camRot.x)
    local rZ = math.rad(camRot.z)

    local dX = -math.sin(rZ) * math.abs(math.cos(rX))
    local dY =  math.cos(rZ) * math.abs(math.cos(rX))
    local dZ =  math.sin(rX)

    local dest = vector3(
        camPos.x + dX * distance,
        camPos.y + dY * distance,
        camPos.z + dZ * distance
    )
    return camPos, dest
end

local function doRaycast()
    local origin, target = screenToWorld(100.0)
    local ray = StartShapeTestLosProbe(origin.x, origin.y, origin.z, target.x, target.y, target.z, 1 + 16, cache.ped, 7)
    -- Must wait a frame for the shape test to complete
    local result, hit, endCoords, surfaceNormal, entityHit
    repeat
        Wait(0)
        result, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(ray)
    until result ~= 1 -- 1 = pending, 2 = complete
    return hit == 1, endCoords, surfaceNormal, entityHit
end

RegisterNUICallback('admin:notify', function(data, cb)
    notify(data)
    cb({ ok = true })
end)

RegisterNUICallback('admin:startPlacement', function(data, cb)
    -- Clean up any existing placement
    cleanupPlacement()

    local modelName = data.model
    local field = data.field
    local entityType = data.entityType or 'prop' -- 'ped' or 'prop'

    if not modelName or modelName == '' then
        cb({ ok = false, reason = 'no_model' })
        return
    end

    local hash = type(modelName) == 'string' and joaat(modelName) or modelName
    if not IsModelInCdimage(hash) then
        notify({ type = 'error', description = 'Invalid model: ' .. tostring(modelName) })
        cb({ ok = false, reason = 'invalid_model' })
        return
    end

    -- Hide NUI focus so player can look around
    SetNuiFocus(false, false)

    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do
        Wait(50)
        tries = tries + 1
    end

    if not HasModelLoaded(hash) then
        SetNuiFocus(true, true)
        cb({ ok = false, reason = 'model_not_found' })
        return
    end

    local playerPos = GetEntityCoords(cache.ped)
    placingHeading = 0.0
    placingField = field
    placingType = entityType

    if entityType == 'ped' then
        placingEntity = CreatePed(4, hash, playerPos.x, playerPos.y, playerPos.z, 0.0, false, false)
    else
        placingEntity = CreateObject(hash, playerPos.x, playerPos.y, playerPos.z, false, false, false)
    end

    if not placingEntity or not DoesEntityExist(placingEntity) then
        SetNuiFocus(true, true)
        cb({ ok = false, reason = 'spawn_failed' })
        return
    end

    -- Configure preview entity
    SetEntityAlpha(placingEntity, 150, false)
    SetEntityCollision(placingEntity, false, false)
    SetEntityInvincible(placingEntity, true)

    if entityType == 'ped' then
        SetBlockingOfNonTemporaryEvents(placingEntity, true)
        FreezeEntityPosition(placingEntity, true)
    end

    lib.showTextUI('[E] Place  [Scroll] Rotate  [Backspace] Cancel', { position = 'top-center' })

    cb({ ok = true })

    -- Placement loop
    CreateThread(function()
        while placingEntity and DoesEntityExist(placingEntity) do
            -- Check controls FIRST (before raycast) so scroll/key events are
            -- never missed due to the raycast yielding a frame internally.

            -- Suppress weapon wheel so scroll events reach us
            DisableControlAction(0, 14, true)  -- next weapon
            DisableControlAction(0, 15, true)  -- prev weapon
            DisableControlAction(0, 16, true)  -- select next weapon
            DisableControlAction(0, 17, true)  -- select prev weapon

            -- Scroll wheel to rotate
            if IsDisabledControlJustPressed(0, 15) then -- scroll up
                placingHeading = (placingHeading + 15.0) % 360.0
            end
            if IsDisabledControlJustPressed(0, 14) then -- scroll down
                placingHeading = (placingHeading - 15.0 + 360.0) % 360.0
            end

            -- E to confirm
            if IsControlJustPressed(0, 38) then
                local finalCoords = GetEntityCoords(placingEntity)
                local finalHead = GetEntityHeading(placingEntity)
                local capturedField = placingField
                local capturedType = placingType
                cleanupPlacement()
                SetNuiFocus(true, true)
                sendNui('admin:positionCaptured', {
                    field = capturedField,
                    entityType = capturedType,
                    x = math.floor(finalCoords.x * 100) / 100,
                    y = math.floor(finalCoords.y * 100) / 100,
                    z = math.floor(finalCoords.z * 100) / 100,
                    heading = math.floor(finalHead * 100) / 100,
                })
                return
            end

            -- Backspace to cancel
            if IsControlJustPressed(0, 177) then
                cleanupPlacement()
                SetNuiFocus(true, true)
                sendNui('admin:placementCancelled', { field = placingField })
                return
            end

            -- Raycast to find ground position (yields at least one frame internally)
            local hit, coords = doRaycast()

            if hit then
                -- Ground snap: PlaceObjectOnGroundProperly works for both props
                -- and peds — more reliable than GetGroundZFor_3dCoord which can
                -- return stale results when terrain isn't loaded yet.
                SetEntityCoordsNoOffset(placingEntity, coords.x, coords.y, coords.z, false, false, false)
                PlaceObjectOnGroundProperly(placingEntity)
                SetEntityHeading(placingEntity, placingHeading)
            end
            -- No trailing Wait(0) needed: doRaycast already yields a frame.
        end
    end)
end)

-- Clean up placement if resource stops
AddEventHandler('onClientResourceStop', function(resName)
    if resName ~= ResourceName then return end
    cleanupPlacement()
end)

-- ── Prop position adjustment (bone-local) ───────────────────────────────────

local CARRY_PRESETS = {
    both_hands = {
        dict = 'anim@heists@box_carry@',
        anim = 'idle',
        bone = 60309,
        pos = vec3(0.025, 0.08, 0.255),
        rot = vec3(-145.0, 290.0, 0.0),
    },
    right_hand = {
        dict = 'anim@heists@narcotics@trash',
        anim = 'idle',
        bone = 28422,
        pos = vec3(0.11, -0.21, -0.43),
        rot = vec3(-11.9, 0.0, 30.0),
    },
}

RegisterNUICallback('admin:startPropAdjust', function(data, cb)
    local propModel = data.prop
    local carryStyle = data.carry or 'both_hands'
    local preset = CARRY_PRESETS[carryStyle]

    if not propModel or propModel == '' or not preset then
        cb({ ok = false, reason = 'invalid_params' })
        return
    end

    local propHash = joaat(propModel)
    if not IsModelInCdimage(propHash) then
        notify({ type = 'error', description = 'Invalid prop model: ' .. tostring(propModel) })
        cb({ ok = false, reason = 'invalid_model' })
        return
    end

    SetNuiFocus(false, false)
    cb({ ok = true })

    CreateThread(function()
        local ped = cache.ped
        local propHash = joaat(propModel)
        local pedModel = GetEntityModel(ped)

        lib.requestAnimDict(preset.dict)
        lib.requestModel(propHash)
        lib.requestModel(pedModel)

        -- Use camera heading so clone spawns where the player is looking
        local pedCoords = GetEntityCoords(ped)
        local camRot = GetGameplayCamRot(2)
        local camYaw = camRot.z
        local rad = math.rad(camYaw)
        local fwd = vector3(-math.sin(rad), math.cos(rad), 0.0)
        local clonePos = pedCoords + fwd * 1.5
        local cloneHeading = (camYaw + 180.0) % 360.0

        local clone = CreatePed(4, pedModel, clonePos.x, clonePos.y, clonePos.z, cloneHeading, false, false)
        SetModelAsNoLongerNeeded(pedModel)

        if not clone or clone == 0 then
            SetNuiFocus(true, true)
            sendNui('admin:propAdjustCancelled', {})
            return
        end

        SetEntityHeading(clone, cloneHeading)
        Wait(50)

        FreezeEntityPosition(clone, true)
        SetEntityInvincible(clone, true)
        SetBlockingOfNonTemporaryEvents(clone, true)
        SetPedCanRagdoll(clone, false)

        -- Play carry animation on clone
        TaskPlayAnim(clone, preset.dict, preset.anim, 5.0, 5.0, -1, 51, 0, false, false, false)
        RemoveAnimDict(preset.dict)
        Wait(200)

        -- Spawn prop
        local obj = CreateObject(propHash, clonePos.x, clonePos.y, clonePos.z + 0.2, false, true, false)
        SetModelAsNoLongerNeeded(propHash)

        if not obj or obj == 0 then
            DeleteEntity(clone)
            SetNuiFocus(true, true)
            sendNui('admin:propAdjustCancelled', {})
            return
        end

        local boneIdx = GetPedBoneIndex(clone, preset.bone)

        -- Initialize bone-local offsets from saved values or preset defaults
        local posX = data.propOffset and data.propOffset.x or preset.pos.x
        local posY = data.propOffset and data.propOffset.y or preset.pos.y
        local posZ = data.propOffset and data.propOffset.z or preset.pos.z
        local rotX = data.propRotation and data.propRotation.x or preset.rot.x
        local rotY = data.propRotation and data.propRotation.y or preset.rot.y
        local rotZ = data.propRotation and data.propRotation.z or preset.rot.z

        -- Initial attach (identical call to delivery.lua startCarry)
        AttachEntityToEntity(obj, clone, boneIdx,
            posX, posY, posZ, rotX, rotY, rotZ,
            true, true, false, true, 1, true)

        -- Probe bone axes: measure how each bone-local axis maps to world space
        -- This lets us convert world-relative input into bone-local deltas
        Wait(0)
        local eps = 0.1
        local basePos = GetEntityCoords(obj)

        local function probeAxis(dx, dy, dz)
            AttachEntityToEntity(obj, clone, boneIdx,
                posX + dx, posY + dy, posZ + dz, rotX, rotY, rotZ,
                true, true, false, true, 1, true)
            Wait(0)
            local p = GetEntityCoords(obj)
            local d = p - basePos
            local len = #d
            if len < 0.001 then return vector3(dx, dy, dz) end -- fallback to identity
            return d / len
        end

        local boneAxisX = probeAxis(eps, 0.0, 0.0)
        local boneAxisY = probeAxis(0.0, eps, 0.0)
        local boneAxisZ = probeAxis(0.0, 0.0, eps)

        -- Restore original attachment
        AttachEntityToEntity(obj, clone, boneIdx,
            posX, posY, posZ, rotX, rotY, rotZ,
            true, true, false, true, 1, true)

        local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

        -- Compute clone-relative directions (fixed for entire session since clone is frozen)
        local cloneYaw = math.rad(GetEntityHeading(clone))
        local cloneFwd = vector3(-math.sin(cloneYaw), math.cos(cloneYaw), 0.0)
        local cloneRight = vector3(math.cos(cloneYaw), math.sin(cloneYaw), 0.0)
        local worldUp = vector3(0.0, 0.0, 1.0)

        -- Hide admin panel
        sendNui('admin:gizmoMode', { active = true })
        Wait(50)

        local adjusting = true
        local rotMode = false -- false = position mode, true = rotation mode
        local lastTextUI = ''

        local function r3(v) return math.floor(v * 1000 + 0.5) / 1000 end

        while adjusting do
            Wait(0)

            -- Disable ALL controls, then re-enable movement + camera only
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)   -- LookLeftRight
            EnableControlAction(0, 2, true)   -- LookUpDown
            EnableControlAction(0, 30, true)  -- MoveLeftRight
            EnableControlAction(0, 31, true)  -- MoveUpDown
            EnableControlAction(0, 32, true)  -- MoveUpOnly
            EnableControlAction(0, 33, true)  -- MoveDownOnly
            EnableControlAction(0, 34, true)  -- MoveLeftOnly
            EnableControlAction(0, 35, true)  -- MoveRightOnly

            -- Shift = fine mode (Disabled variant since all controls are disabled)
            local fine = IsDisabledControlPressed(0, 21)
            local posStep = fine and 0.005 or 0.02
            local rotStep = fine and 1.0 or 5.0

            -- R = toggle position / rotation mode
            if IsDisabledControlJustPressed(0, 45) then
                rotMode = not rotMode
            end

            local changed = false

            if rotMode then
                -- Rotation mode: directly modify one bone-local axis at a time
                if IsDisabledControlJustPressed(0, 175) then rotZ = rotZ + rotStep; changed = true end      -- Right = yaw clockwise
                if IsDisabledControlJustPressed(0, 174) then rotZ = rotZ - rotStep; changed = true end      -- Left = yaw counter-clockwise
                if IsDisabledControlJustPressed(0, 172) then rotX = rotX + rotStep; changed = true end      -- Up = pitch forward
                if IsDisabledControlJustPressed(0, 173) then rotX = rotX - rotStep; changed = true end      -- Down = pitch backward
                if IsDisabledControlJustPressed(0, 15) then rotY = rotY + rotStep; changed = true end       -- Scroll up = roll right
                if IsDisabledControlJustPressed(0, 14) then rotY = rotY - rotStep; changed = true end       -- Scroll down = roll left
            else
                -- Position mode: clone-relative input converted to bone-local deltas
                local worldDelta = vector3(0.0, 0.0, 0.0)
                if IsDisabledControlJustPressed(0, 175) then worldDelta = cloneRight * posStep; changed = true end     -- Right arrow = clone's right
                if IsDisabledControlJustPressed(0, 174) then worldDelta = -cloneRight * posStep; changed = true end    -- Left arrow = clone's left
                if IsDisabledControlJustPressed(0, 172) then worldDelta = cloneFwd * posStep; changed = true end       -- Up arrow = clone's forward
                if IsDisabledControlJustPressed(0, 173) then worldDelta = -cloneFwd * posStep; changed = true end      -- Down arrow = clone's backward
                if IsDisabledControlJustPressed(0, 15) then worldDelta = worldUp * posStep; changed = true end         -- Scroll up = raise
                if IsDisabledControlJustPressed(0, 14) then worldDelta = -worldUp * posStep; changed = true end        -- Scroll down = lower

                if changed then
                    posX = posX + dot(worldDelta, boneAxisX)
                    posY = posY + dot(worldDelta, boneAxisY)
                    posZ = posZ + dot(worldDelta, boneAxisZ)
                end
            end

            -- Re-attach prop with updated offsets (same call as delivery.lua)
            if changed then
                AttachEntityToEntity(obj, clone, boneIdx,
                    posX, posY, posZ, rotX, rotY, rotZ,
                    true, true, false, true, 1, true)
            end

            -- Update textUI with live values
            local modeStr = rotMode and 'ROTATION' or 'POSITION'
            local text = ('[%s]  Pos: %.3f, %.3f, %.3f  |  Rot: %.1f, %.1f, %.1f\n[Arrows] %s  [Scroll] %s  [R] Mode  [Shift] Fine  [E] Save  [Backspace] Cancel'):format(
                modeStr, posX, posY, posZ, rotX, rotY, rotZ,
                rotMode and 'Rotation' or 'Position',
                rotMode and 'Roll' or 'Height')

            if text ~= lastTextUI then
                lastTextUI = text
                lib.showTextUI(text, { position = 'top-center' })
            end

            -- E = confirm
            if IsDisabledControlJustPressed(0, 38) then
                adjusting = false
                pcall(lib.hideTextUI)

                if DoesEntityExist(obj) then
                    SetEntityAsMissionEntity(obj, true, true)
                    DeleteEntity(obj)
                end
                if DoesEntityExist(clone) then DeleteEntity(clone) end

                SetNuiFocus(true, true)
                Wait(100)
                sendNui('admin:gizmoMode', { active = false })
                sendNui('admin:propAdjusted', {
                    propOffset = { x = r3(posX), y = r3(posY), z = r3(posZ) },
                    propRotation = { x = r3(rotX), y = r3(rotY), z = r3(rotZ) },
                })
                return
            end

            -- Backspace = cancel
            if IsDisabledControlJustPressed(0, 177) then
                adjusting = false
                pcall(lib.hideTextUI)

                if DoesEntityExist(obj) then
                    SetEntityAsMissionEntity(obj, true, true)
                    DeleteEntity(obj)
                end
                if DoesEntityExist(clone) then DeleteEntity(clone) end

                SetNuiFocus(true, true)
                Wait(100)
                sendNui('admin:gizmoMode', { active = false })
                sendNui('admin:propAdjustCancelled', {})
                return
            end
        end
    end)
end)
