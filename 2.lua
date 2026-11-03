-- ═══════════════════════════════════════════════════════════════════════════
-- BRPlayerCharacterBase.lua - SAFE SPEED HACK 5X + ANTI-BAN BYPASS
-- ═══════════════════════════════════════════════════════════════════════════

local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}

BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true, Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true, Params = { UEnums.EPropertyClass.Object }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true, Params = { UEnums.EPropertyClass.Int }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true, Params = { UEnums.EPropertyClass.Int }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true, Params = { UEnums.EPropertyClass.Bool }
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local ESpecialMovementType = import("ESpecialMovementType")
local ESpiderSwingMoveState = import("ESpiderSwingMoveState")
local ESurviveWeaponPropSlot = import("ESurviveWeaponPropSlot")
local EParachuteState = import("EParachuteState")
local EMovementMode = import("EMovementMode")
local EStateType = import("EStateType")
local ESTEPoseState = import("ESTEPoseState")
local EGameModeType = import("EGameModeType")
local STExtraGameStateBase = import("STExtraGameStateBase")
local UKismetSystemLibrary = import("KismetSystemLibrary")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")

-- ═══════════════════════════════════════════════════════════════════════════
-- SPEED HACK CONFIG WITH BYPASS SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════
_G.SpeedHackConfig = _G.SpeedHackConfig or {
    Enabled = false,
    Multiplier = 5,              -- 1x to 5x
    
    -- ═══ BYPASS SETTINGS ═══
    BypassEnabled = true,        -- Master switch for bypass
    ServerMaxSpeed = 900,        -- Server sees max 900 (safe)
    RampUpSpeed = 200,           -- Speed per second increase
    CombatSlowdown = true,       -- Slow down when firing
    AutoIdleReset = true,        -- Periodic reset to normal
    AutoIdleInterval = 8,        -- Reset every 8 seconds
    SafeZoneOnly = false,        -- Only apply in safe areas
    JumpProtection = true,       -- Reduce speed while jumping
}

