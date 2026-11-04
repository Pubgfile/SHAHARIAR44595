-- BRPlayerCharacterBase.lua
-- Flash Speed ONLY (Time Dilation + Brute Force)

local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }

local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local EParachuteState = import("EParachuteState")
local EMovementMode = import("EMovementMode")
local STExtraGameStateBase = import("STExtraGameStateBase")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")

function BRPlayerCharacterBase:ctor() end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
  end
  if Client then GameplayData.AddCharacter(self.Object) end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  if PawnState == EPawnState.SwitchPP then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) then pc:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "") end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then GameplayData.RemoveCharacter(self.Object) end
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue() self:HandleNearDeathGiveupRescue() end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local comp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(comp) and self.bCanNearDeathGiveup == true then
    comp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then self:MulticastRPC_GmPlayAction(actionId) end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then return end
  local comp = self:GetPlayEmoteComponent()
  if not slua.isValid(comp) then return end
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then return end
  local asset = slua.loadObject(animCfg.Path)
  local assets = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = asset()
  comp:OnLoadEmoteAssetBegin(handle, actionId, assets, "")
  local asset_util = require("common.asset_util")
  asset_util.GetAssetsArrayAsyncParallel(FuncUtil.LuaArrayToTable(assets), function()
    comp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bSync)
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bSync
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInterrupt)
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInterrupt) end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

-- ============================================================
-- MOD SECTION
-- ============================================================

local function Notify(msg)
  local s = "[UX_Official] " .. tostring(msg)
  pcall(function() if _G.GTLModNotify then _G.GTLModNotify(s) end end)
  print(s)
end

local _slua = rawget(_G, "slua")
local function Valid(obj)
  if not obj then return false end
  if _slua and _slua.isValid then
    local ok, v = pcall(_slua.isValid, obj)
    if not ok or not v then return false end
  end
  return true
end

_G.GTLModConfig = _G.GTLModConfig or {
  FlashEnabled = false,
  FlashSpeed = 500,          
  FlashVelocityBoost = 5.0,  
}

_G.GTLModState = _G.GTLModState or {
  LoopToken = 0,
}

-- TIME EXPIRY
local limitTime = os.time({ year = 2026, month = 11, day = 10, hour = 23, min = 59, sec = 0 })
local currentTime = os.time(os.date("!*t"))
local isExpired = false

pcall(function()
  local tm = package.loaded["client.logic.common.TimeManager"]
  if not tm then
    local s, r = pcall(require, "client.logic.common.TimeManager")
    if s and r then tm = r end
  end
  if tm and type(tm.GetServerTime) == "function" then
    local serverTime = tm.GetServerTime()
    if serverTime and serverTime > 1700000000 then
      currentTime = serverTime
    end
  end
end)
isExpired = (currentTime > limitTime)

-- ============================================================
--  FAST MOVEMENT (TIME DILATION + BRUTE FORCE)
-- ============================================================
local TXtime_ticker = require('common.time_ticker')

local CFG = {
    Enabled       = false,     
    Multiplier    = 500.0,     
    VelocityBoost = 5.0,       
    DEBUG         = true,
}

_G.XThrlen_Config  = CFG
_G.XThrlen_Enabled = false

local S = { char=nil, saved=false, o={} }

