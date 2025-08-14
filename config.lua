Config = {}

-- If true, this resource registers the items below as usable via QBCore.
-- If you already have your own food/med usage system, set this to false
-- and call the server events listed at the bottom of this file.
Config.RegisterUsables = true

-- Items
Config.ItemPills = 'sickness_pills'

-- Cannibal items increase madness
Config.CannibalItems = {
    'human_meat', 'zombie_foot', 'zombie_brain', 'zombie_heart', 'zombie_lungs', 'zombie_arm'
}

-- Clean meats reduce madness slowly over time
Config.CleanMeatItems = {
    'deer_meat', 'hog_meat', 'boar_meat', 'beef', 'pork', 'chicken', 'venison'
}

-- ========= WET CHECK SOURCE =========
-- mode = 'hate-temp' | 'custom' | 'off'
--  - 'hate-temp' uses exports['hate-temp']:iswet()
--  - 'custom'   uses CustomFn() if provided, otherwise calls exports[Resource][Export](table.unpack(Args))
--  - 'off'      disables wet accumulation from water (only cannibal madness remains)
Config.WetCheck = {
    mode = 'hate-temp',
    Resource = '',            -- your resource providing the export (only if mode='custom')
    Export = '',              -- export name (string)            (only if mode='custom')
    Args = {},                -- args for the export (optional)  (only if mode='custom')
    CustomFn = nil            -- function() return boolean end   (only if mode='custom')
}

-- WET SICKNESS (builds while wet)
Config.Wet = {
    TickMs = 2000,              -- how often to tick
    IncreasePerTick = 2.0,      -- added while wet
    Max = 100.0,
    SickThreshold = 25.0,       -- coughs above this
    CoughMinDelay = 18,         -- seconds (randomized)
    CoughMaxDelay = 42
}

-- CANNIBAL MADNESS (builds as you eat cannibal items)
Config.Madness = {
    Max = 100.0,
    AddPerCannibalBite = 15.0,
    CrazyThreshold = 30.0,      -- laughs above this

    -- Laugh timing: gets faster as madness grows
    BaseLaughMin = 90, BaseLaughMax = 160,      -- secs at low madness
    FastLaughMin = 25, FastLaughMax = 55,       -- secs near max
    EvilLaughThreshold = 70.0                    -- female evil laugh past this
}

-- === Healing is SLOW/OVER-TIME ===
-- Rates are "points per second" and stack by extending duration.
Config.Healing = {
    WetFromPills = { ratePerSec = 8.0,  durationSec = 20 }, -- cures wet sickness over ~20s
    MadFromPills = { ratePerSec = 4.0,  durationSec = 30 }, -- reduces madness over ~30s
    MadFromClean = { ratePerSec = 2.0,  durationSec = 20 }  -- reduces madness over ~20s
}

-- ========= PROGRESS BAR =========
-- mode: 'auto' | 'ox' | 'qb' | 'none'
--  - 'auto' prefers ox_lib if started, otherwise falls back to QBCore/progressbar
-- Durations are in milliseconds.
Config.Progress = {
    mode = 'auto', useWhileDead = false, canCancel = true,
    disable = { move = false, car = false, mouse = false, combat = true },
    pills = { duration = 5000, label = 'Taking sickness pills' },
    eatCannibal = { duration = 3000, label = 'Eating human/zombie meat' },
    eatClean = { duration = 3000, label = 'Eating cooked meat' }
}

-- ========= COOLDOWNS =========
-- 5 minutes cooldowns for pills and cannibal meats. Clean meat has no cooldown by default.
Config.Cooldowns = {
    Pills = 5 * 60 * 1000,        -- ms
    Cannibal = 5 * 60 * 1000,     -- ms
    Clean = 0                     -- ms
}

-- Debug
Config.Debug = { Enabled = false, LogIntervalSec = 10 }

-- SFX
Config.Sounds = {
    MaleLaugh = 'tls_male_laugh.ogg',
    FemaleLaugh = 'tls_female_laugh.ogg',
    FemaleEvilLaugh = 'tls_female_evil_laugh.ogg',
    MaleCough = 'tls_male_cough.ogg',
    FemaleCough = 'tls_female_cough.ogg',
    Volume = 0.85
}

-- Logging: 'off' | 'discord' | 'ox' | 'both'
Config.Logging = {
    mode = 'off',
    Discord = {
        Webhook = '', -- put your Discord webhook URL here
        Username = 'tls_sickness',
        Avatar = '',
        Color = 16753920 -- orange ish
    },
    Ox = { Category = 'tls_sickness' }
}

-- Extra logging options
Config.LoggingThresholds = {
    Madness = 50.0,      -- logs when crossing this value (enter/exit)
    WetLevel = nil       -- nil uses Config.Wet.SickThreshold
}
Config.LogCooldownDenials = true
