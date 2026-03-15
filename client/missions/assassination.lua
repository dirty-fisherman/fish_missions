-- Assassination mission module: zone-based networked ped spawning, combat, completion

Missions = Missions or {}

local pedNetIds = {}     -- ordered netIds from server coordination
local pedHandles = {}    -- [index] = local entity handle
local missionBlips = nil
local activeZone = nil
local activeMission = nil
local monitoring = false
local pedsSpawned = false

local function loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 200 do
        Wait(25)
        tries = tries + 1
    end
    return HasModelLoaded(hash)
end

--- Calculate center and bounding radius from target positions.
local function calculateZone(targets)
    local cx, cy, cz = 0, 0, 0
    local n = #targets
    for _, t in ipairs(targets) do
        cx = cx + t.coords.x
        cy = cy + t.coords.y
        cz = cz + t.coords.z
    end
    local center = vec3(cx / n, cy / n, cz / n)

    local maxDist = 0
    for _, t in ipairs(targets) do
        local dist = #(center - vec3(t.coords.x, t.coords.y, t.coords.z))
        if dist > maxDist then maxDist = dist end
    end

    return center, math.max(50.0, maxDist + 30.0)
end

--- Spawn all target peds locally and return their network IDs.
local function spawnTargetPeds(mission)
    local targets = mission.params.targets
    local netIds = {}

    for i, target in ipairs(targets) do
        loadModel(target.model)

        local c = target.coords
        local ped = CreatePed(4, joaat(target.model), c.x, c.y, c.z, c.w or 0.0, true, true)

        if DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            SetPedCanBeTargetted(ped, true)
            SetPedCanRagdoll(ped, true)
            SetPedDropsWeaponsWhenDead(ped, false)
            SetPedDiesWhenInjured(ped, false)

            -- Combat attributes: always fight, never flee
            SetPedCombatAttributes(ped, 46, true) -- CanFightArmedPedsWhenNotArmed
            SetPedCombatAttributes(ped, 5, true)  -- AlwaysFight
            SetPedFleeAttributes(ped, 0, false)
            SetEntityHealth(ped, 200)
            SetPedArmour(ped, 0)

            -- Weapon
            if target.weapon and target.weapon ~= 'unarmed' then
                GiveWeaponToPed(ped, joaat(target.weapon), 250, false, true)
                SetCurrentPedWeapon(ped, joaat(target.weapon), true)
            end

            -- Idle scenario
            if target.scenario then
                TaskStartScenarioInPlace(ped, target.scenario, 0, true)
            end

            pedHandles[i] = ped
            netIds[i] = NetworkGetNetworkIdFromEntity(ped)
        end
    end

    return netIds
end

--- Resolve network IDs to local entity handles.
local function resolvePedNetIds(netIds)
    pedNetIds = netIds
    for i, netId in ipairs(netIds) do
        local ped = NetworkGetEntityFromNetworkId(netId)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            pedHandles[i] = ped
        end
    end
end

--- Make NPCs attack the local player via TaskCombatPed.
local function triggerAggro()
    local playerPed = cache.ped
    for _, ped in pairs(pedHandles) do
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            ClearPedTasks(ped)
            TaskCombatPed(ped, playerPed, 0, 16)
        end
    end
end

--- Request spawn coordination from server and spawn/resolve peds.
local function requestAndSpawnPeds(mission)
    if pedsSpawned then return true end

    local maxRetries = 10
    for _ = 1, maxRetries do
        local result = lib.callback.await(ResourceName .. ':assassination:requestSpawn', false, mission.id)

        if result.status == 'spawn' then
            -- We are the spawner
            local netIds = spawnTargetPeds(mission)
            pedNetIds = netIds
            TriggerServerEvent(ResourceName .. ':assassination:pedsSpawned', mission.id, netIds)
            pedsSpawned = true
            return true

        elseif result.status == 'ready' then
            -- Peds already exist, resolve handles
            resolvePedNetIds(result.netIds)
            pedsSpawned = true
            return true

        elseif result.status == 'wait' then
            -- Another player is currently spawning, retry
            Wait(500)
        end
    end

    return false
end

--- Monitor all peds for death via netIds for robustness across ownership changes.
local function startMonitoring(mission)
    if monitoring then return end
    monitoring = true

    CreateThread(function()
        while monitoring and activeMission do
            Wait(500)

            local allDead = true
            local allResolved = true

            for i, netId in ipairs(pedNetIds) do
                local ped = NetworkGetEntityFromNetworkId(netId)
                if ped and ped ~= 0 and DoesEntityExist(ped) then
                    pedHandles[i] = ped
                    if not IsEntityDead(ped) and not IsPedFatallyInjured(ped) then
                        allDead = false
                    end
                else
                    -- Can't resolve — out of scope or deleted
                    allResolved = false
                    allDead = false
                end
            end

            if allResolved and allDead and #pedNetIds > 0 then
                monitoring = false

                RemoveMissionBlips(missionBlips)
                missionBlips = nil

                if activeZone then
                    activeZone:remove()
                    activeZone = nil
                end

                TriggerServerEvent(ResourceName .. ':assassination:pedsCleared', mission.id)
                TriggerServerEvent(ResourceName .. ':mission:complete', { missionId = mission.id })
                activeMission = nil
            end
        end
    end)
end

local function start(mission)
    -- Use local config for proper vector types (network serialization strips them)
    for _, enc in ipairs(Config.missions) do
        if enc.id == mission.id then
            mission = enc
            break
        end
    end

    local targets = mission.params.targets
    if not targets or #targets == 0 then return end

    activeMission = mission
    local center, radius = calculateZone(targets)

    -- Create blips
    if mission.params.blip then
        missionBlips = CreateMissionBlips({
            location = center,
            label = mission.label,
            area = center,
            radius = radius,
        })
    end

    -- Create zone for proximity-based spawning
    activeZone = lib.zones.sphere({
        coords = center,
        radius = radius,
        onEnter = function()
            if not activeMission then return end
            if requestAndSpawnPeds(activeMission) then
                if activeMission.params.aggressive then
                    triggerAggro()
                end
                startMonitoring(activeMission)
            end
        end,
        onExit = function()
            -- Don't despawn — peds persist for combat and other players
        end,
    })

    -- If player is already inside the zone, spawn immediately
    if #(GetEntityCoords(cache.ped) - center) < radius then
        if requestAndSpawnPeds(mission) then
            if mission.params.aggressive then
                triggerAggro()
            end
            startMonitoring(mission)
        end
    end
end

local function stop()
    monitoring = false

    if activeZone then
        activeZone:remove()
        activeZone = nil
    end

    RemoveMissionBlips(missionBlips)
    missionBlips = nil

    -- Don't delete networked peds — other players may be fighting them
    -- FiveM entity management will clean them up when no player is in scope

    pedNetIds = {}
    pedHandles = {}
    activeMission = nil
    pedsSpawned = false
end

Missions.assassination = {
    start = start,
    stop = stop,
}
