    local QBCore = exports['qb-core']:GetCoreObject()

    local lastPills, lastCannibal = {}, {}
    local store = {} -- citizenid -> { wetLevel, madness, lastSave, prevWet, prevMad }

    local function nowMs() return GetGameTimer() end
    local function remainingMs(last, cd) if not last or last==0 then return 0 end local rem=(last+cd)-nowMs() if rem<0 then return 0 end return rem end

    local function fmtMs(ms) local s=math.floor((ms or 0)/1000) local m=math.floor(s/60) local r=s%60 return (m..":"..(r<10 and "0"..r or r)) end
    local function dbg(msg) if Config.Debug and Config.Debug.Enabled then print('[tls_sickness][DEBUG] '..tostring(msg)) end end

    -- ========= Logging =========
    local function playerTag(src)
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return ('src:%s'):format(src) end
        local cid = Player.PlayerData and Player.PlayerData.citizenid or 'unknown'
        local name = ''
        if Player.PlayerData and Player.PlayerData.charinfo then
            local c = Player.PlayerData.charinfo
            name = ('%s %s'):format(c.firstname or '', c.lastname or '')
        end
        return ('%s (%s)'):format(name ~= ' ' and name or ('src:'..src), cid)
    end

    local function logDiscord(title, description, color)
        local cfg = Config.Logging and Config.Logging.Discord or {}
        weeklyUrl = cfg.Webhook or ''
        if weeklyUrl == '' then return end
        local payload = json.encode({
            username = cfg.Username or 'tls_sickness',
            avatar_url = cfg.Avatar or '',
            embeds = {{
                title = title,
                description = description,
                color = color or (cfg.Color or 16753920),
                timestamp = os.date('!%Y-%m-%dT%H:%M:%S.000Z')
            }}
        })
        PerformHttpRequest(weeklyUrl, function() end, 'POST', payload, { ['Content-Type'] = 'application/json' })
    end

    local function logOx(category, message)
        if GetResourceState('ox_lib') == 'started' and lib and lib.logger then
            lib.logger(category or (Config.Logging and Config.Logging.Ox and Config.Logging.Ox.Category) or 'tls_sickness', message)
        else
            print(('[tls_sickness][LOG] %s'):format(message))
        end
    end

    local function log(kind, src, extra)
        local mode = (Config.Logging and Config.Logging.mode) or 'off'
        if mode == 'off' then return end
        local who = playerTag(src)
        local msg = ('[%s] %s %s'):format(kind, who, extra or '')
        if mode == 'discord' or mode == 'both' then
            logDiscord(('tls_sickness: %s'):format(kind), msg, Config.Logging.Discord and Config.Logging.Discord.Color or 16753920)
        end
        if mode == 'ox' or mode == 'both' then
            logOx((Config.Logging and Config.Logging.Ox and Config.Logging.Ox.Category) or 'tls_sickness', msg)
        end
    end

    -- === Persistence: file & DB ===
    local resourceName = GetCurrentResourceName()
    local function fileName() return (Config.Persistence and Config.Persistence.FileName) or 'data/sickness.json' end
    local function fileLoadAll()
        local content = LoadResourceFile(resourceName, fileName())
        if not content or content=='' then return {} end
        local ok, data = pcall(json.decode, content) if ok and type(data)=='table' then return data else return {} end
    end
    local function fileSaveAll()
        local ok, data = pcall(json.encode, store) if not ok then return end
        SaveResourceFile(resourceName, fileName(), data or "{}", -1)
    end
    local function dbEnsure()
        if not Config.Persistence or not Config.Persistence.useOxMySQL then return end
        if GetResourceState('oxmysql') ~= 'started' then print('[tls_sickness] oxmysql not started; switching persistence to FILE') Config.Persistence.mode='file' return end
        if Config.Persistence.AutoCreateTable then
            local sql = ('CREATE TABLE IF NOT EXISTS %s (citizenid VARCHAR(64) PRIMARY KEY, wet FLOAT NOT NULL DEFAULT 0, madness FLOAT NOT NULL DEFAULT 0, updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP);'):format(Config.Persistence.Table)
            exports.oxmysql:execute(sql, {}, function() end)
        end
    end
    local function dbRead(cid, cb)
        if GetResourceState('oxmysql') ~= 'started' then cb(nil) return end
        exports.oxmysql:query(('SELECT wet, madness FROM %s WHERE citizenid = ?'):format(Config.Persistence.Table), {cid}, function(rows)
            if rows and rows[1] then cb({ wetLevel = rows[1].wet or 0, madness = rows[1].madness or 0 }) else cb(nil) end
        end)
    end
    local function dbWrite(cid, wet, mad)
        if GetResourceState('oxmysql') ~= 'started' then return end
        exports.oxmysql:execute(('INSERT INTO %s (citizenid, wet, madness) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE wet = VALUES(wet), madness = VALUES(madness), updated_at = CURRENT_TIMESTAMP'):format(Config.Persistence.Table), {cid, wet, mad})
    end

    CreateThread(function()
        if Config.Persistence and Config.Persistence.mode=='database' then dbEnsure()
        elseif Config.Persistence and Config.Persistence.mode=='file' then store = fileLoadAll() end
    end)

    -- Remove item helper
    local function tryRemoveItem(src, item, count)
        local Player = QBCore.Functions.GetPlayer(src) if not Player then return false end
        local ok = Player.Functions.RemoveItem(item, count or 1)
        if ok then TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[item], 'remove') return true end
        return false
    end

    local function tellCooldown(src, kind, msLeft) TriggerClientEvent('tls_sickness:client:Cooldown', src, kind, msLeft) end

    local function startPills(src)
        local cd = (Config.Cooldowns and Config.Cooldowns.Pills) or 0
        local rem = remainingMs(lastPills[src], cd) if rem>0 then tellCooldown(src,'pills',rem) if Config.LogCooldownDenials then log('COOLDOWN_DENIED', src, ('pills (%s left)'):format(fmtMs(rem))) end return end
        TriggerClientEvent('tls_sickness:client:UsePillsStart', src)
    end
    local function startCannibal(src, itemName)
        local cd = (Config.Cooldowns and Config.Cooldowns.Cannibal) or 0
        local rem = remainingMs(lastCannibal[src], cd) if rem>0 then tellCooldown(src,'cannibal',rem) if Config.LogCooldownDenials then log('COOLDOWN_DENIED', src, ('cannibal (%s left)'):format(fmtMs(rem))) end return end
        TriggerClientEvent('tls_sickness:client:EatCannibalStart', src, itemName)
    end

    if Config.RegisterUsables then
        QBCore.Functions.CreateUseableItem(Config.ItemPills, function(src, item) startPills(src) end)
        local cannibalSet = {} for _,v in ipairs(Config.CannibalItems) do cannibalSet[v]=true end
        local cleanSet = {} for _,v in ipairs(Config.CleanMeatItems) do cleanSet[v]=true end
        local function regIf(name, fn) if QBCore.Shared.Items[name] then QBCore.Functions.CreateUseableItem(name, fn) end end
        for n,_ in pairs(cannibalSet) do regIf(n, function(src,item) startCannibal(src, item.name) end) end
        for n,_ in pairs(cleanSet) do regIf(n, function(src,item) TriggerClientEvent('tls_sickness:client:EatCleanStart', src, item.name) end) end
    end

    -- Direct events (no progress)
    RegisterNetEvent('tls_sickness:server:UsePills', function()
        local src=source
        local cd=(Config.Cooldowns and Config.Cooldowns.Pills) or 0
        local rem=remainingMs(lastPills[src],cd) if rem>0 then tellCooldown(src,'pills',rem) if Config.LogCooldownDenials then log('COOLDOWN_DENIED', src, ('pills (%s left)'):format(fmtMs(rem))) end return end
        if tryRemoveItem(src, Config.ItemPills, 1) then
            lastPills[src]=nowMs()
            TriggerClientEvent('tls_sickness:client:UsePills', src)
            log('PILLS', src, 'used sickness pills')
        else
            TriggerClientEvent('QBCore:Notify', src, 'You don\'t have sickness pills.', 'error')
        end
    end)
    RegisterNetEvent('tls_sickness:server:ConsumeItemAndApply', function(itemName, kind)
        local src=source if not itemName or type(itemName)~='string' then return end
        if kind=='cannibal' then
            local cd=(Config.Cooldowns and Config.Cooldowns.Cannibal) or 0
            local rem=remainingMs(lastCannibal[src],cd) if rem>0 then tellCooldown(src,'cannibal',rem) if Config.LogCooldownDenials then log('COOLDOWN_DENIED', src, ('cannibal (%s left)'):format(fmtMs(rem))) end return end
            if not tryRemoveItem(src, itemName, 1) then TriggerClientEvent('QBCore:Notify', src, 'Item missing.', 'error') return end
            lastCannibal[src]=nowMs()
            TriggerClientEvent('tls_sickness:client:AteCannibal', src)
            log('CANNIBAL', src, ('ate %s'):format(itemName))
        elseif kind=='clean' then
            if not tryRemoveItem(src, itemName, 1) then TriggerClientEvent('QBCore:Notify', src, 'Item missing.', 'error') return end
            TriggerClientEvent('tls_sickness:client:AteCleanMeat', src)
            log('CLEAN_MEAT', src, ('ate %s'):format(itemName))
        end
    end)

    -- Proximity laughter
    RegisterNetEvent('tls_sickness:server:EmitLaugh', function(variant, pos)
        local src=source
        local radius = (Config.Audio and Config.Audio.Hearing and Config.Audio.Hearing.Radius) or 25.0
        local minV = (Config.Audio and Config.Audio.Hearing and Config.Audio.Hearing.MinVolume) or 0.25
        local maxV = (Config.Audio and Config.Audio.Hearing and Config.Audio.Hearing.MaxVolume) or 0.9
        local p=pos or {x=0.0,y=0.0,z=0.0}
        for _,id in pairs(GetPlayers()) do
            local pid=tonumber(id)
            if pid and pid~=src then
                local ped=GetPlayerPed(pid) if ped and ped~=0 then
                    local x,y,z=table.unpack(GetEntityCoords(ped))
                    local dx,dy,dz=(x-p.x),(y-p.y),(z-p.z)
                    local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
                    if dist<=radius then
                        local t=1.0-(dist/radius) local vol=minV+(maxV-minV)*t
                        TriggerClientEvent('tls_sickness:client:HearLaugh', pid, variant, vol)
                    end
                end
            end
        end
        log('LAUGH', src, ('variant=%s'):format(variant))
    end)

    -- Persistence sync + threshold logs
    RegisterNetEvent('tls_sickness:server:SyncState', function(wet, mad)
        local src=source
        local Player=QBCore.Functions.GetPlayer(src) if not Player then return end
        local cid=Player.PlayerData and Player.PlayerData.citizenid or nil if not cid then return end
        wet=tonumber(wet or 0) or 0 mad=tonumber(mad or 0) or 0
        if not store[cid] then store[cid]={wetLevel=0, madness=0, lastSave=0, prevWet=wet, prevMad=mad} end
        store[cid].wetLevel=wet store[cid].madness=mad

        -- Threshold crossing logs
        local wetThresh = (Config.LoggingThresholds and (Config.LoggingThresholds.WetLevel or Config.Wet.SickThreshold)) or Config.Wet.SickThreshold
        local madThresh = (Config.LoggingThresholds and (Config.LoggingThresholds.Madness or 50.0)) or 50.0
        local prevWet = store[cid].prevWet or wet
        local prevMad = store[cid].prevMad or mad
        local prevWetSick = (prevWet >= wetThresh)
        local currWetSick = (wet >= wetThresh)
        if prevWetSick ~= currWetSick then
            log('THRESHOLD', src, (currWetSick and 'ENTER wetSick' or 'EXIT wetSick')..(' (wet=%.1f thr=%.1f)'):format(wet, wetThresh))
        end
        local prevMadHigh = (prevMad >= madThresh)
        local currMadHigh = (mad >= madThresh)
        if prevMadHigh ~= currMadHigh then
            log('THRESHOLD', src, (currMadHigh and 'ENTER madness>=thr' or 'EXIT madness>=thr')..(' (mad=%.1f thr=%.1f)'):format(mad, madThresh))
        end
        store[cid].prevWet = wet
        store[cid].prevMad = mad

        local minInt=((Config.Persistence and Config.Persistence.Sync and Config.Persistence.Sync.MinSaveIntervalSec) or 20)*1000
        if nowMs()-(store[cid].lastSave or 0) < minInt then return end
        store[cid].lastSave=nowMs()
        if Config.Persistence and Config.Persistence.mode=='database' and GetResourceState('oxmysql')=='started' then
            dbWrite(cid, wet, mad) dbg(('Saved DB %s | wet=%.1f mad=%.1f'):format(cid, wet, mad))
        elseif Config.Persistence and Config.Persistence.mode=='file' then
            fileSaveAll() dbg(('Saved FILE %s | wet=%.1f mad=%.1f'):format(cid, wet, mad))
        end
    end)

    -- Player loaded
    RegisterNetEvent('QBCore:Server:PlayerLoaded', function(player)
        local src=source
        local Player=QBCore.Functions.GetPlayer(src) or player if not Player then return end
        local cid=Player.PlayerData and Player.PlayerData.citizenid or nil if not cid then return end
        if Config.Persistence and Config.Persistence.mode=='database' and GetResourceState('oxmysql')=='started' then
            dbRead(cid, function(row) if row then store[cid]={wetLevel=row.wetLevel or 0, madness=row.madness or 0, lastSave=0} TriggerClientEvent('tls_sickness:client:SetState', src, {wetLevel=store[cid].wetLevel, madness=store[cid].madness}) dbg(('Loaded DB %s | wet=%.1f mad=%.1f'):format(cid, store[cid].wetLevel, store[cid].madness)) end end)
        elseif Config.Persistence and Config.Persistence.mode=='file' then
            local f=store[cid] if f then TriggerClientEvent('tls_sickness:client:SetState', src, {wetLevel=f.wetLevel or 0, madness=f.madness or 0}) dbg(('Loaded FILE %s | wet=%.1f mad=%.1f'):format(cid, f.wetLevel or 0, f.madness or 0)) end
        end
    end)

    AddEventHandler('onResourceStart', function(res)
        if res~=GetCurrentResourceName() then return end
        if Config.Persistence and Config.Persistence.mode=='database' then dbEnsure() end
        Wait(1000)
        for _,id in pairs(GetPlayers()) do
            local src=tonumber(id)
            if src then
                local Player=QBCore.Functions.GetPlayer(src)
                if Player then
                    local cid=Player.PlayerData and Player.PlayerData.citizenid or nil
                    if cid then
                        if Config.Persistence and Config.Persistence.mode=='database' and GetResourceState('oxmysql')=='started' then
                            dbRead(cid, function(row) if row then store[cid]={wetLevel=row.wetLevel or 0, madness=row.madness or 0, lastSave=0} TriggerClientEvent('tls_sickness:client:SetState', src, {wetLevel=store[cid].wetLevel, madness=store[cid].madness}) end end)
                        elseif Config.Persistence and Config.Persistence.mode=='file' then
                            local f=store[cid] if f then TriggerClientEvent('tls_sickness:client:SetState', src, {wetLevel=f.wetLevel or 0, madness=f.madness or 0}) end
                        end
                    end
                end
            end
        end
    end)

    -- ======== Admin helpers ========
    local function isAdmin(src)
        if QBCore.Functions.HasPermission and (QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god')) then
            return true
        end
        if IsPlayerAceAllowed and IsPlayerAceAllowed(src, 'command') then return true end
        return false
    end

    local function parseTargetId(arg)
        local id = tonumber(arg)
        if id and GetPlayerPing(id) > 0 then return id end
        return nil
    end

    local function notify(src, msg, typ)
        TriggerClientEvent('QBCore:Notify', src, msg, typ or 'primary', 7500)
    end

    -- Admin state report from client
    RegisterNetEvent('tls_sickness:server:AdminStateReport', function(requesterSrc, purpose, state)
        local src = source
        if not requesterSrc then return end
        if not isAdmin(requesterSrc) then return end
        local Player = QBCore.Functions.GetPlayer(src) ; if not Player then return end
        local cid = Player.PlayerData and Player.PlayerData.citizenid or nil ; if not cid then return end
        local wet = tonumber(state and state.wetLevel or 0) or 0
        local mad = tonumber(state and state.madness or 0) or 0
        if purpose == 'get' then
            notify(requesterSrc, ('[tls] ID %d wet=%.1f mad=%.1f'):format(src, wet, mad), 'primary')
            log('ADMIN_GET', requesterSrc, ('checked %s: wet=%.1f mad=%.1f'):format(playerTag(src), wet, mad))
        elseif purpose == 'save' then
            if not store[cid] then store[cid] = { wetLevel = 0, madness = 0, lastSave = 0 } end
            store[cid].wetLevel = wet ; store[cid].madness = mad
            if Config.Persistence and Config.Persistence.mode=='database' and GetResourceState('oxmysql')=='started' then
                dbWrite(cid, wet, mad)
            elseif Config.Persistence and Config.Persistence.mode=='file' then
                fileSaveAll()
            end
            notify(requesterSrc, ('[tls] Saved ID %d -> wet=%.1f mad=%.1f'):format(src, wet, mad), 'success')
            log('ADMIN_SAVE', requesterSrc, ('saved %s: wet=%.1f mad=%.1f'):format(playerTag(src), wet, mad))
        end
    end)

    -- ======== Admin Commands ========
    -- /sick_get [id]
    QBCore.Commands.Add('sick_get', 'Get sickness of a player', {{name='id', help='Server ID (optional)'}}, false, function(src, args)
        if not isAdmin(src) then return end
        local target = parseTargetId(args[1]) or src
        TriggerClientEvent('tls_sickness:client:AdminRequestState', target, src, 'get')
    end, 'admin')

    -- /sick_set <id> <wet> <mad>
    QBCore.Commands.Add('sick_set', 'Set wet & madness of a player', {{name='id', help='Server ID'}, {name='wet', help='0-100'}, {name='mad', help='0-100'}}, true, function(src, args)
        if not isAdmin(src) then return end
        local target = parseTargetId(args[1]) ; if not target then notify(src, 'Invalid ID', 'error') return end
        local wet = tonumber(args[2] or '') or 0 ; local mad = tonumber(args[3] or '') or 0
        if wet<0 then wet=0 elseif wet>100 then wet=100 end
        if mad<0 then mad=0 elseif mad>100 then mad=100 end
        local Player = QBCore.Functions.GetPlayer(target) ; if not Player then notify(src, 'Player not online', 'error') return end
        local cid = Player.PlayerData and Player.PlayerData.citizenid or nil ; if not cid then notify(src, 'Missing citizenid', 'error') return end
        if not store[cid] then store[cid] = { wetLevel = 0, madness = 0, lastSave = 0 } end
        store[cid].wetLevel = wet ; store[cid].madness = mad
        TriggerClientEvent('tls_sickness:client:SetState', target, { wetLevel = wet, madness = mad })
        notify(src, ('[tls] Set ID %d -> wet=%.1f mad=%.1f'):format(target, wet, mad), 'success')
        log('ADMIN_SET', src, ('set %s to wet=%.1f mad=%.1f'):format(playerTag(target), wet, mad))
    end, 'admin')

    -- /sick_add <id> <wetDelta> <madDelta>
    QBCore.Commands.Add('sick_add', 'Add to wet & madness', {{name='id', help='Server ID'}, {name='wetDelta', help='delta wet'}, {name='madDelta', help='delta mad'}}, true, function(src, args)
        if not isAdmin(src) then return end
        local target = parseTargetId(args[1]) ; if not target then notify(src, 'Invalid ID', 'error') return end
        local wD = tonumber(args[2] or '0') or 0 ; local mD = tonumber(args[3] or '0') or 0
        local Player = QBCore.Functions.GetPlayer(target) ; if not Player then notify(src, 'Player not online', 'error') return end
        local cid = Player.PlayerData and Player.PlayerData.citizenid or nil ; if not cid then notify(src, 'Missing citizenid', 'error') return end
        local curW = (store[cid] and store[cid].wetLevel) or 0 ; local curM = (store[cid] and store[cid].madness) or 0
        local wet = curW + wD ; if wet<0 then wet=0 elseif wet>100 then wet=100 end
        local mad = curM + mD ; if mad<0 then mad=0 elseif mad>100 then mad=100 end
        if not store[cid] then store[cid] = { wetLevel=0, madness=0, lastSave=0 } end
        store[cid].wetLevel = wet ; store[cid].madness = mad
        TriggerClientEvent('tls_sickness:client:SetState', target, { wetLevel = wet, madness = mad })
        notify(src, ('[tls] Added -> ID %d now wet=%.1f mad=%.1f'):format(target, wet, mad), 'success')
        log('ADMIN_ADD', src, ('added to %s; now wet=%.1f mad=%.1f'):format(playerTag(target), wet, mad))
    end, 'admin')

    -- /sick_reset <id>
    QBCore.Commands.Add('sick_reset', 'Reset wet & madness to 0', {{name='id', help='Server ID'}}, true, function(src, args)
        if not isAdmin(src) then return end
        local target = parseTargetId(args[1]) ; if not target then notify(src, 'Invalid ID', 'error') return end
        local Player = QBCore.Functions.GetPlayer(target) ; if not Player then notify(src, 'Player not online', 'error') return end
        local cid = Player.PlayerData and Player.PlayerData.citizenid or nil ; if not cid then notify(src, 'Missing citizenid', 'error') return end
        if not store[cid] then store[cid] = { wetLevel = 0, madness = 0, lastSave = 0 } end
        store[cid].wetLevel = 0 ; store[cid].madness = 0
        TriggerClientEvent('tls_sickness:client:SetState', target, { wetLevel = 0, madness = 0 })
        notify(src, ('[tls] Reset ID %d'):format(target), 'success')
        log('ADMIN_RESET', src, ('reset %s'):format(playerTag(target)))
    end, 'admin')

    -- /sick_save <id>
    QBCore.Commands.Add('sick_save', 'Force-save player sickness to persistence', {{name='id', help='Server ID'}}, true, function(src, args)
        if not isAdmin(src) then return end
        local target = parseTargetId(args[1]) ; if not target then notify(src, 'Invalid ID', 'error') return end
        TriggerClientEvent('tls_sickness:client:AdminRequestState', target, src, 'save')
    end, 'admin')

    -- /sick_load <id>
    QBCore.Commands.Add('sick_load', 'Reload sickness for player from persistence', {{name='id', help='Server ID'}}, true, function(src, args)
        if not isAdmin(src) then return end
        local target = parseTargetId(args[1]) ; if not target then notify(src, 'Invalid ID', 'error') return end
        local Player = QBCore.Functions.GetPlayer(target) ; if not Player then notify(src, 'Player not online', 'error') return end
        local cid = Player.PlayerData and Player.PlayerData.citizenid or nil ; if not cid then notify(src, 'Missing citizenid', 'error') return end
        if Config.Persistence and Config.Persistence.mode=='database' and GetResourceState('oxmysql')=='started' then
            dbRead(cid, function(row)
                if row then
                    store[cid] = { wetLevel = row.wetLevel or 0, madness = row.madness or 0, lastSave = 0 }
                    TriggerClientEvent('tls_sickness:client:SetState', target, { wetLevel = store[cid].wetLevel, madness = store[cid].madness })
                    notify(src, ('[tls] Loaded DB -> ID %d wet=%.1f mad=%.1f'):format(target, store[cid].wetLevel, store[cid].madness), 'success')
                    log('ADMIN_LOAD', src, ('loaded DB for %s'):format(playerTag(target)))
                else
                    notify(src, '[tls] No DB row found', 'error')
                end
            end)
        elseif Config.Persistence and Config.Persistence.mode=='file' then
            local f = store[cid]
            if f then
                TriggerClientEvent('tls_sickness:client:SetState', target, { wetLevel = f.wetLevel or 0, madness = f.madness or 0 })
                notify(src, ('[tls] Loaded FILE -> ID %d wet=%.1f mad=%.1f'):format(target, f.wetLevel or 0, f.madness or 0), 'success')
                log('ADMIN_LOAD', src, ('loaded FILE for %s'):format(playerTag(target)))
            else
                notify(src, '[tls] No FILE entry', 'error')
            end
        else
            notify(src, '[tls] Persistence off', 'error')
        end
    end, 'admin')

    -- /sick_cooldowns [id]
    QBCore.Commands.Add('sick_cooldowns', 'Show player cooldowns', {{name='id', help='Server ID (optional)'}}, false, function(src, args)
        if not isAdmin(src) then return end
        local target = parseTargetId(args[1]) or src
        local rp = remainingMs(lastPills[target], (Config.Cooldowns and Config.Cooldowns.Pills) or 0)
        local rc = remainingMs(lastCannibal[target], (Config.Cooldowns and Config.Cooldowns.Cannibal) or 0)
        notify(src, ('[tls] ID %d cooldowns -> pills: %s | cannibal: %s'):format(target, fmtMs(rp), fmtMs(rc)), 'primary')
        log('ADMIN_COOLDOWNS', src, ('checked cooldowns of %s'):format(playerTag(target)))
    end, 'admin')

    -- /sick_debug <id> <on/off> [intervalSec]
    QBCore.Commands.Add('sick_debug', 'Toggle client debug prints', {{name='id', help='Server ID'}, {name='on/off', help='on or off'}, {name='interval', help='seconds (optional)'}}, true, function(src, args)
        if not isAdmin(src) then return end
        local target = parseTargetId(args[1]) ; if not target then notify(src, 'Invalid ID', 'error') return end
        local onoff = tostring(args[2] or ''):lower()
        local enable = (onoff == 'on' or onoff == 'true' or onoff == '1')
        local interval = tonumber(args[3] or '') or nil
        TriggerClientEvent('tls_sickness:client:SetDebug', target, enable, interval)
        notify(src, ('[tls] Debug %s for ID %d%s'):format(enable and 'ON' or 'OFF', target, interval and (' @'..interval..'s') or ''), 'success')
        log('ADMIN_DEBUG', src, ('debug %s for %s'):format(enable and 'ON' or 'OFF', playerTag(target)))
    end, 'admin')

    AddEventHandler('playerDropped', function(reason)
        local src=source
        local Player=QBCore.Functions.GetPlayer(src) if not Player then return end
        local cid=Player.PlayerData and Player.PlayerData.citizenid or nil if not cid then return end
        if Config.Persistence and Config.Persistence.mode=='file' then fileSaveAll() dbg(('Dropped -> saved FILE %s'):format(cid)) end
    end)
