-- Cleanup mission module: per-group prop spawning with optional random selection

Missions = Missions or {}

-- ── Seeded PRNG (deterministic across clients) ─────────────────────────────
-- Simple xorshift32 — fast, 32-bit, same output for same seed everywhere.

local function xorshift32(state)
    local s = state
    s = s ~ (s << 13)
    s = s ~ (s >> 17)
    s = s ~ (s << 5)
    -- keep within 32-bit unsigned range
    s = s & 0xFFFFFFFF
    return s
end

--- Return an integer in [0, max) from a seed state, advancing the state.
local function rngInt(state, max)
    state = xorshift32(state)
    return state, (state % max)
end

--- Select `count` items from `allProps` using a seeded Fisher-Yates shuffle.
--- Returns a new array with the selected subset (deterministic for same seed).
local function selectRandomSubset(allProps, count, seed)
    local n = #allProps
    if count >= n then return allProps end
    -- Build index array
    local indices = {}
    for i = 1, n do indices[i] = i end
    -- Partial Fisher-Yates: shuffle first `count` positions
    local state = seed
    for i = 1, count do
        local j
        state, j = rngInt(state, n - i + 1)
        j = j + i -- range [i, n]
        indices[i], indices[j] = indices[j], indices[i]
    end
    -- Collect selected props
    local selected = {}
    for i = 1, count do
        selected[i] = allProps[indices[i]]
    end
    return selected
end

-- ── Module state ────────────────────────────────────────────────────────────

local spawned = {}       -- [flatIndex] = entity handle
local collected = {}     -- [flatIndex] = true
local remaining = 0
local total = 0
local groups = {}        -- [groupIdx] = { startIdx, endIdx, zone, blips, propsSpawned, props }
local activeMission = nil

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

-- ── Per-group spawn/despawn ─────────────────────────────────────────────────

local function despawnGroup(g)
    if not g.propsSpawned then return end
    for i = g.startIdx, g.endIdx do
        local obj = spawned[i]
        if obj and DoesEntityExist(obj) then
            pcall(exports.ox_target.removeLocalEntity, exports.ox_target, obj)
            SetEntityAsMissionEntity(obj, true, true)
            DeleteObject(obj)
        end
        spawned[i] = nil
    end
    g.propsSpawned = false
end

local function collect(index, obj, mission)
    pcall(exports.ox_target.removeLocalEntity, exports.ox_target, obj)
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
    elseif total > 1 then
        msg = Config.strings.cleanup_collected_format:format(completed, total, label)
    else
        msg = Config.strings.cleanup_collected_single:format(label)
    end
    lib.notify({ title = mission.label or 'Cleanup', description = msg, type = 'info' })

    if remaining <= 0 then
        -- Mission complete — clean up all groups
        for _, g in ipairs(groups) do
            despawnGroup(g)
            Client.RemoveMissionBlips(g.blips)
            if g.zone then g.zone:remove() end
        end
        groups = {}
        activeMission = nil
        TriggerServerEvent(ResourceName .. ':mission:complete', { missionId = mission.id })
    end
end

local function spawnGroupProps(g, mission)
    if g.propsSpawned then return end
    g.propsSpawned = true

    for i = g.startIdx, g.endIdx do
        if not collected[i] then
            local prop = g.props[i - g.startIdx + 1]
            loadModel(prop.model)
            local coords = prop.coords
            local obj = CreateObject(joaat(prop.model), coords.x, coords.y, coords.z, false, true, false)
            SetEntityAsMissionEntity(obj, true, true)
            PlaceObjectOnGroundProperly(obj)
            SetEntityHeading(obj, (prop.heading or 0) + 0.0)
            FreezeEntityPosition(obj, true)
            SetEntityInvincible(obj, true)
            spawned[i] = obj

            local enc = mission
            local idx = i
            local objRef = obj
            exports.ox_target:addLocalEntity(objRef, {
                {
                    name = ('%s:pickup:%d'):format(mission.id, i),
                    icon = 'fa-solid fa-hand',
                    label = Config.strings.pickup_label,
                    onSelect = function()
                        collect(idx, objRef, enc)
                    end,
                }
            })
        end
    end
end

-- ── Zone calculation ────────────────────────────────────────────────────────

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
        local pc = vec3(prop.coords.x, prop.coords.y, prop.coords.z)
        local dist = #(center - pc)
        if dist > maxDist then maxDist = dist end
    end

    return center, math.max(50.0, maxDist + 30.0)
end

-- ── Normalize mission data into propGroups ──────────────────────────────────
-- Returns per-group: allProps (full set for zone calculation) and
-- activeProps (subset to actually spawn, after random selection).

local function resolveGroups(mission)
    local params = mission.params or {}
    local runtimeSeed = mission.runtimeSeed or 12345
    if params.propGroups and #params.propGroups > 0 then
        local resolved = {}
        for gi, group in ipairs(params.propGroups) do
            local allProps = group.props or {}
            local activeProps = allProps
            if group.randomize and group.randomCount and group.randomCount < #allProps then
                -- Use runtimeSeed + group index for per-group determinism
                activeProps = selectRandomSubset(allProps, group.randomCount, runtimeSeed + gi)
            end
            resolved[gi] = {
                label = group.label,
                allProps = allProps,
                activeProps = activeProps,
            }
        end
        return resolved
    end
    -- Legacy: wrap flat props in a single group
    if params.props and #params.props > 0 then
        local props = params.props
        return { { label = params.itemLabel or 'Items', allProps = props, activeProps = props } }
    end
    return {}
end

-- ── Start / stop / progress ─────────────────────────────────────────────────

local function start(mission)
    -- Reset
    collected = {}
    spawned = {}
    remaining = 0
    total = 0
    groups = {}

    local resolved = resolveGroups(mission)
    if #resolved == 0 then return end

    activeMission = mission
    local flatIdx = 1

    for gi, rg in ipairs(resolved) do
        local activeProps = rg.activeProps
        local allProps = rg.allProps
        local startIdx = flatIdx
        local endIdx = flatIdx + #activeProps - 1

        -- Use ALL props for zone calculation so the radius covers every
        -- potential placement, not just the randomly-selected subset.
        local center, radius = calculateZone(allProps)

        local blips = Client.CreateMissionBlips({
            location = center,
            label = (rg.label and rg.label ~= '') and (mission.label .. ' — ' .. rg.label) or mission.label,
            area = center,
            radius = radius,
        })

        local g = {
            startIdx = startIdx,
            endIdx = endIdx,
            props = activeProps,
            blips = blips,
            propsSpawned = false,
            zone = nil,
        }

        g.zone = lib.zones.sphere({
            coords = center,
            radius = radius,
            onEnter = function()
                if activeMission then
                    spawnGroupProps(g, activeMission)
                end
            end,
            onExit = function()
                despawnGroup(g)
            end,
        })

        groups[gi] = g
        total = total + #activeProps
        flatIdx = endIdx + 1

        -- If player already inside this group's zone, spawn immediately
        if #(GetEntityCoords(cache.ped) - center) < radius then
            spawnGroupProps(g, mission)
        end
    end

    remaining = total
    -- Apply any previously-set progress (setProgress may have run before start)
    for i in pairs(collected) do
        remaining = remaining - 1
    end
end

local function stop()
    for _, g in ipairs(groups) do
        despawnGroup(g)
        Client.RemoveMissionBlips(g.blips)
        if g.zone then g.zone:remove() end
    end
    groups = {}
    spawned = {}
    collected = {}
    remaining = 0
    total = 0
    activeMission = nil
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
