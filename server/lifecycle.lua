-- Server-side character lifecycle, hydration, restore, exports

local Ox = require '@ox_core.lib.init'

-- ── Hydrate in-memory actives from DB ───────────────────────────────────────

function Server.hydrateActives(src)
    local charId = Server.getCharacterId(src)
    local actives = Server.getActivesFor(src)
    local rows = Server.dbGetAllProgress(charId)
    for _, row in ipairs(rows) do
        if not actives[row.mission_id] and (row.status == 'active' or row.status == 'complete') then
            local progress = nil
            if row.progress then
                local ok, p = pcall(json.decode, row.progress)
                if ok then progress = p end
            end
            actives[row.mission_id] = {
                missionId = row.mission_id,
                npcId = row.npc_id,
                status = row.status == 'active' and 'in-progress' or row.status,
                progress = progress,
            }
        end
    end
end

-- ── Character lifecycle ─────────────────────────────────────────────────────

local function handleCharacterSelected(src, charId)
    if not src or not charId then return end
    Server.active[src] = nil
    Server.playerCharacters[src] = tostring(charId)
    Server.hydrateActives(src)

    -- Send mission list to client for NPC spawning
    TriggerClientEvent(ResourceName .. ':missions:load', src, Server.missionsList)
end

local function handleCharacterDeselected(src)
    if not src then return end
    Server.active[src] = nil
    Server.playerCharacters[src] = nil
end

if Config.characterSelectedEvent then
    RegisterNetEvent(Config.characterSelectedEvent)
    AddEventHandler(Config.characterSelectedEvent, function()
        local src = source
        CreateThread(function()
            local charId
            for _ = 1, 20 do
                local player = Ox.GetPlayer(src)
                if player and player.charId then
                    charId = player.charId
                    break
                end
                Wait(250)
            end
            if charId then
                handleCharacterSelected(src, charId)
            end
        end)
    end)
end

if Config.characterDeselectedEvent then
    RegisterNetEvent(Config.characterDeselectedEvent)
    AddEventHandler(Config.characterDeselectedEvent, function()
        local src = source
        handleCharacterDeselected(src)
    end)
end

exports('setCharacter', function(src, charId)
    handleCharacterSelected(src, charId)
end)

exports('clearCharacter', function(src)
    handleCharacterDeselected(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    Server.active[src] = nil
    Server.playerCharacters[src] = nil
end)

-- ── Dev helpers ─────────────────────────────────────────────────────────────

if Config.EnableNuiCommand then
    lib.addCommand('openNui', nil, function(src)
        if not src then return end
        TriggerClientEvent(ResourceName .. ':openNui', src)
    end)

    lib.addCommand('missionscd', nil, function(src)
        if not src then return end
        local charId = Server.getCharacterId(src)
        MySQL.query.await('UPDATE `fish_mission_progress` SET `cooldown_until` = 0 WHERE `char_id` = ?', { charId })
    end)
end

-- ── Restore request handler ─────────────────────────────────────────────────

RegisterNetEvent(ResourceName .. ':restore:request')
AddEventHandler(ResourceName .. ':restore:request', function()
    local src = source
    Server.hydrateActives(src)

    -- Send missions to client (in case this is a /ensure and client needs them)
    TriggerClientEvent(ResourceName .. ':missions:load', src, Server.missionsList)

    local actives = Server.getActivesFor(src)
    for _, a in pairs(actives) do
        local enc = Server.findMission(a.missionId)
        if enc then
            -- Delivery missions cannot be restored (timer-based, no persistence)
            if enc.type == 'delivery' and a.status == 'in-progress' then
                local charId = Server.getCharacterId(src)
                Server.dbSetCancelled(charId, a.missionId)
                actives[a.missionId] = nil
            elseif a.status == 'in-progress' then
                TriggerClientEvent(ResourceName .. ':mission:start', src, { mission = enc, npcId = a.npcId, progress = a.progress })
            elseif a.status == 'complete' then
                TriggerClientEvent(ResourceName .. ':mission:return', src, { npcId = a.npcId, missionId = a.missionId })
            end
        end
    end
end)
