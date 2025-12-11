-- config.lua

Config = {}

-- Framework
Config.Framework = 'esx'         -- 'esx' or 'standalone' (standalone only partly implemented; ESX recommended)
Config.Debug = true

-- How many businesses a single player can own
Config.MaxBusinessesPerPlayer = 10

-- Interaction: 'target' (ox_target), 'textui' (ox_lib text ui), '3dtext'
Config.InteractionType = 'target'

-- Laptop model per location is configured below (must exist in the interior)
-- If you want ox_target support, ensure ox_target started and installed
Config.UseOxTarget = true

-- Minigames
Config.Minigames = {
    Lockpick = {
        -- you can swap this to your own lockpick resource
        Type = 'event',                     -- 'event' or 'export'
        Event = 'lockpick:client:start',    -- change to your event if needed
        Resource = nil,
        Export = nil
    },
    Hacking = {
        Type = 'export',
        Resource = 'howdy-hackminigame',    -- howdy-hackminigame resource
        Export = 'Begin',                   -- returns boolean, signature Begin(icons, time) :contentReference[oaicite:0]{index=0}
        Args = {
            icons = 4,
            time = 7000
        }
    }
}

-- Discord Logging
Config.Discord = {
    Enabled = true,
    Webhook = 'https://discord.com/api/webhooks/1447878130168758348/txpoz-FvNwi4p5bCUIizsJp94frjBCSYFS4MRWDWCRPFyfRC0cMc8NrltcrZdrJ461AM',
    Username = 'Illegal Businesses',
    Avatar = ''
}

-- Raids
Config.Raids = {
    Enabled = true,
    CheckIntervalMinutes = 30, -- raid check interval
    BaseRaidChance = 0.05,     -- 5% per check before security modifiers
    RequireOnDutyPolice = true,
    MinPolice = 3,
    PoliceJobs = { 'police' },  -- job names to count as police
    SecurityReductionPerLevel = 0.015,      -- reduces raid chance per security level
    RaidWindowMinutes = 30  -- cops have 30 minutes to respond
}

-- tk-dispatch integration
Config.Dispatch = {
    Enabled = true,
    UseTkDispatch = true,
    Jobs = { 'police' },
    Title = 'Suspicious activity at illegal business',
    Code = '10-90',
    Priority = 'high',
    Blip = {
        sprite = 431,
        scale = 1.0,
        color = 1,
        radius = 150.0
    }
}



-- Production settings (base values; upgraded by equipment/employees)
Config.Production = {
    BaseTickMinutes = 10,          -- every 10 minutes a "tick"
    BaseSuppliesPerTick = 5,       -- how many supplies consumed per tick
    BaseProductPerTick = 5,        -- how many products generated per tick
    EquipmentBonusPerLevel = 0.25, -- 25% more product/tick per level
    EmployeeBonusPerLevel = 0.25   -- 25% faster (effective extra tick multiplier)
}

-- Upgrade pricing (per level, level 0-3)
Config.UpgradePrices = {
    equipment = { 100000, 200000, 300000 }, -- lvl 1,2,3
    employees = { 75000, 150000, 225000 },
    security  = { 50000, 100000, 150000 }
}

Config.BusinessNPCs = {
    {
        model = `a_m_m_ktown_01`,
        coords = vec4(1368.738403, 3606.263672, 34.890869, 192.755920), -- example coords, change to your spot
        scenario = 'WORLD_HUMAN_CLIPBOARD'
    }
}

-- Business type definitions (generic settings per type)
Config.BusinessTypes = {
    meth = {
        label = 'Meth Lab',
        maxSupplies = 200,
        maxProduct = 200,
        productSellPrice = 2200,    -- per product unit
        supplyUnitPrice = 600,      -- per supply when buying directly
    },
    coke = {
        label = 'Cocaine Lockup',
        maxSupplies = 200,
        maxProduct = 200,
        productSellPrice = 2600,
        supplyUnitPrice = 700,
    },
    weed = {
        label = 'Weed Farm',
        maxSupplies = 250,
        maxProduct = 250,
        productSellPrice = 800,
        supplyUnitPrice = 350,
    },
    counterfeit = {
        label = 'Counterfeit Cash Factory',
        maxSupplies = 200,
        maxProduct = 200,
        productSellPrice = 1800,
        supplyUnitPrice = 500,
    },
    forgery = {
        label = 'Document Forgery Office',
        maxSupplies = 150,
        maxProduct = 150,
        productSellPrice = 3000,
        supplyUnitPrice = 900,
    }
}

