-- Client-side NPC management: proximity-based ped spawning, ox_target, blips, speech

-- ── NPC interaction ─────────────────────────────────────────────────────────

function Client.openMissionNui(npc, enc)
    SetNuiFocus(true, true)
    Client.trackerVisible = true

    -- Request fresh tracker data
    TriggerServerEvent(ResourceName .. ':tracker:request')

    local npcWithMission = {}
    for k, v in pairs(npc) do npcWithMission[k] = v end
    npcWithMission.missionId = enc.id

    -- Enrich reward items with labels from ox_inventory.
    -- Copy enc shallowly to avoid mutating the shared Client.missionsById entry.
    local mission = enc
    if enc.reward and enc.reward.items and #enc.reward.items > 0 then
        local enrichedItems = {}
        for i, it in ipairs(enc.reward.items) do
            local ok, itemData = pcall(function() return exports['ox_inventory']:Items(it.name) end)
            local lbl = (ok and itemData and itemData.label) or it.name
            enrichedItems[i] = { name = it.name, count = it.count, label = lbl }
        end
        local reward = {}
        for k, v in pairs(enc.reward) do reward[k] = v end
        reward.items = enrichedItems
        mission = {}
        for k, v in pairs(enc) do mission[k] = v end
        mission.reward = reward
    end

    local showPayload = { npc = npcWithMission, mission = mission }

    if not Client.nuiReady then
        Client.sendNui('setVisible', { visible = true })
        Client.pendingMission = { npc = npc, enc = enc }
        -- Delayed attempts in case ready event races
        SetTimeout(150, function()
            Client.sendNui('setVisible', { visible = true })
            Client.sendNui('mission:show', showPayload)
        end)
        SetTimeout(400, function()
            Client.sendNui('setVisible', { visible = true })
            Client.sendNui('mission:show', showPayload)
        end)
        return
    end

    Client.sendNui('setVisible', { visible = true })
    Client.sendNui('mission:show', showPayload)
end

-- ── Proximity-based ped spawning ─────────────────────────────────────────────

local NPC_SPAWN_DIST = 80
local NPC_DESPAWN_DIST = 100
local npcDefs = {}        -- npcId -> { mission data for spawning }
local spawnedNpcPeds = {} -- npcId -> ped handle

local function spawnNpcPed(def)
    -- If we already have a handle, verify the entity still exists
    local existing = spawnedNpcPeds[def.npcId]
    if existing then
        if DoesEntityExist(existing) then return end
        -- Stale handle — clear it so we can respawn
        spawnedNpcPeds[def.npcId] = nil
        Client.npcs[def.npcId] = nil
    end

    local model = lib.requestModel(def.model)
    if not model then return end

    local h = def.heading + 0.0
    -- Non-networked so despawn is reliable and no duplicates from ownership transfer
    local ped = CreatePed(4, model, def.x, def.y, def.z, h, false, false)

    SetEntityHeading(ped, h)
    Wait(0)
    FreezeEntityPosition(ped, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)

    if def.scenario then
        TaskStartScenarioInPlace(ped, def.scenario, 0, false)
    end

    SetModelAsNoLongerNeeded(model)

    -- ox_target
    exports.ox_target:addLocalEntity(ped, {
        {
            name = ('%s:npc:%s'):format(ResourceName, def.npcId),
            icon = (def.npcData.target and def.npcData.target.icon) or 'fa-solid fa-comments',
            label = def.label,
            distance = 2.0,
            onSelect = function()
                local enc = Client.findMissionById(def.missionId)
                if not enc then return end

                local result = lib.callback.await(ResourceName .. ':mission:canAccept', false, def.missionId)
                if result and not result.allowed then
                    local msg = Config.blockedNpcMessage or "I'm not interested in talking to you."
                    local speechName = def.npcData.speech or 'GENERIC_HI'
                    PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force')
                    Client.notify({ title = enc.label or 'Mission', description = msg, type = 'error' })
                    return
                end

                local speechName = def.npcData.speech or 'GENERIC_HI'
                PlayAmbientSpeech1(ped, speechName, 'Speech_Params_Force')
                Client.openMissionNui(def.npcData, enc)
            end,
        }
    })

    spawnedNpcPeds[def.npcId] = ped
    Client.npcs[def.npcId] = ped
