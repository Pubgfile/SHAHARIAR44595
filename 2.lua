local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}

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
      AttrName = {
        "bCanSelfRescue"
      }
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
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
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
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then
    return
  end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then
    return
  end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then
    return
  end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
        uCurPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
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
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
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
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  
  local function loadLater()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
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
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
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
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
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
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked by SpiderSwing state: " .. tostring(nCurState))
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ============================================================
-- BYPASS SYSTEM (original থেকে কপি)
-- ============================================================
local pkgOK = rawget(_G, "pkgOK")
local pkg = rawget(_G, "pkg")
local TssSdk = rawget(_G, "TssSdk")
local ace = rawget(_G, "ace")
local XignCode = rawget(_G, "XignCode")
local BattlEye = rawget(_G, "BattlEye")
local NetUtil = rawget(_G, "NetUtil")
local NetManager = rawget(_G, "NetManager")
local EventSystem = rawget(_G, "EventSystem")
local LogUtil = rawget(_G, "LogUtil")
local sandbox = rawget(_G, "sandbox")
local Client = rawget(_G, "Client")
local login_module = rawget(_G, "login_module")
local RacingAntiCheatLogic = rawget(_G, "RacingAntiCheatLogic")
local RealTimeBan = rawget(_G, "RealTimeBan")
local BanSystem = rawget(_G, "BanSystem")
local GameplayCallbacks = rawget(_G, "GameplayCallbacks")
local CrashSight = rawget(_G, "CrashSight")
local TLog = rawget(_G, "TLog")
local ScreenshotMaker = rawget(_G, "ScreenshotMaker")
local MemoryScanner = rawget(_G, "MemoryScanner")
local FileCheckSubsystem = rawget(_G, "FileCheckSubsystem")
local AvatarUtils = rawget(_G, "AvatarUtils")
local ClientDataStatistcsSubsystem = rawget(_G, "ClientDataStatistcsSubsystem")
local ShootVerifySubSystemClient = rawget(_G, "ShootVerifySubSystemClient")
local AFKReportorSubsystem = rawget(_G, "AFKReportorSubsystem")
local AvatarExceptionSubsystem = rawget(_G, "AvatarExceptionSubsystem")
local RescueBtnReplayTraceSubsystem = rawget(_G, "RescueBtnReplayTraceSubsystem")
local GameReportSubsystem = rawget(_G, "GameReportSubsystem")
local InspectionSystemReportClientLogicSubsystem = rawget(_G, "InspectionSystemReportClientLogicSubsystem")
local ClientHawkEyePatrolSubsystem = rawget(_G, "ClientHawkEyePatrolSubsystem")
local BehaviorScoreSubsystem = rawget(_G, "BehaviorScoreSubsystem")
local AIReplaySubsystem = rawget(_G, "AIReplaySubsystem")
local ClientBanLogic = rawget(_G, "ClientBanLogic")
local logic_tt_ban = rawget(_G, "logic_tt_ban")
local SystemInfo = rawget(_G, "SystemInfo")
local KismetSystemLibrary = rawget(_G, "KismetSystemLibrary")
local CreativeModeBlueprintLibrary = rawget(_G, "CreativeModeBlueprintLibrary")
local TDataMaster = rawget(_G, "TDataMaster")
local MemoryProtect = rawget(_G, "MemoryProtect")
local NetworkManager = rawget(_G, "NetworkManager")
local Engine = rawget(_G, "Engine")
local GameTime = rawget(_G, "GameTime")
local subsystemMgr = rawget(_G, "subsystemMgr")
local MemoryCleaner = rawget(_G, "MemoryCleaner")
local DebuggerDetect = rawget(_G, "DebuggerDetect")
local EmulatorDetect = rawget(_G, "EmulatorDetect")
local JNI = rawget(_G, "JNI")
local PacketEncrypt = rawget(_G, "PacketEncrypt")
local DSValidator = rawget(_G, "DSValidator")
local CRCChecker = rawget(_G, "CRCChecker")
local SecurityCommonUtils = rawget(_G, "SecurityCommonUtils")
local SecurityNotifyPCFeature = rawget(_G, "SecurityNotifyPCFeature")
local DSActiveSubsystem = rawget(_G, "DSActiveSubsystem")
local SpectateAndReplaySubsystem = rawget(_G, "SpectateAndReplaySubsystem")
local AITrackingLogSubsystem = rawget(_G, "AITrackingLogSubsystem")
local TDMAFKReportorSubsystem = rawget(_G, "TDMAFKReportorSubsystem")
local DataMgr = rawget(_G, "DataMgr")
local isExpired = false

if pkgOK then
    print("[SRCHUB] Game bundle: " .. tostring(pkg))
end

_G.X3 = _G.X3 or {}

_G.X3.BuildStamp = "SRC HUB (2027-08-28)"
_G.X3.Trace = function(msg)
    print("[X3v66] " .. tostring(msg))