-- Where the supply truck spawns for setup missions
Config.SetupTruck = vec4(2904.290039, 4383.072754, 50.325317, 19.842520)

Config.IPLSetup = {
    meth = {
        -- Shared interior coords for ALL meth labs (biker meth)
        interiorCoords = vec4(996.883545, -3200.769287, -36.400757, 277.795288),
        exitCoords     = vec4(996.883545, -3200.769287, -36.400757, 85.039368),

        -- Laptop inside interior
        laptopCoords = vec4(1001.907715, -3194.228516, -39.169922, 0.0),
        laptopModel  = `prop_laptop_lester2`,

        -- Where the stash is inside the lab
        stashCoords  = vec4(1004.45, -3194.67, -38.99, 359.75),

        cameraAccessCoords = vec4(1002.79, -3194.27, -39.169922, 360.00),
        cameraCoords = vec4(1469.02, 3588.08, 48.32, 76.09),

        securityGuards = {
            { coords = vec4(999.38, -3200.60, -37.3, 88.83), scenario = 'WORLD_HUMAN_GUARD_STAND' },
            { coords = vec4(998.59, -3199.87, -40.0, 272.22), scenario = 'WORLD_HUMAN_GUARD_PATROL' },
            -- (3rd slot used only at higher level, optional)
        },

        confiscateCoords = {
            x = 1017.28,
            y = -3199.23,
            z = -38.99,
        },

        -- Not used for meth because we use bob74_ipl directly,
        -- but keeping it for parity with other types if needed later.
        interiorConfig = nil
    },

    weed = {
        -- Shared interior coords for ALL meth labs (biker meth)
        interiorCoords = vec4(1066.114258, -3183.388916, -39.164062, 90.708656),
        exitCoords     = vec4(1066.351685, -3183.388916, -39.164062, 272.125977),

        -- Laptop inside interior
        laptopCoords = vec4(1045.120850, -3194.835205, -39.169922, 0.0),
        laptopModel  = `prop_laptop_lester2`,

        -- Where the stash is inside the lab
        stashCoords  = vec4(1042.958252, -3192.725342, -37.917236, 357.165344),

        -- Optional: camera position for security UI / camera system later
        cameraCoords = vec3(1710.290161, 4728.527344, 42.136230),

        -- Not used for meth because we use bob74_ipl directly,
        -- but keeping it for parity with other types if needed later.
        interiorConfig = nil
    },

    coke = {
        interiorCoords = vec4(1088.73, -3188.75, -38.99, 183.37),
        exitCoords     = vec4(1088.64, -3187.46, -38.99, 5.64),

        -- Laptop inside interior
        laptopCoords = vec4(1086.56, -3194.24, -39.169922, 90.00),
        laptopModel  = `prop_laptop_lester2`,

        -- Where the stash is inside the lab
        stashCoords  = vec4(1042.958252, -3192.725342, -37.917236, 357.165344),

        -- Optional: camera position for security UI / camera system later
        cameraCoords = vec3(716.72, -654.70, 27.78),

        -- Not used for meth because we use bob74_ipl directly,
        -- but keeping it for parity with other types if needed later.
        interiorConfig = nil
    },

    counterfeit = {
        interiorCoords = vec4(1138.07, -3198.96, -39.67, 22.84),
        exitCoords     = vec4(1138.08, -3199.16, -39.67, 185.40),

        -- Laptop inside interior
        laptopCoords = vec4(1129.52, -3193.67, -40.40, 178.57),
        laptopModel  = `prop_laptop_lester2`,

        -- Where the stash is inside the lab
        stashCoords  = vec4(1138.34, -3193.72, -40.39, 347.86),

        -- Optional: camera position for security UI / camera system later
        cameraCoords = vec3(-55.00, 6392.57, 31.62),

        -- Not used for meth because we use bob74_ipl directly,
        -- but keeping it for parity with other types if needed later.
        interiorConfig = nil
    },

    forgery = {
        interiorCoords = vec4(1172.99, -3196.31, -39.01, 87.34),
        exitCoords     = vec4(1173.78, -3196.62, -39.01, 270.90),

        -- Laptop inside interior
        laptopCoords = vec4(1160.20, -3192.77, -39.01, 187.31),
        laptopModel  = `prop_laptop_lester2`,

        -- Where the stash is inside the lab
        stashCoords  = vec4(1156.56, -3196.61, -39.01, 105.52),

        -- Optional: camera position for security UI / camera system later
        cameraCoords = vec3(-252.72, -2591.06, 6.00),

        -- Not used for meth because we use bob74_ipl directly,
        -- but keeping it for parity with other types if needed later.
        interiorConfig = nil
    },
}


