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
    seedMissions = true, -- Set to false to prevent example missions from being inserted on startup

    missions = {
        {
            id = 'cleanup_beach',
            label = 'Beach Cleanup',
            description = 'Some dirty bastard has chucked about a load of bin bags around the beach! Can you help me clear them up?',
            type = 'cleanup',
            cooldownSeconds = 10,
            npc = {
                id = 'beach_keeper',
                model = 'S_F_Y_Baywatch_01',
                coords = vec4(-1605.68, -1111.22, 2.32, 130.0),
                scenario = 'WORLD_HUMAN_CLIPBOARD',
                target = { icon = 'fa-solid fa-recycle', label = 'Help Stranger' },
                blip = { sprite = 317, color = 3, scale = 0.7 },
                speech = 'GENERIC_HOWS_IT_GOING',
                speechClaim = 'GENERIC_THANKS',
                speechBye = 'GENERIC_BYE',
            },
            params = {
                props = {
                    { model = 'prop_rub_binbag_01', coords = vec3(-1465.32, -1204.21, 2.92) },
                    { model = 'prop_ld_rub_binbag_01', coords = vec3(-1470.54, -1198.83, 2.92) },
                    { model = 'prop_rub_binbag_01', coords = vec3(-1458.19, -1209.67, 2.92) },
                    { model = 'prop_ld_rub_binbag_01', coords = vec3(-1475.11, -1195.30, 2.92) },
                    { model = 'prop_rub_binbag_01', coords = vec3(-1462.78, -1215.42, 2.92) },
                },
                itemLabel = 'trash bag',
            },
            messages = {
                pickup = 'You picked up a trash bag.',
            },
            reward = {
                cash = 2500,
                items = {
                    { name = 'water', count = 2 },
                },
            },
        },
        {
            id = 'delivery_quickdrop',
            label = 'Express Delivery',
            description = 'Deliver this package across town before the timer runs out.',
            type = 'delivery',
            cooldownSeconds = 10,
            npc = {
                id = 'courier_bob',
                model = 's_m_m_postal_01',
                coords = vec4(84.57, 110.16, 78.15, 83.6),
                scenario = 'WORLD_HUMAN_CLIPBOARD',
                target = { icon = 'fa-solid fa-box', label = 'Talk: Express Delivery' },
                blip = { sprite = 501, color = 5, scale = 0.7 },
                speechClaim = 'GENERIC_THANKS',
                speechBye = 'GENERIC_BYE',
            },
            params = {
                destination = vec3(-537.46, -216.97, 37.65),
                timeSeconds = 90,
                prop = 'hei_prop_heist_box',
                carry = 'both_hands',
            },
            reward = {
                cash = 1500,
                items = {},
            },
        },
        {
            id = 'assassination_parksuspect',
            label = 'Park Pervert',
            description = "There's some pervert lurking in the park, his name is James Day, If you deal with him I'll make it worth your while.",
            type = 'assassination',
            cooldownSeconds = 1000,
            npc = {
                id = 'fixer_joe',
                model = 's_m_y_dealer_01',
                coords = vec4(-1082.93, -1674.28, 3.70, 0.0),
                target = { icon = 'fa-solid fa-skull', label = 'Help Stranger' },
                blip = { sprite = 303, color = 1, scale = 0.7 },
                speechClaim = 'GENERIC_THANKS',
                speechBye = 'GENERIC_BYE',
            },
            params = {
                aggressive = false,
                targets = {
                    {
                        model = 'a_m_y_acult_01',
                        coords = vec4(202.02, -932.53, 30.69, 0.0),
                        scenario = 'WORLD_HUMAN_STAND_MOBILE',
                    },
                },
                blip = true,
            },
            reward = { cash = 3000, items = {} },
        },
        {
            id = 'assassination_gang_melee',
            label = 'Ambush the Ambushers',
            description = "Some biker freaks are planning to ambush a shipment we've got coming into the docks. Fuck 'em up!",
            type = 'assassination',
            cooldownSeconds = 10,
            npc = {
                id = 'gang_informant',
                model = 'g_m_y_ballaeast_01',
                coords = vec4(118.33, -1928.17, 19.71, 149.7),
                scenario = 'WORLD_HUMAN_SMOKING',
                target = { icon = 'fa-solid fa-user-slash', label = 'Help Stranger' },
                blip = { sprite = 303, color = 6, scale = 0.7 },
                speech = 'GENERIC_CHEER',
                speechClaim = 'GENERIC_CHEER',
                speechBye = 'GENERIC_BYE',
            },
            params = {
                aggressive = true,
                targets = {
                    {
                        model = 'g_m_y_lost_01',
                        coords = vec4(1205.67, -3116.23, 5.54, 85.0),
                        weapon = 'WEAPON_BAT',
                    },
                    {
                        model = 'g_m_y_lost_02',
                        coords = vec4(1208.42, -3113.78, 5.54, 200.0),
                    },
                    {
                        model = 'g_m_y_lost_03',
                        coords = vec4(1202.15, -3119.94, 5.54, 15.0),
                        weapon = 'WEAPON_MACHETE',
                    },
                },
                blip = true,
            },
            reward = {
                cash = 7500,
                items = {
                    { name = 'bandage', count = 3 },
                },
            },
        },
    },
}