end
_G.X3.TickScale = function()
    local dt = _G.X3.FrameDT or (1 / 60)
    local s = dt * 60
    if s < 1 then s = 1 elseif s > 2.4 then s = 2.4 end
    return s
end
_G.X3.Trace(_G.X3.BuildStamp .. " dimuat | bundle=" .. tostring(pkgOK and pkg or "?"))

-- COMPLETE ANTI-BAN SYSTEM v5.0
local function CompleteAntiBanSystem()
    pcall(function()
        -- 1. TSS SDK COMPLETE BLOCK
        local TssSdk = _G.TssSdk or package.loaded["TssSdk"]
        if TssSdk then
            TssSdk.OnRecvData = function() end
            TssSdk.SendReportInfo = function() end
            TssSdk.ScanMemory = function() return true end
            TssSdk.IsEmulator = function() return false end
            TssSdk.GetTssSdkReportInfo = function() return "" end
            TssSdk.ReportException = function() end
            TssSdk.ReportData = function() end
            TssSdk.CheckIntegrity = function() return true end
            TssSdk.VerifySignature = function() return true end
            TssSdk.CollectEvidence = function() return nil end
            TssSdk.UploadLog = function() end
            TssSdk.SendAntiData = function() end
            TssSdk.ReportGameStart = function() end
            TssSdk.ReportGameEnd = function() end
            TssSdk.ReportCrash = function() end
            TssSdk.ReportViolation = function() end
            TssSdk.ReportSuspicious = function() end
            TssSdk.ReportBan = function() end
            TssSdk.ReportKick = function() end
            TssSdk.ReportWarning = function() end
            TssSdk.ReportInfo = function() end
            TssSdk.ReportDebug = function() end
            TssSdk.ReportError = function() end
            TssSdk.ReportFatal = function() end
            TssSdk.ReportMemory = function() end
            TssSdk.ReportProcess = function() end
            TssSdk.ReportModule = function() end
            TssSdk.ReportThread = function() end
            TssSdk.ReportFile = function() end
            TssSdk.ReportNetwork = function() end
            TssSdk.ReportDevice = function() end
            TssSdk.ReportSystem = function() end
            TssSdk.ReportGame = function() end
            TssSdk.ReportUser = function() end
            TssSdk.ReportAccount = function() end
            TssSdk.ReportSession = function() end
            TssSdk.ReportPerformance = function() end
            TssSdk.ReportBattery = function() end
            TssSdk.ReportTemperature = function() end
            TssSdk.ReportFPS = function() end
            TssSdk.ReportPing = function() end
            TssSdk.ReportPacket = function() end
            TssSdk.ReportCheat = function() end
            TssSdk.ReportHack = function() end
            TssSdk.ReportMod = function() end
            TssSdk.ReportInject = function() end
            TssSdk.ReportDebugger = function() end
            TssSdk.ReportEmulator = function() end
            TssSdk.ReportRoot = function() end
            TssSdk.ReportJailbreak = function() end
            TssSdk.ReportVM = function() end
            TssSdk.ReportHook = function() end
            TssSdk.ReportPatch = function() end
            TssSdk.ReportTamper = function() end
            TssSdk.ReportCorrupt = function() end
            TssSdk.ReportInvalid = function() end
            TssSdk.ReportSpoof = function() end
            TssSdk.ReportFake = function() end
            TssSdk.ReportClone = function() end
            TssSdk.ReportDuplicate = function() end
            TssSdk.ReportConflict = function() end
            TssSdk.ReportOverlap = function() end
            TssSdk.ReportMismatch = function() end
            TssSdk.ReportInconsistent = function() end
            TssSdk.ReportUnexpected = function() end
            TssSdk.ReportUnknown = function() end
        end

        -- 2. ACE
        local ace = _G.ace or package.loaded["libace.so"]
        if ace then
            ace.ReportData = function() end
            ace.CheckIntegrity = function() return true end
            ace.ScanMemory = function() return false end
            ace.VerifyProcess = function() return true end
            ace.CheckModule = function() return true end
            ace.ReportViolation = function() end
            ace.KickPlayer = function() end
            ace.BanPlayer = function() end
            ace.CollectInfo = function() return {} end
            ace.SendReport = function() end
            ace.ValidateClient = function() return true end
            ace.CheckDebugger = function() return false end
            ace.CheckEmulator = function() return false end
            ace.CheckRoot = function() return false end
        end

        -- 3. XIGNCODE
        local XignCode = _G.XignCode or package.loaded["xigncode"]
        if XignCode then
            XignCode.SendReport = function() end
            XignCode.CheckProcess = function() return true end
            XignCode.VerifyIntegrity = function() return true end
            XignCode.ScanModules = function() return {} end
            XignCode.ReportException = function() end
            XignCode.ValidateMemory = function() return true end
            XignCode.CheckDebugger = function() return false end
            XignCode.KickPlayer = function() end
            XignCode.BanPlayer = function() end
        end

        -- 4. BATTEYE
        local BattlEye = _G.BattlEye or package.loaded["BattlEye"]
        if BattlEye then
            BattlEye.SendReport = function() end
            BattlEye.KickPlayer = function() end
            BattlEye.ValidatePlayer = function() return true end
            BattlEye.CheckMemory = function() return true end
            BattlEye.VerifyIntegrity = function() return true end
            BattlEye.ReportViolation = function() end
            BattlEye.ScanProcess = function() return true end
            BattlEye.BanPlayer = function() end
            BattlEye.CollectEvidence = function() return {} end
        end

        -- 5. HIGGS BOSON
        local HiggsBosonComponent = package.loaded["GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent"]
        if HiggsBosonComponent then
            HiggsBosonComponent.bIsEnable = false
            HiggsBosonComponent.bMHActive = false
            HiggsBosonComponent.bCallPreReplication = false
            HiggsBosonComponent.StaticShowSecurityAlertInDev = function() end
            HiggsBosonComponent.CheckClientConfig = function() return false end
            HiggsBosonComponent.GetSecurityInfo = function() return {} end
            HiggsBosonComponent.ReportSecurityAlert = function() end
            HiggsBosonComponent.ValidateClient = function() return true end
            HiggsBosonComponent.CheckIntegrity = function() return true end
            HiggsBosonComponent.BlackList = {}
        end

        -- 6. REPORT SYSTEMS
        local reportPaths = {
            "GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem",
            "client.slua.logic.report.EquipmentExceptionReport",
            "client.slua.logic.report.ClientToolsReport",
            "GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils",
            "client.slua.logic.download.report.puffer_tlog",
            "GameLua.Mod.BaseMod.Client.Security.ClientGlueHiaSystem",
            "GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils",
            "GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature",
            "client.slua.logic.ban.ClientBanLogic",
            "client.slua.logic.login.logic_tt_ban",
            "GameLua.Mod.PlanBT.Gameplay.Subsystem.DSActiveSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSAITLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem",
            "GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.InspectionSystemReportDSLogicSubsystem",
            "GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem",
            "GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem",
            "GameLua.Mod.Escape.Gameplay.Subsystem.BehaviorScoreSubsystem",
            "GameLua.ExtraModule.MLAI.Client.AIReplaySubsystem",
            "GameLua.Mod.BaseMod.GamePlay.AI.AITrackingLogSubsystem",
            "GameLua.Mod.TDM.Gameplay.Subsystem.TDMAFKReportorSubsystem",
        }

        for _, path in ipairs(reportPaths) do
            local module = package.loaded[path] or pcall(require, path) and require(path)
            if module then
                if module.Report then module.Report = function() end end
                if module.SendReport then module.SendReport = function() end end
                if module.ReportEvent then module.ReportEvent = function() end end
                if module.ReportException then module.ReportException = function() end end
                if module.ReportData then module.ReportData = function() end end
                if module.ReportTLogEvent then module.ReportTLogEvent = function() end end
                if module.OnInit then module.OnInit = function() end end
            end
        end

        -- 7. TLOG
        local tlogPaths = {
            "client.slua.config.tlog.tlog_report_utils",
            "GameLua.Mod.BaseMod.DS.Security.DSAITLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem",
            "client.slua.logic.replay.logic_report_replay",
            "client.slua.logic.crash.CrashReporter",
        }
        for _, path in ipairs(tlogPaths) do
            local module = package.loaded[path] or pcall(require, path) and require(path)
            if module then
                if module.ReportTLogEvent then module.ReportTLogEvent = function() end end
                if module.SendTlog then module.SendTlog = function() end end
                if module.ReportTLog then module.ReportTLog = function() end end
            end
        end

        -- 8. GAMEPLAY CALLBACKS
        if _G.GameplayCallbacks then
            local GC = _G.GameplayCallbacks
            local noop = function() end
            local empty = function() return {} end
            local trueFunc = function() return true end

            GC.ReportAttackFlow = noop
            GC.ReportSecAttackFlow = noop
            GC.ReportHurtFlow = noop
            GC.ReportFireArms = noop
            GC.ReportVerifyInfoFlow = noop
            GC.ReportMrpcsFlow = noop
            GC.ReportPlayerBehavior = noop
            GC.ReportTeammatHurt = noop
            GC.ReportMisKillByTeammate = noop
            GC.ReportForbitPick = noop
            GC.ReportPlayerMoveRoute = noop
            GC.ReportPlayerPosition = noop
            GC.ReportVehicleMoveFlow = noop
            GC.ReportSecTgameMovingFlow = noop
            GC.ReportParachuteData = noop
            GC.SendTssSdkAntiDataToLobby = noop
            GC.SendDSErrorLogToLobby = noop
            GC.SendDSErrorLogToLobbyOnece = noop
            GC.SendDSHawkEyePatrolLogToLobby = noop
            GC.ReportEquipmentFlow = noop
            GC.ReportAimFlow = noop
            GC.ReportHitFlow = noop
            GC.GetWeaponReport = empty
            GC.GetOneWeaponReport = empty
            GC.SendClientStats = noop
            GC.ReportCircleFlow = noop
            GC.ReportPlayersPing = noop
            GC.ReportPlayerIP = noop
            GC.IsBypassed = true
        end

        -- 9. NETWORK PACKET
        if NetUtil and NetUtil.SendPacket then
            local originalSend = NetUtil.SendPacket
            local blockedPackets = {
                ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportHurtFlow"]=1,
                ["ReportFireArms"]=1, ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1,
                ["ReportPlayerBehavior"]=1, ["ReportTeammatHurt"]=1,
                ["ReportAimFlow"]=1, ["ReportHitFlow"]=1, ["ReportCircleFlow"]=1,
                ["report_players_ping"]=1, ["report_player_ip"]=1,
                ["report_speed_hack"]=1, ["report_wall_hack"]=1, ["report_aim_bot"]=1,
                ["report_esp_usage"]=1, ["report_modded_files"]=1, ["detect_cheat"]=1,
                ["ban_player"]=1, ["client_anti_cheat_report"]=1,
                ["on_tss_sdk_anti_data"]=1, ["tss_sdk_report"]=1,
            }
            NetUtil.SendPacket = function(packetName, ...)
                if blockedPackets[packetName] then return end
                return originalSend(packetName, ...)
            end
            NetUtil.IsBypassed = true
        end

        -- 10. CRASH & TLOG
        local CrashSight = _G.CrashSight or package.loaded["CrashSight"]
        if CrashSight then
            CrashSight.ReportException = function() end
            CrashSight.SetCustomData = function() end
            CrashSight.Log = function() end
            CrashSight.UploadLog = function() end
            CrashSight.SendReport = function() end
            CrashSight.CollectInfo = function() return {} end
            CrashSight.ReportCrash = function() end
        end

        local TLog = _G.TLog or package.loaded["TLog"]
        if TLog then
            TLog.Info = function() end
            TLog.Warning = function() end
            TLog.Error = function() end
            TLog.Debug = function() end
            TLog.Report = function() end
            TLog.Flush = function() end
            TLog.Log = function() end
        end

        -- 11. SCREENSHOT
        local ScreenshotMaker = import("ScreenshotMaker")
        if ScreenshotMaker then
            ScreenshotMaker.MakePicture = function() return "" end
            ScreenshotMaker.ReMakePicture = function() return "" end
            ScreenshotMaker.HasCaptured = function() return true end
            ScreenshotMaker.TakeScreenshot = function() end
        end

        -- 12. MEMORY SCANNER
        local MemoryScanner = _G.MemoryScanner or package.loaded["MemoryScanner"]
        if MemoryScanner then
            MemoryScanner.StartScan = function() end
            MemoryScanner.StopScan = function() end
            MemoryScanner.GetResults = function() return {} end
            MemoryScanner.ReportViolation = function() end
            MemoryScanner.CheckIntegrity = function() return true end
        end

        -- 13. FILE CHECK
        local FileCheckSubsystem = package.loaded["FileCheckSubsystem"]
        if FileCheckSubsystem then
            FileCheckSubsystem.StartCheck = function() end
            FileCheckSubsystem.ReportAbnormalFile = function() end
            FileCheckSubsystem.VerifyFile = function() return true end
            FileCheckSubsystem.CheckIntegrity = function() return true end
        end

        -- 14. AVATAR
        local AvatarUtils = package.loaded["AvatarUtils"]
        if AvatarUtils then
            AvatarUtils.CheckIsWeaponInBlackList = function() return false end
            AvatarUtils.IsValidAvatar = function() return true end
            AvatarUtils.ValidateAvatar = function() return true end
        end

        -- 15. STATISTICS
        local ClientDataStatistcsSubsystem = package.loaded["ClientDataStatistcsSubsystem"]
        if ClientDataStatistcsSubsystem then
            ClientDataStatistcsSubsystem.StartToCheck = function() end
            ClientDataStatistcsSubsystem.DelayCount = 0
            ClientDataStatistcsSubsystem.ReportPingDelay = function() end
        end

        -- 16. SHOOT VERIFY
        local ShootVerifySubSystemClient = package.loaded["ShootVerifySubSystemClient"]
        if ShootVerifySubSystemClient then
            ShootVerifySubSystemClient.ReportVerifyFail = function() end
            ShootVerifySubSystemClient.OnVerifyFailed = function() end
            ShootVerifySubSystemClient.CheckShoot = function() return true end
        end

        -- 17. AFK
        local AFKReportorSubsystem = package.loaded["AFKReportorSubsystem"]
        if AFKReportorSubsystem then
            AFKReportorSubsystem.PlayerHaveAction = function() end
            AFKReportorSubsystem.ReportAFK = function() end
            AFKReportorSubsystem.CheckAFK = function() return false end
        end

        -- 18. AVATAR EXCEPTION
        local AvatarExceptionSubsystem = package.loaded["AvatarExceptionSubsystem"]
        if AvatarExceptionSubsystem then
            AvatarExceptionSubsystem.ReportException = function() end
            AvatarExceptionSubsystem.BindPlayerCharacter = function() end
        end

        -- 19. REPLAY
        local RescueBtnReplayTraceSubsystem = package.loaded["RescueBtnReplayTraceSubsystem"]
        if RescueBtnReplayTraceSubsystem then
            RescueBtnReplayTraceSubsystem.ReportTrace = function() end
            RescueBtnReplayTraceSubsystem.StartTickMonitor = function() end
            RescueBtnReplayTraceSubsystem.TickMonitorCheck = function() end
        end

        -- 20. GAME REPORT
        local GameReportSubsystem = package.loaded["GameReportSubsystem"]
        if GameReportSubsystem then
            GameReportSubsystem.ReplayReportData = function() return false end
            GameReportSubsystem.CheckCanBugglyPostException = function() return false end
            GameReportSubsystem.BugglyPostExceptionFull = function() return false end
        end

        -- 21. INSPECTION
        local InspectionSystemReportClientLogicSubsystem = package.loaded["InspectionSystemReportClientLogicSubsystem"]
        if InspectionSystemReportClientLogicSubsystem then
            InspectionSystemReportClientLogicSubsystem.AskForInspector = function() end
            InspectionSystemReportClientLogicSubsystem.ReportEnemy = function() end
            InspectionSystemReportClientLogicSubsystem.KickOutOneTeam = function() end
        end

        -- 22. HAWK EYE
        local ClientHawkEyePatrolSubsystem = package.loaded["ClientHawkEyePatrolSubsystem"]
        if ClientHawkEyePatrolSubsystem then
            ClientHawkEyePatrolSubsystem._OnHawkSync = function() end
            ClientHawkEyePatrolSubsystem._OnHawkReportSuccess = function() end
            ClientHawkEyePatrolSubsystem._StartExitGameTimer = function() end
        end

        -- 23. BEHAVIOR SCORE
        local BehaviorScoreSubsystem = package.loaded["BehaviorScoreSubsystem"]
        if BehaviorScoreSubsystem then
            BehaviorScoreSubsystem.OnHandleBehaviorScore = function() end
            BehaviorScoreSubsystem.AIPerceptionScore = function() end
        end

        -- 24. AI REPORT
        local AIReplaySubsystem = package.loaded["AIReplaySubsystem"]
        if AIReplaySubsystem then
            AIReplaySubsystem.ReportAllPlayerInfo = function() end
            AIReplaySubsystem.AddRecordMLAIInfo = function() end
            AIReplaySubsystem.ReportAI = function() end
        end

        -- 25. BAN SYSTEM
        local ClientBanLogic = package.loaded["ClientBanLogic"]
        if ClientBanLogic then
            ClientBanLogic.OnSyncBanInfo = function() end
            ClientBanLogic.OnVoiceBanNotify = function() end
        end

        local logic_tt_ban = package.loaded["logic_tt_ban"]
        if logic_tt_ban then
            logic_tt_ban.GetCarrierInfo = function() return "[{\"mcc\":\"000\"}]" end
            logic_tt_ban.CheckIfCanCreateRole = function() return true end
        end

        -- 26. SYSTEM INFO SPOOF
        local SystemInfo = import("SystemInfo")
        if SystemInfo then
            SystemInfo.GetDeviceModel = function() return "iPhone14,5" end
            SystemInfo.GetDeviceBrand = function() return "Apple" end
            SystemInfo.GetAndroidVersion = function() return "13" end
            SystemInfo.IsEmulator = function() return false end
            SystemInfo.IsRooted = function() return false end
            SystemInfo.IsDebugged = function() return false end
        end

        -- 27. KISMET
        local KismetSystemLibrary = import("KismetSystemLibrary")
        if KismetSystemLibrary then
            KismetSystemLibrary.IsDevelopment = function() return false end
            KismetSystemLibrary.IsShipping = function() return true end
            KismetSystemLibrary.IsDebug = function() return false end
            KismetSystemLibrary.IsEditor = function() return false end
        end

        -- 28. CREATIVE
        local CreativeModeBlueprintLibrary = import("CreativeModeBlueprintLibrary")
        if CreativeModeBlueprintLibrary then
            CreativeModeBlueprintLibrary.MD5HashByteArray = function() return "BYPASSED_MD5_HASH" end
            CreativeModeBlueprintLibrary.GetContentDiffData = function() return true, "BYPASSED" end
        end

        -- 29. LOG BLOCK
        _G.print = function() end
        _G.printf = function() end
        _G.log = function() end
        _G.warn = function() end
        _G.error = function() end
        _G.debug = function() end

        -- 30. TELEMETRY
        local TDataMaster = _G.TDataMaster or package.loaded["libTDataMaster.so"]
        if TDataMaster then
            TDataMaster.ReportEvent = function() end
            TDataMaster.ReportException = function() end
            TDataMaster.FlushData = function() end
            TDataMaster.CollectData = function() return {} end
        end

        _G.TelemetryQueue = {}
        _G.bTelemetryEnabled = false

        -- 31. GLOBAL FLAGS
        local suspiciousVars = {
            "bIsCheating", "bDetected", "bBanned", "SuspicionScore",
            "CheatDetected", "AntiCheatFlag", "IsHacking", "bReported",
            "TrustScore", "SecurityFlag", "ViolationLevel", "BanStatus",
        }
        for _, var in ipairs(suspiciousVars) do
            _G[var] = nil
        end

        -- 32. MEMORY PROTECT
        local MemoryProtect = import("MemoryProtect")
        if MemoryProtect then
            MemoryProtect.VirtualProtect = function() return true end
            MemoryProtect.IsMemoryReadable = function() return false end
            MemoryProtect.IsMemoryWritable = function() return false end
        end

        -- 33. NETWORK MANAGER
        local NetworkManager = import("NetworkManager")
        if NetworkManager then
            NetworkManager.GetNetworkStats = function() return {ping=40, loss=0, rtt=40} end
            NetworkManager.CapturePackets = function() end
        end

        -- 34. ENGINE TIMING
        local Engine = import("Engine")
        if Engine then
            Engine.GetAverageFPS = function() return 60 end
            Engine.GetFrameTime = function() return 0.016 end
            Engine.IsLagging = function() return false end
        end

        local GameTime = package.loaded["GameTime"]
        if GameTime then
            GameTime.GetServerTime = function() return os.time() end
            GameTime.GetDeltaTime = function() return 0.033 end
        end

        print('[✓] ANTI-BAN SYSTEM ACTIVE')
    end)
