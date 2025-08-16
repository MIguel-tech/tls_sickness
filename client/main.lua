local QBCore = exports['qb-core']:GetCoreObject()

-- STATE
local wetLevel = 0.0
local madness = 0.0

local nextCoughAt = 0
local nextLaughAt = 0

local heal = { wet = { rate=0.0, endsAt=0 }, mad = { rate=0.0, endsAt=0 } }

local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function randomRange(a,b) return math.random(a,b) end

--ped-gender detection (prefers character data, then model, then native)
local function getPedGender()
    local ped = PlayerPedId()
    -- QBCore character data first
    local ok, pdata = pcall(function() return QBCore.Functions.GetPlayerData() end)
    if ok and type(pdata) == 'table' and pdata.charinfo ~= nil and pdata.charinfo.gender ~= nil then
        local g = pdata.charinfo.gender
        if g == 1 or g == 'F' or g == 'f' then return 'female' else return 'male' end
    end
    -- Model checks
    local model = GetEntityModel(ped)
    if model == GetHashKey('mp_f_freemode_01') then return 'female' end
    if model == GetHashKey('mp_m_freemode_01') then return 'male' end
    -- Fallback to native
    if not IsPedMale(ped) then return 'female' end
    return 'male'
end

-- Progress helper
local function doProgress(kind)
    local P = Config.Progress or {}
    local opt = (P[kind] or { duration = 2000, label = 'Working...' })
    local mode = (P.mode or 'auto')
    local canCancel = (P.canCancel ~= false)
    local useWhileDead = (P.useWhileDead == true)
    local disable = P.disable or { move = true, car = true, mouse = false, combat = true }

    local chosen = mode
    if mode == 'auto' then
        if GetResourceState('ox_lib') == 'started' and lib and lib.progressBar then chosen='ox' else chosen='qb' end
    end
    if chosen=='ox' and lib and lib.progressBar then
        return lib.progressBar({ duration=opt.duration, label=opt.label, useWhileDead=useWhileDead, canCancel=canCancel,
            disable={ move=disable.move, car=disable.car, mouse=disable.mouse, combat=disable.combat } })
    elseif chosen=='qb' and QBCore.Functions and QBCore.Functions.Progressbar then
        if GetResourceState('progressbar') ~= 'started' then Wait(opt.duration) return true end
        local p = promise.new()
        QBCore.Functions.Progressbar('tls_'..kind, opt.label, opt.duration, useWhileDead, canCancel, {
            disableMovement=disable.move, disableCarMovement=disable.car, disableMouse=disable.mouse, disableCombat=disable.combat
        }, {}, {}, {}, function() p:resolve(true) end, function() p:resolve(false) end)
        return Citizen.Await(p)
    else
        Wait(opt.duration) return true
    end
end

-- NUI sound
local function playSound(file, vol) SendNUIMessage({ action='play', file=file, volume=vol or Config.Sounds.Volume }) end

local function scheduleNextCough() nextCoughAt = GetGameTimer()+randomRange(Config.Wet.CoughMinDelay*1000, Config.Wet.CoughMaxDelay*1000) end
local function scheduleNextLaugh()
    local frac = madness/Config.Madness.Max
    local minS = math.floor(Config.Madness.BaseLaughMin + (Config.Madness.FastLaughMin-Config.Madness.BaseLaughMin)*frac)
    local maxS = math.floor(Config.Madness.BaseLaughMax + (Config.Madness.FastLaughMax-Config.Madness.BaseLaughMax)*frac)
    if maxS<=minS then maxS=minS+1 end
    nextLaughAt = GetGameTimer()+randomRange(minS*1000, maxS*1000)
end

local function isWetSick() return wetLevel>=Config.Wet.SickThreshold end
local function isCrazy() return madness>=Config.Madness.CrazyThreshold end

local function checkWet()
    local WC=Config.WetCheck or {} local mode=WC.mode or 'hate-temp'
    if mode=='off' then return false end
    if mode=='hate-temp' then if exports['hate-temp'] and exports['hate-temp'].iswet then return exports['hate-temp']:iswet() end return false end
    if type(WC.CustomFn)=='function' then local ok,ret=pcall(WC.CustomFn) if ok then return ret end return false end
    if (WC.Resource or '')~='' and (WC.Export or '')~='' then
        local ok,ret=pcall(function() return exports[WC.Resource][WC.Export](table.unpack(WC.Args or {})) end) if ok then return ret end
    end
    return false
