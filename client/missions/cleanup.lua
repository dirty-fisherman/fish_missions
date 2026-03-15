-- Cleanup mission module: zone-based prop spawning, pickup tracking

Missions = Missions or {}

local spawned = {}       -- [index] = entity handle
local collected = {}     -- [index] = true
local remaining = 0
local total = 0
local missionBlips = nil
local activeZone = nil
local activeMission = nil
local propsSpawned = false

local function loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do
        Wait(25)
        tries = tries + 1
    end
    return HasModelLoaded(hash)
end

local function despawnProps()
    if not propsSpawned then return end
    for i, obj in pairs(spawned) do
        if DoesEntityExist(obj) then
            exports.ox_target:removeLocalEntity(obj)
            DeleteObject(obj)
        end
        spawned[i] = nil
    end
    propsSpawned = false
end

local function collect(index, obj, mission)
    exports.ox_target:removeLocalEntity(obj)
    SetEntityAsMissionEntity(obj, true, true)
    DeleteObject(obj)

    spawned[index] = nil
    collected[index] = true
    remaining = remaining - 1

    local completed = total - remaining
    TriggerServerEvent(ResourceName .. ':mission:progress', {
        missionId = mission.id,
        type = 'cleanup',
        completed = completed,
        total = total,
    })

    local label = (mission.params and mission.params.itemLabel) or 'item'
    local msg
    if mission.messages and mission.messages.pickup then
        msg = mission.messages.pickup
    else
        msg = ('Collected %d/%d %s'):format(completed, total, label)
    end
    lib.notify({ title = mission.label or 'Cleanup', description = msg, type = 'info' })

    if remaining <= 0 then
        despawnProps()
        RemoveMissionBlips(missionBlips)
        missionBlips = nil
        if activeZone then
            activeZone:remove()
            activeZone = nil
        end
        activeMission = nil
        TriggerServerEvent(ResourceName .. ':mission:complete', { missionId = mission.id })
    end
end

local function spawnProps(mission)
    if propsSpawned then return end
    propsSpawned = true

    local props = mission.params.props
    for i, prop in ipairs(props) do
        if not collected[i] then
            loadModel(prop.model)
            local coords = prop.coords
            local obj = CreateObject(joaat(prop.model), coords.x, coords.y, coords.z, false, true, false)
            PlaceObjectOnGroundProperly(obj)
            FreezeEntityPosition(obj, true)
            spawned[i] = obj

            local enc = mission
            local idx = i
            local objRef = obj
            exports.ox_target:addLocalEntity(objRef, {
                {
                    name = ('%s:pickup:%d'):format(mission.id, i),
                    icon = 'fa-solid fa-hand',
                    label = 'Pick up',
                    onSelect = function()
                        collect(idx, objRef, enc)
                    end,
                }
            })
        end
    end
end

--- Calculate center and bounding radius from prop positions.
local function calculateZone(props)
    local cx, cy, cz = 0, 0, 0
    local n = #props
    for _, prop in ipairs(props) do
        cx = cx + prop.coords.x
        cy = cy + prop.coords.y
        cz = cz + prop.coords.z
    end
    local center = vec3(cx / n, cy / n, cz / n)

    local maxDist = 0
    for _, prop in ipairs(props) do
        local dist = #(center - prop.coords)
        if dist > maxDist then maxDist = dist end
    end

    return center, math.max(50.0, maxDist + 30.0)
end

local function start(mission)
    -- Use local config for proper vector types (network serialization strips them)
    for _, enc in ipairs(Config.missions) do
        if enc.id == mission.id then
            mission = enc
            break
        end
    end

    local props = mission.params.props
    total = #props

    local numCollected = 0
    for _ in pairs(collected) do numCollected = numCollected + 1 end
    remaining = total - numCollected

    if remaining <= 0 then return end

    activeMission = mission
    local center, radius = calculateZone(props)

    missionBlips = CreateMissionBlips({
        location = center,
        label = mission.label,
        area = center,
        radius = radius,
    })

    activeZone = lib.zones.sphere({
        coords = center,
        radius = radius,
        onEnter = function()
            if activeMission then
                spawnProps(activeMission)
            end
        end,
        onExit = function()
            despawnProps()
        end,
    })

    -- If player is already inside the zone, spawn immediately
    if #(GetEntityCoords(cache.ped) - center) < radius then
        spawnProps(mission)
    end
end

local function stop()
    despawnProps()
    if activeZone then
        activeZone:remove()
        activeZone = nil
    end
    RemoveMissionBlips(missionBlips)
    missionBlips = nil
    spawned = {}
    collected = {}
    remaining = 0
    total = 0
    activeMission = nil
    propsSpawned = false
end

local function setProgress(progress)
    if not progress then return end
    local t = progress.total
    local c = progress.completed or 0
    if t and t > 0 then
        total = t
        for i = 1, c do
            collected[i] = true
        end
        remaining = math.max(0, t - c)
    end
end

Missions.cleanup = {
    start = start,
    stop = stop,
    setProgress = setProgress,
}
