-- ============================================================
--  FAST MOVEMENT BY SRC HUB MADE BY @XTHRLEN
-- ============================================================

local TXtime_ticker = require('common.time_ticker')

local CFG = {
    Enabled       = true,
    Multiplier    = 10.0,  
    MaxSafe       = 25.0,
    RampTime      = 0.5,
    VelocityBoost = 1.0,   
    DEBUG         = true,
}

_G.XThrlen_Config  = CFG
_G.XThrlen_Enabled = true

local S = { char=nil, saved=false, o={}, curMult=1.0, hbT=0 }

local LOG_PATHS = {
    '/storage/emulated/0/Android/data/com.tencent.ig/files/XThrlen_log.txt',
    '/storage/emulated/0/Android/data/com.pubg.krmobile/files/XThrlen_log.txt',
}
local LOG_PATH = nil

local function Log(msg, force)
    if not (CFG.DEBUG or force) then return end
    pcall(function()
        if not LOG_PATH then
            for _, p in ipairs(LOG_PATHS) do
                local f = io.open(p, 'a')
                if f then f:close() LOG_PATH = p break end
            end
            if not LOG_PATH then LOG_PATH = LOG_PATHS[1] end
        end
        local f = io.open(LOG_PATH, 'a')
        if f then
            f:write(os.date('%H:%M:%S ') .. tostring(msg) .. '\n')
            f:close()
        end
    end)
end

pcall(function()
    local f = io.open(LOG_PATHS[1], 'w')
    if f then f:write('=== Fast Movement ===\n') f:close() end
    LOG_PATH = LOG_PATHS[1]
end)

local function PLog(msg)
    print(msg)
    Log(msg, true)
end

local function GetMyChar()
    local ok, ch = pcall(function()
        if not slua_GameFrontendHUD then return nil end
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not pc or not slua.isValid(pc) then return nil end
        return pc:GetPlayerCharacterSafety()
    end)
    if ok and ch and slua.isValid(ch) then return ch end
    return nil
end

local function IsSafeContext(ch)
    local safe = true
    pcall(function()
        local veh = ch.CurrentVehicle
        if veh and slua.isValid(veh) then safe = false end
    end)
    return safe
end

local function SaveOriginals(ch, cm)
    if S.saved then return end
    S.saved = true
    local o = S.o
    pcall(function() o.SpeedRate  = tonumber(cm.SpeedRate) or 1 end)
    pcall(function() o.Scale      = tonumber(ch.SpeedScale) or 1 end)
    pcall(function() o.Value      = tonumber(ch.SpeedValue) or 0 end)
    pcall(function() o.Def        = tonumber(cm.DefaultMaxWalkSpeed) or 600 end)
    pcall(function() o.Max        = tonumber(cm.MaxWalkSpeed) or 600 end)
    pcall(function() o.Sprint     = tonumber(ch.MaxSprintSpeed) or 600 end)
    pcall(function() o.High       = tonumber(ch.HighWalkSpeed) or o.Sprint end)
    pcall(function() o.Crouch     = tonumber(ch.MaxCrouchSpeed) or 300 end)
    pcall(function() o.Prone      = tonumber(ch.MaxProneSpeed) or 100 end)
    pcall(function() o.SprintCr   = tonumber(ch.MaxSprintCrouchSpeed) or 400 end)
    Log(string.format('orig: rate=%.2f scale=%.2f max=%.0f sprint=%.0f high=%.0f',
        o.SpeedRate, o.Scale, o.Max, o.Sprint, o.High))
end

