# tls_sickness (v0.3)

DayZ-style sickness for QB-Core. Wet exposure causes illness; eating human/zombie meat causes madness (laughing). Gradual cures, HUD exports, progress bars, cooldowns, persistence (DB/file), proximity audio, logging, admin commands, and debug tools.

## Install
1. Drop the folder into `resources` and `ensure tls_sickness` **after** `qb-core` (and `hate-temp` if your using it).
2. HUD hook (example for hate-dayzhud):
   ```lua
   Config.GetSickness = function()
       return exports['tls_sickness']:GetSicknessForHUD()
   end
   ```
3. Qbcore Items (For Core Inventory)
  ```
  sickness_pills   = { name = 'sickness_pills', label = 'Sickness Pills', weight = 0, type = 'item', image = 'sickness_pills.png', unique = false, useable = true, shouldClose = true, description = 'The Label Has Been Ripped Off', x = 1,   y = 2, category = 'ENTER YOUR CATEGORY HERE!!!!!!', },
  ```
  (Non Core Inventory)
  ```
  sickness_pills   = { name = 'sickness_pills', label = 'Sickness Pills', weight = 0, type = 'item', image = 'sickness_pills.png', unique = false, useable = true, shouldClose = true, description = 'The Label Has Been Ripped Off',},
  ```

## Persistence (Default: Database via oxmysql)
- Configure in `config.lua`:
  ```lua
  Config.Persistence = {
    mode = 'database',     -- 'off' | 'file' | 'database'
    useOxMySQL = true,
    Table = 'tls_sickness',
    AutoCreateTable = true,
    FileName = 'data/sickness.json',
    Sync = { IntervalSec = 30, OnlyIfChanged = true, MinSaveIntervalSec = 20 }
  }
  ```
- **SQL (if you prefer to create manually):**
  ```sql
  CREATE TABLE IF NOT EXISTS `tls_sickness` (
    `citizenid` VARCHAR(64) PRIMARY KEY,
    `wet` FLOAT NOT NULL DEFAULT 0,
    `madness` FLOAT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  );
  ```

## Logging
Configure one of:
```lua
-- 'off' | 'discord' | 'ox' | 'both'
Config.Logging = {
  mode = 'discord',
  Discord = {
    Webhook = 'https://discord.com/api/webhooks/XXXX/XXXX', -- put your URL
    Username = 'tls_sickness',
    Avatar = '',
    Color = 16753920
  },
  Ox = { Category = 'tls_sickness' }
}
-- Extra logging
Config.LoggingThresholds = { Madness = 50.0, WetLevel = nil } -- nil uses Wet.SickThreshold
Config.LogCooldownDenials = true
```
- Logs pills usage, cannibal/clean meat, laughter, **threshold crossings** (enter/exit), and **cooldown denials**.

## Admin Commands
- `/sick_get [id]` — show current wet & madness.
- `/sick_set <id> <wet> <mad>` — set both values.
- `/sick_add <id> <wetDelta> <madDelta>` — add/subtract amounts.
- `/sick_reset <id>` — reset to 0.
- `/sick_save <id>` — force-save to persistence.
- `/sick_load <id>` — reload from persistence.
- `/sick_cooldowns [id]` — show remaining cooldowns.
- `/sick_debug <id> <on/off> [intervalSec]` — toggle client debug prints.

## Cooldowns + Progress
- 5-minute cooldown on pills and human/zombie meat (10s on-screen message with time left).
- Uses `ox_lib` progress bar if available, else QBCore/progressbar, else a simple wait.

## Wet Source
- `Config.WetCheck.mode`: `'hate-temp' | 'custom' | 'off'`.

## Audio (proximity)
- Others within `Config.Audio.Hearing.Radius` hear laughs with distance-based volume.

## Exports (for HUD)
- `GetSicknessForHUD()`, `GetSicknessState()`, `IsWetSick()`, `IsCannibalCrazy()`, etc.

## Debug
- `Config.Debug.Enabled = true` to print periodic sickness values to console (or use `/sick_debug`). 
