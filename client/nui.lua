-- Client-side NUI callbacks (gameplay) and server event handlers

-- ── NUI Callbacks ───────────────────────────────────────────────────────────

RegisterNUICallback('panel:openAdmin', function(_, cb)
    cb({ ok = true })
    lib.callback(ResourceName .. ':admin:checkPermission', false, function(allowed)
        if not allowed then
            Client.notify({ title = 'Mission Admin', description = Config.strings.no_permission, type = 'error' })
            return
        end
        Client.sendNui('admin:open', {})
    end)
end)

RegisterNUICallback('exit', function(data, cb)
    SetNuiFocus(false, false)
    Client.trackerVisible = false
    if data and data.npcId then
        Client.playNpcSpeech(data.npcId, 'bye')
    end
    cb({})
end)

RegisterNUICallback('ui:ready', function(_, cb)
    Client.nuiReady = true
    if Client.pendingMission then
        local npc = Client.pendingMission.npc
        local enc = Client.pendingMission.enc
        local npcWithMission = {}
        for k, v in pairs(npc) do npcWithMission[k] = v end
        npcWithMission.missionId = enc.id
        Client.sendNui('setVisible', { visible = true })
        Client.sendNui('mission:show', { npc = npcWithMission, mission = enc })
        Client.pendingMission = nil
    end
    cb({ ok = true })
end)

RegisterNUICallback('mission:accept', function(data, cb)
    SetNuiFocus(false, false)
    Client.trackerVisible = false
    if data.npcId then Client.playNpcSpeech(data.npcId, 'bye') end
    if not Client.npcs[data.npcId] then return cb({ ok = false, reason = 'npc_missing' }) end
    TriggerServerEvent(ResourceName .. ':mission:accept', data)
    cb({ ok = true })
end)

RegisterNUICallback('mission:reject', function(data, cb)
    SetNuiFocus(false, false)
    Client.trackerVisible = false
    if data and data.npcId then Client.playNpcSpeech(data.npcId, 'bye') end
    cb({ ok = true })
end)

RegisterNUICallback('mission:cancel', function(data, cb)
    SetNuiFocus(false, false)
    Client.trackerVisible = false
    if data and data.npcId then Client.playNpcSpeech(data.npcId, 'bye') end
    if data and data.missionId then
        TriggerServerEvent(ResourceName .. ':mission:cancel', { missionId = data.missionId })
    end
    cb({ ok = true })
end)

RegisterNUICallback('panel:getVisible', function(_, cb)
    cb({ visible = Client.trackerVisible })
end)

RegisterNUICallback('focus:set', function(data, cb)
    pcall(SetNuiFocus, not not data.hasFocus, not not data.hasCursor)
    Client.trackerVisible = not not data.hasFocus
    cb({ ok = true })
end)

RegisterNUICallback('tracker:request', function(_, cb)
    TriggerServerEvent(ResourceName .. ':tracker:request')
    cb({ ok = true })
end)

RegisterNUICallback('mission:waypoint', function(data, cb)
    pcall(SetNuiFocus, false, false)
    if data and data.missionId then
        local mission = Client.findMissionById(data.missionId)
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
        Client.playNpcSpeech(data.npcId, 'claim')
        SetTimeout(1500, function()
            Client.playNpcSpeech(data.npcId, 'bye')
        end)
        TriggerServerEvent(ResourceName .. ':mission:claim', { missionId = data.missionId, npcId = data.npcId })
    end
    cb({ ok = true })
end)

RegisterNUICallback('tracker:exit', function(data, cb)
    Client.trackerVisible = false
    pcall(SetNuiFocus, false, false)
    if data and data.npcId then Client.playNpcSpeech(data.npcId, 'bye') end
    Client.sendNui('tracker:toggle', { visible = false })
    cb({ ok = true })
end)

