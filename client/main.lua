\
local QBCore = exports['qb-core']:GetCoreObject()

-- STATE
local wetLevel = 0.0
local madness = 0.0

local nextCoughAt = 0
local nextLaughAt = 0

local heal = { wet = { rate=0.0, endsAt=0 }, mad = { rate=0.0, endsAt=0 } }

local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function isMale(ped) return IsPedMale(ped) end
local function randomRange(a,b) return math.random(a,b) end

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

-- Anim helpers
local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer()+5000
    while not HasAnimDictLoaded(dict) do Wait(10) if GetGameTimer()>t then break end end
    return HasAnimDictLoaded(dict)
end

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
        local ped=PlayerPedId()
        if isMale(ped) then playSound(Config.Sounds.MaleCough) else playSound(Config.Sounds.FemaleCough) end
        scheduleNextCough()
    end
end
local function laughMaybe()
    if not isCrazy() then return end
    if GetGameTimer()>=nextLaughAt then
        local ped=PlayerPedId()
        local variant='male'
        if isMale(ped) then playSound(Config.Sounds.MaleLaugh) variant='male'
        else
            if madness>=Config.Madness.EvilLaughThreshold and Config.Sounds.FemaleEvilLaugh then playSound(Config.Sounds.FemaleEvilLaugh) variant='female_evil'
            else playSound(Config.Sounds.FemaleLaugh) variant='female' end
        end
        local p=GetEntityCoords(ped)
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
    if anim.dict and anim.anim and loadAnimDict(anim.dict) then TaskPlayAnim(ped, anim.dict, anim.anim, 1.0,1.0,-1, anim.flag or 0, 0.0,false,false,false) playing=true end
    local progressed=false
    CreateThread(function() Wait(math.max(0, anim.stopEarlyMs or 2500)) if playing and not progressed then StopAnimTask(ped, anim.dict, anim.anim, 1.0) end end)
    if doProgress('pills') then progressed=true ClearPedTasks(ped) TriggerServerEvent('tls_sickness:server:UsePills') else progressed=true ClearPedTasks(ped) QBCore.Functions.Notify('Canceled.','error') end
end)
RegisterNetEvent('tls_sickness:client:EatCannibalStart', function(item) if doProgress('eatCannibal') then TriggerServerEvent('tls_sickness:server:ConsumeItemAndApply', item, 'cannibal') else QBCore.Functions.Notify('Canceled.','error') end end)
RegisterNetEvent('tls_sickness:client:EatCleanStart', function(item) if doProgress('eatClean') then TriggerServerEvent('tls_sickness:server:ConsumeItemAndApply', item, 'clean') else QBCore.Functions.Notify('Canceled.','error') end end)

RegisterNetEvent('tls_sickness:client:Cooldown', function(kind,msLeft) local what = (kind=='pills' and 'take medication') or (kind=='cannibal' and 'eat human/zombie meat') or 'use this' QBCore.Functions.Notify(('You can\'t %s for %s.'):format(what, fmt(msLeft or 0)), 'error', 10000) end)

RegisterNetEvent('tls_sickness:client:UsePills', function()
    local w=Config.Healing.WetFromPills local m=Config.Healing.MadFromPills
    if w and w.ratePerSec and w.durationSec then startWetHeal(w.ratePerSec, w.durationSec, true) end
    if m and m.ratePerSec and m.durationSec then startMadHeal(m.ratePerSec, m.durationSec, true) end
    QBCore.Functions.Notify('You take sickness pills…', 'success')
end)
RegisterNetEvent('tls_sickness:client:AteCannibal', function() madness=clamp(madness+Config.Madness.AddPerCannibalBite,0.0,Config.Madness.Max) QBCore.Functions.Notify('You feel… off.','error') scheduleNextLaugh() end)
RegisterNetEvent('tls_sickness:client:AteCleanMeat', function() local c=Config.Healing.MadFromClean if c and c.ratePerSec and c.durationSec then startMadHeal(c.ratePerSec, c.durationSec, true) end QBCore.Functions.Notify('You feel more grounded.','success') end)