Config.Locations = {
    -- Cocaine lockup
    coke_1 = {
        type  = 'coke',
        label = 'Cocaine Lockup',

        -- currently using interior coords as enter; later you’ll want an outside door
        enterCoords = vec4(716.72, -654.70, 27.78, 93.09),

        -- Setup truck alignment area (inside meth interior)
        setupDelivery = vec4(722.56, -640.54, 28.12, 358.37),

        price = 275000,
        area  = 'Del Perro Fwy',
        image = 'images/delperro.png',
        description = 'Secure lockup for high-value cocaine shipments.'
    },

    -- Counterfeit cash factory
    counterfeit_1 = {
        type  = 'counterfeit',
        label = 'Counterfeit Cash Factory',

        enterCoords = vec4(-55.00, 6392.57, 31.62, 228.24),

        setupDelivery = vec4(-72.01, 6392.43, 31.49, 137.35),

        price = 225000,
        area  = 'Great Ocean Hwy',
        image = 'images/greatocean.png',
        description = 'Underground printing operation for fake currency.'
    },

    -- Document forgery
    forgery_1 = {
        type  = 'forgery',
        label = 'Document Forgery Office',

        enterCoords = vec4(-252.72, -2591.06, 6.00, 273.71),

        setupDelivery = vec4(-240.55, -2558.03, 6.00, 268.91),

        price = 180000,
        area  = 'Plaice Pl',
        image = 'images/plaice.png',
        description = 'Quiet office dedicated to document forgery.'
    },

    -- Meth lab (this one is fully wired for the new system)
    meth_1 = {
        type  = 'meth',
        label = 'Meth Lab',

        -- OUTSIDE door (Ace Liquor)
        enterCoords = vec4(1406.676880, 3603.956055, 35.008789, 17.007874),

        -- Setup truck alignment area (inside meth interior)
        setupDelivery = vec4(1421.657104, 3616.852783, 34.924561, 22.677164),

        price = 200000,
        area  = 'Algonquin Boulevard',
        image = 'images/aceliquor.png',
        description = 'Industrial grow operation with loading bay access.'
    },

    -- Weed farm
    weed_1 = {
        type  = 'weed',
        label = 'Weed Farm',

        enterCoords = vec4(1710.290161, 4728.527344, 42.136230, 283.464569),

        setupDelivery = vec4(1722.751709, 4702.457031, 42.557495, 280.629913),

        price = 190000,
        area  = 'Grapeseed Main St',
        image = 'images/grapeseed.png',
        description = 'Hydroponic grow operation hidden underground.'
    }
}

-- Resupply mission definitions (simple single-point missions, expand as needed)
Config.ResupplyMissions = {
    [1] = {
        label = 'Cartel Smuggling Site',
        description = 'Steal a shipment from a cartel smuggling outpost.',
        coords = vec4(1402.53, 1148.39, 114.33, 265.0) -- example, change to your own spot
    },
    [2] = {
        label = 'Police Warehouse',
        description = 'Hit a lightly guarded police evidence warehouse.',
        coords = vec4(452.36, -981.07, 30.69, 180.0) -- example: near Mission Row
    },
    [3] = {
        label = 'MC Gang Convoy',
        description = 'Intercept an MC gang\'s supply stash.',
        coords = vec4(2335.67, 3126.45, 48.21, 95.0) -- example: highway area
    }
}

-- Sell mission definitions (deliver product to different buyers)
Config.SellMissions = {
    [1] = {
        label = 'Street Dealer',
        description = 'Sell your product to a local street dealer.',
        coords = vec4(-1172.43, -1571.76, 4.66, 130.0)
    },
    [2] = {
        label = 'Nightclub Contact',
        description = 'Deliver a shipment to a nightclub contact in the city.',
        coords = vec4(355.12, 297.52, 103.88, 160.0)
    },
    [3] = {
        label = 'Dockside Buyer',
        description = 'Load the product onto a container at the docks.',
        coords = vec4(1204.52, -3259.23, 5.09, 90.0)
    }
}

-- Anti-cheat: tokens used to validate mission completions, etc.
Config.MissionTokenLength = 16