-- ── Server event handlers ───────────────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':mission:start')
AddEventHandler(ResourceName .. ':mission:start', function(data)
    -- Restore progress if provided
    if data.progress then
        pcall(Client.setMissionProgress, data.mission.id, data.progress)
    end
    Client.activeMissions[data.mission.id] = { npcId = data.npcId, status = 'in-progress', type = data.mission.type }
    Client.missionTypes[data.mission.id] = data.mission.type
    Client.startMission(data.mission)
end)

RegisterNetEvent(ResourceName .. ':mission:return')
AddEventHandler(ResourceName .. ':mission:return', function(data)
    Client.claimableMissions[data.missionId] = true
    local t = Client.missionTypes[data.missionId]
    Client.activeMissions[data.missionId] = { npcId = data.npcId, status = 'complete', type = t }

    if not data.silent then
        local mission = Client.findMissionById(data.missionId)
        local missionTitle = mission and mission.label or 'Mission'
        Client.notify({ title = missionTitle, description = Config.strings.mission_complete_return, type = 'success', duration = 10000 })

        if mission and mission.npc and mission.npc.coords then
            pcall(SetNewWaypoint, mission.npc.coords.x, mission.npc.coords.y)
        end
    end
end)

RegisterNetEvent(ResourceName .. ':mission:claimed')
AddEventHandler(ResourceName .. ':mission:claimed', function(data)
    Client.claimableMissions[data.missionId] = nil
    Client.activeMissions[data.missionId] = nil
    if Client.trackerVisible then
        TriggerServerEvent(ResourceName .. ':tracker:request')
    end
end)

RegisterNetEvent(ResourceName .. ':mission:cooldown')
AddEventHandler(ResourceName .. ':mission:cooldown', function(data)
    local mins = math.ceil(data.seconds / 60)
    Client.notify({ title = 'Mission', description = Config.strings.cooldown_format:format(mins), type = 'error' })
    if Client.trackerVisible then
        TriggerServerEvent(ResourceName .. ':tracker:request')
    end
end)

RegisterNetEvent(ResourceName .. ':mission:busy')
AddEventHandler(ResourceName .. ':mission:busy', function(data)
    local msg = data.status == 'complete' and Config.strings.busy_turnin or Config.strings.busy_active
    Client.notify({ title = 'Mission', description = msg, type = 'error', duration = 10000 })
end)

RegisterNetEvent(ResourceName .. ':mission:blocked')
AddEventHandler(ResourceName .. ':mission:blocked', function(data)
    local msg = Config.blockedNpcMessage or "I'm not interested in talking to you."
    Client.notify({ title = 'Mission', description = msg, type = 'error' })
end)

RegisterNetEvent(ResourceName .. ':mission:cancelled')
AddEventHandler(ResourceName .. ':mission:cancelled', function(data)
    local t = Client.missionTypes[data.missionId]
    if t then
        Client.stopMission(t)
    else
        Client.stopAllMissions()
    end

    Client.claimableMissions[data.missionId] = nil
    Client.activeMissions[data.missionId] = nil
    Client.missionTypes[data.missionId] = nil

    local msg = data.appliedCooldown and Config.strings.cancelled_by_player or Config.strings.cancelled
    Client.notify({ title = 'Mission', description = msg, type = 'warning', duration = 10000 })

    if Client.trackerVisible then
        TriggerServerEvent(ResourceName .. ':tracker:request')
    end
end)

RegisterNetEvent(ResourceName .. ':tracker:data')
AddEventHandler(ResourceName .. ':tracker:data', function(data)
    Client.sendNui('tracker:data', data)
end)

-- Receive mission definitions from server (loaded from DB)
RegisterNetEvent(ResourceName .. ':missions:load')
AddEventHandler(ResourceName .. ':missions:load', function(data)
    Client.missionsList = data or {}
    Client.missionsById = {}
    for _, enc in ipairs(Client.missionsList) do
        Client.missionsById[enc.id] = enc
    end
    Client.spawnAllNpcs()
end)