_G.SpeedHackState = _G.SpeedHackState or {
    Applied = false,
    LastMultiplier = 0,
    OrigWalk = nil,
    OrigRun = nil,
    OrigCrouch = nil,
    OrigSwim = nil,
    CurrentSpeed = 0,
    TargetSpeed = 0,
    LastCombatCheck = 0,
    LastIdleReset = 0,
    IsCombat = false,
    IsJumping = false,
    IsInSafeState = false,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- BYPASS: DETECT COMBAT STATE
-- ═══════════════════════════════════════════════════════════════════════════
local function DetectCombatState(localPlayer)
    local combat = false
    pcall(function()
        -- Check firing
        if localPlayer.bIsWeaponFiring == true then combat = true end
        -- Check aiming
        if localPlayer.bIsGunADS == true then combat = true end
        -- Check recent damage (last 3 seconds)
        if localPlayer.LastDamageTime then
            local timeSince = os.clock() - localPlayer.LastDamageTime
            if timeSince < 3.0 then combat = true end
        end
    end)
    return combat
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BYPASS: DETECT JUMP STATE
-- ═══════════════════════════════════════════════════════════════════════════
local function DetectJumpState(localPlayer)
    local jumping = false
    pcall(function()
        local CM = localPlayer.CharacterMovement
        if slua.isValid(CM) then
            if CM.MovementMode == EMovementMode.MOVE_Falling then
                jumping = true
            end
            if CM.IsFalling and CM:IsFalling() then
                jumping = true
            end
        end
    end)
    return jumping
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BYPASS: CALCULATE SAFE SPEED
-- ═══════════════════════════════════════════════════════════════════════════
local function CalculateSafeSpeed(baseSpeed, multiplier, combat, jumping)
    local targetSpeed = baseSpeed * multiplier
    
    -- Bypass not enabled -> return as-is (unsafe)
    if not _G.SpeedHackConfig.BypassEnabled then
        return targetSpeed
    end
    
    -- Combat slowdown (50% reduction)
    if _G.SpeedHackConfig.CombatSlowdown and combat then
        targetSpeed = targetSpeed * 0.5
    end
    
    -- Jump protection (30% reduction)
    if _G.SpeedHackConfig.JumpProtection and jumping then
        targetSpeed = targetSpeed * 0.7
    end
    
    -- Auto ramp-up (gradual increase)
    local state = _G.SpeedHackState
    local current = state.CurrentSpeed or baseSpeed
    local maxChange = _G.SpeedHackConfig.RampUpSpeed * 0.2  -- 200/sec -> 40 per tick (0.2s tick)
    
    if current < targetSpeed then
        targetSpeed = math.min(current + maxChange, targetSpeed)
    elseif current > targetSpeed then
        targetSpeed = math.max(current - maxChange * 2, targetSpeed)  -- Faster decrease
    end
    
    return targetSpeed
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BYPASS: SERVER REPLICATION MASKING
-- Server এ normal speed দেখাবে (client e 5x)
-- ═══════════════════════════════════════════════════════════════════════════
local function ApplyServerMasking(CM, realSpeed)
    if not _G.SpeedHackConfig.BypassEnabled then
        return realSpeed
    end
    
    -- Save real speed to CustomMovementSpeed (not replicated)
    -- and set replicated MaxWalkSpeed to safe value
    pcall(function()
        local safeSpeed = math.min(realSpeed, _G.SpeedHackConfig.ServerMaxSpeed)
        
        -- MaxWalkSpeed is replicated - server sees this
        CM.MaxWalkSpeed = safeSpeed
        
        -- MaxCustomMovementSpeed might not be replicated - use for real speed
        -- (depends on game version)
        if CM.MaxCustomMovementSpeed ~= nil then
            CM.MaxCustomMovementSpeed = realSpeed
        end
    end)
    
    return realSpeed
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN SPEED HACK LOGIC WITH BYPASS
-- ═══════════════════════════════════════════════════════════════════════════
local function ApplySpeedHack(localPlayer)
    if not slua.isValid(localPlayer) then return end
    
    pcall(function()
        local CM = localPlayer.CharacterMovement
        if not slua.isValid(CM) then return end
        
        local state = _G.SpeedHackState
        local config = _G.SpeedHackConfig
        
        -- Save original values first time
        if not state.OrigWalk then
            state.OrigWalk = CM.MaxWalkSpeed or 600
            state.OrigRun = CM.MaxCustomMovementSpeed or 600
            state.OrigCrouch = CM.MaxWalkSpeedCrouched or 300
            state.OrigSwim = CM.MaxSwimSpeed or 300
            state.CurrentSpeed = state.OrigWalk
            print(string.format("[SpeedHack] Original saved: Walk=%s Crouch=%s Swim=%s",
                tostring(state.OrigWalk), tostring(state.OrigCrouch), tostring(state.OrigSwim)))
        end
        
        if config.Enabled then
            local multiplier = tonumber(config.Multiplier) or 5
            if multiplier > 5 then multiplier = 5 end
            if multiplier < 1 then multiplier = 1 end
            
            local now = os.clock()
            
            -- ═══ BYPASS: Detect states ═══
            local isCombat = DetectCombatState(localPlayer)
            local isJumping = DetectJumpState(localPlayer)
            
            -- ═══ BYPASS: Auto idle reset ═══
            if config.AutoIdleReset and config.BypassEnabled then
                if not state.LastIdleReset then state.LastIdleReset = now end
                if (now - state.LastIdleReset) > config.AutoIdleInterval then
                    state.LastIdleReset = now
                    -- Briefly reset to normal
                    local baseSpeed = state.OrigWalk or 600
                    CM.MaxWalkSpeed = baseSpeed
                    CM.MaxCustomMovementSpeed = state.OrigRun or 600
                    state.CurrentSpeed = baseSpeed
                    print("[SpeedHack] Auto idle reset -> 600")
                    return  -- Skip this tick
                end
            end
            
            -- ═══ Calculate target speed ═══
            local baseSpeed = state.OrigWalk or 600
            local targetSpeed = CalculateSafeSpeed(baseSpeed, multiplier, isCombat, isJumping)
            
            -- ═══ Apply speed ═══
            if state.LastMultiplier ~= multiplier or math.abs(state.CurrentSpeed - targetSpeed) > 10 then
                state.LastMultiplier = multiplier
                state.CurrentSpeed = targetSpeed
                state.IsCombat = isCombat
                state.IsJumping = isJumping
                
                -- Apply with server masking
                local realSpeed = ApplyServerMasking(CM, targetSpeed)
                
                -- Crouch and Swim at reduced speed
                CM.MaxWalkSpeedCrouched = realSpeed * 0.5
                CM.MaxSwimSpeed = realSpeed * 0.5
                
                state.Applied = true
                
                print(string.format("[SpeedHack] %dx -> %.0f (Combat:%s Jump:%s)",
                    multiplier, targetSpeed,
                    tostring(isCombat), tostring(isJumping)))
            end
        else
            -- ═══ RESTORE original ═══
            if state.Applied then
                CM.MaxWalkSpeed = state.OrigWalk or 600
                CM.MaxCustomMovementSpeed = state.OrigRun or 600
                CM.MaxWalkSpeedCrouched = state.OrigCrouch or 300
                CM.MaxSwimSpeed = state.OrigSwim or 300
                
                state.LastMultiplier = 0
                state.CurrentSpeed = state.OrigWalk or 600
                state.Applied = false
                print("[SpeedHack] Restored to original")
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SPEED HACK LOOP (0.2s tick)
-- ═══════════════════════════════════════════════════════════════════════════
local function SpeedHackTick()
    pcall(function()
        local pc = GameplayData.GetPlayerController()
        if not slua.isValid(pc) then return end
        
        local localPlayer = pc:GetPlayerCharacterSafety()
        if not slua.isValid(localPlayer) then return end
        
        ApplySpeedHack(localPlayer)
    end)
    
    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.2, SpeedHackTick)
    end
end

pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(1.0, SpeedHackTick)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- SPEED HACK MENU (WITH BYPASS OPTIONS)
-- ═══════════════════════════════════════════════════════════════════════════
function _G.InitSpeedHackMenu()
    if _G.SpeedHackMenuInitialized then return end
    _G.SpeedHackMenuInitialized = true
    
    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = require("client.common.LocUtil")
    end
    
    if LocUtil and not LocUtil._IsSpeedHackMenuHooked then
        local old_get = LocUtil.GetLocalizeResStr
        LocUtil.GetLocalizeResStr = function(id)
            if type(id) == "string" and not tonumber(id) then
                return id
            end
            return old_get(id)
        end
        LocUtil._IsSpeedHackMenuHooked = true
    end
    
    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    
    if not SettingPageDefine.SpeedHackMenu then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
        
        local StackSpeedHack = {
            -- Main toggle
            { Key = "ModMenu_Speed_Ex", UI = AliasMap.TitleSwitcher, 
              Text = "⚡ SPEED HACK (1X - 5X)", ExpandIndex = 0, 
              GetFunc = function() return _G.SpeedHackConfig.Enabled end, 
              SetFunc = function(c,v) 
                  _G.SpeedHackConfig.Enabled = v 
                  if v == false then
                      _G.SpeedHackState.LastMultiplier = 0
                  end
                  return true 
              end },
            
            -- Multiplier slider
            { Key = "ModMenu_Speed_Multiplier", UI = AliasMap.Slider, 
              Text = "   MULTIPLIER (1=Normal, 5=5x)", 
              ExpandHandle = "ModMenu_Speed_Ex", 
              MinValue = 1, MaxValue = 5, min = 1, max = 5,
              GetFunc = function() return _G.SpeedHackConfig.Multiplier or 5 end, 
              SetFunc = function(c,v) 
                  local val = math.floor(v + 0.5)
                  if val < 1 then val = 1 end
                  if val > 5 then val = 5 end
                  _G.SpeedHackConfig.Multiplier = val
                  _G.SpeedHackState.LastMultiplier = 0
                  return true 
              end },
            
            -- ═══ BYPASS SECTION ═══
            { Key = "ModMenu_Bypass_Ex", UI = AliasMap.TitleSwitcher, 
              Text = "🛡️ ANTI-BAN BYPASS", ExpandIndex = 0, 
              GetFunc = function() return _G.SpeedHackConfig.BypassEnabled end, 
              SetFunc = function(c,v) 
                  _G.SpeedHackConfig.BypassEnabled = v 
                  return true 
              end },
            
            -- Combat slowdown
            { Key = "ModMenu_Bypass_Combat", UI = AliasMap.Switcher, 
              Text = "   Combat Slowdown (Fire/Aim)", 
              ExpandHandle = "ModMenu_Bypass_Ex",
              GetFunc = function() return _G.SpeedHackConfig.CombatSlowdown end, 
              SetFunc = function(c,v) 
                  _G.SpeedHackConfig.CombatSlowdown = v 
                  return true 
              end },
            
            -- Jump protection
            { Key = "ModMenu_Bypass_Jump", UI = AliasMap.Switcher, 
              Text = "   Jump Protection", 
              ExpandHandle = "ModMenu_Bypass_Ex",
              GetFunc = function() return _G.SpeedHackConfig.JumpProtection end, 
              SetFunc = function(c,v) 
                  _G.SpeedHackConfig.JumpProtection = v 
                  return true 
              end },
            
            -- Auto idle reset
            { Key = "ModMenu_Bypass_Idle", UI = AliasMap.Switcher, 
              Text = "   Auto Idle Reset (8s)", 
              ExpandHandle = "ModMenu_Bypass_Ex",
              GetFunc = function() return _G.SpeedHackConfig.AutoIdleReset end, 
              SetFunc = function(c,v) 
                  _G.SpeedHackConfig.AutoIdleReset = v 
                  return true 
              end },
            
            -- Ramp up speed
            { Key = "ModMenu_Bypass_Ramp", UI = AliasMap.Slider, 
              Text = "   Ramp Speed (50-500/sec)", 
              ExpandHandle = "ModMenu_Bypass_Ex",
              MinValue = 50, MaxValue = 500, min = 50, max = 500,
              GetFunc = function() return _G.SpeedHackConfig.RampUpSpeed or 200 end, 
              SetFunc = function(c,v) 
                  _G.SpeedHackConfig.RampUpSpeed = v
                  return true 
              end },
            
            -- Server max speed
            { Key = "ModMenu_Bypass_ServerMax", UI = AliasMap.Slider, 
              Text = "   Server Max (600-1200)", 
              ExpandHandle = "ModMenu_Bypass_Ex",
              MinValue = 600, MaxValue = 1200, min = 600, max = 1200,
              GetFunc = function() return _G.SpeedHackConfig.ServerMaxSpeed or 900 end, 
              SetFunc = function(c,v) 
                  _G.SpeedHackConfig.ServerMaxSpeed = v
                  return true 
              end },
        }
        
        SettingPageDefine.SpeedHackMenu = {
            Key = "SpeedHackMenu",
            Text = "⚡ SPEED HACK",
            UIKey = "Setting_Page_Privacy",
            Category = {
                { Key = "Cat_SpeedHack", Text = "⚡ SPEED HACK ⚡", Stack = StackSpeedHack }
            }
        }
        
        table.insert(SettingCatalog, SettingPageDefine.SpeedHackMenu)
    end
    
    local UIManager = _G.UIManager
    if UIManager and not UIManager._IsSpeedHackMenuHooked then
        local old_ShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...)
            
            if config and config.keyName and string.find(string.lower(config.keyName), "setting") then
                local catalog = args[1]
                if type(catalog) == "table" then
                    local hasMenu = false
                    for _, page in ipairs(catalog) do
                        if type(page) == "table" and page.Key == "SpeedHackMenu" then
                            hasMenu = true
                            break
                        end
                    end
                    if not hasMenu then
                        table.insert(catalog, SettingPageDefine.SpeedHackMenu)
                    end
                end
            end
            local table_unpack = table.unpack or unpack
            return old_ShowUI(config, table_unpack(args, 1, n))
        end
        UIManager._IsSpeedHackMenuHooked = true
    end
end

pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(2.0, function()
            pcall(_G.InitSpeedHackMenu)
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- BRPlayerCharacterBase CLASS METHODS (Base code, must keep)
-- ═══════════════════════════════════════════════════════════════════════════

function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = { "bCanSelfRescue" }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local EDynamicSimpleQueryConfigDisableMask = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(EDynamicSimpleQueryConfigDisableMask.Bit0, true)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
    end
  end
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then return end
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then return end
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then return end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  local loadLater = function()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(SpiderSwingObj) then
      local nCurState = SpiderSwingObj:GetCurMoveState()
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS REGISTRATION (MUST KEEP)
-- ═══════════════════════════════════════════════════════════════════════════
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
