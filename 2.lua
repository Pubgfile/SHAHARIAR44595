-- ============================================================
--  FAST MOVEMENT (FORWARD ×3, HIGH ×3) BY @XTHRLEN
-- ============================================================

local BRPlayerCharacterBase = {
  ServerRPC = {}, ClientRPC = {}, MulticastRPC = {}, LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }

local TXtime_ticker = require('common.time_ticker')

local CFG = {
    Enabled       = true,
    Multiplier    = 10.0,
    MaxSafe       = 25.0,
    RampTime      = 0.5,
    VelocityBoost = 1.0,
    DEBUG         = true,
    ForwardBoost  = 3.0,   -- 🎯 FORWARD SPEED × 3
    HighBoost     = 3.0,   -- 🎯 HIGH SPEED × 3
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
    if f then f:write('=== Fast Movement 3X ===\n') f:close() end
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
end

-- 🎯 ENFORCE: Forward ×3, High ×3
local function Enforce(ch, cm, m)
    local mFwd  = m * (CFG.ForwardBoost or 3.0)
    local mHigh = m * (CFG.HighBoost or 3.0)
    
    pcall(function() cm.SpeedRate          = S.o.SpeedRate * m end)
    pcall(function() ch.SpeedValue         = S.o.Value * m end)
    pcall(function() cm.DefaultMaxWalkSpeed = S.o.Def * m end)
    
    -- FORWARD ×3
    pcall(function() ch.SpeedScale         = S.o.Scale * mFwd end)
    pcall(function() cm.MaxWalkSpeed        = S.o.Max * mFwd end)
    
    -- HIGH ×3
    pcall(function() ch.MaxSprintSpeed      = S.o.Sprint * mHigh end)
    pcall(function() ch.HighWalkSpeed       = S.o.High * mHigh end)
    
    pcall(function() ch.MaxCrouchSpeed      = S.o.Crouch * m end)
    pcall(function() ch.MaxProneSpeed       = S.o.Prone * m end)
    pcall(function() ch.MaxSprintCrouchSpeed= S.o.SprintCr * m end)
end

function _G.XThrlen_Speed(mult)
    mult = tonumber(mult) or 1.0
    if mult > CFG.MaxSafe then mult = CFG.MaxSafe end
    CFG.Multiplier = mult
    PLog(string.format('[SRCHUB] SPEED x%.1f (Forward x%.1f, High x%.1f)',
        mult, mult * (CFG.ForwardBoost or 3), mult * (CFG.HighBoost or 3)))
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
            Log(string.format('[hb] walk=%.0f high=%.0f vel=%.0f',
                tonumber(cm.MaxWalkSpeed) or -1,
                tonumber(ch.HighWalkSpeed) or -1,
                spd))
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
end

local function Tick(dt)
    local okT, err = pcall(TickInner, dt)
    if not okT then Log('TICK ERROR: ' .. tostring(err), true) end
end

if TXtime_ticker then
    _G.XThrlen_TimerIndex = TXtime_ticker.AddTimerLoop(0, Tick, -1, 0)
    PLog('[SRCHUB] Fast Movement 3X loaded - Forward ×3, High ×3!')
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
-- MENU (with debug print to find failure)
-- ============================================================
local function XThrlen_RegisterMenu()
    -- Debug: check each dependency
    local ok1, SettingPageDefine = pcall(require, "client.logic.NewSetting.SettingPageDefine")
    PLog("[SRCHUB] SettingPageDefine: " .. tostring(ok1) .. " / " .. tostring(SettingPageDefine ~= nil))
    
    local ok2, SettingCatalog = pcall(require, "client.logic.NewSetting.SettingCatalog")
    PLog("[SRCHUB] SettingCatalog: " .. tostring(ok2) .. " / " .. tostring(SettingCatalog ~= nil))
    
    local ok3, AliasMap = pcall(require, "client.slua.umg.NewSetting.Item.AliasMap")
    PLog("[SRCHUB] AliasMap: " .. tostring(ok3) .. " / " .. tostring(AliasMap ~= nil))
    
    if not (ok1 and ok2 and ok3 and SettingPageDefine and SettingCatalog and AliasMap) then
        PLog("[SRCHUB] ❌ Menu framework missing - use console")
        PLog("  _G.XThrlen_Speed(10)")
        PLog("  _G.XThrlen_Config.ForwardBoost = 3")
        PLog("  _G.XThrlen_Config.HighBoost = 3")
        return
    end
    
    -- Check Switcher/Slider exists
    PLog("[SRCHUB] AliasMap.Switcher: " .. tostring(AliasMap.Switcher))
    PLog("[SRCHUB] AliasMap.Slider: " .. tostring(AliasMap.Slider))
    
    if not AliasMap.Switcher or not AliasMap.Slider then
        PLog("[SRCHUB] ❌ Switcher/Slider missing")
        return
    end
    
    local ok = pcall(function()
        if SettingPageDefine.XThrlenFastMenu then
            PLog("[SRCHUB] Menu already registered")
            return
        end

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
            Key      = "XThrlen_Fast_ForwardBoost",
            UI       = AliasMap.Slider,
            Text     = "FORWARD BOOST (1-5x)",
            MinValue = 1, MaxValue = 5,
            min      = 1, max      = 5,
            GetFunc  = function() return _G.XThrlen_Config.ForwardBoost or 3 end,
            SetFunc  = function(_, v)
                _G.XThrlen_Config.ForwardBoost = v
                PLog("[SRCHUB] ForwardBoost: " .. tostring(v))
                return true
            end,
        })

        table.insert(items, {
            Key      = "XThrlen_Fast_HighBoost",
            UI       = AliasMap.Slider,
            Text     = "HIGH BOOST (1-5x)",
            MinValue = 1, MaxValue = 5,
            min      = 1, max      = 5,
            GetFunc  = function() return _G.XThrlen_Config.HighBoost or 3 end,
            SetFunc  = function(_, v)
                _G.XThrlen_Config.HighBoost = v
                PLog("[SRCHUB] HighBoost: " .. tostring(v))
                return true
            end,
        })

        SettingPageDefine.XThrlenFastMenu = {
            Key   = "XThrlenFastMenu",
            Text  = "FAST MOVEMENT 3X",
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
        PLog("[SRCHUB] ✅ Menu registered OK")
    end)

    if not ok then
        PLog("[SRCHUB] ❌ Menu insert failed")
    end
end

pcall(XThrlen_RegisterMenu)

-- ============================================================
-- CLASS REGISTRATION
-- ============================================================
local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)

return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  { SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature" },
  { CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature" },
  { SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature" },
  { TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature" },
  { LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature" },
  { FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature" },
  { CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCampCharacterFeature" },
  { BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature" },
  { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },
  { ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature" },
  { SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature" },
  { GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature" }
}, "BRPlayerCharacterBase")
