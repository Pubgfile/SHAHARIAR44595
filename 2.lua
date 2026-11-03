-- ============================================================================
-- BRPlayerCharacterBase.lua - SPEED HACK WITH SETTINGS MENU (NO ERRORS)
-- ============================================================================

local BRPlayerCharacterBase = {
  ServerRPC = {}, ClientRPC = {}, MulticastRPC = {}, LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }

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
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")

-- ============================================================================
-- SPEED CONFIGURATION
-- ============================================================================
_G.SpeedHackConfig = _G.SpeedHackConfig or {
    Enabled = false,
    SpeedMultiplier = 100, -- 1 = Normal, 100 = Max
}

local SPEED_CFG = {
    BASE_SPEED       = 600,
    MAX_SPEED        = 20000,
    MIN_MOVE_SPEED   = 0.1,
    REAPPLY_DELTA    = 10,
    TICK_INTERVAL    = 0.001,
}

-- ============================================================================
-- SPEED HACK LOGIC
-- ============================================================================
local function ApplySpeedHack(localPlayer, CM)
    if not _G.SpeedHackConfig.Enabled then return end
    if localPlayer.Role ~= ENetRole.ROLE_AutonomousProxy then return end
    if not slua.isValid(CM) then return end

    local mult = _G.SpeedHackConfig.SpeedMultiplier or 100
    local targetSpeed = SPEED_CFG.BASE_SPEED + ((SPEED_CFG.MAX_SPEED - SPEED_CFG.BASE_SPEED) * (mult / 100.0))

    if localPlayer._origWalkSpeed == nil then
        localPlayer._origWalkSpeed   = CM.MaxWalkSpeed or 600
    end

    if math.abs(CM.MaxWalkSpeed - targetSpeed) > SPEED_CFG.REAPPLY_DELTA then
        CM.MaxWalkSpeed = targetSpeed
        CM.MaxCustomMovementSpeed = targetSpeed
        CM.MaxAcceleration = 999999
        CM.BrakingDecelerationWalking = 999999
    end

    local vel = CM.Velocity
    if not vel then return end

    local vx, vy = vel.X, vel.Y
    local speed2D = math.sqrt(vx * vx + vy * vy)

    if speed2D > SPEED_CFG.MIN_MOVE_SPEED then
        local scale = targetSpeed / speed2D
        pcall(function()
            vel.X = vx * scale
            vel.Y = vy * scale
            CM.Velocity = vel
        end)
    end
end

-- ============================================================================
-- SAFE TICK HELPER
-- ============================================================================
local function SafeTick()
    local pc = GameplayData.GetPlayerController()
    if not slua.isValid(pc) then return end
    local lp = pc:GetPlayerCharacterSafety()
    if not slua.isValid(lp) then return end
    local CM = lp.CharacterMovement
    if not slua.isValid(CM) then return end
    
    local ok, err = pcall(ApplySpeedHack, lp, CM)
    if not ok then print("[SpeedHack] Tick Error: " .. tostring(err)) end
end

-- ============================================================================
-- TICK HOOK
-- ============================================================================
local _hookInstalled = false
local function InstallSpeedHook()
    if _hookInstalled then return end
    local success = false
    
    local ok, err = pcall(function()
        local ui_util = require("client.common.ui_util")
        local gi = ui_util and ui_util.GetGameInstance and ui_util.GetGameInstance()
        local preTick = gi and gi.EnginePreTick
        if preTick and preTick.Add then
            preTick:Add(SafeTick)
            success = true
        end
    end)
    
    if not ok then print("[SpeedHack] EnginePreTick Error: " .. tostring(err)) end
    
    if not success then
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerOnce then
            local function Loop()
                if not _hookInstalled then return end
                pcall(SafeTick)
                ticker.AddTimerOnce(SPEED_CFG.TICK_INTERVAL, Loop)
            end
            ticker.AddTimerOnce(0.05, Loop)
            success = true
        end
    end
    
    if success then _hookInstalled = true end
end

-- ============================================================================
-- SETTINGS MENU
-- ============================================================================
function _G.InitSpeedHackMenu()
    if _G.SpeedHackMenuInit then return end
    _G.SpeedHackMenuInit = true

    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then LocUtil = require("client.common.LocUtil") end
    if LocUtil and not LocUtil._SpeedHacked then
        local old_get = LocUtil.GetLocalizeResStr
        LocUtil.GetLocalizeResStr = function(id)
            if type(id) == "string" and not tonumber(id) then return id end
            return old_get(id)
        end
        LocUtil._SpeedHacked = true
    end

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")

    if not SettingPageDefine.SpeedHackMenu then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
        local StackSpeedHack = {
            { Key = "ModMenu_Speed_Ex", UI = AliasMap.TitleSwitcher, 
              Text = "SPEED HACK", ExpandIndex = 0, 
              GetFunc = function() return _G.SpeedHackConfig.Enabled end, 
              SetFunc = function(c,v) _G.SpeedHackConfig.Enabled = v return true end },
            
            { Key = "ModMenu_Speed_Value", UI = AliasMap.Slider, 
              Text = "SPEED VALUE (1 = Normal, 100 = Max)", 
              ExpandHandle = "ModMenu_Speed_Ex", 
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return math.floor(_G.SpeedHackConfig.SpeedMultiplier or 100) end, 
              SetFunc = function(c,v) 
                  _G.SpeedHackConfig.SpeedMultiplier = math.floor(v + 0.5)
                  return true 
              end },
        }

        SettingPageDefine.SpeedHackMenu = {
            Key = "SpeedHackMenu",
            Text = "SPEED HACK",
            UIKey = "Setting_Page_Privacy",
            Category = { { Key = "Cat_Speed", Text = "SPEED HACK", Stack = StackSpeedHack } }
        }
        table.insert(SettingCatalog, SettingPageDefine.SpeedHackMenu)
    end

    local UIManager = _G.UIManager
    if UIManager and not UIManager._SpeedHackedUI then
        local old_ShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...)
            if config and config.keyName and string.find(string.lower(config.keyName), "setting") then
                local catalog = args[1]
                if type(catalog) == "table" then
                    local hasMenu = false
                    for _, page in ipairs(catalog) do
                        if type(page) == "table" and page.Key == "SpeedHackMenu" then hasMenu = true break end
                    end
                    if not hasMenu then table.insert(catalog, SettingPageDefine.SpeedHackMenu) end
                end
            end
            local table_unpack = table.unpack or unpack
            return old_ShowUI(config, table_unpack(args, 1, n))
        end
        UIManager._SpeedHackedUI = true
    end