-- Hear others' laughter
RegisterNetEvent('tls_sickness:client:HearLaugh', function(variant,vol)
    local file=Config.Sounds.MaleLaugh
    if variant=='female' then file=Config.Sounds.FemaleLaugh elseif variant=='female_evil' then file=Config.Sounds.FemaleEvilLaugh end
    playSound(file, math.max(0.0, math.min(1.0, vol or 0.6)))
end)

-- Admin-support: client debug & state replies
local dbgOverride = nil
local dbgIntervalOverride = nil
RegisterNetEvent('tls_sickness:client:SetDebug', function(enable, intervalSec) dbgOverride = enable dbgIntervalOverride = intervalSec end)
RegisterNetEvent('tls_sickness:client:AdminRequestState', function(requesterSrc, purpose)
    TriggerServerEvent('tls_sickness:server:AdminStateReport', requesterSrc, purpose, {
        wetLevel = wetLevel, madness = madness,
        wetSick = (wetLevel >= Config.Wet.SickThreshold),
        crazy = (madness >= Config.Madness.CrazyThreshold)
    })
end)

RegisterNetEvent('tls_sickness:client:SetState', function(saved) if type(saved)~='table' then return end wetLevel=tonumber(saved.wetLevel or wetLevel) or wetLevel madness=tonumber(saved.madness or madness) or madness end)

-- Periodic sync
CreateThread(function()
    local s=(Config.Persistence and Config.Persistence.Sync) or { IntervalSec=30, OnlyIfChanged=true }
    local interval=math.max(5, s.IntervalSec or 30)*1000 local onlyChanged=(s.OnlyIfChanged~=false)
    local lw, lm = -1, -1
    while true do Wait(interval) if Config.Persistence and Config.Persistence.mode~='off' then if (not onlyChanged) or (wetLevel~=lw or madness~=lm) then lw, lm = wetLevel, madness TriggerServerEvent('tls_sickness:server:SyncState', wetLevel, madness) end end end
end)

-- Debug (admin override capable)
CreateThread(function()
    while true do
        local interval = dbgIntervalOverride or ((Config.Debug and Config.Debug.LogIntervalSec) or 10)
        if interval < 3 then interval = 3 end
        Wait(interval * 1000)
        local enabled = (dbgOverride ~= nil and dbgOverride) or (Config.Debug and Config.Debug.Enabled)
        if enabled then
            print(('[tls_sickness] wet=%.1f mad=%.1f wetSick=%s crazy=%s'):format(
                wetLevel, madness,
                tostring(wetLevel >= Config.Wet.SickThreshold),
                tostring(madness >= Config.Madness.CrazyThreshold)
            ))
        end
    end
end)

-- Exports
exports('GetWetSicknessLevel', function() return wetLevel end)
exports('GetCannibalMadnessLevel', function() return madness end)
exports('IsWetSick', function() return wetLevel>=Config.Wet.SickThreshold end)
exports('IsCannibalCrazy', function() return madness>=Config.Madness.CrazyThreshold end)
exports('GetSicknessState', function() return { wetLevel=wetLevel, madness=madness, wetSick=wetLevel>=Config.Wet.SickThreshold, crazy=madness>=Config.Madness.CrazyThreshold, nextCoughIn=math.max(0, nextLaughAt-GetGameTimer()), nextLaughIn=math.max(0, nextLaughAt-GetGameTimer()), healing={wetEndsAt=heal.wet.endsAt, madEndsAt=heal.mad.endsAt} } end)
exports('GetSicknessForHUD', function() local wetPct=wetLevel/Config.Wet.Max local madPct=madness/Config.Madness.Max return math.floor((math.max(wetPct, madPct)*100)+0.5) end)
