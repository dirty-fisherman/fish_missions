-- Client-side admin: command, CRUD NUI callbacks, speech preview

local adminMode = false
local speechPreviewPed = nil

-- ── Admin command ───────────────────────────────────────────────────────────

RegisterCommand(Config.commands.missionadmin, function()
    lib.callback(ResourceName .. ':admin:checkPermission', false, function(allowed)
        if not allowed then
            Client.notify({ title = 'Mission Admin', description = Config.strings.no_permission, type = 'error' })
            return
        end
        adminMode = true
        SetNuiFocus(true, true)
        Client.sendNui('admin:open', {})
    end)
end, false)

RegisterNUICallback('admin:close', function(_, cb)
    adminMode = false
    Client.trackerVisible = false
    SetNuiFocus(false, false)
    -- Clean up any in-progress placement or prop adjust session
    if Client.cleanupPlacement then Client.cleanupPlacement() end
    if Client.cleanupPropAdjust then Client.cleanupPropAdjust() end
    Client.sendNui('admin:closed', {})
    cb({ ok = true })
end)

-- ── Speech preview ──────────────────────────────────────────────────────────

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
            Client.notify({ type = 'error', description = 'Invalid NPC model: ' .. model })
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

-- ── CRUD NUI callbacks ──────────────────────────────────────────────────────

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

RegisterNUICallback('admin:notify', function(data, cb)
    Client.notify(data)
    cb({ ok = true })
end)