end

-- ============================================================================
-- BASE METHODS
-- ============================================================================
function BRPlayerCharacterBase:ctor()
    if BRPlayerCharacterBase.__super and BRPlayerCharacterBase.__super.ctor then
        BRPlayerCharacterBase.__super.ctor(self)
    end
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
        if slua.isValid(CheckFallingDistanceComponent_C)
            and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
            Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
        end
    end

    if slua.isValid(self.STCharacterMovement) then
        self.STCharacterMovement.bPositiveBlowUp = true
    end

    if self.Role == ENetRole.ROLE_AutonomousProxy then
        self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
        self:AddControlEvent(self, "OnPawnStateEnabled",  self.OnPawnStateChange, self)
    end

    if Client then
        GameplayData.AddCharacter(self.Object)
    else
        self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
            [1] = "FinishedState"
        }, self.HandleFinishedState, self)
    end

    if Client and self.Role == ENetRole.ROLE_AutonomousProxy then
        InstallSpeedHook()
        pcall(_G.InitSpeedHackMenu)
    end
end

function BRPlayerCharacterBase:ReceiveTick(deltaTime)
    if BRPlayerCharacterBase.__super.ReceiveTick then
        BRPlayerCharacterBase.__super.ReceiveTick(self, deltaTime)
    end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
    BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)

    local CM = self.CharacterMovement
    if slua.isValid(CM) and self._origWalkSpeed then
        pcall(function()
            CM.MaxWalkSpeed = self._origWalkSpeed
        end)
    end

    if Client then GameplayData.RemoveCharacter(self.Object) end
end

function BRPlayerCharacterBase:HandleFinishedState()
    if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
        local EDynamicSimpleQueryConfigDisableMask = import("EDynamicSimpleQueryConfigDisableMask")
        self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(
            EDynamicSimpleQueryConfigDisableMask.Bit0, true)
    end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
    if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
        local GameModeType = CGameMode.GameModeType
        local GameModeID = tonumber(CGameState.GameModeID)
        local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode
            or GameModeType == EGameModeType.EFourInOneGameMode
            or GameModeType == EGameModeType.EHeavyWeaponGameMode
        local bModeIDSatisfy = not MatchModeIds[GameModeID]
        return bModeTypeSatisfy and bModeIDSatisfy
    end
    return false
end

-- ============================================================================
-- STUB METHODS
-- ============================================================================
function BRPlayerCharacterBase:OnPawnStateChange(PawnState) end
function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState) end
function BRPlayerCharacterBase:OnLanded() end
function BRPlayerCharacterBase:IsWarGameMode() return false end
function BRPlayerCharacterBase:BPOnRecycled() end
function BRPlayerCharacterBase:BPOnRespawned() end
function BRPlayerCharacterBase:ReceiveOnRecycle() if Client then GameplayData.RemoveCharacter(self.Object) end end
function BRPlayerCharacterBase:ReceiveOnSpawn() if Client then GameplayData.AddCharacter(self.Object) end end
function BRPlayerCharacterBase:HandleOnMovementModeChangedNew() end
function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord() end
function BRPlayerCharacterBase:ParachuteJump() end
function BRPlayerCharacterBase:CheckForbidFlaregun() return false end
function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue() end
function BRPlayerCharacterBase:HandleNearDeathGiveupRescue() end
function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId) end
function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId) end
function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(b) end
function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState() end
function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(b) end
function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(b) end
function BRPlayerCharacterBase:SetAreaID(id) self:SetAttrValue("AreaID", id, -1) end
function BRPlayerCharacterBase:GetAreaID() return 0 end
function BRPlayerCharacterBase:CannotChangeIntoPetSpectator() return false end
function BRPlayerCharacterBase:DoModChangeToBT() end
function BRPlayerCharacterBase:SwitchCameraToParachuteOpening() end
function BRPlayerCharacterBase:SwitchCameraToParachuteFalling() end
function BRPlayerCharacterBase:SwitchCameraToNormal() end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
    return BRPlayerCharacterBase.__super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ============================================================================
-- CLASS REGISTRATION
-- ============================================================================
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