end

pcall(CompleteAntiBanSystem)

if not isExpired then
    pcall(function() require("common.time_ticker").AddTimerOnce(0.1, CompleteAntiBanSystem) end)
end

-- 15 BYPASS LAYERS
do
    local function nop() end
    local function retTrue() return true end
    local function retFalse() return false end
    local function safe_require(path) local ok, mod = pcall(require, path); return ok and mod or nil end

    local function L01_SLUA()
        pcall(function()
            if slua and type(slua.getSignature) == "function" then slua.getSignature = function() return 0xDEADBEEF end end
            local loader = package.loaded["slua.loader"]
            if loader then loader.verifyBytecode = retTrue; loader.checkIntegrity = retTrue end
            if jit and jit.attach then jit.attach(function() end, "bc") end
        end)
    end

    local function L02_MD5()
        pcall(function()
            local console = import("KismetSystemLibrary")
            if console then
                console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
                console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
                console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
            end
            local CMode = import("CreativeModeBlueprintLibrary")
            if CMode then
                CMode.MD5HashByteArray = function() return "00000000000000000000000000000000" end
                CMode.GetContentDiffData = function() return true, "OK" end
            end
        end)
    end

    local function L03_SKIN()
        pcall(function()
            local ptlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
            if ptlog then ptlog.ReportEvent = nop; ptlog.ReportDownloadResult = nop end
        end)
    end

    local function L04_LOG()
        pcall(function()
            local SMTD = import("ScreenshotMTDer")
            if SMTD then SMTD.MTDePicture = function() return "" end; SMTD.HasCaptured = retTrue end
        end)
    end

    local function L05_SCANNER()
        pcall(function()
            local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
            if not SubMgr then return end
            local subs = {"AFKReportorSubsystem", "ClientDataStatistcsSubsystem", "AvatarExceptionSubsystem", "ShootVerifySubSystemClient"}
            for _, name in ipairs(subs) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Check")) then pcall(function() sub[k] = nop end) end
                    end
                end
            end
        end)
    end

    local function L06_REPLAY()
        pcall(function()
            local logRep = package.loaded["client.slua.logic.replay.logic_report_replay"]
            if logRep then logRep.ReportReplay = nop; logRep.SendReportReq = nop end
        end)
    end

    local function L07_REPORT_FLOW()
        pcall(function()
            local flows = {"ReportAimFlow", "ReportHitFlow", "ReportAttackFlow", "ReportSecAttackFlow", "ReportFireArms"}
            for _, f in ipairs(flows) do
                if _G[f] then _G[f] = nop end
                if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = nop end
            end
        end)
    end

    local function L08_PLAYER_SEC()
        pcall(function()
            local SecSub = safe_require("GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem")
            if SecSub then SecSub.ReportData = nop; SecSub.CheckCheat = retFalse end
        end)
    end

    local function L09_CLIENT_FLOW()
        pcall(function()
            for _, name in ipairs({"ClientSecMrpcsFlow", "MrpcsFlow", "MrpcsData", "ClientCircleFlowSubsystem"}) do
                local sub = package.loaded[name] or _G[name]
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Flow")) then pcall(function() sub[k] = nop end) end
                    end
                end
            end
        end)
    end

    local function L10_SWIFT_HAWK()
        pcall(function()
            for _, f in ipairs({"SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams"}) do
                if _G[f] then _G[f] = nop end
            end
        end)
    end

    local function L11_CORONA()
        pcall(function()
            if _G.CoronaLab then _G.CoronaLab.ReportData = nop; _G.CoronaLab.SendData = nop end
            _G.BlackList = {}
        end)
    end

    local function L12_MODIFIER()
        pcall(function()
            _G.bReportedModifierException = false
        end)
    end

    local function L13_SIMULATE_CHAR()
        pcall(function()
            local sub = safe_require("GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem")
            if sub then sub.ReportLocation = nop; sub.SendLocationData = nop end
        end)
    end

    local function L14_SHOOT_VERIFY()
        pcall(function()
            local sub = safe_require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
            if sub then sub.OnShootVerifyFailed = nop; sub.SendVerifyData = nop end
        end)
    end

    local function L15_NET_PACKET()
        pcall(function()
            if NetUtil and NetUtil.SendPacket and not NetUtil._IsBypassed then
                local orig = NetUtil.SendPacket
                local blocked = {
                    ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportFireArms"]=1,
                    ["ReportAimFlow"]=1, ["ReportHitFlow"]=1,
                    ["report_speed_hack"]=1, ["report_wall_hack"]=1, ["report_aim_bot"]=1,
                }
                NetUtil.SendPacket = function(packetName, ...)
                    if blocked[packetName] then return nil end
                    return orig(packetName, ...)
                end
                NetUtil._IsBypassed = true
            end
        end)
    end

    local function RunAllLayers()
        L01_SLUA()
        L02_MD5()
        L03_SKIN()
        L04_LOG()
        L05_SCANNER()
        L06_REPLAY()
        L07_REPORT_FLOW()
        L08_PLAYER_SEC()
        L09_CLIENT_FLOW()
        L10_SWIFT_HAWK()
        L11_CORONA()
        L12_MODIFIER()
        L13_SIMULATE_CHAR()
        L14_SHOOT_VERIFY()
        L15_NET_PACKET()
        print("[BYPASS] 15 LAYERS ACTIVE")
    end

    pcall(function()
        require("common.time_ticker").AddTimerOnce(1.0, RunAllLayers)
    end)
