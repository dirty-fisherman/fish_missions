-- Server-side rewards, XP, daily tracking, prerequisites

-- ── XP helpers ──────────────────────────────────────────────────────────────

function Server.dbGetXp(charId)
    local row = MySQL.single.await('SELECT `xp` FROM `fish_mission_xp` WHERE `char_id` = ?', { charId })
    return row and row.xp or 0
end

function Server.dbIncrementXp(charId)
    MySQL.query.await([[
        INSERT INTO `fish_mission_xp` (`char_id`, `xp`) VALUES (?, 1)
        ON DUPLICATE KEY UPDATE `xp` = `xp` + 1
    ]], { charId })
end

-- ── Daily completion helpers ────────────────────────────────────────────────

local function todayDate()
    return os.date('%Y-%m-%d')
end

function Server.dbGetDailyCompletions(charId)
    local row = MySQL.single.await('SELECT `completions`, `reset_date` FROM `fish_mission_daily` WHERE `char_id` = ?', { charId })
    if not row then return 0 end
    if row.reset_date ~= todayDate() then return 0 end
    return row.completions or 0
end

function Server.dbIncrementDaily(charId)
    local today = todayDate()
    MySQL.query.await([[
        INSERT INTO `fish_mission_daily` (`char_id`, `completions`, `reset_date`) VALUES (?, 1, ?)
        ON DUPLICATE KEY UPDATE
            `completions` = IF(`reset_date` = VALUES(`reset_date`), `completions` + 1, 1),
            `reset_date` = VALUES(`reset_date`)
    ]], { charId, today })
end

-- ── Prerequisite check ──────────────────────────────────────────────────────

function Server.checkPrerequisites(charId, enc)
    if not enc.prerequisites or #enc.prerequisites == 0 then return true end
    local rows = Server.dbGetAllProgress(charId)
    local completed = {}
    for _, row in ipairs(rows) do
        if row.times_completed and row.times_completed > 0 then
            completed[row.mission_id] = true
        end
    end
    for _, prereqId in ipairs(enc.prerequisites) do
        if not completed[prereqId] then return false end
    end
    return true
end

-- ── Rewards ─────────────────────────────────────────────────────────────────

function Server.grantReward(src, reward)
    if not reward then return end
    if reward.cash and reward.cash > 0 then
        local ok = pcall(function()
            exports.ox_core:addMoney(src, 'cash', reward.cash, 'mission_reward')
        end)
        if not ok then
            pcall(function()
                exports.ox_inventory:AddItem(src, 'money', reward.cash)
            end)
        end
    end
    if reward.items then
        for _, item in ipairs(reward.items) do
            pcall(function()
                exports.ox_inventory:AddItem(src, item.name, item.count or 1)
            end)
        end
    end
end
