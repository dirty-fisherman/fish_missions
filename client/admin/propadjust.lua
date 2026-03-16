-- Client-side admin: bone-local prop position adjustment tool

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

        -- Spawn prop
        local obj = CreateObject(propHash, clonePos.x, clonePos.y, clonePos.z + 0.2, false, true, false)
        SetModelAsNoLongerNeeded(propHash)

        if not obj or obj == 0 then
            DeleteEntity(clone)
            SetNuiFocus(true, true)
            Client.sendNui('admin:propAdjustCancelled', {})
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
        Client.sendNui('admin:gizmoMode', { active = true })
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
                Client.sendNui('admin:gizmoMode', { active = false })
                Client.sendNui('admin:propAdjusted', {
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
                Client.sendNui('admin:gizmoMode', { active = false })
                Client.sendNui('admin:propAdjustCancelled', {})
                return
            end
        end
    end)
end)
