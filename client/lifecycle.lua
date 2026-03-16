-- Client-side state, orchestration, resource lifecycle, dev commands

-- ── State variables (namespaced for cross-file access) ──────────────────────

Client.npcs = {}            -- npcId -> ped handle
Client.npcBlips = {}
Client.nuiReady = false
Client.pendingMission = nil -- { npc, enc }
Client.trackerVisible = false

Client.claimableMissions = {}
Client.activeMissions = {}  -- missionId -> { npcId, status, type }
Client.missionTypes = {}    -- missionId -> type

-- Server-provided mission data (loaded from DB)
Client.missionsList = {}
Client.missionsById = {}

-- ── Find helpers ────────────────────────────────────────────────────────────

function Client.findNpcById(npcId)
    for _, mission in ipairs(Client.missionsList) do
        if mission.npc and mission.npc.id == npcId then
            return mission.npc, mission
        end
    end
    return nil, nil
end

function Client.findMissionById(missionId)
    return Client.missionsById[missionId]
end

-- ── Mission module orchestration ────────────────────────────────────────────

Missions = Missions or {}

function Client.startMission(missionData)
    local mod = Missions[missionData.type]
    if mod and mod.start then
        mod.start(missionData)
    end
end

function Client.stopMission(mtype)
    local mod = Missions[mtype]
    if mod and mod.stop then
        pcall(mod.stop)
    end
end

function Client.stopAllMissions()
    for _, mod in pairs(Missions) do
        if mod.stop then pcall(mod.stop) end
    end
end

function Client.setMissionProgress(missionId, progress)
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
    Client.trackerVisible = false
    Client.sendNui('tracker:toggle', { visible = false })

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
    Client.cleanupAllNpcs()

    -- Ask server to restore state + send missions
    SetTimeout(500, function()
        TriggerServerEvent(ResourceName .. ':restore:request')
    end)
end)

AddEventHandler('onClientResourceStop', function(resName)
    if resName ~= ResourceName then return end
    pcall(SetNuiFocus, false, false)
    Client.trackerVisible = false
    Client.sendNui('tracker:toggle', { visible = false })
    Client.cleanupAllNpcs()
    Client.stopAllMissions()
end)

-- Clean up missions on character deselect / logout
if Config.characterDeselectedEvent then
    AddEventHandler(Config.characterDeselectedEvent, function()
        Client.stopAllMissions()
    end)
end

-- ── Dev commands ────────────────────────────────────────────────────────────

if Config.EnableNuiCommand then
    RegisterNetEvent(ResourceName .. ':openNui')
    AddEventHandler(ResourceName .. ':openNui', function()
        SetNuiFocus(true, true)
        Client.sendNui('setVisible', { visible = true })
    end)

    RegisterCommand('missions_testui', function()
        local npc = { id = 'test', target = { label = 'Test Giver' } }
        local enc = { id = 'test_enc', label = 'Test Mission', description = 'Debug modal render', reward = { cash = 1 } }
        Client.openMissionNui(npc, enc)
    end, false)
end

-- Toggle tracker UI (always available)
RegisterCommand(Config.commands.missions, function()
    Client.sendNui('tracker:toggle', {})
end, false)

-- Default keybind
pcall(RegisterKeyMapping, Config.commands.missions, Config.keybindDescription, 'keyboard', Config.keybind)
