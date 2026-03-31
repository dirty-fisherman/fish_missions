-- Client-side admin: placement tool (camera raycast with preview entity)

local PED_PREVIEW_Z_OFFSET = 1.0 -- visual-only upward shift so preview peds aren't clipped into the ground

local placingEntity = nil
local placingField = nil
local placingHeading = 0.0
local placingPitch = 0.0
local placingRoll = 0.0
local placingRotMode = 1 -- 1 = Yaw, 2 = Pitch, 3 = Roll (prop placement only)
local placingType = nil -- 'ped' or 'prop'
local contextHandles = {} -- entities shown for spatial context during placement
local lastGroundCoords = nil -- true ground position for ped previews (before visual Z offset)

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
    placingPitch = 0.0
    placingRoll = 0.0
    placingRotMode = 1
    lastGroundCoords = nil
end

Client.cleanupPlacement = cleanupPlacement

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

local rotModeNames = { 'Yaw', 'Pitch', 'Roll' }
local function updatePlacementHint()
    local modeName = rotModeNames[placingRotMode] or 'Yaw'
    lib.showTextUI(('[E] Place  [Scroll] %s  [R] Cycle Axis  [Backspace] Cancel'):format(modeName), { position = 'top-center' })
end

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
    placingPitch = 0.0
    placingRoll = 0.0
    placingRotMode = 1
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
                        ctxEnt = CreatePed(4, ctxHash, ctx.coords.x, ctx.coords.y, ctx.coords.z, (ctx.heading or 0) + 0.0, false, false)
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
                        SetEntityRotation(ctxEnt, (ctx.pitch or 0) + 0.0, (ctx.roll or 0) + 0.0, (ctx.heading or 0) + 0.0, 2, true)
                        contextHandles[#contextHandles + 1] = ctxEnt
                    end
                end
            end
        end
    end

    updatePlacementHint()

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
            DisableControlAction(0, 45, true)  -- reload (R — cycle rotation axis)
            DisableControlAction(0, 140, true) -- Disable INPUT_MELEE_ATTACK_LIGHT

            -- R cycles the active rotation axis (prop placement only)
            if placingType == 'prop' and IsDisabledControlJustPressed(0, 45) then
                placingRotMode = (placingRotMode % 3) + 1
                updatePlacementHint()
            end

            -- Scroll wheel: adjust active rotation axis
            local scrollUp   = IsDisabledControlJustPressed(0, 15)
            local scrollDown = IsDisabledControlJustPressed(0, 14)
            if scrollUp or scrollDown then
                local delta = scrollUp and 15.0 or -15.0
                if placingRotMode == 1 or placingType ~= 'prop' then
                    placingHeading = (placingHeading + delta + 360.0) % 360.0
                elseif placingRotMode == 2 then
                    placingPitch = (placingPitch + delta + 360.0) % 360.0
                else
                    placingRoll = (placingRoll + delta + 360.0) % 360.0
                end
            end

            -- E to confirm
            if IsControlJustPressed(0, 38) then
                -- For peds use the stored ground coords (before the visual Z offset)
                local finalCoords = (placingType == 'ped' and lastGroundCoords) or GetEntityCoords(placingEntity)
                local finalHead  = placingHeading
                local finalPitch = placingPitch
                local finalRoll  = placingRoll
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
                    heading = math.floor(finalHead  * 100) / 100,
                    pitch   = math.floor(finalPitch * 100) / 100,
                    roll    = math.floor(finalRoll  * 100) / 100,
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
                if placingType == 'prop' then
                    SetEntityRotation(placingEntity, placingPitch, placingRoll, placingHeading, 2, true)
                else
                    SetEntityHeading(placingEntity, placingHeading)
                    -- Capture true ground coords, then shift the preview up so the
                    -- ped isn't visually clipped into the ground. The saved Z from
                    -- lastGroundCoords is used on E-press, not the offset position.
                    lastGroundCoords = GetEntityCoords(placingEntity)
                    SetEntityCoordsNoOffset(placingEntity,
                        lastGroundCoords.x, lastGroundCoords.y, lastGroundCoords.z + PED_PREVIEW_Z_OFFSET,
                        false, false, false)
                end
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
