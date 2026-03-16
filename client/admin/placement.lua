-- Client-side admin: placement tool (camera raycast with preview entity)

local placingEntity = nil
local placingField = nil
local placingHeading = 0.0
local placingType = nil -- 'ped' or 'prop'
local contextHandles = {} -- entities shown for spatial context during placement

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function cleanupPlacement()
    pcall(lib.hideTextUI)
    if placingEntity and DoesEntityExist(placingEntity) then
        DeleteEntity(placingEntity)
    end
    for _, ent in ipairs(contextHandles) do
        if DoesEntityExist(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
    end
    contextHandles = {}
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

-- ── Placement NUI callback ──────────────────────────────────────────────────

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
        Client.notify({ type = 'error', description = 'Invalid model: ' .. tostring(modelName) })
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

    -- Spawn context entities (other placed props/targets for spatial reference)
    if data.contextEntities then
        for _, ctx in ipairs(data.contextEntities) do
            local ctxHash = type(ctx.model) == 'string' and joaat(ctx.model) or ctx.model
            if IsModelInCdimage(ctxHash) then
                RequestModel(ctxHash)
                local ctxTries = 0
                while not HasModelLoaded(ctxHash) and ctxTries < 60 do
                    Wait(50)
                    ctxTries = ctxTries + 1
                end
                if HasModelLoaded(ctxHash) then
                    local ctxEnt
                    local ctxType = ctx.entityType or 'prop'
                    if ctxType == 'ped' then
                        ctxEnt = CreatePed(4, ctxHash, ctx.coords.x, ctx.coords.y, ctx.coords.z, ctx.heading or 0.0, false, false)
                    else
                        ctxEnt = CreateObject(ctxHash, ctx.coords.x, ctx.coords.y, ctx.coords.z, false, false, false)
                    end
                    if ctxEnt and DoesEntityExist(ctxEnt) then
                        SetEntityCollision(ctxEnt, false, false)
                        SetEntityInvincible(ctxEnt, true)
                        FreezeEntityPosition(ctxEnt, true)
                        if ctxType == 'ped' then
                            SetBlockingOfNonTemporaryEvents(ctxEnt, true)
                        else
                            PlaceObjectOnGroundProperly(ctxEnt)
                        end
                        if ctx.heading then
                            SetEntityHeading(ctxEnt, ctx.heading)
                        end
                        contextHandles[#contextHandles + 1] = ctxEnt
                    end
                end
            end
        end
    end

    lib.showTextUI(Config.strings.placement_hint, { position = 'top-center' })

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
                local finalHead = placingHeading
                local capturedField = placingField
                local capturedType = placingType
                cleanupPlacement()
                SetNuiFocus(true, true)
                Client.sendNui('admin:positionCaptured', {
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
                Client.sendNui('admin:placementCancelled', { field = placingField })
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