end

local function despawnNpcPed(npcId)
    local ped = spawnedNpcPeds[npcId]
    if not ped then return end

    spawnedNpcPeds[npcId] = nil
    Client.npcs[npcId] = nil

    pcall(function() exports.ox_target:removeLocalEntity(ped) end)
    if DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
end

-- Proximity polling thread
local npcProximityActive = false
local npcProximityGen = 0  -- generation counter to invalidate stale threads

local function startNpcProximityThread()
    npcProximityGen = npcProximityGen + 1
    local myGen = npcProximityGen

    if npcProximityActive then return end
    npcProximityActive = true

    CreateThread(function()
        while npcProximityActive and myGen == npcProximityGen and next(npcDefs) do
            local playerCoords = GetEntityCoords(cache.ped)
            for npcId, def in pairs(npcDefs) do
                -- Re-check generation after any yield (spawnNpcPed yields)
                if myGen ~= npcProximityGen then break end

                local dist = #(playerCoords - vec3(def.x, def.y, def.z))

                if dist < NPC_SPAWN_DIST and not spawnedNpcPeds[npcId] then
                    spawnNpcPed(def)
                elseif dist > NPC_DESPAWN_DIST and spawnedNpcPeds[npcId] then
                    despawnNpcPed(npcId)
                end
            end
            Wait(1000)
        end
        -- Only clear the flag if we're still the current generation
        if myGen == npcProximityGen then
            npcProximityActive = false
        end
    end)
end

-- ── Cleanup / spawn ─────────────────────────────────────────────────────────

function Client.cleanupAllNpcs()
    npcProximityActive = false
    npcProximityGen = npcProximityGen + 1  -- invalidate any sleeping thread

    for npcId in pairs(spawnedNpcPeds) do
        despawnNpcPed(npcId)
    end
    npcDefs = {}

    for _, b in ipairs(Client.npcBlips) do
        pcall(RemoveBlip, b)
    end
    Client.npcBlips = {}
end

function Client.spawnAllNpcs()
    Client.cleanupAllNpcs()
    local maxBlips = Config.maxNpcBlips or 10
    local blipCount = 0

    for _, mission in ipairs(Client.missionsList) do
        local n = mission.npc
        if n then
            local heading = tonumber(mission.npcHeading) or 0.0
            local label = (n.target and n.target.label) or ('Talk to ' .. n.id)

            npcDefs[n.id] = {
                npcId = n.id,
                missionId = mission.id,
                model = n.model,
                x = n.coords.x,
                y = n.coords.y,
                z = n.coords.z,
                heading = heading,
                scenario = n.scenario,
                label = label,
                npcData = n,
            }

            -- Blips are created immediately (they don't need streaming)
            if Config.npcBlips and n.blip ~= false and blipCount < maxBlips then
                local blip = AddBlipForCoord(n.coords.x, n.coords.y, n.coords.z)
                SetBlipSprite(blip, Config.npcBlipSprite or 280)
                SetBlipColour(blip, Config.npcBlipColor or 29)
                SetBlipScale(blip, Config.npcBlipScale or 0.7)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(label)
                EndTextCommandSetBlipName(blip)
                Client.npcBlips[#Client.npcBlips + 1] = blip
                blipCount = blipCount + 1
            end
        end
    end

    startNpcProximityThread()
end

-- ── NPC speech helpers ──────────────────────────────────────────────────────

function Client.playNpcSpeech(npcId, speechType)
    local ped = Client.npcs[npcId]
    if not ped or not DoesEntityExist(ped) then return end
    local npc = Client.findNpcById(npcId)
    if not npc then return end

    local speech
    if speechType == 'bye' then
        speech = npc.speechBye or 'GENERIC_BYE'
    elseif speechType == 'claim' then
        speech = npc.speechClaim or 'GENERIC_THANKS'
    else
        speech = npc.speech or 'GENERIC_HI'
    end
    PlayAmbientSpeech1(ped, speech, 'Speech_Params_Force')
end
