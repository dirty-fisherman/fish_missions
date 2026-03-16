-- Client-side admin: bone-local prop position adjustment tool

local adjustClone = nil
local adjustObj = nil
local adjustCam = nil
local adjustPed = nil
local adjustActive = false

local function cleanupPropAdjust()
    pcall(lib.hideTextUI)
    adjustActive = false
    if adjustObj and DoesEntityExist(adjustObj) then
        DeleteEntity(adjustObj)
    end
    if adjustClone and DoesEntityExist(adjustClone) then DeleteEntity(adjustClone) end
    if adjustCam and DoesCamExist(adjustCam) then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(adjustCam, false)
    end
    if adjustPed then
        SetEntityVisible(adjustPed, true, false)
        FreezeEntityPosition(adjustPed, false)
        ClearPedTasks(adjustPed)
    end
    ClearWeatherTypePersist()
    ClearOverrideWeather()
    NetworkClearClockTimeOverride()
    adjustClone = nil
    adjustObj = nil
    adjustCam = nil
    adjustPed = nil
end

Client.cleanupPropAdjust = cleanupPropAdjust

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
        Client.notify({ type = 'error', description = 'Invalid prop model: ' .. tostring(propModel) })
        cb({ ok = false, reason = 'invalid_model' })
        return
    end

    -- Clean up any existing prop adjust session
    cleanupPropAdjust()

    SetNuiFocus(false, false)
    cb({ ok = true })

    CreateThread(function()
        local ped = cache.ped
        adjustPed = ped
        local propHash = joaat(propModel)
        local pedModel = GetEntityModel(ped)

        lib.requestAnimDict(preset.dict)
        lib.requestModel(propHash)
        lib.requestModel(pedModel)

        -- Hide player so they don't block the view
        SetEntityVisible(ped, false, false)
        FreezeEntityPosition(ped, true)

        -- Override weather/time locally so the preview is well-lit
        SetWeatherTypeOvertimePersist('EXTRASUNNY', 0.0)
        NetworkOverrideClockTime(12, 0, 0)

        -- Use camera heading so clone spawns where the player is looking
        local pedCoords = GetEntityCoords(ped)
        local camRot = GetGameplayCamRot(2)
        local camYaw = camRot.z
        local rad = math.rad(camYaw)
        local fwd = vector3(-math.sin(rad), math.cos(rad), 0.0)
        local clonePos = pedCoords + fwd * 1.5
        local cloneHeading = (camYaw + 180.0) % 360.0

        local clone = CreatePed(4, pedModel, clonePos.x, clonePos.y, clonePos.z, cloneHeading, false, false)
        adjustClone = clone
        SetModelAsNoLongerNeeded(pedModel)
        adjustActive = true

        if not clone or clone == 0 then
            cleanupPropAdjust()
            SetNuiFocus(true, true)
            Client.sendNui('admin:propAdjustCancelled', {})
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

        local boneIdx = GetPedBoneIndex(clone, preset.bone)
        local bonePos = GetWorldPositionOfEntityBone(clone, boneIdx)

        -- Spawn prop as non-networked at the bone's world position so the engine
        -- doesn't have to teleport it from an unrelated location on attachment
        lib.requestModel(propHash)
        local obj = CreateObject(propHash, bonePos.x, bonePos.y, bonePos.z, false, false, false)
        if not obj or obj == 0 then
            -- Retry once
            Wait(100)
            lib.requestModel(propHash)
            obj = CreateObject(propHash, bonePos.x, bonePos.y, bonePos.z, false, false, false)
        end
        adjustObj = obj
        SetModelAsNoLongerNeeded(propHash)

        if not obj or obj == 0 then
            cleanupPropAdjust()
            SetNuiFocus(true, true)
            Client.sendNui('admin:propAdjustCancelled', {})
            return
        end

        -- Initialize bone-local offsets from saved values or preset defaults
        -- Force float coercion (+0.0): JSON round-trip turns whole numbers into
        -- Lua 5.4 integers (e.g. -145, 290, 0) which AttachEntityToEntity mishandles.
        local posX = (data.propOffset and data.propOffset.x or preset.pos.x) + 0.0
        local posY = (data.propOffset and data.propOffset.y or preset.pos.y) + 0.0
        local posZ = (data.propOffset and data.propOffset.z or preset.pos.z) + 0.0
        local rotX = (data.propRotation and data.propRotation.x or preset.rot.x) + 0.0
        local rotY = (data.propRotation and data.propRotation.y or preset.rot.y) + 0.0
        local rotZ = (data.propRotation and data.propRotation.z or preset.rot.z) + 0.0

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

        -- Scripted camera: orbitable position facing the clone
        local camPos = clonePos + fwd * -2.0 + vector3(0.0, 0.0, 0.5)
        local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, 50.0, false, 0)
        adjustCam = cam
        PointCamAtEntity(cam, clone, 0.0, 0.0, 0.0, true)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, false)

        -- Hide admin panel
        Client.sendNui('admin:gizmoMode', { active = true })
        Wait(50)

        local rotMode = false -- false = position mode, true = rotation mode
        local lastTextUI = ''

        local function r3(v) return math.floor(v * 1000 + 0.5) / 1000 end

        while adjustActive do
            Wait(0)

            -- Disable ALL controls
            DisableAllControlActions(0)

            -- Shift = fine mode
            local fine = IsDisabledControlPressed(0, 21)
            local posStep = fine and 0.005 or 0.02
            local rotStep = fine and 1.0 or 5.0
            local camStep = fine and 0.02 or 0.05

            -- WASD + Q/Z = move camera (continuous, relative to camera-to-clone direction)
            local camToClone = clonePos - camPos
            local camFwd2d = vector3(camToClone.x, camToClone.y, 0.0)
            local camFwdLen = #camFwd2d
            if camFwdLen > 0.001 then camFwd2d = camFwd2d / camFwdLen end
            local camRight2d = vector3(camFwd2d.y, -camFwd2d.x, 0.0)

            local camMoved = false
            if IsDisabledControlPressed(0, 32) then camPos = camPos + camFwd2d * camStep; camMoved = true end   -- W = toward clone
            if IsDisabledControlPressed(0, 33) then camPos = camPos - camFwd2d * camStep; camMoved = true end   -- S = away from clone
            if IsDisabledControlPressed(0, 35) then camPos = camPos + camRight2d * camStep; camMoved = true end -- D = orbit right
            if IsDisabledControlPressed(0, 34) then camPos = camPos - camRight2d * camStep; camMoved = true end -- A = orbit left
            if IsDisabledControlPressed(0, 44) then camPos = camPos + worldUp * camStep; camMoved = true end    -- Q = raise cam
            if IsDisabledControlPressed(0, 20) then camPos = camPos - worldUp * camStep; camMoved = true end    -- Z = lower cam

            if camMoved then
                SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
            end

            -- R = toggle position / rotation mode
            if IsDisabledControlJustPressed(0, 45) then
                rotMode = not rotMode
            end

            local changed = false

            if rotMode then
                -- Rotation mode: direct bone-local axis control
                -- Arrows = X/Y rotation, Scroll = Z rotation
                if IsDisabledControlJustPressed(0, 175) then rotX = rotX + rotStep; changed = true end   -- Right = +rotX
                if IsDisabledControlJustPressed(0, 174) then rotX = rotX - rotStep; changed = true end   -- Left  = -rotX
                if IsDisabledControlJustPressed(0, 172) then rotY = rotY + rotStep; changed = true end   -- Up    = +rotY
                if IsDisabledControlJustPressed(0, 173) then rotY = rotY - rotStep; changed = true end   -- Down  = -rotY
                if IsDisabledControlJustPressed(0, 15) then rotZ = rotZ + rotStep; changed = true end    -- Scroll up   = +rotZ
                if IsDisabledControlJustPressed(0, 14) then rotZ = rotZ - rotStep; changed = true end    -- Scroll down = -rotZ
            else
                -- Position mode: clone-relative input converted to bone-local deltas
                local worldDelta = vector3(0.0, 0.0, 0.0)
                if IsDisabledControlJustPressed(0, 175) then worldDelta = cloneRight * posStep; changed = true end     -- Right arrow = clone's right
                if IsDisabledControlJustPressed(0, 174) then worldDelta = -cloneRight * posStep; changed = true end    -- Left arrow  = clone's left
                if IsDisabledControlJustPressed(0, 172) then worldDelta = cloneFwd * posStep; changed = true end       -- Up arrow    = clone's forward
                if IsDisabledControlJustPressed(0, 173) then worldDelta = -cloneFwd * posStep; changed = true end      -- Down arrow  = clone's backward
                if IsDisabledControlJustPressed(0, 15) then worldDelta = worldUp * posStep; changed = true end         -- Scroll up   = raise
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
            local text
            if rotMode then
                text = ('%s |  Pos: %.3f, %.3f, %.3f  |  Rot: %.1f, %.1f, %.1f | rotX/rotY: [Arrows] | rotZ: [Scroll] | Camera: [WASD/Q/Z] | Mode : [R] | Fine: [Shift] | Save: [E] | Cancel: [Bksp]'):format(
                    modeStr, posX, posY, posZ, rotX, rotY, rotZ)
            else
                text = ('%s |  Pos: %.3f, %.3f, %.3f  |  Rot: %.1f, %.1f, %.1f | Move: [Arrows] | Height: [Scroll] | Camera: [WASD/Q/Z] | Mode: [R] | Fine: [Shift] | Save: [E] | Cancel: [Bksp]'):format(
                    modeStr, posX, posY, posZ, rotX, rotY, rotZ)
            end

            if text ~= lastTextUI then
                lastTextUI = text
                lib.showTextUI(text, { position = 'top-center' })
            end

            -- E = confirm
            if IsDisabledControlJustPressed(0, 38) then
                cleanupPropAdjust()

                SetNuiFocus(true, true)
                Wait(100)
                Client.sendNui('admin:gizmoMode', { active = false })
                Client.sendNui('admin:propAdjusted', {
                    propOffset = { x = r3(posX), y = r3(posY), z = r3(posZ) },
                    propRotation = { x = r3(rotX), y = r3(rotY), z = r3(rotZ) },
                })
                return
            end

            -- Backspace = cancel
            if IsDisabledControlJustPressed(0, 177) then
                cleanupPropAdjust()

                SetNuiFocus(true, true)
                Wait(100)
                Client.sendNui('admin:gizmoMode', { active = false })
                Client.sendNui('admin:propAdjustCancelled', {})
                return
            end
        end
    end)
end)