local function Enforce(ch, cm, m)
    pcall(function() cm.SpeedRate          = S.o.SpeedRate * m end)
    pcall(function() ch.SpeedScale         = S.o.Scale * m end)
    pcall(function() ch.SpeedValue         = S.o.Value * m end)
    pcall(function() cm.MaxWalkSpeed        = S.o.Max * m end)
    pcall(function() cm.DefaultMaxWalkSpeed = S.o.Def * m end)
    pcall(function() ch.MaxSprintSpeed      = S.o.Sprint * m end)
    pcall(function() ch.HighWalkSpeed       = S.o.High * m end)
    pcall(function() ch.MaxCrouchSpeed      = S.o.Crouch * m end)
    pcall(function() ch.MaxProneSpeed       = S.o.Prone * m end)
    pcall(function() ch.MaxSprintCrouchSpeed= S.o.SprintCr * m end)
end

function _G.XThrlen_Speed(mult)
    mult = tonumber(mult) or 1.0
    if mult > CFG.MaxSafe then mult = CFG.MaxSafe end
    CFG.Multiplier = mult
    PLog(string.format('[SRCHUB] SPEED x%.1f', mult))
end

local function TickInner(dt)
    if not _G.XThrlen_Enabled then return end
    dt = math.min(tonumber(dt) or 0.033, 0.2)

    local ch = GetMyChar()
    if ch ~= S.char then
        if S.char and slua.isValid(S.char) then
            local okO, ocm = pcall(function()
                return S.char.STCharacterMovement or S.char.CharacterMovement
            end)
            if okO and ocm and slua.isValid(ocm) then
                pcall(function() ocm.SpeedRate = S.o.SpeedRate or 1 end)
            end
        end
        S.char = ch
        S.saved = false
        S.curMult = 1.0
    end
    if not ch then return end

    local cm = nil
    pcall(function() cm = ch.STCharacterMovement or ch.CharacterMovement end)
    if not cm or not slua.isValid(cm) then return end

    SaveOriginals(ch, cm)

    S.hbT = S.hbT + dt
    if S.hbT >= 3 then
        S.hbT = 0
        pcall(function()
            local v = ch:GetVelocity()
            local spd = math.sqrt(v.X * v.X + v.Y * v.Y)
            Log(string.format('[hb] rate=%.2f target=%.1f vel=%.0f',
                tonumber(cm.SpeedRate) or -1, CFG.Multiplier, spd))
        end)
    end

    local targetMult = (_G.XThrlen_Enabled and CFG.Enabled and IsSafeContext(ch))
        and CFG.Multiplier or 1.0

    if S.curMult < targetMult then
        S.curMult = math.min(S.curMult + dt / CFG.RampTime, targetMult)
    elseif S.curMult > targetMult then
        S.curMult = math.max(S.curMult - dt / CFG.RampTime, targetMult)
    end

    Enforce(ch, cm, S.curMult)

    if CFG.VelocityBoost > 1.01 then
        pcall(function()
            local v = cm.Velocity or ch:GetVelocity()
            if not v then return end
            local hs = math.sqrt(v.X * v.X + v.Y * v.Y)
            if hs < 80 then return end
            cm.Velocity = FVector(v.X * CFG.VelocityBoost,
                v.Y * CFG.VelocityBoost, v.Z)
        end)
    end
end

local function Tick(dt)
    local okT, err = pcall(TickInner, dt)
    if not okT then Log('TICK ERROR: ' .. tostring(err), true) end
end

if TXtime_ticker then
    _G.XThrlen_TimerIndex = TXtime_ticker.AddTimerLoop(0, Tick, -1, 0)
    PLog('[SRCHUB] Fast Movement loaded - 10x ON!')
else
    PLog('[SRCHUB] ERROR: time_ticker Not Found')
end

function _G.XThrlen_Unload()
    _G.XThrlen_Enabled = false
    local ch = S.char
    if ch and slua.isValid(ch) then
        pcall(function()
            local cm = ch.STCharacterMovement or ch.CharacterMovement
            if cm and slua.isValid(cm) then
                cm.SpeedRate = S.o.SpeedRate or 1
                cm.MaxWalkSpeed = S.o.Max or 600
                cm.DefaultMaxWalkSpeed = S.o.Def or 600
            end
            ch.SpeedScale = S.o.Scale or 1
            ch.MaxSprintSpeed = S.o.Sprint or 600
        end)
    end
    if _G.XThrlen_TimerIndex and TXtime_ticker then
        pcall(TXtime_ticker.RemoveTimer, _G.XThrlen_TimerIndex)
    end
    PLog('[SRCHUB] unloaded')
