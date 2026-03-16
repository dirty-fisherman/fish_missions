-- Client-side shared helpers (loaded first)

Client = {}

function Client.notify(payload)
    pcall(function()
        lib.notify(payload)
    end)
end

function Client.sendNui(action, data)
    SendNUIMessage(json.encode({ action = action, data = data or {} }))
end

function Client.loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do
        Wait(50)
        tries = tries + 1
    end
    return HasModelLoaded(hash)
end

-- ── Blip helpers ────────────────────────────────────────────────────────────

function Client.CreateMissionBlips(config)
    local location = config.area or config.location
    local label = config.label or 'Mission'
    local sprite = config.sprite or 1
    local color = config.color or 5
    local scale = config.scale or 1.0

    local missionBlip = AddBlipForCoord(location.x, location.y, location.z)
    SetBlipSprite(missionBlip, sprite)
    SetBlipColour(missionBlip, color)
    SetBlipScale(missionBlip, scale)
    SetBlipAsShortRange(missionBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Mission: ' .. label)
    EndTextCommandSetBlipName(missionBlip)

    local result = { missionBlip = missionBlip }

    if config.area and config.radius and config.radius > 0 then
        local areaBlip = AddBlipForRadius(config.area.x, config.area.y, config.area.z, config.radius)
        SetBlipColour(areaBlip, color)
        SetBlipAlpha(areaBlip, 64)
        result.areaBlip = areaBlip
    end

    return result
end

function Client.RemoveMissionBlips(blips)
    if not blips then return end
    pcall(function()
        if blips.missionBlip and DoesBlipExist(blips.missionBlip) then
            RemoveBlip(blips.missionBlip)
        end
    end)
    pcall(function()
        if blips.areaBlip and DoesBlipExist(blips.areaBlip) then
            RemoveBlip(blips.areaBlip)
        end
    end)
end
