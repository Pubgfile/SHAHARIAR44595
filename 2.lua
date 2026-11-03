-- ═══════════════════════════════════════════════════════════════════════════
-- BRPlayerCharacterBase.lua - FIXED 5X SPEED HACK (INSTANT APPLY)
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
-- SPEED HACK CONFIG (FIXED FOR SLIDER)
-- ═══════════════════════════════════════════════════════════════════════════
_G.SpeedHackConfig = _G.SpeedHackConfig or {
    Enabled = false,
    Multiplier = 5,              -- 1x to 5x
    BypassEnabled = true,
    CombatSlowdown = true,
    JumpProtection = true,
    AutoIdleReset = false,       -- অটো রিসেট বন্ধ করে দিলাম যাতে স্পিড না কমে
    RampUpSpeed = 3000,          -- র‍্যাম্প স্পিড বাড়িয়ে দিলাম যাতে সাথে সাথে ফুল স্পিড হয়
    ServerMaxSpeed = 1200,       -- সার্ভার ম্যাক্স বাড়িয়ে দিলাম
}

_G.SpeedHackState = _G.SpeedHackState or {
    Applied = false,
    LastMultiplier = 0,
    OrigWalk = nil,
    OrigRun = nil,
    OrigCrouch = nil,
    OrigSwim = nil,
    CurrentSpeed = 0,
    LastIdleReset = 0,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- SPEED HACK LOGIC (INSTANT APPLY & FIXED)
-- ═══════════════════════════════════════════════════════════════════════════
local function ApplySpeedHack(localPlayer)
    if not slua.isValid(localPlayer) then return end
    
    pcall(function()
        local CM = localPlayer.CharacterMovement
        if not slua.isValid(CM) then return end
        
        local state = _G.SpeedHackState
        local config = _G.SpeedHackConfig
        
        -- Save original values (first time)
        if not state.OrigWalk then
            state.OrigWalk = CM.MaxWalkSpeed or 600
            state.OrigRun = CM.MaxCustomMovementSpeed or 600
            state.OrigCrouch = CM.MaxWalkSpeedCrouched or 300
            state.OrigSwim = CM.MaxSwimSpeed or 300
            state.CurrentSpeed = state.OrigWalk
        end
        
        if config.Enabled then
            local multiplier = tonumber(config.Multiplier) or 5
            
            -- Slider fix: গেমে স্লাইডার ১০০ দেখালেও আমরা কোডে ৫ ধরব
            if multiplier > 5 then multiplier = 5 end
            if multiplier < 1 then multiplier = 1 end
            
            local baseSpeed = state.OrigWalk or 600
            local targetSpeed = baseSpeed * multiplier
            
            -- Combat/Jump bypass
            if config.BypassEnabled then
                if config.CombatSlowdown and (localPlayer.bIsWeaponFiring or localPlayer.bIsGunADS) then
                    targetSpeed = targetSpeed * 0.8 -- কমায় না, শুধু একটু কমিয়ে ৮০% করে (সেফটির জন্য)
                end
                if config.JumpProtection and CM.MovementMode == EMovementMode.MOVE_Falling then
                    targetSpeed = targetSpeed * 0.9 -- জাম্পের সময় ৯০% থাকে
                end
            end
            
            -- যেকোনো পরিবর্তন হলেই সাথে সাথে অ্যাপ্লাই হবে
            if state.LastMultiplier ~= multiplier or math.abs(state.CurrentSpeed - targetSpeed) > 5 then
                state.LastMultiplier = multiplier
                state.CurrentSpeed = targetSpeed
                state.Applied = true
                
                -- Apply to character
                CM.MaxWalkSpeed = targetSpeed
                CM.MaxCustomMovementSpeed = targetSpeed
                CM.MaxWalkSpeedCrouched = targetSpeed * 0.5
                CM.MaxSwimSpeed = targetSpeed * 0.5
                
                print(string.format("[SpeedHack] Fast Applied -> %dx (Speed: %.0f)", multiplier, targetSpeed))
            end
        else
            -- Restore when OFF
            if state.Applied then
                CM.MaxWalkSpeed = state.OrigWalk or 600
                CM.MaxCustomMovementSpeed = state.OrigRun or 600
                CM.MaxWalkSpeedCrouched = state.OrigCrouch or 300
                CM.MaxSwimSpeed = state.OrigSwim or 300
                
                state.LastMultiplier = 0
                state.CurrentSpeed = state.OrigWalk or 600
                state.Applied = false
                print("[SpeedHack] Restored to normal")
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SPEED HACK LOOP (0.1s tick for instant feel)
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
        ticker.AddTimerOnce(0.1, SpeedHackTick) -- 0.1s (আগে ছিল 0.2s)
    end
end

pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(1.0, SpeedHackTick)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- SPEED HACK MENU (FIXED SLIDER MAX VALUES)
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
                  if v == false then _G.SpeedHackState.LastMultiplier = 0 end
                  return true 
              end },
            
            -- Multiplier Slider (1 to 5)
            { Key = "ModMenu_Speed_Multiplier", UI = AliasMap.Slider, 
              Text = "   MULTIPLIER (1=Normal, 5=Max 5x)", 
              ExpandHandle = "ModMenu_Speed_Ex", 
              MinValue = 1, MaxValue = 5, min = 1, max = 5,
              GetFunc = function() return math.floor(_G.SpeedHackConfig.Multiplier or 5) end, 
              SetFunc = function(c,v) 
                  local val = math.floor(v + 0.5)
                  if val < 1 then val = 1 end
                  if val > 5 then val = 5 end
                  _G.SpeedHackConfig.Multiplier = val
                  _G.SpeedHackState.LastMultiplier = 0 -- Force instant update
                  return true 
              end },
            
            -- ═══ BYPASS SECTION ═══
            { Key = "ModMenu_Bypass_Ex", UI = AliasMap.TitleSwitcher, 
              Text = "🛡️ ANTI-BAN BYPASS", ExpandIndex = 0, 
              GetFunc = function() return _G.SpeedHackConfig.BypassEnabled end, 
              SetFunc = function(c,v) _G.SpeedHackConfig.BypassEnabled = v return true end },
            
            { Key = "ModMenu_Bypass_Combat", UI = AliasMap.Switcher, 
              Text = "   Combat Slowdown (Fire/Aim)", ExpandHandle = "ModMenu_Bypass_Ex",
              GetFunc = function() return _G.SpeedHackConfig.CombatSlowdown end, 
              SetFunc = function(c,v) _G.SpeedHackConfig.CombatSlowdown = v return true end },
            
            { Key = "ModMenu_Bypass_Jump", UI = AliasMap.Switcher, 
              Text = "   Jump Protection", ExpandHandle = "ModMenu_Bypass_Ex",
              GetFunc = function() return _G.SpeedHackConfig.JumpProtection end, 
              SetFunc = function(c,v) _G.SpeedHackConfig.JumpProtection = v return true end },
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
        ticker.AddTimerOnce(2.0, function() pcall(_G.InitSpeedHackMenu) end)
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
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
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
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
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
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
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
  if Client then GameplayData.RemoveCharacter(self.Object) end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled() end
function BRPlayerCharacterBase:BPOnRespawned() end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  if Client then GameplayData.RemoveCharacter(self.Object) end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  if Client then GameplayData.AddCharacter(self.Object) end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord() end

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
  if not slua.isValid(uPlayerState) then return false end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then uPlayerController:DisplayGameTipWithMsgID(48532) end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue() self:HandleNearDeathGiveupRescue() end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then uPlayerState:AddGeneralCount(1613, 1, false) end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then self:MulticastRPC_GmPlayAction(actionId) end
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
  local loadLater = function() uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0) end
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt) end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID) self:SetAttrValue("AreaID", AreaID, -1) end
function BRPlayerCharacterBase:GetAreaID() return math.floor(self:GetAttrValue("AreaID") + 0.5) end
function BRPlayerCharacterBase:CannotChangeIntoPetSpectator() return self.bCannotChangeIntoPetSpectator end

function BRPlayerCharacterBase:DoModChangeToBT()
  if self:HasState(EPawnState.SpecialSuit) then self:TriggerEntrySkillWithID(4301101, true) end
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
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then return false end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS REGISTRATION
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