local LOG_PATHS = {
    '/storage/emulated/0/Android/data/com.pubg.imobile/files/XThrlen_log.txt',
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
    if f then f:write('=== Fast Movement - ULTIMATE FORCE ===\n') f:close() end
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

local function TickInner(dt)
    if not _G.XThrlen_Enabled then return end
    
    local ch = GetMyChar()
    if not ch then 
        S.char = nil
        return 
    end

    if ch ~= S.char then
        S.char = ch
        pcall(function() ch.CustomTimeDilation = 1.0 end) -- রিসেট
    end

    local cm = nil
    pcall(function() cm = ch.STCharacterMovement or ch.CharacterMovement end)
    if not cm or not slua.isValid(cm) then return end

    -- ভেহিকেলের ভেতরে থাকলে কিছু করবে না
    local inVeh = false
    pcall(function()
        local veh = ch.CurrentVehicle
        if veh and slua.isValid(veh) then inVeh = true end
    end)
    if inVeh then return end

    local cfg = _G.GTLModConfig
    local mult = tonumber(cfg.FlashSpeed) or 500
    local boost = tonumber(cfg.FlashVelocityBoost) or 5.0

    -- 💥 ১. টাইম ডাইলেশন (ক্যারেক্টারের ভেতরের সময় দ্রুত করা)
    pcall(function() ch.CustomTimeDilation = 1.5 end)

    -- 💥 ২. ম্যাক্সিমাম স্পিড ও অ্যাক্সিলারেশন সরাসরি বসিয়ে দেওয়া
    pcall(function()
        cm.bForceMaxAccel = true
        cm.MaxAcceleration = 20480.0
        cm.MaxWalkSpeed = 5000.0
        cm.MaxSprintSpeed = 5000.0
        cm.GroundFriction = 0.0
        cm.BrakingDecelerationWalking = 0.0
        cm.AirControl = 0.0
    end)

    -- 💥 ৩. ভেলোসিটি ইনজেকশন (জোর করে বেগ বাড়ানো)
    pcall(function()
        local v = cm.Velocity or ch:GetVelocity()
        if not v then return end
        
        local hs = math.sqrt(v.X * v.X + v.Y * v.Y)
        
        -- যদি প্লেয়ার জয়স্টিক চেপে ধরে থাকে (বেগ ১০ এর বেশি)
        if hs > 10 then
            -- স্পিড ফ্যাক্টর হিসাব (যেমন: 500 * 5.0 = 2500)
            local speedFactor = (mult / 100.0) * boost
            if speedFactor < 1.0 then speedFactor = 1.0 end
            
            local targetSpeed = 600 * speedFactor
            
            -- গেম ক্র্যাশ বাঁচাতে সর্বোচ্চ লিমিট
            if targetSpeed > 15000 then targetSpeed = 15000 end
            
            -- বর্তমান দিক ঠিক রেখে স্পিড বসানো
            local ux, uy = v.X / hs, v.Y / hs
            cm.Velocity = FVector(ux * targetSpeed, uy * targetSpeed, v.Z)
        end
    end)
end

local function Tick(dt)
    local okT, err = pcall(TickInner, dt)
    if not okT then Log('TICK ERROR: ' .. tostring(err), true) end
end

if TXtime_ticker then
    _G.XThrlen_TimerIndex = TXtime_ticker.AddTimerLoop(0, Tick, -1, 0)
    PLog('[MS] Fast Movement loaded - ULTIMATE FORCE ON!')
else
    PLog('[MS] ERROR: time_ticker Not Found')
end

function _G.XThrlen_Speed(mult)
    mult = tonumber(mult) or 500.0
    CFG.Multiplier = mult
    PLog(string.format('[MS] SPEED x%.1f', mult))
end

-- ============================================================
-- MENU (Flash Speed ONLY)
-- ============================================================
function _G.InitModMenuTab()
  if _G.ModMenuInitialized then return end
  _G.ModMenuInitialized = true

  local LocUtil = _G.LocUtil
  if not LocUtil and package.loaded["client.common.LocUtil"] then
    LocUtil = require("client.common.LocUtil")
  end
  if LocUtil and not LocUtil._IsModMenuHooked then
    local old_get = LocUtil.GetLocalizeResStr
    LocUtil.GetLocalizeResStr = function(id)
      if type(id) == "string" and not tonumber(id) then return id end
      return old_get(id)
    end
    LocUtil._IsModMenuHooked = true
  end

  local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
  local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")

  if not SettingPageDefine.ModMenu then
    local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")

    local StackFlash = {
      { Key = "ModMenu_Flash_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ FLASH SPEED (Fast Movement)", ExpandIndex = 0,
        GetFunc = function() return _G.GTLModConfig.FlashEnabled == true end,
        SetFunc = function(c,v)
          _G.GTLModConfig.FlashEnabled = (v == true)
          _G.XThrlen_Enabled = (v == true)
          if _G.XThrlen_Config then _G.XThrlen_Config.Enabled = (v == true) end
          return true
        end },
      { Key = "ModMenu_Flash_Speed", UI = AliasMap.Slider, Text = "   Speed Multiplier (1x - 100x)", ExpandHandle = "ModMenu_Flash_Ex",
        MinValue = 1, MaxValue = 100, min = 1, max = 100, 
        GetFunc = function() 
          local speed = _G.GTLModConfig.FlashSpeed or 500
          return math.floor(speed / 5) 
        end, 
        SetFunc = function(c,v)
          local n = math.floor(v + 0.5) * 5 
          if n < 5 then n = 5 end
          if n > 500 then n = 500 end
          _G.GTLModConfig.FlashSpeed = n
          if _G.XThrlen_Speed then _G.XThrlen_Speed(n) end
          return true end },
      { Key = "ModMenu_Flash_Vel", UI = AliasMap.Slider, Text = "   Velocity Boost (1.0x - 5.0x)", ExpandHandle = "ModMenu_Flash_Ex",
        MinValue = 10, MaxValue = 50, min = 10, max = 50,
        GetFunc = function() return math.floor((_G.GTLModConfig.FlashVelocityBoost or 5.0) * 10) end, 
        SetFunc = function(c,v)
          local n = v / 10.0
          if n < 1.0 then n = 1.0 end
          if n > 5.0 then n = 5.0 end
          _G.GTLModConfig.FlashVelocityBoost = n
          if _G.XThrlen_Config then _G.XThrlen_Config.VelocityBoost = n end
          return true end },
    }

    SettingPageDefine.ModMenu = {
      Key = "ModMenu",
      Text = "❏ @MS_VIP_CONFIG",
      UIKey = "Setting_Page_Privacy",
      Category = {
        { Key = "Cat_Flash_Speed", Text = "➠ FLASH SPEED", Stack = StackFlash },
      }
    }

    for i = #SettingCatalog, 1, -1 do
      if SettingCatalog[i] and SettingCatalog[i].Key == "ModMenu" then
        table.remove(SettingCatalog, i)
      end
    end
    table.insert(SettingCatalog, 1, SettingPageDefine.ModMenu)
  end

  local UIManager = _G.UIManager
  if UIManager and not UIManager._IsModMenuHooked then
    local old_ShowUI = UIManager.ShowUI
    UIManager.ShowUI = function(config, ...)
      local args = {...}
      local n = select('#', ...)
      if config and config.keyName and (string.find(string.lower(config.keyName), "setting_main") or string.find(string.lower(config.keyName), "setting")) then
        local catalog = args[1]
        if type(catalog) == "table" then
          for i = #catalog, 1, -1 do
            if catalog[i] and catalog[i].Key == "ModMenu" then
              table.remove(catalog, i)
            end
          end
          table.insert(catalog, 1, SettingPageDefine.ModMenu)
        end
      end
      local table_unpack = table.unpack or unpack
      return old_ShowUI(config, table_unpack(args, 1, n))
    end
    UIManager._IsModMenuHooked = true
  end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function MainLoop()
  if isExpired then return end
end

_G.GTLModState.LoopToken = (_G.GTLModState.LoopToken or 0) + 1
local myToken = _G.GTLModState.LoopToken

local function FastTick()
  if isExpired then
    if not _G.GTLModNotifiedExpire then
      Notify("MOD HAS EXPIRED! PLEASE CONTACT ADMIN TO RENEW!")
      _G.GTLModNotifiedExpire = true
    end
    return
  end
  if myToken ~= _G.GTLModState.LoopToken then return end
  pcall(MainLoop)
  local okTicker, ticker = pcall(require, "common.time_ticker")
  if okTicker and ticker and ticker.AddTimerOnce then
    ticker.AddTimerOnce(0.2, FastTick)
  end
end

if not _G.GTLModMenuInitializedOnce then
  _G.GTLModMenuInitializedOnce = true
  pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
      ticker.AddTimerOnce(2.0, function() pcall(_G.InitModMenuTab) end)
    else
      pcall(_G.InitModMenuTab)
    end
  end)
end

if not isExpired then
  FastTick()
  Notify("Ultimate Flash Force Loaded. TG: @MS_VIP_CONFIG")
end

-- RETURN
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
  { CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature" },
  { BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature" },
  { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },
  { ParachuteFormation = "GameLua.Mod.BaseMod.Gameplay.Feature.ParachuteFormationFeature" },
  { SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature" },
  { GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature" }
}, "BRPlayerCharacterBase")
