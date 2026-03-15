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
                        local speechName = n.speech or 'GENERIC_HI'
                        PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force')
                        openMissionNui(n, enc)
                    end,
                }
            })
        end)
    end

    -- NPC blip
    if Config.npcBlips and n.blip then
        local blip = AddBlipForEntity(ped)
        SetBlipSprite(blip, n.blip.sprite or 280)
        SetBlipColour(blip, n.blip.color or 0)
        SetBlipScale(blip, n.blip.scale or 0.8)
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
    for _, mission in ipairs(missionsList) do
        local n = mission.npc
        if n then
            local ok, ped = pcall(createPedForNpc, n, mission.id)
            if ok and ped then
                npcs[n.id] = ped
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