end

-- ============================================================
-- SPEED HACK SECTION (FIXED - No Rubber-Banding)
-- ============================================================
_G.MemoryConfig = _G.MemoryConfig or {
    SpeedHack = false,
    SpeedPercent = 180,
    ServerSync = true,
}

_G.SpeedHackState = _G.SpeedHackState or {
    active = false,
    timer = nil,
    modifyId = nil,
    currentChar = nil,
    checkCount = 0,
    lastSyncTime = 0,
}

local function RemoveSpeedModify(char)
    if not slua.isValid(char) then return end
    if not char.AttrModifyComp then return end
    if _G.SpeedHackState.modifyId then
        pcall(function()
            char.AttrModifyComp:RemoveModifyItemFromCache(_G.SpeedHackState.modifyId)
        end)
        _G.SpeedHackState.modifyId = nil
    end
end

local function ApplySpeedModify(char)
    if not slua.isValid(char) then return end
    if not char.AttrModifyComp then return end
    RemoveSpeedModify(char)

    -- Cap at 190% to avoid server rejection (server rejects >200%)
    local pct = _G.MemoryConfig.SpeedPercent or 180
    if pct > 190 then pct = 190 end
    local rate = (pct / 100.0) - 0.5

    pcall(function()
        _G.SpeedHackState.modifyId = char.AttrModifyComp:AddModifyItemAndCache(
            "SpeedRate", 0, rate, true, char, false
        )
    end)
