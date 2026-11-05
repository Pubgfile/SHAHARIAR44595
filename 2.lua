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

function BRPlayerCharacterBase:ctor() end

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
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", { AttrName = { "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1] = "FinishedState" }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "") end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "") end
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
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI() end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam() end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState() end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState() end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI() end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then GameplayData.RemoveCharacter(self.Object) end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then return uGameState.GameModeType == EGameModeType.EWarGameMode else return false end
end

function BRPlayerCharacterBase:BPOnRecycled() if Client then self:ResetMeshRelativeLocationAndRotation() end end
function BRPlayerCharacterBase:BPOnRespawned() if Client then self:ResetMeshRelativeLocationAndRotation() end end
function BRPlayerCharacterBase:ReceiveOnRecycle() if Client then self:ResetMeshRelativeLocationAndRotation(); GameplayData.RemoveCharacter(self.Object) end end
function BRPlayerCharacterBase:ReceiveOnSpawn() if Client then self:ResetMeshRelativeLocationAndRotation(); GameplayData.AddCharacter(self.Object) end end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    if self.Mesh.K2_SetRelativeRotation then self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false) end
    self:CacheInitialMeshOffset(FVector(0, 0, 0), uDefaultMeshRot)
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

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord() end
function BRPlayerCharacterBase:PreAttachedToVehicle() end

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

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then return end
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then MedievalCrane:RemoveCharacter(self.Object) end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then return end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) or not Lifter.AddCharacter then return end
  return Lifter
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
  local EmoteHandleAsset = slua.loadObject(animCfg.Path)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  function loadLater() uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0) end
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  if slua.isValid(self.ParachuteComponent) then self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall end
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
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then uPlayerController:DisplayGameTipWithMsgID(47306) end
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

-- ============================================================
-- START FULL LOGIC MOD ==========================
-- ============================================================
local function Notify(msg) 
    local s = "[MS_CONFIG_VIP] " .. tostring(msg)
    pcall(function() 
        local sh = import("ScriptHelperClient") 
        if sh and sh.AddOnScreenDebugMessage then 
            sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1, G=1, B=0, A=1}, {X=1.2, Y=1.2}) 
        end 
    end)
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

local C_GREEN = {R=0, G=255, B=0, A=255}
local C_RED = {R=255, G=0, B=0, A=255}
local C_CYAN = {R=0, G=255, B=255, A=255}
local C_YELLOW = {R=255, G=255, B=0, A=255}
local C_WHITE = {R=255, G=255, B=255, A=255}
local C_BLUE_TEXT = {R=0, G=200, B=255, A=255}

_G.GTLModConfig = _G.GTLModConfig or {
    EspV2Enabled = true, EspV2Counter = true, EspV2Name = false, EspV2Health = true, EspV2Bracket = true, EspV2SnapLine = false, EspV2Distance = true, EspV2Offscreen = false,
    AimTouchEnable = false, AimTouchHipIgKnock = true, AimTouchHipIgBot = true, AimTouchSGIgKnock = true, AimTouchSGIgBot = true, AimTouchHipVisCheck = true, AimTouchSGVisCheck = true, AimTouchHipfire = false, AimTouchSG = false, AimTouchSGAutoFire = false, AimTouchScopeAll = false, AimTouchScopeIgKnock = true, AimTouchScopeIgBot = true, AimTouchScopeVisCheck = true, AimTouchScopeSniper = false, AimTouchSniperIgKnock = true, AimTouchSniperIgBot = false, AimTouchSniperVisCheck = true,
    ModSkin = true, OutlineThickness = 10,
}

_G.GTLModConfig.EspVip = false; _G.GTLModConfig.EspVipPro = false; _G.GTLModConfig.EspDistance = false; _G.GTLModConfig.EspRadar = false; _G.GTLModConfig.Esp5 = false; _G.GTLModConfig.Esp6 = false; _G.GTLModConfig.Esp7 = false; _G.GTLModConfig.Esp8 = false; _G.GTLModConfig.EspAntenna = false; _G.GTLModConfig.EspName = false; _G.GTLModConfig.EspOutline = false; _G.GTLModConfig.Wallhack = false; _G.GTLModConfig.ColorBodyNew = false; _G.GTLModConfig.CustomMagicBullet = false; _G.GTLModConfig.MagicBullet = false; _G.GTLModConfig.AutoHead = false; _G.GTLModConfig.GodMode = false; _G.GTLModConfig.CustomAimbot = false; _G.GTLModConfig.CustomAimbotClose = false; _G.GTLModConfig.CustomHRecoil = false; _G.GTLModConfig.CustomVRecoil = false; _G.GTLModConfig.LessShake = false; _G.GTLModConfig.Accuracy = false; _G.GTLModConfig.Crosshair = false; _G.GTLModConfig.RemoveGrass = false; _G.GTLModConfig.RemoveFog = false; _G.GTLModConfig.WhiteBody = false; _G.GTLModConfig.BlackSky = false; _G.GTLModConfig.UnlockFPS = false; _G.GTLModConfig.IpadView = false; _G.GTLModConfig.VehicleEnabled = false; _G.GTLModConfig.ThrowableEnabled = false; _G.GTLModConfig.EspLoot = false; _G.GTLModConfig.EspStatic = false; _G.GTLModConfig.EspEnemyCount = false; _G.GTLModConfig.EspWeaponStatus = false; _G.GTLModConfig.KillMessage = false; _G.GTLModConfig.SkinDeadBox = false; _G.GTLModConfig.KillCountUI = false; _G.GTLModConfig.ExpertEnabled = false; _G.GTLModConfig.EnableWeaponMod = false;

_G.GTLModState = _G.GTLModState or {
    LoopToken = 0, AimbotLoopToken = 0, NativeESPReady = false, GraphicsUnlocked = false, MenuStep = 0, LastCmdTime = 0, TrackedMarks = {}, EnemyMarks = {}, LastAimbotCheckTime = 0, CustomTextData = nil, LastAimbotConfigString = "", MagicUpdateVersion = 1, LastMagicConfigHash = "", PrevGraphicsState = {}, SkinWasApplied = false, ConsoleNewWallReady = false,
}