end

-- ============================================================
-- MENU (appended only - nothing above changed)
-- ============================================================
local function XThrlen_RegisterMenu()
    local ok = pcall(function()
        local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
        local SettingCatalog    = require("client.logic.NewSetting.SettingCatalog")
        local AliasMap          = require("client.slua.umg.NewSetting.Item.AliasMap")

        if SettingPageDefine.XThrlenFastMenu then return end

        local items = {}

        table.insert(items, {
            Key     = "XThrlen_Fast_Enable",
            UI      = AliasMap.Switcher,
            Text    = "FAST MOVEMENT (ON/OFF)",
            GetFunc = function() return _G.XThrlen_Enabled end,
            SetFunc = function(_, v)
                _G.XThrlen_Enabled = v
                PLog("[SRCHUB] Toggle: " .. tostring(v))
                return true
            end,
        })

        table.insert(items, {
            Key      = "XThrlen_Fast_Mult",
            UI       = AliasMap.Slider,
            Text     = "SPEED MULTIPLIER (1-25)",
            MinValue = 1, MaxValue = 25,
            min      = 1, max      = 25,
            GetFunc  = function() return _G.XThrlen_Config.Multiplier or 10 end,
            SetFunc  = function(_, v)
                _G.XThrlen_Speed(v)
                return true
            end,
        })

        table.insert(items, {
            Key      = "XThrlen_Fast_Ramp",
            UI       = AliasMap.Slider,
            Text     = "RAMP TIME (0.1-2.0s)",
            MinValue = 0.1, MaxValue = 2.0,
            min      = 0.1, max      = 2.0,
            GetFunc  = function() return _G.XThrlen_Config.RampTime or 0.5 end,
            SetFunc  = function(_, v)
                _G.XThrlen_Config.RampTime = v
                PLog("[SRCHUB] RampTime: " .. tostring(v))
                return true
            end,
        })

        table.insert(items, {
            Key     = "XThrlen_Fast_VelBoost",
            UI      = AliasMap.Switcher,
            Text    = "VELOCITY BOOST (extra push)",
            GetFunc = function() return (_G.XThrlen_Config.VelocityBoost or 1.0) > 1.01 end,
            SetFunc = function(_, v)
                _G.XThrlen_Config.VelocityBoost = v and 1.15 or 1.0
                PLog("[SRCHUB] VelBoost: " .. tostring(v))
                return true
            end,
        })

        SettingPageDefine.XThrlenFastMenu = {
            Key   = "XThrlenFastMenu",
            Text  = "FAST MOVEMENT",
            UIKey = "Setting_Page_Privacy",
            Category = {
                {
                    Key   = "Cat_XThrlenFast",
                    Text  = "SPEED SETTINGS",
                    Stack = items,
                },
            },
        }

        table.insert(SettingCatalog, #SettingCatalog + 1, SettingPageDefine.XThrlenFastMenu)
        PLog("[SRCHUB] Menu registered OK")
    end)

    if not ok then
        PLog("[SRCHUB] Menu unavailable - use console commands")
    end
end

pcall(XThrlen_RegisterMenu)

local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  {
    SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature"
  },
  {
    CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature"
  },
  {
    SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature"
  },
  {
    TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature"
  },
  {
    LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature"
  },
  {
    FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature"
  },
  {
    CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature"
  },
  {
    BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"
  },
  {
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
  },
  {
    ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"
  },
  {
    SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature"
  },
  {
    GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature"
  }
}, "BRPlayerCharacterBase")
