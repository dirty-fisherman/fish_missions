-- Server-side DB access helpers

function Server.dbGetProgress(charId, missionId)
    return MySQL.single.await(
        'SELECT * FROM `fish_mission_progress` WHERE `char_id` = ? AND `mission_id` = ?',
        { charId, missionId }
    )
end

function Server.dbUpsertProgress(charId, missionId, data)
    MySQL.query.await([[
        INSERT INTO `fish_mission_progress` (`char_id`, `mission_id`, `status`, `npc_id`, `progress`, `cooldown_until`, `times_completed`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `status` = VALUES(`status`),
            `npc_id` = VALUES(`npc_id`),
            `progress` = VALUES(`progress`),
            `cooldown_until` = VALUES(`cooldown_until`),
            `times_completed` = VALUES(`times_completed`)
    ]], {
        charId,
        missionId,
        data.status or 'available',
        data.npcId or nil,
        data.progress and json.encode(data.progress) or nil,
        data.cooldownUntil or 0,
        data.timesCompleted or 0,
    })
end

function Server.dbUpdateStatus(charId, missionId, status)
    MySQL.query.await(
        'UPDATE `fish_mission_progress` SET `status` = ? WHERE `char_id` = ? AND `mission_id` = ?',
        { status, charId, missionId }
    )
end

function Server.dbUpdateProgress(charId, missionId, progress)
    MySQL.query.await(
        'UPDATE `fish_mission_progress` SET `progress` = ? WHERE `char_id` = ? AND `mission_id` = ?',
        { progress and json.encode(progress) or nil, charId, missionId }
    )
end

function Server.dbSetCooldown(charId, missionId, untilTs, timesCompleted)
    MySQL.query.await([[
        INSERT INTO `fish_mission_progress` (`char_id`, `mission_id`, `status`, `cooldown_until`, `times_completed`)
        VALUES (?, ?, 'available', ?, ?)
        ON DUPLICATE KEY UPDATE
            `status` = 'available',
            `cooldown_until` = VALUES(`cooldown_until`),
            `times_completed` = VALUES(`times_completed`),
            `progress` = NULL,
            `npc_id` = NULL
    ]], { charId, missionId, untilTs, timesCompleted or 0 })
end

function Server.dbSetCancelled(charId, missionId)
    MySQL.query.await([[
        INSERT INTO `fish_mission_progress` (`char_id`, `mission_id`, `status`)
        VALUES (?, ?, 'cancelled')
        ON DUPLICATE KEY UPDATE
            `status` = 'cancelled',
            `progress` = NULL,
            `npc_id` = NULL
    ]], { charId, missionId })
end

function Server.dbGetAllProgress(charId)
    return MySQL.query.await(
        'SELECT * FROM `fish_mission_progress` WHERE `char_id` = ?',
        { charId }
    ) or {}
end