_G.__CLEAR_VISION_V2_INIT_OK, _G.__CLEAR_VISION_V2_INIT_ERROR = pcall(function()
    local FVector2D = _G.FVector2D or import("Vector2D")
    local FLinearColor = _G.FLinearColor or import("LinearColor")
    local SlateBlueprintLibrary = nil
    local WidgetLayoutLibrary = nil
    pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
    pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") end)

    local function IsValid(o)
        if not o then return false end
        local ok, value = pcall(function() return slua.isValid(o) end)
        return ok and value == true
    end

    local function V2(x, y)
        if FVector2D then return FVector2D(x, y) end
        return {X=x, Y=y}
    end

    local function Color(r, g, b, a)
        if FLinearColor then return FLinearColor(r, g, b, a or 1.0) end
        return {R=r, G=g, B=b, A=a or 1.0}
    end

    local function CV2Flag(key, defaultValue)
        local cfg = rawget(_G, "GTLModConfig")
        if type(cfg) ~= "table" then return defaultValue == true end
        local v = cfg[key]
        if v == nil then return defaultValue == true end
        return v == true
    end

    local COLORS = {
        Gold = Color(1.00, 0.84, 0.42, 1.00), GoldBright = Color(1.00, 0.92, 0.62, 1.00),
        GoldSoft = Color(1.00, 0.90, 0.56, 0.42), GoldDim = Color(0.36, 0.25, 0.055, 0.96),
        White = Color(0.98, 0.98, 0.98, 1.00), Dark2 = Color(0.045, 0.045, 0.055, 0.97),
        Gray = Color(0.42, 0.42, 0.42, 1.00), RedDim = Color(0.25, 0.02, 0.02, 0.95),
        RedSoft = Color(1.00, 0.28, 0.28, 0.30), GreenDim = Color(0.03, 0.20, 0.05, 0.96),
        GreenSoft = Color(0.38, 1.00, 0.50, 0.28), BloodRed = Color(0.84, 0.010, 0.018, 1.00),
        BloodRedBright = Color(1.00, 0.025, 0.040, 1.00), BloodRedSoft = Color(1.00, 0.24, 0.22, 0.46),
        BloodRedDim = Color(0.26, 0.002, 0.008, 0.98), BloodRedShade = Color(0.10, 0.000, 0.004, 0.66),
        Yellow = Color(1.00, 0.76, 0.000, 1.00), YellowBright = Color(1.00, 0.96, 0.10, 1.00),
        YellowSoft = Color(1.00, 0.88, 0.20, 0.48), YellowDim = Color(0.48, 0.27, 0.000, 0.98),
        YellowShade = Color(0.16, 0.075, 0.000, 0.66), BotRedText = Color(0.94, 0.010, 0.020, 1.00),
        RedBright = Color(1.00, 0.28, 0.28, 1.00), GreenBright = Color(0.38, 1.00, 0.50, 1.00),
    }

    local ClearVisionV2 = rawget(_G, "__CLEAR_VISION_ESP_V2")
    local CV2_BUILD = "cv-esp-v2-matchfix-r2-033"

    if type(ClearVisionV2) == "table" and ClearVisionV2.Build ~= CV2_BUILD
        and type(ClearVisionV2.Stop) == "function" then
        pcall(ClearVisionV2.Stop)
    end

    if type(ClearVisionV2) ~= "table" or ClearVisionV2.Build ~= CV2_BUILD then
        ClearVisionV2 = {
            Build = CV2_BUILD, Active = false, ESPCanvas = nil, Controller = nil, LocalPawn = nil,
            EnemyCache = {}, EnemyWidgets = {}, MaxEnemies = 20, RangeMeters = 250.0,
            ScanInterval = 1.0, DrawInterval = 0.0167, _CanvasScaleX = 1.0, _CanvasScaleY = 1.0,
            _CanvasOffsetX = 0.0, _CanvasOffsetY = 0.0, _CachedViewportW = 1920, _CachedViewportH = 1080,
            _CapsuleCache = setmetatable({}, {__mode="k"}), _ProjectionCache = {}, EnemyMeta = {},
            RealEnemyCount = 0, BotEnemyCount = 0, Counter = nil, _FrameSerial = 0,
            _TransformEveryNFrames = 6, _CounterEveryNFrames = 6, _TimerGeneration = 0,
        }
        _G.__CLEAR_VISION_ESP_V2 = ClearVisionV2
    end

    local REF_W = 688.0
    local REF_H = 996.0
    local REF_BODY_TOP = 172.0
    local REF_BODY_BOTTOM = 900.0
    local REF_BODY_SPAN = REF_BODY_BOTTOM - REF_BODY_TOP

    local function SetVisible(widget, visible)
        if not IsValid(widget) then return false end
        local vis = visible and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed
        return pcall(function() widget:SetWidgetVisibility(vis) end)
    end

    local function SetTextColor(widget, linearColor)
        if not IsValid(widget) then return false end
        return pcall(function()
            local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            if FSlateColor then widget:SetColorAndOpacity(FSlateColor(linearColor))
            else widget:SetColorAndOpacity(linearColor) end
        end)
    end

    local function SetFontSize(widget, size)
        if not IsValid(widget) then return false end
        return pcall(function()
            if widget.Font then
                local f = widget.Font
                f.Size = math.max(5, math.floor(size + 0.5))
                widget:SetFont(f)
            end
        end)
    end

    local function SetFontBold(widget)
        if not IsValid(widget) then return false end
        return pcall(function()
            if widget.Font then
                local f = widget.Font
                pcall(function() f.TypefaceFontName = "Bold" end)
                widget:SetFont(f)
            end
        end)
    end

    local function DestroyWidget(widget)
        if not widget then return end
        pcall(function() widget:RemoveFromParent() end)
        pcall(function() widget:ConditionalBeginDestroy() end)
    end

    local function GetWorldSafe()
        local world=nil
        pcall(function() if slua and slua.getWorld then world=slua.getWorld() end end)
        return world
    end

    local function ResolveControllerFresh()
        local pc=nil
        pcall(function() if GameplayData and GameplayData.GetPlayerController then pc=GameplayData.GetPlayerController() end end)
        if not IsValid(pc) then pcall(function() if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then pc=slua_GameFrontendHUD:GetPlayerController() end end) end
        return IsValid(pc) and pc or nil
    end

    local function GetController()
        local fresh=ResolveControllerFresh()
        if IsValid(fresh) then return fresh end
        local cached=ClearVisionV2.Controller
        return IsValid(cached) and cached or nil
    end

    local function ResolveLocalPawnFresh(pc)
        local pawn=nil
        pcall(function() if GameplayData and GameplayData.GetPlayerCharacter then pawn=GameplayData.GetPlayerCharacter() end end)
        if not IsValid(pawn) and IsValid(pc) then pcall(function() if pc.GetPlayerCharacterSafety then pawn=pc:GetPlayerCharacterSafety() end end) end
        return IsValid(pawn) and pawn or nil
    end

    local function GetLocalPawn(pc)
        local fresh=ResolveLocalPawnFresh(pc)
        if IsValid(fresh) then return fresh end
        local cached=ClearVisionV2.LocalPawn
        return IsValid(cached) and cached or nil
    end

    local function GetActorLocation(actor)
        if not IsValid(actor) then return nil end
        local loc = nil
        pcall(function() if actor.K2_GetActorLocation then loc = actor:K2_GetActorLocation() end end)
        return loc
    end

    local function DistanceMeters(a, b)
        if not a or not b then return math.huge end
        local dx, dy, dz = (a.X or 0)-(b.X or 0), (a.Y or 0)-(b.Y or 0), (a.Z or 0)-(b.Z or 0)
        return math.sqrt(dx*dx + dy*dy + dz*dz) / 100.0
    end

    local function GetPlayerState(character)
        if not IsValid(character) then return nil end
        local ps = nil
        pcall(function() if character.GetPlayerStateSafety then ps = character:GetPlayerStateSafety() end end)
        return IsValid(ps) and ps or nil
    end

    local function GetTeamID(character)
        if not IsValid(character) then return nil end
        local team = nil
        pcall(function() if character.GetTeamID then team = character:GetTeamID() end end)
        return team
    end

    local function IsAlive(character)
        if not IsValid(character) then return false end
        local ok, alive = pcall(function() if type(character.IsAlive) == "function" then return character:IsAlive() end end)
        if ok and type(alive) == "boolean" then return alive end
        local hp = nil
        pcall(function() if character.Health ~= nil then hp = character.Health end end)
        return tonumber(hp) ~= nil and tonumber(hp) > 0
    end

    local function GetHealthPercent(character)
        local hp, maxHp = nil, nil
        pcall(function()
            if character.Health ~= nil then hp = character.Health end
            if character.HealthMax ~= nil then maxHp = character.HealthMax end
        end)
        hp = tonumber(hp) or 0; maxHp = tonumber(maxHp) or 100
        if maxHp <= 0 then maxHp = 100 end
        return math.max(0, math.min(1, hp / maxHp))
    end

    local function GetPlayerKey(character)
        local key = nil
        pcall(function() if character.PlayerKey then key = character.PlayerKey end end)
        return key
    end

    local function Clamp(v, lo, hi)
        if v < lo then return lo end; if v > hi then return hi end; return v
    end

    local function GetPlayerName(character)
        if not IsValid(character) then return "ENEMY", false end
        local name = nil
        pcall(function() if type(character.GetPlayerNameSafety) == "function" then name = tostring(character:GetPlayerNameSafety()) end end)
        return name or "ENEMY", name ~= nil
    end

    local function IsAI(character)
        if not IsValid(character) then return false end
        local isAI = false
        pcall(function() if character.bIsAI == true then isAI = true end end)
        return isAI
    end

    local function GetViewportSize(pc)
        local w, h = 0, 0
        pcall(function() if pc and pc.GetViewportSize then local v = V2(0,0); pc:GetViewportSize(v); w,h = v.X,v.Y end end)
        return w > 0 and w or 1920, h > 0 and h or 1080
    end

    local function GetCharacterBounds(character)
        if not IsValid(character) then return nil, nil end
        local center, halfHeight = nil, 85
        pcall(function() if character.K2_GetActorLocation then center = character:K2_GetActorLocation() end end)
        if not center then return nil, nil end
        return {X=center.X, Y=center.Y, Z=center.Z + halfHeight}, {X=center.X, Y=center.Y, Z=center.Z - halfHeight}
    end

    local function ScreenToCanvas(p)
        if not p then return nil end
        return {X = p.X * (ClearVisionV2._CanvasScaleX or 1.0) + (ClearVisionV2._CanvasOffsetX or 0.0), Y = p.Y * (ClearVisionV2._CanvasScaleY or 1.0) + (ClearVisionV2._CanvasOffsetY or 0.0)}
    end

    local function ProjectToCanvas(pc, worldLoc, cache)
        cache = cache or {}; cache.Pix = cache.Pix or V2(0,0)
        local pix = cache.Pix; pix.X, pix.Y = 0,0
        local ok = false
        pcall(function() local res = pc:ProjectWorldLocationToScreen(worldLoc, pix, true); ok = (res == true or (pix.X ~= 0 or pix.Y ~= 0)) end)
        if not ok then return false, nil end
        return true, ScreenToCanvas(pix)
    end

    local function NewWidget(path, outer)
        local obj = nil; pcall(function() obj = CGame:NewObjectFromPath(path, outer) end)
        return IsValid(obj) and obj or nil
    end

    local function AddChild(parent, child, zOrder)
        if not IsValid(parent) or not IsValid(child) then return nil end
        local slot = nil
        pcall(function() slot = parent:AddChildToCanvas(child); if slot then slot:SetAutoSize(false); if zOrder then slot:SetZOrder(zOrder) end end end)
        return IsValid(slot) and slot or nil
    end

    local function CreateBorder(parent, color, z)
        local widget = NewWidget("/Script/UMG.Border", parent)
        if not widget then return nil end
        pcall(function() widget:SetBrushColor(color); widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible); widget:SetRenderTransformPivot(V2(0.0,0.5)) end)
        local slot = AddChild(parent, widget, z or 1)
        if not slot then DestroyWidget(widget); return nil end
        return {Widget=widget, Slot=slot}
    end

    local function CreateText(parent, value, color, fontSize, z)
        local widget = NewWidget("/Script/UMG.TextBlock", parent)
        if not widget then return nil end
        pcall(function() widget:SetText(tostring(value or "")); widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        SetTextColor(widget, color or COLORS.White); SetFontSize(widget, fontSize or 12)
        local slot = AddChild(parent, widget, z or 5)
        if not slot then DestroyWidget(widget); return nil end
        return {Widget=widget, Slot=slot}
    end

    local function SetRect(item, x, y, w, h)
        if not item or not IsValid(item.Slot) then return false end
        return pcall(function() item.Slot:SetPosition(V2(x,y)); item.Slot:SetSize(V2(math.max(0.5,w), math.max(0.5,h))) end)
    end

    local function SetLine(item, x1, y1, x2, y2, thickness)
        if not item or not IsValid(item.Widget) or not IsValid(item.Slot) then return false end
        local dx, dy = x2-x1, y2-y1
        local length = math.sqrt(dx*dx + dy*dy)
        if length < 0.2 then SetVisible(item.Widget, false); return false end
        local angle = ((math.atan2 and math.atan2(dy,dx)) or math.atan(dy,dx)) * 180.0 / math.pi
        return pcall(function() item.Slot:SetPosition(V2(x1, y1-thickness*0.5)); item.Slot:SetSize(V2(length, math.max(0.5,thickness))); item.Widget:SetRenderAngle(angle); item.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    end

    local function SetBorderColor(item, color)
        if item and IsValid(item.Widget) then pcall(function() item.Widget:SetBrushColor(color) end) end
    end

    local function SetTextValue(item, value)
        if item and IsValid(item.Widget) then pcall(function() item.Widget:SetText(tostring(value)) end) end
    end

    local function ApplyEnemyTheme(data, isAI)
        if not data then return end
        local stroke = isAI and COLORS.YellowBright or COLORS.BloodRedBright
        local dim = isAI and COLORS.YellowDim or COLORS.BloodRedDim
        local topGlow = isAI and COLORS.YellowSoft or COLORS.BloodRedSoft
        local bottomShade = isAI and COLORS.YellowShade or COLORS.BloodRedShade
        local textColor = isAI and COLORS.BotRedText or COLORS.White
        for _,item in ipairs(data.Arc or {}) do SetBorderColor(item, stroke) end
        for _,item in ipairs(data.PlateLines or {}) do SetBorderColor(item, stroke) end
        for _,item in ipairs(data.StatusOuter or {}) do SetBorderColor(item, stroke) end
        for _,item in ipairs(data.PlateCornerFill or {}) do SetBorderColor(item, dim) end
        if data.PlateBGCore then SetBorderColor(data.PlateBGCore, dim) end
        if data.PlateTopGlow then SetBorderColor(data.PlateTopGlow, topGlow) end
        if data.PlateBottomShade then SetBorderColor(data.PlateBottomShade, bottomShade) end
        if data.SnapLine then SetBorderColor(data.SnapLine, stroke) end
        if data.TitleText then SetTextColor(data.TitleText.Widget, textColor) end
        if data.DistanceText then SetTextColor(data.DistanceText.Widget, textColor) end
        if data.DistanceTextBack then SetTextColor(data.DistanceTextBack.Widget, textColor) end
    end

    local function ApplyV2FeatureVisibility(data)
        if not data then return end
        local showBracket = CV2Flag("EspV2Bracket", true)
        local showName = CV2Flag("EspV2Name", true)
        local showHealth = CV2Flag("EspV2Health", true)
        if data._VisBracket ~= showBracket then data._VisBracket = showBracket; for _,item in ipairs(data.Arc or {}) do if item and item.Widget then SetVisible(item.Widget, showBracket) end end end
        if data._VisName ~= showName then data._VisName = showName; local items = {data.PlateBGCore, data.PlateBGMid, data.PlateTopGlow, data.PlateBottomShade, data.TitleText}; for _,item in ipairs(items) do if item and item.Widget then SetVisible(item.Widget, showName) end end end
        if data._VisHealth ~= showHealth then data._VisHealth = showHealth; for _,item in ipairs(data.StatusOuter or {}) do if item and item.Widget then SetVisible(item.Widget, showHealth) end end; for _,item in ipairs(data.StatusInner or {}) do if item and item.Widget then SetVisible(item.Widget, showHealth) end end end
    end

    local function SetRootVisible(data, visible)
        if not data or not data.Root or data._RootVisible == visible then return end
        data._RootVisible = visible; SetVisible(data.Root, visible)
    end

    local function SetSnapVisible(data, visible)
        if not data or not data.SnapLine or not data.SnapLine.Widget or data._SnapVisible == visible then return end
        data._SnapVisible = visible; SetVisible(data.SnapLine.Widget, visible)
    end

    local function SetDistanceVisible(data, visible)
        if not data or data._DistanceVisible == visible then return end
        data._DistanceVisible = visible
        if data.DistanceText and data.DistanceText.Widget then SetVisible(data.DistanceText.Widget, visible) end
        if data.DistanceTextBack and data.DistanceTextBack.Widget then SetVisible(data.DistanceTextBack.Widget, visible) end
    end

    local function CreateEnemyWidget(key)
        if not ClearVisionV2.InitCanvas(false) then return nil end
        local parent = ClearVisionV2.ESPCanvas
        if not IsValid(parent) then return nil end
        local root = NewWidget("/Script/UMG.CanvasPanel", parent)
        if not root then return nil end
        local rootSlot = AddChild(parent, root, 20)
        if not rootSlot then DestroyWidget(root); return nil end
        local data = {Root=root, RootSlot=rootSlot, Arc={}, PlateLines={}, PlateCornerFill={}, StatusOuter={}, StatusInner={}, Key=key}
        data.PlateBGCore = CreateBorder(root, COLORS.Dark2, 4); data.PlateBGMid = CreateBorder(root, COLORS.Dark2, 4)
        data.PlateTopGlow = CreateBorder(root, COLORS.GoldSoft, 5); data.PlateBottomShade = CreateBorder(root, Color(0.05,0.025,0.0,0.50), 5)
        data.TitleText = CreateText(root, "", COLORS.White, 22, 7)
        data.DistanceTextBack = CreateText(parent, "", COLORS.Gold, 20, 58); data.DistanceText = CreateText(parent, "", COLORS.Gold, 20, 59)
        SetFontBold(data.DistanceTextBack and data.DistanceTextBack.Widget); SetFontBold(data.DistanceText and data.DistanceText.Widget)
        for i=1,8 do data.PlateLines[i] = CreateBorder(root, COLORS.Gold, 6) end
        for i=1,4 do data.PlateCornerFill[i] = CreateBorder(root, COLORS.GoldDim, 4) end
        for i=1,4 do data.StatusOuter[i] = CreateBorder(root, COLORS.Gold, 6); data.StatusInner[i] = CreateBorder(root, COLORS.Gray, 7) end
        for i=1,22 do data.Arc[i] = CreateBorder(root, COLORS.Gold, 2) end
        data.SnapLine = CreateBorder(parent, COLORS.Gold, 1)
        if not data.PlateBGCore or not data.TitleText or not data.DistanceText or not data.SnapLine then DestroyWidget(root); return nil end
        ClearVisionV2.EnemyWidgets[key] = data
        return data
    end

    local function LayoutEnemy(data, s, displayName)
        if not data then return end
        local function X(v) return v*s end; local function Y(v) return v*s end
        pcall(function() data.RootSlot:SetSize(V2(REF_W*s, REF_H*s)) end)
        local arcIndex = 1; local cx, cy = 343, 550; local rx, ry = 195.5, 356.0
        local function drawTaperedArc(a0, a1, segments)
            local px,py=nil,nil
            for i=0,segments do
                local t=i/segments; local a=a0+(a1-a0)*t; local xx=cx+math.cos(a)*rx; local yy=cy+math.sin(a)*ry
                if px then local mid=(i-0.5)/segments; local bell=math.sin(math.pi*mid); if bell<0 then bell=0 end; local thin=Clamp(2.4*s,1.0,1.8); local thick=Clamp(12.5*s,3.0,6.0); local thickness=thin+(thick-thin)*(bell^1.45); SetLine(data.Arc[arcIndex],X(px),Y(py),X(xx),Y(yy),thickness); arcIndex=arcIndex+1 end
                px,py=xx,yy
            end
        end
        drawTaperedArc(math.pi*0.56,math.pi*1.44,7); drawTaperedArc(-math.pi*0.44,math.pi*0.44,7)
        local innerRX,innerRY=166.0,296.0
        local function miniBracket(centerA, slot)
            local d=math.pi*0.030; local p={}
            for j=-1,1 do local a=centerA+j*d; p[#p+1]={cx+math.cos(a)*innerRX,cy+math.sin(a)*innerRY} end
            local t=Clamp(7.0*s,1.6,3.8); SetLine(data.Arc[slot],X(p[1][1]),Y(p[1][2]),X(p[2][1]),Y(p[2][2]),t); SetLine(data.Arc[slot+1],X(p[2][1]),Y(p[2][2]),X(p[3][1]),Y(p[3][2]),t)
        end
        miniBracket(math.pi*0.84,15); miniBracket(math.pi*1.16,17); miniBracket(-math.pi*0.16,19); miniBracket(math.pi*0.16,21)
        displayName=tostring(displayName or "ENEMY")
        local nameLen=#displayName; pcall(function() if utf8 and utf8.len then nameLen=utf8.len(displayName) or nameLen end end)
        if nameLen < 1 then nameLen=1 end
        local nameFont=Clamp(58*s,13,44); local estimated=nameLen*nameFont*0.60
        if estimated+24.0>420.0 then nameFont=math.max(9.0,(420.0-24.0)/(nameLen*0.60)); estimated=nameLen*nameFont*0.60 end
        local plateW=Clamp(estimated+24.0,118.0,420.0); local plateH=Clamp(nameFont*1.50,28,64)
        local q=Clamp(28*s,7,21); local gap=Clamp(8*s,3,8); local statusW=q*4+gap*3; local headLocalY=REF_BODY_TOP*s; local bodyGap=Clamp(18*s,8,18); local statusGap=Clamp(7*s,3,8); local statusY=headLocalY-bodyGap-q; local plateY=statusY-statusGap-plateH; local plateCX=X(343); local plateX=plateCX-plateW*0.5; local cut=Clamp(plateH*0.24,6,16)
        local pts={{plateX+cut,plateY},{plateX+plateW-cut,plateY},{plateX+plateW,plateY+cut},{plateX+plateW,plateY+plateH-cut},{plateX+plateW-cut,plateY+plateH},{plateX+cut,plateY+plateH},{plateX,plateY+plateH-cut},{plateX,plateY+cut}}
        SetRect(data.PlateBGCore,plateX+cut,plateY,math.max(1,plateW-cut*2),plateH); SetRect(data.PlateBGMid,plateX,plateY+cut,plateW,math.max(1,plateH-cut*2))
        local textPad=math.max(6.0,cut*0.60); SetRect(data.TitleText,plateX+textPad,plateY+2,plateW-textPad*2,plateH-4); SetFontSize(data.TitleText.Widget,nameFont)
        for i=1,8 do local a=pts[i]; local b=pts[(i%8)+1]; SetLine(data.PlateLines[i],a[1],a[2],b[1],b[2],Clamp(3.1*s,1.2,2.8)) end
        local statusX=plateCX-statusW*0.5
        for i=1,4 do local bx=statusX+(i-1)*(q+gap); SetRect(data.StatusOuter[i],bx,statusY,q,q); local inset=math.max(2,q*0.14); SetRect(data.StatusInner[i],bx+inset,statusY+inset,q-inset*2,q-inset*2) end
        data.LastScale=s; data._VisName=nil; data._VisBracket=nil; data._VisHealth=nil
    end

    local function UpdateHealthSegments(data, pct, isAI)
        if not data then return end
        local themeColor=isAI and COLORS.YellowBright or COLORS.BloodRedBright; local progress=math.max(0,math.min(1,pct or 0))*4.0
        for i=1,4 do local c; if progress>=i then c=themeColor elseif progress>(i-1) then c=COLORS.White else c=COLORS.Gray end; SetBorderColor(data.StatusInner[i],c) end
    end

    function ClearVisionV2.RemoveEnemy(key)
        local data = ClearVisionV2.EnemyWidgets[key]
        if data then if data.Root then DestroyWidget(data.Root) end; if data.SnapLine and data.SnapLine.Widget then DestroyWidget(data.SnapLine.Widget) end; if data.DistanceText and data.DistanceText.Widget then DestroyWidget(data.DistanceText.Widget) end; if data.DistanceTextBack and data.DistanceTextBack.Widget then DestroyWidget(data.DistanceTextBack.Widget) end end
        ClearVisionV2.EnemyWidgets[key]=nil; ClearVisionV2.EnemyCache[key]=nil; ClearVisionV2.EnemyMeta[key]=nil; ClearVisionV2._ProjectionCache[key]=nil
    end

    local function CreateCounterOverlay()
        if ClearVisionV2.Counter and IsValid(ClearVisionV2.Counter.Root) then return ClearVisionV2.Counter end
        if not ClearVisionV2.InitCanvas(false) then return nil end
        local parent=ClearVisionV2.ESPCanvas
        if not IsValid(parent) then return nil end
        local root=NewWidget("/Script/UMG.CanvasPanel",parent)
        if not root then return nil end
        local slot=AddChild(parent,root,60)
        if not slot then DestroyWidget(root); return nil end
        local c={Root=root,Slot=slot}
        c.PlayerText=CreateText(root,"PLAYER: 0",COLORS.White,20,8); c.BotText=CreateText(root,"BOT: 0",COLORS.BotRedText,20,8)
        ClearVisionV2.Counter=c; return c
    end

    local function UpdateCounterOverlay(pc)
        local c=CreateCounterOverlay(); if not c then return end
        local viewW,viewH=GetViewportSize(pc); local screenW=Clamp(viewW*0.248,208,420); local screenH=Clamp(screenW*0.105,24,42); local top=Clamp(viewH*0.026,10,30)
        local topLeft=ScreenToCanvas({X=(viewW-screenW)*0.5,Y=top}); local bottomRight=ScreenToCanvas({X=(viewW+screenW)*0.5,Y=top+screenH})
        local w=bottomRight.X-topLeft.X; local h=bottomRight.Y-topLeft.Y; if w<=0 or h<=0 then return end
        pcall(function() c.Slot:SetPosition(V2(topLeft.X,topLeft.Y)); c.Slot:SetSize(V2(w,h)) end)
        local font=Clamp(h*0.42,10,19); SetFontSize(c.PlayerText.Widget,font); SetFontSize(c.BotText.Widget,font)
        SetTextValue(c.PlayerText,"PLAYER: "..tostring(ClearVisionV2.RealEnemyCount or 0)); SetTextValue(c.BotText,"BOT: "..tostring(ClearVisionV2.BotEnemyCount or 0))
    end

    local function AppendPawnCollection(out, seen, collection)
        if collection==nil then return end
        pcall(function() for _,pawn in pairs(collection) do if IsValid(pawn) and not seen[pawn] then seen[pawn]=true; out[#out+1]=pawn end end end)
    end

    local function CollectPlayerPawns()
        local out,seen={},{}; pcall(function() if GameplayData and GameplayData.GetAllPlayerCharacters then AppendPawnCollection(out,seen,GameplayData.GetAllPlayerCharacters()) end end); return out
    end

    function ClearVisionV2.RefreshEnemies()
        if not ClearVisionV2.Active then return false end
        local pc = GetController(); local me = GetLocalPawn(pc)
        if not IsValid(pc) or not IsValid(me) then return false end
        local myTeam = GetTeamID(me); local myLoc = GetActorLocation(me)
        if not myLoc then return false end
        local pawns=CollectPlayerPawns(); local candidates = {}; local seen = {}
        pcall(function()
            for _,pawn in pairs(pawns) do
                if IsValid(pawn) and pawn ~= me and IsAlive(pawn) then
                    local team=GetTeamID(pawn)
                    if team~=myTeam then
                        local loc = GetActorLocation(pawn); local d = DistanceMeters(myLoc,loc)
                        if d <= ClearVisionV2.RangeMeters then local key = tostring(GetPlayerKey(pawn) or pawn)
                            if not seen[key] then seen[key]=true; local name,resolved=GetPlayerName(pawn); local bot=IsAI(pawn); candidates[#candidates+1]={Key=key,Pawn=pawn,Distance=d,Name=name,NameResolved=resolved,IsAI=bot} end
                        end
                    end
                end
            end
        end)
        table.sort(candidates,function(a,b) return a.Distance < b.Distance end)
        local selected, meta = {}, {}; local realCount, botCount = 0,0; local count = math.min(#candidates,ClearVisionV2.MaxEnemies)
        for i=1,count do local c=candidates[i]; selected[c.Key]=c.Pawn; meta[c.Key]={Name=c.Name,NameResolved=c.NameResolved,IsAI=c.IsAI}; if c.IsAI then botCount=botCount+1 else realCount=realCount+1 end end
        local stale={}; for key in pairs(ClearVisionV2.EnemyCache) do if selected[key]==nil then stale[#stale+1]=key end end; for _,key in ipairs(stale) do ClearVisionV2.RemoveEnemy(key) end
        ClearVisionV2.EnemyCache=selected; ClearVisionV2.EnemyMeta=meta; ClearVisionV2.RealEnemyCount=realCount; ClearVisionV2.BotEnemyCount=botCount
        return true
    end

    local function GetCameraContext(pc)
        if not IsValid(pc) then return nil,nil end
        local camLoc,camYaw=nil,nil; local mgr=pc:GetPlayerCameraManager()
        if IsValid(mgr) then pcall(function() camLoc=mgr:GetCameraLocation() end); pcall(function() local r=mgr:GetCameraRotation(); if r then camYaw=math.rad(r.Yaw) end end) end
        if not camLoc then camLoc=GetActorLocation(GetLocalPawn(pc)) end
        return camLoc,camYaw
    end

    local function CanvasBounds(viewW,viewH) local a=ScreenToCanvas({X=0,Y=0}); local b=ScreenToCanvas({X=viewW,Y=viewH}); return math.min(a.X,b.X),math.max(a.X,b.X),math.min(a.Y,b.Y),math.max(a.Y,b.Y) end

    function ClearVisionV2.Update()
        if not CV2Flag("EspV2Enabled", false) then if ClearVisionV2.Active then ClearVisionV2.Stop() end; return false end
        if not ClearVisionV2.Active then return false end; if not ClearVisionV2.InitCanvas(false) then return false end
        local pc=GetController(); local me=GetLocalPawn(pc); if not IsValid(pc) or not IsValid(me) then return false end
        ClearVisionV2._FrameSerial=(ClearVisionV2._FrameSerial or 0)+1
        if ClearVisionV2.Counter and ClearVisionV2.Counter.Root then UpdateCounterOverlay(pc); SetVisible(ClearVisionV2.Counter.Root, CV2Flag("EspV2Counter", true)) end
        local myLoc=GetActorLocation(me); if not myLoc then return false end
        local viewW,viewH=GetViewportSize(pc); local topOrigin=ScreenToCanvas({X=viewW*0.5,Y=0}); local frameBounds={CanvasBounds(viewW,viewH)}; local camLoc,camYaw=GetCameraContext(pc)
        for key,character in pairs(ClearVisionV2.EnemyCache) do
            if not IsValid(character) or not IsAlive(character) then ClearVisionV2.RemoveEnemy(key)
            else
                local headLoc,feetLoc=GetCharacterBounds(character); local data=ClearVisionV2.EnemyWidgets[key]
                if not data then data=CreateEnemyWidget(key) end
                if data and headLoc and feetLoc then
                    local meta=ClearVisionV2.EnemyMeta[key] or {}; local isAI=meta.IsAI==true
                    if data.LastThemeAI~=isAI then ApplyEnemyTheme(data,isAI) end
                    local proj=ClearVisionV2._ProjectionCache[key]; if not proj then proj={Head={},Feet={}} ClearVisionV2._ProjectionCache[key]=proj end
                    local headOK,head=ProjectToCanvas(pc,headLoc,proj.Head); local feetOK,feet=ProjectToCanvas(pc,feetLoc,proj.Feet)
                    local onScreen=headOK and feetOK and head and feet and feet.Y>head.Y
                    local distance=DistanceMeters(myLoc,headLoc); local rounded=math.max(0,math.floor(distance+0.5))
                    if data.LastDistanceRounded ~= rounded then data.LastDistanceRounded=rounded; data.LastDistanceText=tostring(rounded).."m" end
                    if onScreen then
                        local s=(feet.Y-head.Y)/REF_BODY_SPAN; local centerX=(head.X+feet.X)*0.5; local rootX=centerX-(REF_W*s*0.5); local rootY=feet.Y-(REF_BODY_BOTTOM*s)
                        local name=meta.Name or "ENEMY"
                        if not data.LastScale or math.abs(data.LastScale-s)>0.003 or data.LastName~=name then LayoutEnemy(data,s,name); data.LastName=name; ApplyEnemyTheme(data,isAI) end
                        if not data.LastX or math.abs(data.LastX-rootX)>0.2 or not data.LastY or math.abs(data.LastY-rootY)>0.2 then pcall(function() data.RootSlot:SetPosition(V2(rootX,rootY)) end); data.LastX,data.LastY=rootX,rootY end
                        if data.LastRenderedName~=name then SetTextValue(data.TitleText,name); data.LastRenderedName=name end
                        ApplyV2FeatureVisibility(data)
                        local health=GetHealthPercent(character); if data.LastHealth==nil or math.abs(data.LastHealth-health)>0.01 or data.LastHealthAI~=isAI then UpdateHealthSegments(data,health,isAI); data.LastHealth=health; data.LastHealthAI=isAI end
                        if data.SnapLine and topOrigin and CV2Flag("EspV2SnapLine", true) then SetLine(data.SnapLine,topOrigin.X,topOrigin.Y,head.X,head.Y,1.5); SetSnapVisible(data,true) else SetSnapVisible(data,false) end
                        local distFont=Clamp(60*s,13,42); local distGap=Clamp(16*s,8,16); local distanceTextColor=isAI and COLORS.BotRedText or COLORS.White
                        if CV2Flag("EspV2Distance", true) then
                            local text=data.LastDistanceText or "--m"; local width=Clamp(#text*distFont*0.72+12,46,180); local height=Clamp(distFont*1.35,24,58)
                            SetRect(data.DistanceTextBack,feet.X-width*0.5+1.0,feet.Y+distGap+distFont*0.58-height*0.5+1.0,width,height); SetRect(data.DistanceText,feet.X-width*0.5,feet.Y+distGap+distFont*0.58-height*0.5,width,height)
                            SetFontSize(data.DistanceText.Widget,distFont); SetTextValue(data.DistanceText,text); SetDistanceVisible(data,true)
                        else SetDistanceVisible(data,false) end
                        SetRootVisible(data,true)
                    else SetRootVisible(data,false); SetSnapVisible(data,false); SetDistanceVisible(data,false) end
                elseif data then SetRootVisible(data,false); SetSnapVisible(data,false); SetDistanceVisible(data,false) end
            end
        end
        return true
    end

    function ClearVisionV2.RemoveTimers()
        local owner = ClearVisionV2.TimerOwner; if IsValid(owner) then if ClearVisionV2.ScanTimer then pcall(function() owner:RemoveGameTimer(ClearVisionV2.ScanTimer) end) end; if ClearVisionV2.DrawTimer then pcall(function() owner:RemoveGameTimer(ClearVisionV2.DrawTimer) end) end end
        ClearVisionV2.ScanTimer=nil; ClearVisionV2.DrawTimer=nil; ClearVisionV2.TimerOwner=nil
    end

    function ClearVisionV2.Stop()
        ClearVisionV2.Active=false; ClearVisionV2.RemoveTimers()
        for key,data in pairs(ClearVisionV2.EnemyWidgets) do ClearVisionV2.RemoveEnemy(key) end
        if ClearVisionV2.Counter and ClearVisionV2.Counter.Root then DestroyWidget(ClearVisionV2.Counter.Root) end
        ClearVisionV2.Counter=nil; ClearVisionV2.EnemyCache={}; ClearVisionV2.EnemyMeta={}; ClearVisionV2._ProjectionCache={}; ClearVisionV2.Controller=nil; ClearVisionV2.LocalPawn=nil; ClearVisionV2.ESPCanvas=nil; return true
    end

    function ClearVisionV2.Start()
        if not CV2Flag("EspV2Enabled", false) then return false end
        if ClearVisionV2.Active then return true end
        local pc=ResolveControllerFresh() or GetController(); local me=ResolveLocalPawnFresh(pc) or GetLocalPawn(pc)
        if not IsValid(pc) or not IsValid(me) then return false end
        ClearVisionV2.Controller=pc; ClearVisionV2.LocalPawn=me; ClearVisionV2.ESPCanvas=nil
        if not ClearVisionV2.InitCanvas(true) then return false end
        ClearVisionV2.RemoveTimers(); ClearVisionV2.Active=true; ClearVisionV2.TimerOwner=pc
        pcall(ClearVisionV2.RefreshEnemies); pcall(ClearVisionV2.Update)
        local ok1,t1=pcall(function() return pc:AddGameTimer(1.0,true,function() if ClearVisionV2.Active then pcall(ClearVisionV2.RefreshEnemies) end end) end)
        local ok2,t2=pcall(function() return pc:AddGameTimer(0.0167,true,function() if ClearVisionV2.Active then pcall(ClearVisionV2.Update) end end) end)
        if ok1 and t1 then ClearVisionV2.ScanTimer=t1 end; if ok2 and t2 then ClearVisionV2.DrawTimer=t2 end
        if not ClearVisionV2.ScanTimer or not ClearVisionV2.DrawTimer then ClearVisionV2.Stop(); return false end
        return true
    end

    function ClearVisionV2.SyncEnabled()
        if not CV2Flag("EspV2Enabled", false) then if ClearVisionV2.Active then ClearVisionV2.Stop() end; return true end
        if not ClearVisionV2.Active then return ClearVisionV2.Start() end
        return true
    end

    _G.ClearVisionV2Runtime = ClearVisionV2
    _G.ClearVisionV2Start = function() return ClearVisionV2.Start() end
    _G.ClearVisionV2Stop = function() return ClearVisionV2.Stop() end
    _G.ClearVisionV2Sync = function() return ClearVisionV2.SyncEnabled() end
    _G.ClearVisionV2Update = function() return ClearVisionV2.Update() end
end)

local limitTime = os.time({ year = 2026, month = 12, day = 4, hour = 23, min = 59, sec = 0 })
local currentTime = os.time(os.date("!*t"))
local isExpired = (currentTime > limitTime)

F = {}
DEBUG = false
function F.log(...) if DEBUG then print("[AddOutfit]", ...) end end
_avatarItemsRegistered = false
MATCH_CONFIG = { outfitRes=0, hatRes=0, maskRes=0, glassRes=0, tshirtRes=0, pantsRes=0, shoesRes=0, bagRes=0, helmetRes=0, weaponSkins={} }
ITEMS = {}
INS_BASE = 2000000000; PKG_SLOT = 3; MELEE_ID = 108; HAT_SUB = 401; MASK_SUB = 402; OUTFIT_SUB = 403; PANTS_SUB = 404; SHOES_SUB = 405; GLASS_SUB = 407; GLOVES_SUB = 452
GLIDER_SUBS = { [413]=true, [414]=true, [415]=true }
F.CUST_SLOT = { NONE=0, HeadEquipemtSlot=1, HairEquipemtSlot=2, HatEquipemtSlot=3, FaceEquipemtSlot=4, ClothesEquipemtSlot=5, PantsEquipemtSlot=6, ShoesEquipemtSlot=7, BackpackEquipemtSlot=8, HelmetEquipemtSlot=9, ArmorEquipemtSlot=10, ParachuteEquipemtSlot=11, GlassEquipemtSlot=12, NightVisionEquipemtSlot=13, BeardEquipemtSlot=14, GlideEquipemtSlot=15, HandEffectEquipemtSlot=16, BackPack_PendantSlot=17 }
_G.CustSlotType = F.CUST_SLOT
TAB_CLOTHES = 3; PAGE_AVATAR = 1; PAGE_VEHICLE = 6; PAGE_PARACHUTE = 5; TAB_SUIT = 10; PARACHUTE_SUB = 701
local HAT_SUBS = { [401]=true }; local HELMET_SUBS = { [502]=true, [505]=true }; local HEAD_SUBS = { [401]=true }; local BAG_SUBS = { [501]=true, [504]=true }; local FACE_SUBS = { [402]=true, [407]=true }; local BODY_SUBS = { [404]=true, [405]=true, [501]=true, [504]=true, [502]=true, [505]=true }
GUN_SUB = { [101]=true, [102]=true, [103]=true, [104]=true, [105]=true, [106]=true, [107]=true }
NET_OK = NetErrorCode_NONE or "ok"
R = { insToRes={}, resToIns={}, byWeapon={} }
_G.AddOutfitPersist = _G.AddOutfitPersist or { path=nil, dirty=false, scheduled=false, loaded=nil, lastWritten=nil, configVehicleSlots=nil, configWeapons=nil, configSlots=nil }
PERSIST = _G.AddOutfitPersist
PERF = { lobbySynced=false, mappingsDirty=true, desiredSkins=nil, skinTarget={}, matchActive=false, lastBootstrapAt=0, wearDoneThisMatch=false }
MATCH_TICK_SEC = 4.0; MATCH_MAX_SEC = 45.0; BOOTSTRAP_COOLDOWN = 2.0; INJECT_RETRY_MAX = 5; INJECT_RETRY_SEC = 3.0

function F.cache() _G.AddOutfitEquippedCache = _G.AddOutfitEquippedCache or { outfitRes=nil, hatRes=nil, maskRes=nil, glassRes=nil, tshirtRes=nil, pantsRes=nil, shoesRes=nil, bagRes=nil, helmetRes=nil, weapons={}, parachuteRes=nil, gliderRes=nil, glovesRes=nil }; return _G.AddOutfitEquippedCache end
function F.cfg(resID) if not resID or not CDataTable or not CDataTable.GetTableData then return nil end; return CDataTable.GetTableData("Item", resID) end
function F.subType(c) return c and (c.ItemSubType or c.itemSubType) or nil end
function F.wardrobeTab(resID) local c = F.cfg(resID); return c and tonumber(c.WardrobeTab) or 0 end
function F.isSuitRes(resID) if F.subType(F.cfg(resID)) ~= OUTFIT_SUB then return false end; return F.wardrobeTab(resID) ~= TAB_CLOTHES end
function F.isTshirtRes(resID) return F.subType(F.cfg(resID)) == OUTFIT_SUB and F.wardrobeTab(resID) == TAB_CLOTHES end
function F.weaponIdFromSkin(resID) local m = CDataTable and CDataTable.GetTableData and CDataTable.GetTableData("WeaponSkinMapping", resID); if not m then return nil end; return m.WeaponID or m.WeaponId end
function F.isWeaponSkinRes(resID) resID = tonumber(resID); if not resID then return false end; local st = F.subType(F.cfg(resID)); return GUN_SUB[st] or st == MELEE_ID end
function F.isWeaponSkinIns(insID) insID = tonumber(insID); if not insID then return false end; local res = R.insToRes[insID]; return res and F.isWeaponSkinRes(res) end
function F.isInjectedIns(ins) return ins and R.insToRes[tonumber(ins)] ~= nil end
function F.isInjectedRes(res) return res and R.resToIns[tonumber(res)] ~= nil end
function F.indexWeaponSkin(resID, insID) resID, insID = tonumber(resID), tonumber(insID); if not resID or not insID then return end; local c = F.cfg(resID); local st = F.subType(c); if not (GUN_SUB[st] or st == MELEE_ID) then return end; local wid = F.weaponIdFromSkin(resID); wid = tonumber(wid); if not wid or wid <= 0 then return end; R.byWeapon[wid] = R.byWeapon[wid] or {}; R.byWeapon[wid][resID] = insID end

_G._SkinZoneInitWeaponSystem = function()
pcall(function()
_G.WeaponSkinID = _G.WeaponSkinID or {}
_G.WeaponIDSets = { M416 = {[101004]=true, [1010041]=true, [1010042]=true, [1010043]=true, [1010044]=true, [1010045]=true, [1010046]=true, [1010047]=true, [1010049]=true}, AKM = {[101001]=true, [1010011]=true, [1010012]=true, [1010013]=true, [1010014]=true, [1010015]=true, [1010016]=true, [1010017]=true, [1010019]=true}, SCAR = {[101003]=true, [1010031]=true, [1010032]=true, [1010033]=true, [1010034]=true, [1010035]=true, [1010036]=true, [1010037]=true, [1010039]=true}, M762 = {[101008]=true, [1010081]=true, [1010082]=true, [1010083]=true, [1010084]=true, [1010085]=true, [1010086]=true, [1010087]=true, [1010089]=true}, GROZA = {[101005]=true, [1010051]=true, [1010052]=true, [1010053]=true, [1010054]=true, [1010055]=true, [1010056]=true, [1010057]=true, [1010059]=true}, AUG = {[101006]=true, [1010061]=true, [1010062]=true, [1010063]=true, [1010064]=true, [1010065]=true, [1010066]=true, [1010067]=true}, QBZ = {[101007]=true, [1010071]=true, [1010072]=true, [1010073]=true, [1010074]=true, [1010075]=true, [1010076]=true, [1010077]=true}, M16A4 = {[101002]=true, [1010021]=true, [1010022]=true, [1010023]=true, [1010024]=true, [1010025]=true}, FAMAS = {[101100]=true, [1011001]=true, [1011002]=true, [1011003]=true, [1011004]=true, [1011005]=true, [1011006]=true, [1011007]=true}, ACE32 = {[101102]=true, [1011021]=true, [1011022]=true, [1011023]=true, [1011024]=true, [1011025]=true, [1011026]=true, [1011027]=true}, ASM = {[101101]=true, [1011011]=true, [1011012]=true, [1011013]=true, [1011014]=true, [1011015]=true, [1011016]=true, [1011017]=true}, Mk47 = {[101009]=true, [1010091]=true, [1010092]=true, [1010093]=true, [1010094]=true, [1010095]=true, [1010096]=true, [1010097]=true, [1010099]=true}, G36C = {[101010]=true, [1010101]=true, [1010102]=true, [1010103]=true, [1010104]=true, [1010105]=true, [1010106]=true, [1010107]=true, [1010109]=true}, HoneyPot = {[101012]=true, [1010121]=true, [1010122]=true, [1010123]=true, [1010124]=true, [1010125]=true, [1010126]=true, [1010127]=true, [1010129]=true}, UMP = {[102002]=true, [1020021]=true, [1020022]=true, [1020023]=true, [1020024]=true, [1020025]=true, [1020029]=true}, VECTOR = {[102003]=true, [1020031]=true, [1020032]=true, [1020033]=true, [1020034]=true, [1020035]=true, [1020036]=true, [1020037]=true}, UZI = {[102001]=true, [1020011]=true, [1020012]=true, [1020013]=true, [1020014]=true, [1020015]=true}, THOMPSON = {[102004]=true, [1020041]=true, [1020042]=true, [1020043]=true, [1020044]=true, [1020045]=true}, BIZON = {[102005]=true, [1020051]=true, [1020052]=true, [1020053]=true, [1020054]=true, [1020055]=true, [1020059]=true}, P90 = {[102105]=true, [1021051]=true, [1021052]=true, [1021053]=true, [1021054]=true, [1021055]=true, [1021056]=true, [1021057]=true}, MP5K = {[102007]=true, [1020071]=true, [1020072]=true, [1020073]=true, [1020074]=true, [1020075]=true, [1020076]=true, [1020077]=true, [1020079]=true}, JS9 = {[102008]=true, [1020081]=true, [1020082]=true, [1020083]=true, [1020084]=true, [1020085]=true, [1020086]=true, [1020087]=true, [1020089]=true}, AWM = {[103003]=true, [1030031]=true, [1030032]=true, [1030033]=true, [1030034]=true, [1030035]=true, [1030036]=true, [1030037]=true, [1030039]=true}, M24 = {[103002]=true, [1030021]=true, [1030022]=true, [1030023]=true, [1030024]=true, [1030025]=true, [1030026]=true, [1030027]=true}, K98 = {[103001]=true, [1030011]=true, [1030012]=true, [1030013]=true, [1030014]=true, [1030015]=true, [1030019]=true}, MK14 = {[103007]=true, [1030071]=true, [1030072]=true, [1030073]=true, [1030074]=true, [1030075]=true, [1030076]=true, [1030077]=true}, AMR = {[103012]=true, [1030121]=true, [1030122]=true, [1030123]=true, [1030124]=true, [1030125]=true, [1030126]=true, [1030127]=true}, DSR = {[103102]=true, [1031021]=true, [1031022]=true, [1031023]=true, [1031024]=true, [1031025]=true, [1031026]=true, [1031027]=true, [1031029]=true}, SKS = {[103004]=true, [1030041]=true, [1030042]=true, [1030043]=true, [1030044]=true, [1030045]=true, [1030046]=true, [1030047]=true, [1030049]=true}, Mini14 = {[103006]=true, [1030061]=true, [1030062]=true, [1030063]=true, [1030064]=true, [1030065]=true, [1030066]=true, [1030067]=true, [1030069]=true}, VSS = {[103005]=true, [1030051]=true, [1030052]=true, [1030053]=true, [1030054]=true, [1030055]=true, [1030056]=true, [1030057]=true, [1030059]=true}, Win94 = {[103008]=true, [1030081]=true, [1030082]=true, [1030083]=true, [1030084]=true, [1030085]=true, [1030086]=true, [1030087]=true, [1030089]=true}, M1Garand = {[103103]=true}, SLR = {[103009]=true, [1030091]=true, [1030092]=true, [1030093]=true, [1030094]=true, [1030095]=true, [1030096]=true, [1030097]=true, [1030099]=true}, QBU = {[103010]=true, [1030101]=true, [1030102]=true, [1030103]=true, [1030104]=true, [1030105]=true, [1030106]=true, [1030107]=true, [1030109]=true}, Mosin = {[103011]=true, [1030111]=true, [1030112]=true, [1030113]=true, [1030114]=true, [1030115]=true, [1030116]=true, [1030117]=true, [1030119]=true}, Mk12 = {[103100]=true, [1031001]=true, [1031002]=true, [1031003]=true, [1031004]=true, [1031005]=true, [1031006]=true, [1031007]=true, [1031009]=true}, S686 = {[104001]=true, [1040011]=true, [1040012]=true, [1040013]=true, [1040014]=true, [1040015]=true, [1040016]=true, [1040017]=true, [1040019]=true}, S1897 = {[104002]=true, [1040021]=true, [1040022]=true, [1040023]=true, [1040024]=true, [1040025]=true, [1040026]=true, [1040027]=true, [1040029]=true}, S12K = {[104003]=true, [1040031]=true, [1040032]=true, [1040033]=true, [1040034]=true, [1040035]=true, [1040036]=true, [1040037]=true, [1040039]=true}, DBS = {[104004]=true, [1040041]=true, [1040042]=true, [1040043]=true, [1040044]=true, [1040045]=true, [1040046]=true, [1040047]=true, [1040049]=true}, M1014 = {[104101]=true, [1041011]=true, [1041012]=true, [1041013]=true, [1041014]=true, [1041015]=true, [1041016]=true, [1041017]=true, [1041019]=true}, NS2000 = {[104102]=true, [1041021]=true, [1041022]=true, [1041023]=true, [1041024]=true, [1041025]=true, [1041026]=true, [1041027]=true, [1041029]=true}, M249 = {[105001]=true, [1050011]=true, [1050012]=true, [1050013]=true, [1050014]=true, [1050015]=true, [1050016]=true, [1050017]=true}, DP28 = {[105002]=true, [1050021]=true, [1050022]=true, [1050023]=true, [1050024]=true, [1050025]=true, [1050026]=true, [1050027]=true, [1050029]=true}, MG3 = {[105010]=true, [1050101]=true, [1050102]=true, [1050103]=true, [1050104]=true, [1050105]=true, [1050106]=true, [1050107]=true, [1050109]=true}, PAN = {[108004]=true, [1080041]=true}, Dagger = {[108005]=true}, Machete = {[108001]=true, [1080011]=true}, GRENADE = {[602004]=true} }
function _G.getBaseWeaponID(wid) if not wid then return nil end; for t, ids in pairs(_G.WeaponIDSets) do if ids[wid] then local m=math.huge; for id in pairs(ids) do if id<m then m=id end end; return m end end; return wid end
_G.apply_attachment = function(w, av) return false end
_G.equip_weapon_avatar = function(c) local wm=c:GetWeaponManager(); if not slua.isValid(wm) then return end; local wl=wm:GetAllInventoryWeaponList(false); if not slua.isValid(wl) then return end; for i=0,wl:Num()-1 do local w=wl:Get(i); if slua.isValid(w) then local arr=w.synData; if slua.isValid(arr) then local d=arr:Get(7); if d and slua.isValid(d) then local sid=slua.IndexReference(d,'defineID').TypeSpecificID; if sid and sid>0 then local t=sid; local wid0=0; pcall(function() wid0=w:GetItemDefineID().TypeSpecificID end); if wid0>0 and _G.get_skin_id2 then local t0=_G.get_skin_id2(wid0); if t0 and t0>0 and t0~=wid0 then t=t0 end end; if t>0 and t~=w:GetWeaponID() and sid~=t then pcall(function() d.defineID.TypeSpecificID=t; arr:Set(7,d) end) end end end end end end end
function _G.get_skin_id2(wid) if not wid then return nil end; local base=_G.getBaseWeaponID(wid); if _G.WeaponSkinID and _G.WeaponSkinID[base] and _G.WeaponSkinID[base]~=0 then return _G.WeaponSkinID[base] end; return base end
function _G.GameAvatarHandlerweapons() pcall(function() local pc=slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController(); if not pc then return end; local c=pc:GetPlayerCharacterSafety(); if not c or not slua.isValid(c) then return end; if _G.equip_weapon_avatar then _G.equip_weapon_avatar(c) end; local w=c:GetCurrentWeapon(); if w and slua.isValid(w) then local id=w:GetItemDefineID().TypeSpecificID; local t=_G.get_skin_id2(id); local cur=slua.IndexReference(w.synData:Get(7),"defineID").TypeSpecificID; local base=_G.getBaseWeaponID(id); local arr=w.synData; local fp=tostring(t); for i=0,5 do local d=arr:Get(i); fp=fp..(d and tostring(slua.IndexReference(d,"defineID").TypeSpecificID) or "0").."," end; if not _G._weaponSyncCache then _G._weaponSyncCache={} end; if _G._weaponSyncCache[base]~=fp then if cur~=t then local sd=arr:Get(7); if sd then sd.defineID.TypeSpecificID=t; arr:Set(7,sd) end end; _G._weaponSyncCache[base]=fp; if w.DelayHandleAvatarMeshChanged then w:DelayHandleAvatarMeshChanged() end end end end) end
TXtime_ticker = nil; pcall(function() TXtime_ticker = require("common.time_ticker") end)
if TXtime_ticker then _G.Mytimer_ticker = TXtime_ticker; if _G.weaponAvatarTimerIndex and TXtime_ticker.IsRunning(_G.weaponAvatarTimerIndex) then TXtime_ticker.RemoveTimer(_G.weaponAvatarTimerIndex) end; _G.weaponAvatarTimerIndex = TXtime_ticker.AddTimerLoop(0, function() if _G.GameAvatarHandlerweapons then pcall(_G.GameAvatarHandlerweapons) end end, -1, 0.5) end
_G.SkinZoneGuns = { { key="M416", name="M416", wid=101004, ids={1101004046, 1101004062, 1101004078, 1101004086, 1101004098, 1101004138, 1101004163}, names={"Glacier-M416", "Joker-M416", "Exotic-M416", "Roaring-M416", "Call-M416", "Tech-M416", "Tidal-M416"} }, { key="AKM", name="AKM", wid=101001, ids={1101001042, 1101001063, 1101001068, 1101001089, 1101001103}, names={"Ornate-AKM", "Raging-AKM", "White-AKM", "Frost-AKM", "Block-AKM"} }, { key="M762", name="M762", wid=101008, ids={1101008163, 1101008154, 1101008146, 1101008136}, names={"Spirit-M762", "Platinum-M762", "Pale-M762", "Glaze-M762"} } }
_G.SkinZoneSuits = { { id=1408045, name="Frost X-Suit" }, { id=1407995, name="New Arrival" }, { id=1407921, name="Demon Heart" }, { id=1408078, name="Platinum Soul" }, { id=1407917, name="Pollux" }, { id=1407916, name="Castor" } }
_G.SkinZoneHelmets = { { id=1502001014, name="Hell Knight" }, { id=1502001439, name="Auric Reign" }, { id=1502001031, name="Mutated" }, { id=1502001003, name="Cyan Cyberpunk" } }
_G.SkinZoneBags = { { id=1501001024, name="Bat Count" }, { id=1501001726, name="Wrath" }, { id=1501001707, name="Prison" }, { id=1501001672, name="Stellarwing" } }
end)
do local tk=require("common.time_ticker"); if tk and tk.AddTimerOnce then tk.AddTimerOnce(1.0, _G._SkinZoneInitWeaponSystem) else _G._SkinZoneInitWeaponSystem() end end

function F.getAvatarComp2(c) if not c or not slua.isValid(c) then return nil end; local comp; pcall(function() if c.getAvatarComponent2 then comp=c:getAvatarComponent2() end; if (not comp or not slua.isValid(comp)) and c.CharacterAvatarComp2_BP then comp=c.CharacterAvatarComp2_BP end end); return comp end
function F.getLocalChar() local ok, GD = pcall(require, "GameLua.GameCore.Data.GameplayData"); if not ok or not GD then return nil end; local c=GD.GetPlayerCharacter(); if c and slua.isValid(c) then return c end; return nil end
function F.isInRealMatch() local ok, r = pcall(function() return GameStatus and GameStatus.IsInFightingStatus and GameStatus.IsInFightingStatus() end); return ok and r == true end
function F.ensureSkinDownload(resID) resID = tonumber(resID); if not resID or resID <= 0 then return end; _G.skinIdCache = _G.skinIdCache or {}; if not _G.skinIdCache[resID] then F.requestResourceDownload(resID); _G.skinIdCache[resID] = true end end
function F.requestResourceDownload(resID) resID = tonumber(resID); if not resID or resID <= 0 then return end; pcall(function() local PM = require("client.slua.logic.download.puffer.puffer_manager"); local PC = require("client.slua.logic.download.puffer_const"); if PM and PC and PC.ENUM_DownloadType and PC.ENUM_DownloadState then if PM.GetState(PC.ENUM_DownloadType.ODPAK, {resID}) ~= PC.ENUM_DownloadState.Done then PM.Download(PC.ENUM_DownloadType.ODPAK, {resID}) end end end) end
function F.setMakeSkin(comp, resID, slotID, opts) opts = opts or {}; slotID, resID = tonumber(slotID), tonumber(resID); if not comp or not slua.isValid(comp) or not slotID or not resID or resID <= 0 then return false end; local changed = false; local already = false; pcall(function() local net = comp.NetAvatarData; if not net then return end; local applyData = net.SlotSyncData; if not applyData or not slua.isValid(applyData) then return end; local num = applyData:Num(); for i = 0, num - 1 do local equipment = applyData:Get(i); if equipment and equipment.SlotID == slotID then local cur = tonumber(equipment.ItemId) or tonumber(equipment.ItemID) or 0; if cur == resID then already = true elseif cur ~= resID then F.ensureSkinDownload(resID); equipment.ItemId = resID; if equipment.ItemID ~= nil then equipment.ItemID = resID end; applyData:Set(i, equipment); changed = true end; break end end; if changed and not opts.skipRep and comp.OnRep_BodySlotStateChanged then comp:OnRep_BodySlotStateChanged() end; if opts.inAir and comp.PutOnCustomEquipmentByID then comp:PutOnCustomEquipmentByID(resID) end end); if already or changed then return true end; if opts.allowPutOn and comp.PutOnCustomEquipmentByID then pcall(function() comp:PutOnCustomEquipmentByID(resID) end); return true end; return false end
F.setSlotSkin = F.setMakeSkin
function F.applySlotSkinBatch(comp, entries, opts) opts = opts or {}; if not comp or not slua.isValid(comp) or not entries then return false end; local changed, anyOk = false, false; pcall(function() local net = comp.NetAvatarData; if not net then return end; local applyData = net.SlotSyncData; if not applyData or not slua.isValid(applyData) then return end; local num = applyData:Num(); for _, e in ipairs(entries) do local itemId, slotId = tonumber(e[1]), tonumber(e[2]); if itemId and itemId > 0 and slotId then F.ensureSkinDownload(itemId); for i = 0, num - 1 do local equipment = applyData:Get(i); if equipment and equipment.SlotID == slotId then local cur = tonumber(equipment.ItemId) or tonumber(equipment.ItemID) or 0; if cur == itemId then anyOk = true elseif cur ~= itemId then equipment.ItemId = itemId; if equipment.ItemID ~= nil then equipment.ItemID = itemId end; applyData:Set(i, equipment); changed = true; anyOk = true end; break end end end end; if (changed or opts.forceRep) and comp.OnRep_BodySlotStateChanged then comp:OnRep_BodySlotStateChanged() end end); return anyOk or changed end
function F.getDesiredWear(configKey, cacheResKey, globalKey, syncFn) local fixed = MATCH_CONFIG[configKey] and tonumber(MATCH_CONFIG[configKey]); if fixed and fixed > 0 then return fixed end; if PERSIST.configSlots then local persistKey = cacheResKey and cacheResKey:gsub("Res$", ""); if persistKey then local pr = tonumber(PERSIST.configSlots[persistKey]); if pr and pr > 0 then return pr end end end; if syncFn then syncFn() end; local v = F.cache()[cacheResKey]; if v and tonumber(v) > 0 then return tonumber(v) end; return tonumber(_G[globalKey]) or nil end
function F.getDesiredOutfit() if MATCH_CONFIG.outfitRes and MATCH_CONFIG.outfitRes > 0 then return MATCH_CONFIG.outfitRes end; local wornSuitRes; pcall(function() local _, res = F.findWornInsBySubType(OUTFIT_SUB, function(r) return F.isSuitRes(r) end); wornSuitRes = tonumber(res) end); if wornSuitRes and wornSuitRes > 0 then return wornSuitRes end; local tshirtWorn = false; pcall(function() local ins = F.findWornInsBySubType(OUTFIT_SUB, function(r) return F.isTshirtRes(r) end); tshirtWorn = ins ~= nil end); if tshirtWorn then return nil end; F.syncBodyCacheFromLobby(); local c = F.cache(); return c.outfitRes end
function F.getDesiredHat() if MATCH_CONFIG.hatRes and tonumber(MATCH_CONFIG.hatRes) > 0 then return tonumber(MATCH_CONFIG.hatRes) end; F.syncHatCacheFromLobby(); local h = F.cache().hatRes; if h and tonumber(h) > 0 then return tonumber(h) end; return tonumber(_G.AddOutfitLastLobbyHatRes) or nil end
function F.getDesiredMask() if MATCH_CONFIG.maskRes and tonumber(MATCH_CONFIG.maskRes) > 0 then return tonumber(MATCH_CONFIG.maskRes) end; F.syncFaceCacheFromLobby(); local m = F.cache().maskRes; if m and tonumber(m) > 0 then return tonumber(m) end; return tonumber(_G.AddOutfitLastLobbyMaskRes) or nil end
function F.getDesiredGlass() if MATCH_CONFIG.glassRes and tonumber(MATCH_CONFIG.glassRes) > 0 then return tonumber(MATCH_CONFIG.glassRes) end; F.syncFaceCacheFromLobby(); local g = F.cache().glassRes; if g and tonumber(g) > 0 then return tonumber(g) end; return tonumber(_G.AddOutfitLastLobbyGlassRes) or nil end
function F.getDesiredParachuteRes() F.applyPersistSlotsToCache(); local r = tonumber(PERSIST.configSlots and PERSIST.configSlots.parachute); if r and r > 0 then return r end; return F.getDesiredWear("parachuteRes", "parachuteRes", "AddOutfitLastLobbyParachuteRes") end
function F.getDesiredGliderRes() F.applyPersistSlotsToCache(); local r = tonumber(PERSIST.configSlots and PERSIST.configSlots.glider); if r and r > 0 then return r end; return F.getDesiredWear("gliderRes", "gliderRes", "AddOutfitLastLobbyGliderRes") end
function F.findWornInsBySubType(st, filterFn) st = tonumber(st); if not st then return nil end; local wd = require("client.slua.logic.wardrobe.wardrobe_data"); local AvatarData = require("client.logic.data.AvatarData"); for _, ins in pairs(AvatarData.GetRoleWear()) do ins = tonumber(ins); if ins and ins > 0 then local d = wd:GetHallDepotItemDataByInsID(ins); if d and tonumber(d.itemSubType) == st then local res = tonumber(d.resID); if not filterFn or filterFn(res, d) then return ins, res end end end end; return nil end
function F.syncHatCacheFromLobby() local cch = F.cache(); pcall(function() local ins, res = F.findWornInsBySubType(HAT_SUB); if ins and res and tonumber(res) > 0 then cch.hatRes, cch.hatIns = tonumber(res), ins; return end end) end
function F.syncFaceCacheFromLobby() local cch = F.cache(); pcall(function() local ins, res = F.findWornInsBySubType(MASK_SUB); if ins and res and tonumber(res) > 0 then cch.maskRes, cch.maskIns = tonumber(res), ins; _G.AddOutfitLastLobbyMaskRes = tonumber(res) end end); pcall(function() local ins, res = F.findWornInsBySubType(GLASS_SUB); if ins and res and tonumber(res) > 0 then cch.glassRes, cch.glassIns = tonumber(res), ins; _G.AddOutfitLastLobbyGlassRes = tonumber(res) end end) end
function F.syncBodyCacheFromLobby() local cch = F.cache(); pcall(function() local ins, res = F.findWornInsBySubType(OUTFIT_SUB, function(r) return F.wardrobeTab(r) == TAB_CLOTHES end); if ins and res and tonumber(res) > 0 then cch.tshirtRes, cch.tshirtIns = tonumber(res), ins end end); pcall(function() local ins, res = F.findWornInsBySubType(PANTS_SUB); if ins and res and tonumber(res) > 0 then cch.pantsRes, cch.pantsIns = tonumber(res), ins end end); pcall(function() local ins, res = F.findWornInsBySubType(SHOES_SUB); if ins and res and tonumber(res) > 0 then cch.shoesRes, cch.shoesIns = tonumber(res), ins end end); pcall(function() local ins, res = F.findWornInsBySubType(GLOVES_SUB); if ins and res and tonumber(res) > 0 then cch.glovesRes, cch.glovesIns = tonumber(res), ins end end); pcall(function() for st in pairs(BAG_SUBS) do local ins, res = F.findWornInsBySubType(st); if ins and res and tonumber(res) > 0 then cch.bagRes, cch.bagIns = tonumber(res), ins; break end end end); pcall(function() for st in pairs(HELMET_SUBS) do local ins, res = F.findWornInsBySubType(st); if ins and res and tonumber(res) > 0 then cch.helmetRes, cch.helmetIns = tonumber(res), ins; break end end end); pcall(function() local ins, res = F.findWornInsBySubType(OUTFIT_SUB, function(r) return F.isSuitRes(r) end); if ins and res and tonumber(res) > 0 then cch.outfitRes, cch.outfitIns = tonumber(res), ins end end) end
function F.syncWeaponCacheFromLobby(force) if LOBBY.lobbySynced and not force then return end; LOBBY.lobbySynced = true; PERF.mappingsDirty = true; PERF.desiredSkins = nil; for k in pairs(PERF.skinTarget) do PERF.skinTarget[k] = nil end; F.syncHatCacheFromLobby(); F.syncFaceCacheFromLobby(); F.syncBodyCacheFromLobby() end
function F.applyPersistSlotsToCache() if not PERSIST.configSlots then return end; local cch = F.cache(); local PERSIST_SLOTS = { { "outfit", "outfitRes", "outfitIns", "AddOutfitLastLobbyOutfitRes" }, { "tshirt", "tshirtRes", "tshirtIns", "AddOutfitLastLobbyTshirtRes" }, { "pants", "pantsRes", "pantsIns", "AddOutfitLastLobbyPantsRes" }, { "shoes", "shoesRes", "shoesIns", "AddOutfitLastLobbyShoesRes" }, { "hat", "hatRes", "hatIns", "AddOutfitLastLobbyHatRes" }, { "mask", "maskRes", "maskIns", "AddOutfitLastLobbyMaskRes" }, { "glass", "glassRes", "glassIns", "AddOutfitLastLobbyGlassRes" }, { "bag", "bagRes", "bagIns", "AddOutfitLastLobbyBagRes" }, { "helmet", "helmetRes", "helmetIns", "AddOutfitLastLobbyHelmetRes" }, { "parachute", "parachuteRes", "parachuteIns", "AddOutfitLastLobbyParachuteRes" }, { "glider", "gliderRes", "gliderIns", "AddOutfitLastLobbyGliderRes" }, { "gloves", "glovesRes", "glovesIns", "AddOutfitLastLobbyGlovesRes" } }; for _, s in ipairs(PERSIST_SLOTS) do local slotName, cacheResKey, cacheInsKey, globalKey = s[1], s[2], s[3], s[4]; local res = tonumber(PERSIST.configSlots[slotName]); if res and res > 0 then cch[cacheResKey] = res; _G[globalKey] = res end end end
function F.matchApplyWearItem(char, resID, slotID, label, opts) if not resID or resID <= 0 then return true end; slotID = slotID or F.resToCustSlot(resID); if not slotID then return false end; local comp = F.getAvatarComp2(char); if not comp then return false end; opts = opts or {}; opts.allowPutOn = true; local ok = F.setMakeSkin(comp, resID, slotID, opts); return ok end
function F.resToCustSlot(resID, st) resID, st = tonumber(resID), tonumber(st); if not resID or resID <= 0 then return nil end; st = st or F.subType(F.cfg(resID)); if st == HAT_SUB or HAT_SUBS[st] then return F.CUST_SLOT.HatEquipemtSlot end; if st == OUTFIT_SUB then return F.CUST_SLOT.ClothesEquipemtSlot end; if st == PANTS_SUB then return F.CUST_SLOT.PantsEquipemtSlot end; if st == SHOES_SUB then return F.CUST_SLOT.ShoesEquipemtSlot end; if st == MASK_SUB then return F.CUST_SLOT.FaceEquipemtSlot end; if st == GLASS_SUB then return F.CUST_SLOT.GlassEquipemtSlot end; if st == GLOVES_SUB then return F.CUST_SLOT.HandEffectEquipemtSlot end; if BAG_SUBS[st] then return F.CUST_SLOT.BackpackEquipemtSlot end; if HELMET_SUBS[st] then return F.CUST_SLOT.HelmetEquipemtSlot end; if st == PARACHUTE_SUB then return F.CUST_SLOT.ParachuteEquipemtSlot end; if GLIDER_SUBS[st] then return F.CUST_SLOT.GlideEquipemtSlot end; return nil end
function F.matchApplyOutfit(char) local outfitRes = F.getDesiredOutfit(); if not outfitRes then return true end; if not F.isResourcesReady(outfitRes) then F.requestResourceDownload(outfitRes); return false end; local comp = F.getAvatarComp2(char); if not comp then return false end; local ok = F.setMakeSkin(comp, outfitRes, F.CUST_SLOT.ClothesEquipemtSlot, { allowPutOn = true }); return ok end
function F.isResourcesReady(resID) resID = tonumber(resID); if not resID or resID <= 0 then return false end; return true end
function F.matchApplyHat(char) local hatRes = tonumber(F.getDesiredHat()); if not hatRes or hatRes <= 0 then return true end; char = char or F.getLocalChar(); if not char then return false end; local comp = F.getAvatarComp2(char); if not comp then return false end; local slotID = F.CUST_SLOT.HatEquipemtSlot; local ok = false; pcall(function() local net = comp.NetAvatarData; if not net then return end; local applyData = net.SlotSyncData; if not applyData or not slua.isValid(applyData) then return end; local found = false; for i = 0, applyData:Num() - 1 do local equipment = applyData:Get(i); if equipment and equipment.SlotID == slotID then found = true; local cur = tonumber(equipment.ItemId) or tonumber(equipment.ItemID) or 0; if cur ~= hatRes then F.ensureSkinDownload(hatRes); equipment.ItemId = hatRes; if equipment.ItemID ~= nil then equipment.ItemID = hatRes end; if equipment.FakeItemID ~= nil then equipment.FakeItemID = hatRes end; applyData:Set(i, equipment) end; ok = true; break end end; if not found then F.ensureSkinDownload(hatRes); local ESyncOperation = import("ESyncOperation"); local entry = import("AvatarSyncData")(); entry.SlotID = slotID; entry.ItemId = hatRes; entry.ItemID = hatRes; entry.FakeItemID = hatRes; entry.OperationType = ESyncOperation.PutOn; applyData:Add(entry); ok = true end end); return ok end
function F.matchApplyFaceWear(char) local maskRes = F.getDesiredMask(); local glassRes = F.getDesiredGlass(); if (not maskRes or maskRes <= 0) and (not glassRes or glassRes <= 0) then return true end; char = char or F.getLocalChar(); if not char then return false end; local comp = F.getAvatarComp2(char); if not comp then return false end; local ok = false; pcall(function() local EAvatarSlotType = import("EAvatarSlotType"); local ESyncOperation = import("ESyncOperation"); local net = comp.NetAvatarData; local applyData = net and net.SlotSyncData; local function forceApplySlot(resID, slotID, slotNameStr) if not resID or resID <= 0 then return end; local slotEnum = EAvatarSlotType and EAvatarSlotType[slotNameStr]; local needRep = false; if applyData and slua.isValid(applyData) then local found = false; for i = 0, applyData:Num() - 1 do local equipment = applyData:Get(i); if equipment and equipment.SlotID == slotID then found = true; local cur = tonumber(equipment.ItemId) or tonumber(equipment.ItemID) or 0; if cur ~= resID then F.ensureSkinDownload(resID); equipment.ItemId = resID; if equipment.ItemID ~= nil then equipment.ItemID = resID end; if equipment.FakeItemID ~= nil then equipment.FakeItemID = resID end; applyData:Set(i, equipment); needRep = true end; break end end; if not found then F.ensureSkinDownload(resID); local entry = import("AvatarSyncData")(); entry.SlotID = slotID; entry.ItemId = resID; entry.ItemID = resID; entry.FakeItemID = resID; entry.OperationType = ESyncOperation.PutOn; applyData:Add(entry); needRep = true end end; _G.FaceWearStateCache = _G.FaceWearStateCache or {}; local cacheKey = tostring(comp) .. "_" .. tostring(slotID); if needRep or _G.FaceWearStateCache[cacheKey] ~= resID then if slotEnum then if comp.CancelHideAvatarBySlot then comp:CancelHideAvatarBySlot(slotEnum) end; if comp.SetAvatarVisibility then comp:SetAvatarVisibility(slotEnum, true, true) end end; if comp.PutOnCustomEquipmentByID then comp:PutOnCustomEquipmentByID(resID) end; _G.FaceWearStateCache[cacheKey] = resID; ok = true else if slotEnum and comp.CancelHideAvatarBySlot then comp:CancelHideAvatarBySlot(slotEnum) end end end; forceApplySlot(maskRes, F.CUST_SLOT.FaceEquipemtSlot, "EAvatarSlotType_FaceEquipemtSlot"); forceApplySlot(glassRes, F.CUST_SLOT.GlassEquipemtSlot, "EAvatarSlotType_GlassEquipemtSlot"); if ok and comp.OnRep_BodySlotStateChanged then comp:OnRep_BodySlotStateChanged() end end); return ok end
function F.applyEquipSkinToComp(comp, bagRes, helmetRes) local applied, found = false, false; pcall(function() local EAvatarSlotType = import("EAvatarSlotType"); local BackpackUtils = import("BackpackUtils"); local function doSlot(slotEnum, res, levelFn) res = tonumber(res) or 0; if res <= 0 or not slotEnum then return end; local sync = comp.GetSlotSyncData and comp:GetSlotSyncData(slotEnum); if not sync then return end; local cur = tonumber(sync.ItemID) or 0; local addID = tonumber(sync.AdditionalItemID) or 0; if cur <= 0 and addID <= 0 then return end; found = true; local lvl = 1; pcall(function() if levelFn then lvl = levelFn(addID > 0 and addID or cur) or 1 end end); if lvl < 1 then lvl = 1 end; local target = res + (lvl - 1) * 1000; if target > 0 and cur ~= target then sync.ItemID = target; comp:ChangeSlotSyncData(sync); applied = true end end; doSlot(EAvatarSlotType.EAvatarSlotType_BackpackEquipemtSlot, bagRes, BackpackUtils.GetEquipmentBagLevel); doSlot(EAvatarSlotType.EAvatarSlotType_HelmetEquipemtSlot, helmetRes, BackpackUtils.GetEquipmentHelmetLevel) end); return applied, found end
function F.matchApplyEquipmentSkin(char, bagRes, helmetRes) bagRes = tonumber(bagRes) or 0; helmetRes = tonumber(helmetRes) or 0; if bagRes <= 0 and helmetRes <= 0 then return true end; local comp = char.CharacterAvatarComp2_BP; if not slua.isValid(comp) then return false end; local applied, found = F.applyEquipSkinToComp(comp, bagRes, helmetRes); if applied then pcall(function() if comp.OnRep_BodySlotStateChanged then comp:OnRep_BodySlotStateChanged() end end); return true end; return found end
function F.applyAirborneSlots(char, forceInAir) local comp = F.getAvatarComp2(char); if not comp or not slua.isValid(comp) then return false end; local inAir = forceInAir == true; local any = false; local paraRes = F.getDesiredParachuteRes(); if paraRes and paraRes > 0 then any = true; if not F.isResourcesReady(paraRes) then F.requestResourceDownload(paraRes) end; F.setMakeSkin(comp, paraRes, F.CUST_SLOT.ParachuteEquipemtSlot, { inAir = inAir }) end; local gliderRes = F.getDesiredGliderRes(); if gliderRes and gliderRes > 0 then any = true; if not F.isResourcesReady(gliderRes) then F.requestResourceDownload(gliderRes) end; F.setMakeSkin(comp, gliderRes, F.CUST_SLOT.GlideEquipemtSlot, { inAir = inAir }) end; return any end
function F.matchApplyBodyWear(char) local pieces = {}; if not F.getDesiredOutfit() then pieces[#pieces + 1] = { F.getDesiredWear("tshirtRes", "tshirtRes", "AddOutfitLastLobbyTshirtRes", F.syncBodyCacheFromLobby), F.CUST_SLOT.ClothesEquipemtSlot, "tshirt" } end; pieces[#pieces + 1] = { F.getDesiredWear("pantsRes", "pantsRes", "AddOutfitLastLobbyPantsRes", F.syncBodyCacheFromLobby), F.CUST_SLOT.PantsEquipemtSlot, "pants" }; pieces[#pieces + 1] = { F.getDesiredWear("shoesRes", "shoesRes", "AddOutfitLastLobbyShoesRes", F.syncBodyCacheFromLobby), F.CUST_SLOT.ShoesEquipemtSlot, "shoes" }; pieces[#pieces + 1] = { F.getDesiredWear("glovesRes", "glovesRes", "AddOutfitLastLobbyGlovesRes", F.syncBodyCacheFromLobby), F.CUST_SLOT.HandEffectEquipemtSlot, "gloves" }; local any, okAll = false, true; for _, p in ipairs(pieces) do local res, slot, label = p[1], p[2], p[3]; if res and res > 0 then any = true; okAll = F.matchApplyWearItem(char, res, slot, label) and okAll end end; local anyAir = F.applyAirborneSlots(char, false); if anyAir then any = true end; local bagRes = F.getDesiredWear("bagRes", "bagRes", "AddOutfitLastLobbyBagRes", F.syncBodyCacheFromLobby); local helmetRes = F.getDesiredWear("helmetRes", "helmetRes", "AddOutfitLastLobbyHelmetRes", F.syncBodyCacheFromLobby); if (tonumber(bagRes) or 0) > 0 or (tonumber(helmetRes) or 0) > 0 then any = true; okAll = F.matchApplyEquipmentSkin(char, bagRes, helmetRes) and okAll end; return not any or okAll end
function F.matchApplyAllSlots(char) if not char then return false end; local comp = F.getAvatarComp2(char); if not comp then return false end; local entries = {}; local function add(skin, slot) skin = tonumber(skin); if skin and skin > 0 and slot then entries[#entries + 1] = { skin, slot } end end; local outfitRes = F.getDesiredOutfit(); if outfitRes then add(outfitRes, F.CUST_SLOT.ClothesEquipemtSlot) end; add(F.getDesiredWear("tshirtRes", "tshirtRes", "AddOutfitLastLobbyTshirtRes", F.syncBodyCacheFromLobby), F.CUST_SLOT.ClothesEquipemtSlot); add(F.getDesiredWear("pantsRes", "pantsRes", "AddOutfitLastLobbyPantsRes", F.syncBodyCacheFromLobby), F.CUST_SLOT.PantsEquipemtSlot); add(F.getDesiredWear("shoesRes", "shoesRes", "AddOutfitLastLobbyShoesRes", F.syncBodyCacheFromLobby), F.CUST_SLOT.ShoesEquipemtSlot); add(F.getDesiredWear("glovesRes", "glovesRes", "AddOutfitLastLobbyGlovesRes", F.syncBodyCacheFromLobby), F.CUST_SLOT.HandEffectEquipemtSlot); add(F.getDesiredHat(), F.CUST_SLOT.HatEquipemtSlot); add(F.getDesiredMask(), F.CUST_SLOT.FaceEquipemtSlot); add(F.getDesiredGlass(), F.CUST_SLOT.GlassEquipemtSlot); local ok = false; if #entries > 0 then ok = F.applySlotSkinBatch(comp, entries, { forceRep = true }); if not ok then for _, e in ipairs(entries) do if F.setMakeSkin(comp, e[1], e[2], { allowPutOn = true }) then ok = true end end end end; F.applyAirborneSlots(char, false); local bagRes = F.getDesiredWear("bagRes", "bagRes", "AddOutfitLastLobbyBagRes", F.syncBodyCacheFromLobby); local helmetRes = F.getDesiredWear("helmetRes", "helmetRes", "AddOutfitLastLobbyHelmetRes", F.syncBodyCacheFromLobby); if (tonumber(bagRes) or 0) > 0 or (tonumber(helmetRes) or 0) > 0 then ok = F.matchApplyEquipmentSkin(char, bagRes, helmetRes) or ok end; return ok or #entries == 0 end

function F.getLocalChar() local ok, GD = pcall(require, "GameLua.GameCore.Data.GameplayData"); if not ok or not GD then return nil end; local char = GD.GetPlayerCharacter(); if char and slua.isValid(char) then return char end; return nil end
function F.bootstrapMatch(char) char = char or F.getLocalChar(); if not char or not slua.isValid(char) then return false end; if PERF.matchActive then return true end; local now = os.clock(); if (now - PERF.lastBootstrapAt) < BOOTSTRAP_COOLDOWN then return false end; PERF.lastBootstrapAt = now; F.syncWeaponCacheFromLobby(true); F.applyPersistSlotsToCache(); F.syncGlobalWearSkins(); F.startMatchWatcher(char); return true end

local _matchTimer = nil
local _matchWearDone = false
function F.startMatchWatcher(char)
    if _matchTimer or PERF.matchActive then return end
    PERF.matchActive = true; _matchWearDone = PERF.wearDoneThisMatch; _avatarItemsRegistered = false; local elapsed = 0
    _matchTimer = char:AddGameTimer(MATCH_TICK_SEC, true, function()
        elapsed = elapsed + MATCH_TICK_SEC; local cur = F.getLocalChar(); if not cur or not slua.isValid(cur) then return end
        if not _matchWearDone then _matchWearDone = F.matchApplyAllSlots(cur) end
        F.matchApplyHat(cur); F.matchApplyFaceWear(cur); F.matchApplyWeaponSkin(cur)
        if F.isCharacterAirborne and F.isCharacterAirborne(cur) then F.applyAirborneSlots(cur, true) end
        if (_matchWearDone) or elapsed >= MATCH_MAX_SEC then
            if _matchWearDone then PERF.wearDoneThisMatch = true end
            if _matchTimer and cur.RemoveGameTimer then pcall(function() cur:RemoveGameTimer(_matchTimer) end) end
            _matchTimer = nil; PERF.matchActive = false
        end
    end)
end

function F.isCharacterAirborne(char) if not char or not slua.isValid(char) then return false end; local ok, r = pcall(function() local EParachuteState = import("EParachuteState"); local st = char.ParachuteState; return st and st ~= EParachuteState.PS_None end); return ok and r == true end
function F.syncGlobalWearSkins() _G.CustSlotType = F.CUST_SLOT; _G.skinIdCache = _G.skinIdCache or {}; _G.HatSkin = tonumber(F.getDesiredHat()) or 0; local outfit = F.getDesiredOutfit(); _G.SuitSkin = tonumber(outfit) or tonumber(_G.SuitSkin) or 0; _G.PantsSkin = tonumber(F.getDesiredWear("pantsRes", "pantsRes", "AddOutfitLastLobbyPantsRes", F.syncBodyCacheFromLobby)) or 0; _G.ShoesSkin = tonumber(F.getDesiredWear("shoesRes", "shoesRes", "AddOutfitLastLobbyShoesRes", F.syncBodyCacheFromLobby)) or 0; _G.GlovesSkin = tonumber(F.getDesiredWear("glovesRes", "glovesRes", "AddOutfitLastLobbyGlovesRes", F.syncBodyCacheFromLobby)) or 0; _G.MaskSkin = tonumber(F.getDesiredMask()) or 0; _G.GlassSkin = tonumber(F.getDesiredGlass()) or 0; _G.GliderSkin = tonumber(F.getDesiredGliderRes()) or 0; _G.ParachuteSkin = tonumber(F.getDesiredParachuteRes()) or 0 end

function _G.SkinZoneApply()
    if not _G.AddOutfit then return end; local F2 = _G.AddOutfit; local cfg = _G.GTLModConfig or {}; local skins = {}
    for _, g in ipairs(_G.SkinZoneGuns or {}) do local id = tonumber(cfg["SkinGun_" .. g.key]) or 0; if id > 0 then skins[g.wid] = id end end
    local gid = tonumber(cfg.SkinGrenadeID) or 0; if gid > 0 then skins[602004] = gid end
    pcall(function() local glid = tonumber(cfg.SkinGloveID) or 0; if glid > 0 then if _G.download_item then pcall(_G.download_item, glid) end; if F2.ensureSkinDownload then pcall(F2.ensureSkinDownload, glid) end; if F2.persistRememberSlot then pcall(F2.persistRememberSlot, "gloves", glid) end else if F2.persistForgetSlot then pcall(F2.persistForgetSlot, "gloves") end end; if F2.applyPersistSlotsToCache then pcall(F2.applyPersistSlotsToCache) end end)
    if F2.setWeaponSkins then F2.setWeaponSkins(skins) end; _G.WeaponSkinID = _G.WeaponSkinID or {}; for wid, _ in pairs(_G.WeaponSkinID) do _G.WeaponSkinID[wid] = nil end; for wid, id in pairs(skins) do _G.WeaponSkinID[wid] = id end
    if not _G.GameAvatarHandlerweapons and _G._SkinZoneInitWeaponSystem then pcall(_G._SkinZoneInitWeaponSystem) end; if _G.GameAvatarHandlerweapons then pcall(_G.GameAvatarHandlerweapons) end
    if F2.setZoneBaseRes then local effSuit = tonumber(cfg.CustSuit) or 0; if effSuit <= 0 then effSuit = tonumber(cfg.SkinSuit) or 0 end; F2.setZoneBaseRes(effSuit, tonumber(cfg.SkinBag) or 0, tonumber(cfg.SkinHelmet) or 0) end
    for _, id in pairs(skins) do pcall(F2.ensureSkinDownload, id) end; for _, id in ipairs({ tonumber(cfg.SkinSuit) or 0, tonumber(cfg.SkinBag) or 0, tonumber(cfg.SkinHelmet) or 0 }) do pcall(F2.ensureSkinDownload, id) end
    pcall(F2.syncGlobalWearSkins); pcall(function() if F2.isInRealMatch and F2.isInRealMatch() then local char = F2.getLocalChar and F2.getLocalChar(); if char then if F2.matchApplyAllSlots then pcall(F2.matchApplyAllSlots, char) end; if F2.matchApplyWeaponSkin then pcall(F2.matchApplyWeaponSkin, char) end; if _G.GameAvatarHandlerweapons then pcall(_G.GameAvatarHandlerweapons) end end end end)
end

function F.setZoneBaseRes(outfitRes, bagRes, helmetRes) MATCH_CONFIG.outfitRes = tonumber(outfitRes) or 0; MATCH_CONFIG.bagRes = tonumber(bagRes) or 0; MATCH_CONFIG.helmetRes = tonumber(helmetRes) or 0; local cch = F.cache(); cch.outfitRes = MATCH_CONFIG.outfitRes > 0 and MATCH_CONFIG.outfitRes or nil; cch.outfitIns = nil; F.perfInvalidateLobby() end
function F.persistRememberSlot(slotName, resID) slotName = slotName and tostring(slotName); resID = tonumber(resID); if not slotName or not resID or resID <= 0 then return end; PERSIST.configSlots = PERSIST.configSlots or {}; PERSIST.configSlots[slotName] = resID end
function F.persistForgetSlot(slotName) if PERSIST.configSlots and slotName then PERSIST.configSlots[tostring(slotName)] = nil end end

function F.hookWardrobeData() pcall(function() local wd = require("client.slua.logic.wardrobe.wardrobe_data"); if wd._AddOutfitDataHooked then return end; wd._AddOutfitDataHooked = true; local function wrapGet(name) local o = wd[name]; if not o then return end; wd[name] = function(self, insID, ...) insID = tonumber(insID); local r; if F.isInjectedIns(insID) then local e = F.getEntity(); if e then r = e:GetDataByInsID(insID) end else r = o(self, insID, ...) end; if r and (F.isInjectedIns(insID) or F.isInjectedRes(r.resID or r.res_id)) then r.expire_ts = 0; r.expireTS = 0; r.valid_hours = 0 end; return r end end; wrapGet("GetHallDepotItemDataByInsID"); wrapGet("GetValidHallDepotItemDataByInsID") end) end
function F.getEntity() local ok, dc = pcall(require, "client.slua.logic.wardrobe.logic_wardrobe_data_center"); if not ok or not dc then return nil end; local ok2, e = pcall(dc.GetWardrobeData); return ok2 and e or nil end
function F.hookArmory() pcall(function() local Arm = require("client.logic.armory.logic_armory"); if Arm._AddOutfitArmoryHooked then return end; Arm._AddOutfitArmoryHooked = true end) end
function F.hookPutOn() pcall(function() local WRH = require("client.network.Protocol.WardRobeHandler"); if WRH._AddOutfitPutOnHooked then return end; WRH._AddOutfitPutOnHooked = true end) end
function F.hookPutDown() pcall(function() local WRH = require("client.network.Protocol.WardRobeHandler"); if WRH._AddOutfitPutDownHooked then return end; WRH._AddOutfitPutDownHooked = true end) end
function F.getPC() if slua_GameFrontendHUD then local pc = slua_GameFrontendHUD:GetPlayerController(); if slua.isValid(pc) then return pc end end; local ok, gd = pcall(require, "GameLua.GameCore.Data.GameplayData"); if ok and gd then local pc = gd.GetPlayerController(); if slua.isValid(pc) then return pc end end; return nil end
function F.getMatchVehicle() local found = nil; pcall(function() local subs = SubsystemMgr:Get("VehicleControlUISubSystem"); if subs and subs.GetVehicleUserComponent then local uuc = subs:GetVehicleUserComponent(); if slua.isValid(uuc) and slua.isValid(uuc.Vehicle) then found = uuc.Vehicle end end end); if slua.isValid(found) then return found end; local pc = F.getPC(); if slua.isValid(pc) and pc.GetPlayerCharacterSafety then local char = pc:GetPlayerCharacterSafety(); if slua.isValid(char) then if char.GetCurrentVehicle then local v = char:GetCurrentVehicle(); if slua.isValid(v) then return v end end; if char.CurrentVehicle and slua.isValid(char.CurrentVehicle) then return char.CurrentVehicle end end end; return nil end
function F.applyVehicleSkinsToPC(pc) return false end
function F.getVehicleAvatarComp(vehicle) if not slua.isValid(vehicle) then return nil end; local av = nil; pcall(function() av = vehicle.VehicleAvatar end); if slua.isValid(av) then return av end; pcall(function() if vehicle.GetAvatarComponent then av = vehicle:GetAvatarComponent() end end); if slua.isValid(av) then return av end; pcall(function() av = vehicle.VehicleAvatarComponent_BP end); if slua.isValid(av) then return av end; return nil end
function F.forceVehicleAvatar(skinId, vehicle) skinId = tonumber(skinId); if not skinId or skinId <= 0 then return false end; vehicle = slua.isValid(vehicle) and vehicle or F.getMatchVehicle(); if not slua.isValid(vehicle) then return false end; local av = F.getVehicleAvatarComp(vehicle); if not slua.isValid(av) then return false end; local applied = false; pcall(function() if av.CanChangeAvatar ~= nil then av.CanChangeAvatar = true end end); pcall(function() av:ChangeItemAvatar(skinId, true); applied = true; _G.CurrentEquipVehicleID = skinId end); return applied end
function F.matchApplyVehicleSkin(skinId) skinId = tonumber(skinId); if not skinId or skinId <= 0 then return false end; local vehicle = F.getMatchVehicle(); return F.forceVehicleAvatar(skinId, vehicle) end

function F.start() if _G.AddOutfitStarted2 then return end; _G.AddOutfitStarted2 = true; pcall(function() F.syncWeaponCacheFromLobby(true); F.applyPersistSlotsToCache(); F.syncGlobalWearSkins() end); pcall(F.hookWardrobeData); pcall(F.hookArmory); pcall(F.hookPutOn); pcall(F.hookPutDown); pcall(function() if F.isInRealMatch() then local char = F.getLocalChar(); if char then F.bootstrapMatch(char) end end end) end
_G.AddOutfit = F

_G.GetEnemyTargetsFromActors = function(radius) local result = {}; local player = GameplayData.GetPlayerCharacter(); if not slua.isValid(player) then return result end; local allCharacters = {}; if GameplayData.GetAllPlayerCharacters then allCharacters = GameplayData.GetAllPlayerCharacters() elseif GameplayData.GameCharacters then for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end end; local myTeam = player:GetTeamID(); for _, actor in pairs(allCharacters) do if slua.isValid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then if actor:GetTeamID() ~= myTeam then local dist = player:GetDistanceTo(actor); if dist <= radius then table.insert(result, actor) end end end end; return result end

_G.AimTouch = function()
    pcall(function()
        if not _G.GTLModConfig.AimTouchEnable then return end; local player = GameplayData.GetPlayerCharacter(); if not slua.isValid(player) then return end; local pc = player:GetPlayerControllerSafety(); if not slua.isValid(pc) then return end; local isFiring = player.bIsWeaponFiring; local isADS = player.bIsGunADS
        local weapon = player.WeaponManagerComponent and player.WeaponManagerComponent.CurrentWeaponReplicated; if not weapon and type(player.GetCurrentShootWeapon) == "function" then weapon = player:GetCurrentShootWeapon() end
        local isShotgun = false; local isSniper = false; local currentAmmo = 1
        if slua.isValid(weapon) then local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0; local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""; if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then isShotgun = true end; if wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then isSniper = true end; if type(weapon.GetCurrentAmmo) == "function" then currentAmmo = weapon:GetCurrentAmmo() elseif weapon.ShootWeaponComponent and type(weapon.ShootWeaponComponent.GetCurrentAmmo) == "function" then currentAmmo = weapon.ShootWeaponComponent:GetCurrentAmmo() elseif weapon.CurrentAmmo ~= nil then currentAmmo = weapon.CurrentAmmo end end
        if _G.GTLModState.IsAutoFiring then pcall(function() player.bIsWeaponFiring = false; if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(false) end; if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(false) end; local wepMgr = player.WeaponManagerComponent; if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = false end end); _G.GTLModState.IsAutoFiring = false end
        if isShotgun and currentAmmo <= 0 then return end
        local cond = 2; local prioMode = 1; local boneIdx = 1; local speedVal = 50; local fovVal = 30; local maxDistMeters = 50; local useVisCheck = false; local igKnock = false; local igBot = false; local predVal = 0; local recoilCompVal = 0
        if isShotgun and _G.GTLModConfig.AimTouchSG then cond = _G.GTLModState.CustomTextData.AimTouchSGCond or 1; if _G.GTLModConfig.AimTouchSGAutoFire then cond = 2 end; if cond == 1 and not isFiring then return end; prioMode = _G.GTLModState.CustomTextData.AimTouchSGPrio or 1; boneIdx = _G.GTLModState.CustomTextData.AimTouchSGBone or 2; speedVal = _G.GTLModState.CustomTextData.AimTouchSGSpeed or 80; fovVal = _G.GTLModState.CustomTextData.AimTouchSGFOV or 40; maxDistMeters = _G.GTLModState.CustomTextData.AimTouchSGDist or 30; useVisCheck = _G.GTLModConfig.AimTouchSGVisCheck; igKnock = _G.GTLModConfig.AimTouchSGIgKnock; igBot = _G.GTLModConfig.AimTouchSGIgBot
        elseif isADS then if isSniper and _G.GTLModConfig.AimTouchScopeSniper then cond = _G.GTLModState.CustomTextData.AimTouchSniperCond or 2; if cond == 1 and not isFiring then return end; prioMode = _G.GTLModState.CustomTextData.AimTouchSniperPrio or 1; boneIdx = _G.GTLModState.CustomTextData.AimTouchSniperBone or 1; speedVal = _G.GTLModState.CustomTextData.AimTouchSniperSpeed or 30; fovVal = _G.GTLModState.CustomTextData.AimTouchSniperFOV or 20; maxDistMeters = _G.GTLModState.CustomTextData.AimTouchSniperDist or 400; useVisCheck = _G.GTLModConfig.AimTouchSniperVisCheck; igKnock = _G.GTLModConfig.AimTouchSniperIgKnock; igBot = _G.GTLModConfig.AimTouchSniperIgBot; predVal = _G.GTLModState.CustomTextData.AimTouchSniperPred or 0
        elseif _G.GTLModConfig.AimTouchScopeAll then cond = _G.GTLModState.CustomTextData.AimTouchScopeCond or 1; if cond == 1 and not isFiring then return end; prioMode = _G.GTLModState.CustomTextData.AimTouchScopePrio or 1; boneIdx = _G.GTLModState.CustomTextData.AimTouchScopeBone or 2; speedVal = _G.GTLModState.CustomTextData.AimTouchScopeSpeed or 40; fovVal = _G.GTLModState.CustomTextData.AimTouchScopeFOV or 20; maxDistMeters = _G.GTLModState.CustomTextData.AimTouchScopeDist or 300; useVisCheck = _G.GTLModConfig.AimTouchScopeVisCheck; igKnock = _G.GTLModConfig.AimTouchScopeIgKnock; igBot = _G.GTLModConfig.AimTouchScopeIgBot; predVal = _G.GTLModState.CustomTextData.AimTouchScopePred or 0; recoilCompVal = _G.GTLModState.CustomTextData.AimTouchScopeRecoil or 0
        else return end
        else if not _G.GTLModConfig.AimTouchHipfire then return end; cond = _G.GTLModState.CustomTextData.AimTouchHipCond or 1; if cond == 1 and not isFiring then return end; prioMode = _G.GTLModState.CustomTextData.AimTouchHipPrio or 1; boneIdx = _G.GTLModState.CustomTextData.AimTouchHipBone or 1; speedVal = _G.GTLModState.CustomTextData.AimTouchHipSpeed or 50; fovVal = _G.GTLModState.CustomTextData.AimTouchHipFOV or 30; maxDistMeters = _G.GTLModState.CustomTextData.AimTouchHipDist or 250; useVisCheck = _G.GTLModConfig.AimTouchHipVisCheck; igKnock = _G.GTLModConfig.AimTouchHipIgKnock; igBot = _G.GTLModConfig.AimTouchHipIgBot end
        local currentMaxDist = maxDistMeters * 100; local enemies = _G.GetEnemyTargetsFromActors(currentMaxDist); if not enemies or #enemies == 0 then return end
        local FVector2D = import("Vector2D"); local UGameplayStatics = import("GameplayStatics"); local KismetMathLibrary = import("KismetMathLibrary"); local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0); if not slua.isValid(camManager) then return end; local camLoc = camManager:GetCameraLocation(); if not camLoc then return end
        local ui_util = require("client.common.ui_util"); if not ui_util then return end; local viewportSize = ui_util.GetViewportSize(); if not viewportSize then return end; local centerX = viewportSize.X * 0.5; local centerY = viewportSize.Y * 0.5; local FOV_RADIUS = (fovVal / 100.0) * (viewportSize.X / 2.0)
        local bestTarget = nil; local bestScore = 99999999; local selBoneName = "head"; if boneIdx == 1 then selBoneName = "head" elseif boneIdx == 2 then selBoneName = "spine_03" elseif boneIdx == 3 then selBoneName = "spine_01" elseif boneIdx == 4 then selBoneName = "pelvis" end
        for i, target in ipairs(enemies) do if not slua.isValid(target) then goto continue end; pcall(function() if slua.isValid(target.Mesh) then target.Mesh.MeshComponentUpdateFlag = 0 end end); if igKnock and target.HealthStatus == 1 then goto continue end
            if igBot then local tIsBot = false; if target.bIsAI == true or target.IsAI == true then tIsBot = true end; local pState = target.PlayerState; if slua.isValid(pState) and (pState.bIsABot or pState.bIsBot) then tIsBot = true end; if tIsBot then goto continue end end
            if useVisCheck then local curTime = os.clock(); local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target); _G.AimTouchVisCache = _G.AimTouchVisCache or {}; if not _G.AimTouchVisCache[tId] or (curTime - _G.AimTouchVisCache[tId].time) > 0.2 then local isHidden = true; pcall(function() if pc:LineOfSightTo(target) then isHidden = false end end); _G.AimTouchVisCache[tId] = { hidden = isHidden, time = curTime } end; if _G.AimTouchVisCache[tId].hidden then goto continue end end
            local tPos = target:GetBonePos(selBoneName, {X=0, Y=0, Z=0}); if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then if type(target.GetSocketLocation) == "function" then tPos = target:GetSocketLocation(selBoneName) end end; if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then if type(target.K2_GetActorLocation) == "function" then tPos = target:K2_GetActorLocation(); if tPos then if boneIdx == 1 then tPos.Z = tPos.Z + 70 elseif boneIdx == 2 then tPos.Z = tPos.Z + 40 elseif boneIdx == 3 then tPos.Z = tPos.Z + 20 end end end end; if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then goto continue end
            local screen = FVector2D(); local success = pc:ProjectWorldLocationToScreen(tPos, screen, false); if not success or screen.X <= 0 or screen.Y <= 0 then goto continue end; local dx = screen.X - centerX; local dy = screen.Y - centerY; local distScreen = math.sqrt(dx*dx + dy*dy); if distScreen > FOV_RADIUS then goto continue end
            local currentScore = distScreen; if prioMode == 2 then currentScore = player:GetDistanceTo(target) elseif prioMode == 3 then currentScore = target.Health or 100 elseif prioMode == 4 then local hp = target.Health or 100; local maxhp = target.HealthMax or 100; if maxhp <= 0 then maxhp = 100 end; currentScore = hp / maxhp end
            if currentScore < bestScore then bestScore = currentScore; bestTarget = target end
            ::continue::
        end
        if not slua.isValid(bestTarget) then return end; local finalBonePos = bestTarget:GetBonePos(selBoneName, {X=0, Y=0, Z=0}); if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then if type(bestTarget.GetSocketLocation) == "function" then finalBonePos = bestTarget:GetSocketLocation(selBoneName) end end; if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then if type(bestTarget.K2_GetActorLocation) == "function" then finalBonePos = bestTarget:K2_GetActorLocation(); if finalBonePos then if boneIdx == 1 then finalBonePos.Z = finalBonePos.Z + 70 elseif boneIdx == 2 then finalBonePos.Z = finalBonePos.Z + 40 elseif boneIdx == 3 then finalBonePos.Z = finalBonePos.Z + 20 end end end end; if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then return end
        if predVal > 0 then pcall(function() local tVelocity = nil; if type(bestTarget.GetVelocity) == "function" then tVelocity = bestTarget:GetVelocity() end; if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then local distToEnemy = player:GetDistanceTo(bestTarget) / 100.0; local ToF = (distToEnemy / 800.0) * (predVal / 50.0); finalBonePos.X = finalBonePos.X + (tVelocity.X * ToF); finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * ToF) end end) end
        local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalBonePos); if not rot then return end; local currentRot = pc:GetControlRotation(); if not currentRot then return end; local deltaYaw = rot.Yaw - currentRot.Yaw; local deltaPitch = rot.Pitch - currentRot.Pitch
        if isADS then local camRot = nil; if type(camManager.GetCameraRotation) == "function" then camRot = camManager:GetCameraRotation() end; if camRot then deltaYaw = deltaYaw - (camRot.Yaw - currentRot.Yaw); deltaPitch = deltaPitch - (camRot.Pitch - currentRot.Pitch) end end
        if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end; if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end; if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end; if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end
        local smoothFactor = 0.0; if speedVal >= 100 then smoothFactor = 1.0 else smoothFactor = (speedVal / 100.0) * 0.3; if smoothFactor < 0.01 then smoothFactor = 0.01 end end
        local finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor); local finalYaw = currentRot.Yaw + (deltaYaw * smoothFactor)
        if recoilCompVal > 0 and isFiring then local pullDownForce = (recoilCompVal / 50.0) * 1.5; finalPitch = finalPitch - pullDownForce end
        local finalRot = { Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }; pc:SetControlRotation(finalRot, "AimTouch")
        if isShotgun and _G.GTLModConfig.AimTouchSGAutoFire then pcall(function() local distToTarget = player:GetDistanceTo(bestTarget) / 100; if distToTarget <= maxDistMeters then player.bIsWeaponFiring = true; if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(true) end; if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(true) end; local wepMgr = player.WeaponManagerComponent; if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = true end; local currentWep = player:GetCurrentWeapon(); if slua.isValid(currentWep) and type(currentWep.StartFire) == "function" then currentWep:StartFire() end; _G.GTLModState.IsAutoFiring = true end end) end
    end)
end

function _G.InitModMenuTab()
    if _G.ModMenuInitialized then return end; _G.ModMenuInitialized = true
    _G.GTLModState.CustomTextData = _G.GTLModState.CustomTextData or { OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 58, AimTouchHipFOV = 20, AimTouchHipDist = 50, AimTouchSGPrio = 1, AimTouchSGBone = 1, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30, AimTouchScopePrio = 1, AimTouchScopeBone = 1, AimTouchScopeCond = 1, AimTouchScopeSpeed = 65, AimTouchScopeFOV = 20, AimTouchScopeDist = 200, AimTouchScopePred = 1, AimTouchScopeRecoil = 4, AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400, AimTouchSniperPred = 0 }
    local LocUtil = _G.LocUtil or require("client.common.LocUtil")
    if LocUtil and not LocUtil._IsModMenuHooked then local old_get = LocUtil.GetLocalizeResStr; LocUtil.GetLocalizeResStr = function(id) if type(id) == "string" and not tonumber(id) then return id end; return old_get(id) end; LocUtil._IsModMenuHooked = true end
    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine"); local SettingCatalog = require("client.logic.NewSetting.SettingCatalog"); if SettingPageDefine.ModMenu then return end
    local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
    local StackESPVisual = { { Key = "ModMenu_ESP_Title", UI = AliasMap.Title, Text = "❏ ESP V2 (Clear Vision)" }, { Key = "ModMenu_ESPV2_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ESP V2", ExpandIndex = 0, GetFunc = function() return _G.GTLModConfig.EspV2Enabled == true end, SetFunc = function(c,v) _G.GTLModConfig.EspV2Enabled = (v == true); if _G.ClearVisionV2Sync then pcall(_G.ClearVisionV2Sync) end; return true end }, { Key = "ModMenu_ESPV2_Bracket", UI = AliasMap.Switcher, Text = "   ESP BOX", ExpandHandle = "ModMenu_ESPV2_Ex", GetFunc = function() return _G.GTLModConfig.EspV2Bracket ~= false end, SetFunc = function(c,v) _G.GTLModConfig.EspV2Bracket = (v == true); if _G.ClearVisionV2Update then pcall(_G.ClearVisionV2Update) end; return true end }, { Key = "ModMenu_ESPV2_Health", UI = AliasMap.Switcher, Text = "   HEALTH BLOCKS", ExpandHandle = "ModMenu_ESPV2_Ex", GetFunc = function() return _G.GTLModConfig.EspV2Health ~= false end, SetFunc = function(c,v) _G.GTLModConfig.EspV2Health = (v == true); if _G.ClearVisionV2Update then pcall(_G.ClearVisionV2Update) end; return true end }, { Key = "ModMenu_ESPV2_Distance", UI = AliasMap.Switcher, Text = "   ESP DISTANCE", ExpandHandle = "ModMenu_ESPV2_Ex", GetFunc = function() return _G.GTLModConfig.EspV2Distance ~= false end, SetFunc = function(c,v) _G.GTLModConfig.EspV2Distance = (v == true); if _G.ClearVisionV2Update then pcall(_G.ClearVisionV2Update) end; return true end }, { Key = "ModMenu_ESPV2_Name", UI = AliasMap.Switcher, Text = "   PLAYER NAME", ExpandHandle = "ModMenu_ESPV2_Ex", GetFunc = function() return _G.GTLModConfig.EspV2Name ~= false end, SetFunc = function(c,v) _G.GTLModConfig.EspV2Name = (v == true); if _G.ClearVisionV2Update then pcall(_G.ClearVisionV2Update) end; return true end }, { Key = "ModMenu_ESPV2_Counter", UI = AliasMap.Switcher, Text = "   PLAYER / BOT COUNTER", ExpandHandle = "ModMenu_ESPV2_Ex", GetFunc = function() return _G.GTLModConfig.EspV2Counter ~= false end, SetFunc = function(c,v) _G.GTLModConfig.EspV2Counter = (v == true); if _G.ClearVisionV2Update then pcall(_G.ClearVisionV2Update) end; return true end }, { Key = "ModMenu_ESPV2_Snap", UI = AliasMap.Switcher, Text = "   ESP LINE (MAY LAG!)", ExpandHandle = "ModMenu_ESPV2_Ex", GetFunc = function() return _G.GTLModConfig.EspV2SnapLine ~= false end, SetFunc = function(c,v) _G.GTLModConfig.EspV2SnapLine = (v == true); return true end } }
    local StackAimbot = { { Key = "ModMenu_AT_Title", UI = AliasMap.Title, Text = "❏ TOUCH AIMBOT" }, { Key = "ModMenu_AT_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ AIMBOT", ExpandIndex = 0, GetFunc = function() return _G.GTLModConfig.AimTouchEnable end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchEnable = v return true end }, { Key = "ModMenu_AT_Hip_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Hipfire Aimbot", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.GTLModConfig.AimTouchHipfire end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchHipfire = v return true end }, { Key = "ModMenu_AT_Hip_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.GTLModConfig.AimTouchHipIgKnock end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchHipIgKnock = v return true end }, { Key = "ModMenu_AT_Hip_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.GTLModConfig.AimTouchHipIgBot end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchHipIgBot = v return true end }, { Key = "ModMenu_AT_Hip_Vis", UI = AliasMap.Switcher, Text = "      Visibility Check", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.GTLModConfig.AimTouchHipVisCheck end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchHipVisCheck = v return true end }, { Key = "ModMenu_AT_Hip_Bone", UI = AliasMap.Switcher, Text = "      Bone Target", ExpandHandle = "ModMenu_AT_Hip_Ex", SwitcherText = {"Head","Chest","Stomach","Pelvis"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchHipBone or 1 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchHipBone = v return true end }, { Key = "ModMenu_AT_Hip_Spd", UI = AliasMap.Slider, Text = "      Speed (60 perfect)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchHipSpeed or 50 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchHipSpeed = v return true end }, { Key = "ModMenu_AT_Hip_FOV", UI = AliasMap.Slider, Text = "      FOV Range", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchHipFOV or 30 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchHipFOV = v return true end }, { Key = "ModMenu_AT_ScopeAll_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Scoped Aimbot", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.GTLModConfig.AimTouchScopeAll end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchScopeAll = v return true end }, { Key = "ModMenu_AT_ScopeAll_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.GTLModConfig.AimTouchScopeIgKnock end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchScopeIgKnock = v return true end }, { Key = "ModMenu_AT_ScopeAll_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.GTLModConfig.AimTouchScopeIgBot end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchScopeIgBot = v return true end }, { Key = "ModMenu_AT_ScopeAll_Vis", UI = AliasMap.Switcher, Text = "      Visibility Check", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.GTLModConfig.AimTouchScopeVisCheck end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchScopeVisCheck = v return true end }, { Key = "ModMenu_AT_ScopeAll_Bone", UI = AliasMap.Switcher, Text = "      Bone Target", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", SwitcherText = {"Head","Chest","Stomach","Pelvis"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchScopeBone or 2 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchScopeBone = v return true end }, { Key = "ModMenu_AT_ScopeAll_Spd", UI = AliasMap.Slider, Text = "      Speed", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchScopeSpeed or 40 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchScopeSpeed = v return true end }, { Key = "ModMenu_AT_ScopeAll_FOV", UI = AliasMap.Slider, Text = "      FOV Range", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchScopeFOV or 20 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchScopeFOV = v return true end }, { Key = "ModMenu_AT_SG_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Shotgun Aimbot", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.GTLModConfig.AimTouchSG end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchSG = v return true end }, { Key = "ModMenu_AT_SG_AutoFire", UI = AliasMap.Switcher, Text = "      Auto Fire", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.GTLModConfig.AimTouchSGAutoFire end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchSGAutoFire = v return true end }, { Key = "ModMenu_AT_SG_Bone", UI = AliasMap.Switcher, Text = "      Bone Target", ExpandHandle = "ModMenu_AT_SG_Ex", SwitcherText = {"Head","Chest","Stomach","Pelvis"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchSGBone or 2 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchSGBone = v return true end }, { Key = "ModMenu_AT_SG_Spd", UI = AliasMap.Slider, Text = "      Speed", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchSGSpeed or 80 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchSGSpeed = v return true end }, { Key = "ModMenu_AT_SG_FOV", UI = AliasMap.Slider, Text = "      FOV Range", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchSGFOV or 40 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchSGFOV = v return true end }, { Key = "ModMenu_AT_Sniper_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Sniper Scope Aimbot", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.GTLModConfig.AimTouchScopeSniper end, SetFunc = function(c,v) _G.GTLModConfig.AimTouchScopeSniper = v return true end }, { Key = "ModMenu_AT_Sniper_Bone", UI = AliasMap.Switcher, Text = "      Bone Target", ExpandHandle = "ModMenu_AT_Sniper_Ex", SwitcherText = {"Head","Chest","Stomach","Pelvis"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchSniperBone or 1 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchSniperBone = v return true end }, { Key = "ModMenu_AT_Sniper_Pred", UI = AliasMap.Slider, Text = "      Movement Prediction", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.GTLModState.CustomTextData.AimTouchSniperPred or 0 end, SetFunc = function(c,v) _G.GTLModState.CustomTextData.AimTouchSniperPred = v return true end } }
    local StackSkin = { { Key = "ModMenu_Skin_Title", UI = AliasMap.Title, Text = "❏ SKIN HACK" }, { Key = "ModMenu_Skin_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ SKIN HACK (ON/OFF)", ExpandIndex = 0, GetFunc = function() return _G.GTLModConfig.ModSkin ~= false end, SetFunc = function(c,v) _G.GTLModConfig.ModSkin = v; if _G.SkinZoneApply then pcall(_G.SkinZoneApply) end return true end }, { Key = "ModMenu_SkinSuit_Title", UI = AliasMap.Title, Text = "   ── SUIT ──" }, { Key = "ModMenu_SkinSuit_Ex", UI = AliasMap.Switcher, Text = "      Suit (Cycle)", ExpandHandle = "ModMenu_Skin_Ex", SwitcherText = {"Off","0","1","2","3","4","5","6","7","8","9","10","11","12","13","14","15"}, SwitcherValue = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}, GetFunc = function() local id = tonumber(_G.GTLModConfig.CustSuit) or 0; for i, v in ipairs(_G.SkinZoneSuits or {}) do if v.id == id then return i + 1 end end return 1 end, SetFunc = function(c,v) v = tonumber(v) or 0; if v <= 1 then _G.GTLModConfig.CustSuit = 0 else local s = (_G.SkinZoneSuits or {})[v-1]; if s then _G.GTLModConfig.CustSuit = s.id end end; if _G.SkinZoneApply then pcall(_G.SkinZoneApply) end return true end }, { Key = "ModMenu_SkinHelmet_Title", UI = AliasMap.Title, Text = "   ── HELMET ──" }, { Key = "ModMenu_SkinHelmet_Ex", UI = AliasMap.Switcher, Text = "      Helmet (Cycle)", ExpandHandle = "ModMenu_Skin_Ex", SwitcherText = {"Off","0","1","2","3","4","5","6","7","8","9","10","11"}, SwitcherValue = {0,1,2,3,4,5,6,7,8,9,10,11,12}, GetFunc = function() local id = tonumber(_G.GTLModConfig.SkinHelmet) or 0; for i, v in ipairs(_G.SkinZoneHelmets or {}) do if v.id == id then return i + 1 end end return 1 end, SetFunc = function(c,v) v = tonumber(v) or 0; if v <= 1 then _G.GTLModConfig.SkinHelmet = 0 else local s = (_G.SkinZoneHelmets or {})[v-1]; if s then _G.GTLModConfig.SkinHelmet = s.id end end; if _G.SkinZoneApply then pcall(_G.SkinZoneApply) end return true end }, { Key = "ModMenu_SkinBag_Title", UI = AliasMap.Title, Text = "   ── BAG ──" }, { Key = "ModMenu_SkinBag_Ex", UI = AliasMap.Switcher, Text = "      Backpack (Cycle)", ExpandHandle = "ModMenu_Skin_Ex", SwitcherText = {"Off","0","1","2","3","4","5","6","7"}, SwitcherValue = {0,1,2,3,4,5,6,7,8}, GetFunc = function() local id = tonumber(_G.GTLModConfig.SkinBag) or 0; for i, v in ipairs(_G.SkinZoneBags or {}) do if v.id == id then return i + 1 end end return 1 end, SetFunc = function(c,v) v = tonumber(v) or 0; if v <= 1 then _G.GTLModConfig.SkinBag = 0 else local s = (_G.SkinZoneBags or {})[v-1]; if s then _G.GTLModConfig.SkinBag = s.id end end; if _G.SkinZoneApply then pcall(_G.SkinZoneApply) end return true end }, { Key = "ModMenu_SkinWeapon_Title", UI = AliasMap.Title, Text = "   ── WEAPON SKINS (group cycle) ──" } }
    for _, g in ipairs(_G.SkinZoneGuns or {}) do local texts = {"Off"}; local vals = {0}; for i, name in ipairs(g.names) do texts[#texts + 1] = name; vals[#vals + 1] = g.ids[i] or 0 end; StackSkin[#StackSkin + 1] = { Key = "ModMenu_SkinGun_" .. g.key, UI = AliasMap.Switcher, Text = "      " .. g.name .. " (" .. #g.ids .. " skins)", ExpandHandle = "ModMenu_Skin_Ex", SwitcherText = texts, SwitcherValue = vals, GetFunc = function() local cur = tonumber(_G.GTLModConfig["SkinGun_" .. g.key]) or 0; for i, v in ipairs(vals) do if v == cur then return i end end; return 1 end, SetFunc = function(c, v) local id = vals[tonumber(v) or 1] or 0; _G.GTLModConfig["SkinGun_" .. g.key] = id; if _G.SkinZoneApply then pcall(_G.SkinZoneApply) end; return true end } end
    local StackBypass = { { Key = "ModMenu_Bypass_Title", UI = AliasMap.Title, Text = "❏ BYPASS STATUS" }, { Key = "ModMenu_Bypass_Info", UI = AliasMap.Title, Text = "   ✓ Anti-Ban System: ACTIVE" }, { Key = "ModMenu_Bypass_Info2", UI = AliasMap.Title, Text = "   ✓ 15 Layers Protection: ACTIVE" }, { Key = "ModMenu_Bypass_Info3", UI = AliasMap.Title, Text = "   ✓ ESP V2 Safe Mode: ACTIVE" } }
    SettingPageDefine.ModMenu = { Key = "ModMenu", Text = "❏ @MS_CONFIG_VIP MENU", UIKey = "Setting_Page_Privacy", Category = { { Key = "Cat_ESP", Text = "➠ ESP V2", Stack = StackESPVisual }, { Key = "Cat_Aimbot", Text = "➠ AIMBOT", Stack = StackAimbot }, { Key = "Cat_Skin", Text = "➠ SKIN HACK", Stack = StackSkin }, { Key = "Cat_Bypass", Text = "➠ BYPASS", Stack = StackBypass } } }
    for i = #SettingCatalog, 1, -1 do if SettingCatalog[i] and SettingCatalog[i].Key == "ModMenu" then table.remove(SettingCatalog, i) end end; table.insert(SettingCatalog, 1, SettingPageDefine.ModMenu)
    local UIManager = _G.UIManager; if UIManager and not UIManager._IsModMenuHooked then local old_ShowUI = UIManager.ShowUI; UIManager.ShowUI = function(config, ...) local args = {...}; local n = select('#', ...); if config and config.keyName and (string.find(string.lower(config.keyName), "setting_main") or string.find(string.lower(config.keyName), "setting")) then local catalog = args[1]; if type(catalog) == "table" then for i = #catalog, 1, -1 do if catalog[i] and catalog[i].Key == "ModMenu" then table.remove(catalog, i) end end; table.insert(catalog, 1, SettingPageDefine.ModMenu) end end; local table_unpack = table.unpack or unpack; return old_ShowUI(config, table_unpack(args, 1, n)) end; UIManager._IsModMenuHooked = true end
end

local function ShowMenuPopup()
    if _G.GTLModMenuShown then return end; _G.GTLModMenuShown = true
    pcall(function() local Msg = require("client.slua.logic.common.logic_common_msg_box"); if not Msg or not Msg.Show then return end; Msg.Show(1, "VIP MOD", "ESP V2 + AIMBOT + SKIN HACK + BYPASS\n\nOK = Open Menu", function() _G.InitModMenuTab(); Notify("VIP MENU loaded. Go to Settings → @MS_CONFIG_VIP MENU") end, function() end, "OKEY", "CLOSE") end)
end

local function MainLoop()
    if isExpired then return end
    if _G.GTLModConfig and _G.GTLModConfig.EspV2Enabled and _G.ClearVisionV2Sync then pcall(_G.ClearVisionV2Sync) end
    if _G.GTLModState.CustomTextData == nil then _G.GTLModState.CustomTextData = { OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 58, AimTouchHipFOV = 20, AimTouchHipDist = 50, AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30, AimTouchScopePrio = 1, AimTouchScopeRecoil = 4, AimTouchScopeBone = 1, AimTouchScopeCond = 1, AimTouchScopeSpeed = 65, AimTouchScopeFOV = 20, AimTouchScopeDist = 180, AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 1, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400 } end
    local okData, GameplayData = pcall(require, "GameLua.GameCore.Data.GameplayData"); if not okData or not GameplayData then return end
    local pc = GameplayData.GetPlayerController(); local localPlayer = nil; if Valid(pc) then localPlayer = pc:GetPlayerCharacterSafety() end; if not Valid(localPlayer) then return end
    if not _G.AddOutfitStarted then _G.AddOutfitStarted = true; pcall(function() if _G.AddOutfit and _G.AddOutfit.start then _G.AddOutfit.start() end end) end
    if not _G.GTLModMenuShown then ShowMenuPopup() end
    pcall(function() if _G.GTLModConfig.ModSkin and _G.AddOutfit and _G.AddOutfit.isInRealMatch and _G.AddOutfit.isInRealMatch() then if not _G.AddOutfitMatchInit then _G.AddOutfitMatchInit = true; pcall(function() _G.AddOutfit.bootstrapMatch() end) end end end)
end

_G.GTLModState.LoopToken = (_G.GTLModState.LoopToken or 0) + 1
local myToken = _G.GTLModState.LoopToken
local function FastTick()
    if isExpired then if not _G.GTLModNotifiedExpire then Notify("MOD EXPIRED"); _G.GTLModNotifiedExpire = true end; return end
    if myToken ~= _G.GTLModState.LoopToken then return end
    pcall(MainLoop)
    local okTicker, ticker = pcall(require, "common.time_ticker"); if okTicker and ticker and ticker.AddTimerOnce then ticker.AddTimerOnce(0.2, FastTick) end
end

local aimbotToken = 0
local function FastAimbotTick()
    if isExpired then return end; if aimbotToken ~= _G.GTLModState.AimbotLoopToken then return end
    pcall(function() if _G.GTLModConfig.AimTouchEnable then _G.AimTouch() end end)
    local okTicker, ticker = pcall(require, "common.time_ticker"); if okTicker and ticker and ticker.AddTimerOnce then ticker.AddTimerOnce(0.016, FastAimbotTick) end
end

if not isExpired then
    FastTick()
    _G.GTLModState.AimbotLoopToken = (_G.GTLModState.AimbotLoopToken or 0) + 1; aimbotToken = _G.GTLModState.AimbotLoopToken
    local okTicker, ticker = pcall(require("common.time_ticker"))
    if okTicker and ticker and ticker.AddTimerOnce then ticker.AddTimerOnce(0.1, FastAimbotTick) end
    if okTicker and ticker and ticker.AddTimerLoop and _G.__szSkinHackLoopStarted ~= 1 then
        _G.__szSkinHackLoopStarted = 1
        ticker.AddTimerLoop(0, function()
            if isExpired then return end; if not _G.GTLModConfig.ModSkin then return end
            pcall(function()
                local GD = require("GameLua.GameCore.Data.GameplayData"); local pc = GD.GetPlayerController(); if not Valid(pc) then return end; local lp = pc:GetPlayerCharacterSafety(); if not Valid(lp) then return end
                local isAlive = type(lp.IsAlive) == "function" and lp:IsAlive() or true; if not isAlive then return end
                if _G.AddOutfit and _G.AddOutfit.isInRealMatch and _G.AddOutfit.isInRealMatch() then _G.AddOutfit.matchApplyAllSlots(lp); _G.AddOutfit.matchApplyWeaponSkin(lp); if _G.AddOutfit.isCharacterAirborne and _G.AddOutfit.isCharacterAirborne(lp) then _G.AddOutfit.applyAirborneSlots(lp, true) end end
            end)
        end, -1, 3.0)
    end
    pcall(function() require("common.time_ticker").AddTimerOnce(0.5, function() if _G.StartBypass_VIP_v3 then _G.StartBypass_VIP_v3() end end) end)
    pcall(function()
        require("common.time_ticker").AddTimerOnce(1.5, function()
            if _G.StartBypass_VIP_v3 then pcall(_G.StartBypass_VIP_v3) end
            if _G.InitModMenuTab then pcall(_G.InitModMenuTab) end
            pcall(function()
                local Msg = require("client.slua.logic.common.logic_common_msg_box")
                if Msg and Msg.Show then Msg.Show(1, "VIP MOD", "ESP V2 + AIMBOT + SKIN HACK + BYPASS\n\nসেটিংস এ গিয়ে '@MS_CONFIG_VIP MENU' দেখো", function() if _G.InitModMenuTab then pcall(_G.InitModMenuTab) end end, function() end, "OKEY", "CLOSE") end
            end)
            Notify("VIP MOD LOADED SUCCESSFULLY!")
        end)
    end)
end

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
  { ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature" },
  { SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature" },
  { GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature" }
}, "BRPlayerCharacterBase")