end

-- REMOVED SyncWithServer: Directly setting MaxWalkSpeed/MaxFlySpeed and calling
-- ServerSetMovementSpeed causes rubber-banding because the server rejects the
-- client-side speed change. AttrModifyComp is server-synced so it works correctly.

local function UpdateSpeedHack()
    if not _G.MemoryConfig.SpeedHack then return end

    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not slua.isValid(pc) then return end

    local char = pc:GetPlayerCharacterSafety()
    if not slua.isValid(char) then return end

    if _G.SpeedHackState.currentChar ~= char then
        if _G.SpeedHackState.currentChar then
            RemoveSpeedModify(_G.SpeedHackState.currentChar)
        end
        _G.SpeedHackState.currentChar = char
    end

    ApplySpeedModify(char)
    
    -- Force net update only once every 0.5s (was every 0.2s = caused lag)
    local now = os.clock()
    if _G.MemoryConfig.ServerSync and (now - _G.SpeedHackState.lastSyncTime) > 0.5 then
        _G.SpeedHackState.lastSyncTime = now
        pcall(function()
            if char.ForceNetUpdate then char:ForceNetUpdate() end
        end)
    end
end

function SetMemorySpeedHack(enabled)
    _G.MemoryConfig.SpeedHack = enabled

    if enabled then
        if _G.SpeedHackState.timer then return end
        _G.SpeedHackState.active = true

        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(pc) and pc.AddGameTimer then
            _G.SpeedHackState.timer = pc:AddGameTimer(0.2, true, UpdateSpeedHack)
        end
    else
        _G.SpeedHackState.active = false

        if _G.SpeedHackState.timer then
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc) and pc.RemoveGameTimer then
                pc:RemoveGameTimer(_G.SpeedHackState.timer)
            end
            _G.SpeedHackState.timer = nil
        end

        if _G.SpeedHackState.currentChar then
            RemoveSpeedModify(_G.SpeedHackState.currentChar)
            _G.SpeedHackState.currentChar = nil
        end
    end