end

local function startWetHeal(rate,dur,extend) local now=GetGameTimer() heal.wet.rate=rate if extend and heal.wet.endsAt>now then heal.wet.endsAt=heal.wet.endsAt+dur*1000 else heal.wet.endsAt=now+dur*1000 end end
local function startMadHeal(rate,dur,extend) local now=GetGameTimer() heal.mad.rate=rate if extend and heal.mad.endsAt>now then heal.mad.endsAt=heal.mad.endsAt+dur*1000 else heal.mad.endsAt=now+dur*1000 end end

local function coughMaybe()
    if not isWetSick() then return end
    if GetGameTimer()>=nextCoughAt then
        local gender = getPedGender()
        if gender == 'male' then playSound(Config.Sounds.MaleCough) else playSound(Config.Sounds.FemaleCough) end
        scheduleNextCough()
    end
end
local function laughMaybe()
    if not isCrazy() then return end
    if GetGameTimer()>=nextLaughAt then
        local gender = getPedGender()
        local variant='male'
        if gender == 'male' then playSound(Config.Sounds.MaleLaugh) variant='male'
        else
            if madness>=Config.Madness.EvilLaughThreshold and Config.Sounds.FemaleEvilLaugh then playSound(Config.Sounds.FemaleEvilLaugh) variant='female_evil'
            else playSound(Config.Sounds.FemaleLaugh) variant='female' end
        end
        local p=GetEntityCoords(PlayerPedId())
        TriggerServerEvent('tls_sickness:server:EmitLaugh', variant, {x=p.x,y=p.y,z=p.z})
        scheduleNextLaugh()
    end
end

local function fmt(ms) local sec=math.floor(ms/1000) local m=math.floor(sec/60) local s=sec%60 return string.format('%d:%02d',m,s) end

CreateThread(function()
    math.randomseed(GetGameTimer()%2147483647)
    scheduleNextCough() scheduleNextLaugh()
    while true do
        local tick=Config.Wet.TickMs Wait(tick) local dt=tick/1000.0 local now=GetGameTimer()
        local wasWet=isWetSick() local wasCrazy=isCrazy()
        if checkWet() then wetLevel=clamp(wetLevel+Config.Wet.IncreasePerTick,0.0,Config.Wet.Max) end
        if heal.wet.endsAt>now and heal.wet.rate>0 then wetLevel=clamp(wetLevel-(heal.wet.rate*dt),0.0,Config.Wet.Max) end
        if heal.mad.endsAt>now and heal.mad.rate>0 then madness=clamp(madness-(heal.mad.rate*dt),0.0,Config.Madness.Max) end
        coughMaybe() laughMaybe()
        if wasWet~=isWetSick() then scheduleNextCough() end
        if wasCrazy~=isCrazy() then scheduleNextLaugh() end
        TriggerEvent('tls_sickness:client:StateUpdated', { wetLevel=wetLevel, madness=madness, wetSick=isWetSick(), crazy=isCrazy(),
            nextCoughIn=math.max(0,nextCoughAt-now), nextLaughIn=math.max(0,nextLaughAt-now), healing={wetEndsAt=heal.wet.endsAt, madEndsAt=heal.mad.endsAt} })
    end
end)

