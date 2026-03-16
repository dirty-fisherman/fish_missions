ResourceName = GetCurrentResourceName()

Config = {
    EnableNuiCommand = false,
    npcBlips = true,
    npcBlipSprite = 280,
    npcBlipColor = 29,
    npcBlipScale = 0.7,
    maxNpcBlips = 10,
    dailyMissionLimit = 20,
    blockedNpcMessage = "I'm not interested in talking to you.",
    sidebarPosition = 'left',
    adminPermission = 'command.missionadmin',
    characterSelectedEvent = 'ox:setActiveCharacter',
    characterDeselectedEvent = 'ox:playerLogout',

    -- Command / keybind names (change these to avoid conflicts)
    commands = {
        missions = 'missions',
        missionadmin = 'missionadmin',
    },
    keybind = 'F6',
    keybindDescription = 'Toggle Missions Tracker',

    -- Player-facing strings (override to localize)
    strings = {
        -- Notifications (Lua)
        mission_complete_return      = 'You did it! Return to claim your reward.',
        cooldown_format              = 'On cooldown (%d min)',
        busy_active                  = 'You already have a mission in progress.',
        busy_turnin                  = 'You already have a mission ready to turn in.',
        cancelled                    = 'Mission cancelled.',
        cancelled_by_player          = 'You cancelled the mission.',
        delivery_timeout             = 'You ran out of time.',
        no_permission                = 'You do not have permission.',
        -- Cleanup
        cleanup_collected_format     = 'Collected %d/%d %s',
        cleanup_collected_single     = 'Collected %s',
        pickup_label                 = 'Pick up',
        -- HUD text
        delivery_near                = 'Press [E] to deliver (%s)',
        delivery_timer               = 'You have %s remaining',
        placement_hint               = '[E] Place  [Scroll] Rotate  [Backspace] Cancel',
        -- NUI panel
        panel_title                  = 'Missions',
        tab_available                = 'Available',
        tab_archived                 = 'Archived',
        filter_placeholder           = 'Filter missions\u{2026}',
        empty_available              = 'Accept missions to add them here.',
        empty_filter                 = 'No missions match your filter.',
        empty_detail                 = 'Select a mission to view details',
        status_active                = 'in progress',
        status_complete              = 'complete',
        status_cooldown              = 'on cooldown',
        status_cancelled             = 'cancelled',
        btn_accept                   = 'Accept',
        btn_reject                   = 'Reject',
        btn_claim                    = 'Claim Reward',
        btn_collect                  = 'Collect Reward',
        btn_cancel                   = 'Cancel',
        btn_waypoint                 = 'Set Waypoint',
        btn_admin                    = 'Mission Admin',
        rewards_label                = 'Rewards',
        cooldown_comeback            = 'Come back in %s',
        currency_prefix              = '$',
    },
}