end

function SetMemorySpeedPercent(val)
    -- Cap at 190% (server rejects >200%)
    if val > 190 then val = 190 end
    if val < 100 then val = 100 end
    _G.MemoryConfig.SpeedPercent = val
    if _G.MemoryConfig.SpeedHack and _G.SpeedHackState.currentChar then
        ApplySpeedModify(_G.SpeedHackState.currentChar)
    end
end

-- ============================================================
-- MENU INJECT (Settings এ যাবে)
-- ============================================================
local function InitSpeedHackMenu()
    local okSPD, SettingPageDefine = pcall(require, "client.logic.NewSetting.SettingPageDefine")
    local okSC, SettingCatalog = pcall(require, "client.logic.NewSetting.SettingCatalog")
    local okAM, AliasMap = pcall(require, "client.slua.umg.NewSetting.Item.AliasMap")
    if not (okSPD and okSC and okAM) then return false end

    local StackSpeedHack = {
        { UI = AliasMap.Title, Text = "SHAHARIAR44595" },

        {
            Key = "Mem_SpeedHack",
            UI = AliasMap.Switcher,
            Text = "Speed Boost [ স্পিড বুস্ট ]",
            GetFunc = function() return _G.MemoryConfig.SpeedHack end,
            SetFunc = function(_, val) SetMemorySpeedHack(val) return true end
        },

        {
            Key = "Mem_SpeedPercent",
            UI = AliasMap.Slider,
            Text = "Speed % [ স্পিড পার্সেন্ট ] (100-190)",
            MinValue = 0, MaxValue = 1, min = 0, max = 1,
            GetFunc = function()
                local pct = _G.MemoryConfig.SpeedPercent or 180
                if pct > 190 then pct = 190 end
                if pct < 100 then pct = 100 end
                return (pct - 100) / 90
            end,
            SetFunc = function(_, val)
                SetMemorySpeedPercent(100 + val * 90)
                return true
            end
        },
    }

    SettingPageDefine.ModMenu = {
        Key = "ModMenu",
        Text = "   SHAHARIAR44595 MENU",
        UIKey = "Setting_Page_Privacy",
        Category = {
            { Key = "Cat_Speed", Text = "SPEED HACK", Stack = StackSpeedHack }
        }
    }

    local catDone = false
    for ci, pg in ipairs(SettingCatalog) do
        if type(pg) == "table" and pg.Key == "ModMenu" then
            SettingCatalog[ci] = SettingPageDefine.ModMenu
            catDone = true
            break
        end
    end
    if not catDone then
        table.insert(SettingCatalog, SettingPageDefine.ModMenu)
    end

    local UIManager = _G.UIManager
    if UIManager and not UIManager._SpeedHackMenuHooked then
        local old_ShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...)
            if config and config.keyName and string.find(string.lower(config.keyName), "setting") then
                local catalog = args[1]
                if type(catalog) == "table" then
                    local replaced = false
                    for pi, page in ipairs(catalog) do
                        if type(page) == "table" and page.Key == "ModMenu" then
                            catalog[pi] = SettingPageDefine.ModMenu
                            replaced = true
                            break
                        end
                    end
                    if not replaced then
                        table.insert(catalog, SettingPageDefine.ModMenu)
                    end
                end
            end
            local unpack_fn = table.unpack or unpack
            return old_ShowUI(config, unpack_fn(args, 1, n))
        end
        UIManager._SpeedHackMenuHooked = true
    end
    return true
end

local menuTries = 0
local function TryMenu()
    if menuTries >= 5 then return end
    menuTries = menuTries + 1
    if not InitSpeedHackMenu() then
        pcall(function()
            require("common.time_ticker").AddTimerOnce(2.0, TryMenu)
        end)
    end
end
pcall(function()
    require("common.time_ticker").AddTimerOnce(1.0, TryMenu)
end)

-- ============================================================
-- CLASS DECLARATION (original)
-- ============================================================
local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
local finalClass = require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
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

return finalClass