-- Progress/anim + start
RegisterNetEvent('tls_sickness:client:UsePillsStart', function()
    local anim=(Config.Anim and Config.Anim.Pills) or { dict='mp_suicide', anim='pill', flag=0, stopEarlyMs=2500 }
    local ped=PlayerPedId() local playing=false
    if anim.dict and anim.anim and HasAnimDictLoaded and RequestAnimDict then
        if not HasAnimDictLoaded(anim.dict) then RequestAnimDict(anim.dict) while not HasAnimDictLoaded(anim.dict) do Wait(10) end end
        TaskPlayAnim(ped, anim.dict, anim.anim, 1.0,1.0,-1, anim.flag or 0, 0.0,false,false,false) playing=true
        CreateThread(function() Wait(math.max(0, anim.stopEarlyMs or 2500)) if playing then StopAnimTask(ped, anim.dict, anim.anim, 1.0) end end)
    end
    if doProgress('pills') then ClearPedTasks(ped) TriggerServerEvent('tls_sickness:server:UsePills') else ClearPedTasks(ped) end
end)
RegisterNetEvent('tls_sickness:client:EatCannibalStart', function(item) if doProgress('eatCannibal') then TriggerServerEvent('tls_sickness:server:ConsumeItemAndApply', item, 'cannibal') end end)
RegisterNetEvent('tls_sickness:client:EatCleanStart', function(item) if doProgress('eatClean') then TriggerServerEvent('tls_sickness:server:ConsumeItemAndApply', item, 'clean') end end)

RegisterNetEvent('tls_sickness:client:Cooldown', function(kind,msLeft) local what = (kind=='pills' and 'take medication') or (kind=='cannibal' and 'eat human/zombie meat') or 'use this' TriggerEvent('QBCore:Notify', ('You can\'t %s for %s.'):format(what, fmt(msLeft or 0)), 'error', 10000) end)

RegisterNetEvent('tls_sickness:client:UsePills', function()
    local w=Config.Healing.WetFromPills local m=Config.Healing.MadFromPills
    if w and w.ratePerSec and w.durationSec then local now=GetGameTimer() local d=w.durationSec*1000 heal.wet.rate=w.ratePerSec heal.wet.endsAt=now+d end
    if m and m.ratePerSec and m.durationSec then local now=GetGameTimer() local d=m.durationSec*1000 heal.mad.rate=m.ratePerSec heal.mad.endsAt=now+d end
    TriggerEvent('QBCore:Notify', 'You take sickness pills…', 'success')
end)
RegisterNetEvent('tls_sickness:client:AteCannibal', function() madness=math.min(Config.Madness.Max, madness+Config.Madness.AddPerCannibalBite) TriggerEvent('QBCore:Notify', 'You feel… off.', 'error') end)
RegisterNetEvent('tls_sickness:client:AteCleanMeat', function() local c=Config.Healing.MadFromClean if c and c.ratePerSec and c.durationSec then local now=GetGameTimer() local d=c.durationSec*1000 heal.mad.rate=c.ratePerSec heal.mad.endsAt=now+d end TriggerEvent('QBCore:Notify', 'You feel more grounded.', 'success') end)

-- Hear others' laughter
RegisterNetEvent('tls_sickness:client:HearLaugh', function(variant,vol)
    local file=Config.Sounds.MaleLaugh
    if variant=='female' then file=Config.Sounds.FemaleLaugh elseif variant=='female_evil' then file=Config.Sounds.FemaleEvilLaugh end
    playSound(file, math.max(0.0, math.min(1.0, vol or 0.6)))
end)

-- Stub admin events needed by server
RegisterNetEvent('tls_sickness:client:SetDebug', function(enable, intervalSec) end)
RegisterNetEvent('tls_sickness:client:AdminRequestState', function(requesterSrc, purpose)
    TriggerServerEvent('tls_sickness:server:AdminStateReport', requesterSrc, purpose, {
        wetLevel = wetLevel, madness = madness,
        wetSick = (wetLevel >= Config.Wet.SickThreshold),
        crazy = (madness >= Config.Madness.CrazyThreshold)
    })
end)

-- Exports
exports('GetWetSicknessLevel', function() return wetLevel end)
exports('GetCannibalMadnessLevel', function() return madness end)
exports('IsWetSick', function() return wetLevel>=Config.Wet.SickThreshold end)
exports('IsCannibalCrazy', function() return madness>=Config.Madness.CrazyThreshold end)
exports('GetSicknessState', function() return { wetLevel=wetLevel, madness=madness, wetSick=wetLevel>=Config.Wet.SickThreshold, crazy=madness>=Config.Madness.CrazyThreshold } end)
exports('GetSicknessForHUD', function() local wetPct=wetLevel/Config.Wet.Max local madPct=madness/Config.Madness.Max return math.floor((math.max(wetPct, madPct)*100)+0.5) end)
