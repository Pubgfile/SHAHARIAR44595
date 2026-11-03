-- ===========================================================================
-- BRPlayerCharacterBase.lua - CHARACTER SPEED HACK + SETTINGS MENU
-- ===========================================================================

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

-- ===========================================================================
-- SPEED CONFIG
-- ===========================================================================
if not _G.MemoryConfig then
    _G.MemoryConfig = {
        SpeedHack    = false,
        SpeedPercent = 180,
        ServerSync   = true,
    }
end

local BASE_WALK_SPEED = 600
local BASE_FLY_SPEED  = 700

-- ===========================================================================
-- CORE SPEED LOGIC
-- ===========================================================================
local function ApplySpeedBoost(self, deltaTime)
    if not _G.MemoryConfig.SpeedHack then return end
    if self.Role ~= ENetRole.ROLE_AutonomousProxy then return end

    local CM = self.STCharacterMovement or self.CharacterMovement
    if not slua.isValid(CM) then return end

    local pct = _G.MemoryConfig.SpeedPercent or 180
    local walk = BASE_WALK_SPEED * (pct / 100.0)
    local fly  = BASE_FLY_SPEED  * (pct / 100.0)

    if self._origWalkSpeed == nil then
        self._origWalkSpeed = CM.MaxWalkSpeed or BASE_WALK_SPEED
        self._origFlySpeed  = CM.MaxFlySpeed  or BASE_FLY_SPEED
    end

    if math.abs((CM.MaxWalkSpeed or 0) - walk) > 10 then
        CM.MaxWalkSpeed = walk
    end
    if math.abs((CM.MaxFlySpeed or 0) - fly) > 10 then
        CM.MaxFlySpeed = fly
    end

    if _G.MemoryConfig.ServerSync then
        pcall(function()
            if type(self.ServerSetMovementSpeed) == "function" then
                self:ServerSetMovementSpeed(walk, fly)
            end
        end)
        pcall(function()
            if type(self.ForceNetUpdate) == "function" then
                self:ForceNetUpdate()
            end
        end)
        pcall(function()
            if slua.isValid(self.AttrModifyComp)
               and type(self.AttrModifyComp.MarkDirty) == "function" then
                self.AttrModifyComp:MarkDirty()
            end
        end)
    end
end

-- ===========================================================================
-- BASE METHODS
-- ===========================================================================
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
end

function BRPlayerCharacterBase:ReceiveTick(deltaTime)
    if BRPlayerCharacterBase.__super.ReceiveTick then
        BRPlayerCharacterBase.__super.ReceiveTick(self, deltaTime)
    end

    if Client and self.Role == ENetRole.ROLE_AutonomousProxy then
        local ok, err = pcall(ApplySpeedBoost, self, deltaTime)
        if not ok then
            print("[SpeedHack] Tick error: " .. tostring(err))
        end
    end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
    BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)

    local CM = self.STCharacterMovement or self.CharacterMovement
    if slua.isValid(CM) and self._origWalkSpeed then
        pcall(function()
            CM.MaxWalkSpeed = self._origWalkSpeed
            CM.MaxFlySpeed  = self._origFlySpeed
        end)
    end
    self._origWalkSpeed = nil
    self._origFlySpeed = nil

    if Client then GameplayData.RemoveCharacter(self.Object) end
end

-- ===========================================================================
-- STUB METHODS
-- ===========================================================================
function BRPlayerCharacterBase:HandleFinishedState()
    if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
        local M = import("EDynamicSimpleQueryConfigDisableMask")
        self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(M.Bit0, true)
    end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
    if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
        local GT = CGameMode.GameModeType
        local GID = tonumber(CGameState.GameModeID)
        local ok1 = GT == EGameModeType.ETypicalGameMode
                 or GT == EGameModeType.EFourInOneGameMode
                 or GT == EGameModeType.EHeavyWeaponGameMode
        return ok1 and not MatchModeIds[GID]
    end
    return false
end

function BRPlayerCharacterBase:OnPawnStateChange(p) end
function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(a, b) end
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
function BRPlayerCharacterBase:RPC_Server_GmPlayAction(id) end
function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(id) end
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

-- ===========================================================================
-- SETTINGS MENU (Speed Hack section)
-- ===========================================================================
local function RegisterSpeedMenu()
    local ok = pcall(function()
        local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
        local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")

        if SettingPageDefine.SpeedMenu then return end

        local menuItems = {}

        -- Toggle Speed Hack
        table.insert(menuItems, {
            Key = "ModMenu_SpeedHack_Enable",
            UI = AliasMap.Switcher,
            Text = "SPEED HACK (ON/OFF)",
            GetFunc = function()
                return _G.MemoryConfig.SpeedHack
            end,
            SetFunc = function(_, value)
                _G.MemoryConfig.SpeedHack = value
                print("[SpeedHack] Toggle: " .. tostring(value))
                return true
            end
        })

        -- Speed Percent Slider
        table.insert(menuItems, {
            Key = "ModMenu_SpeedHack_Percent",
            UI = AliasMap.Slider,
            Text = "SPEED PERCENT (100-400)",
            MinValue = 100,
            MaxValue = 400,
            min = 100,
            max = 400,
            GetFunc = function()
                return _G.MemoryConfig.SpeedPercent or 180
            end,
            SetFunc = function(_, value)
                _G.MemoryConfig.SpeedPercent = value
                print("[SpeedHack] Speed: " .. tostring(value) .. "%")
                return true
            end
        })

        -- Server Sync Toggle
        table.insert(menuItems, {
            Key = "ModMenu_SpeedHack_ServerSync",
            UI = AliasMap.Switcher,
            Text = "SERVER SYNC (anti rubber-band)",
            GetFunc = function()
                return _G.MemoryConfig.ServerSync
            end,
            SetFunc = function(_, value)
                _G.MemoryConfig.ServerSync = value
                print("[SpeedHack] ServerSync: " .. tostring(value))
                return true
            end
        })

        SettingPageDefine.SpeedMenu = {
            Key = "SpeedMenu",
            Text = "SPEED HACK",
            UIKey = "Setting_Page_Privacy",
            Category = {
                {
                    Key = "Cat_Speed",
                    Text = "CHARACTER SPEED",
                    Stack = menuItems,
                },
            },
        }

        table.insert(SettingCatalog, 1, SettingPageDefine.SpeedMenu)
        print("[SpeedHack] Settings menu registered")
    end)

    if not ok then
        print("[SpeedHack] Menu registration failed")
    end
end

-- Register menu on load
pcall(RegisterSpeedMenu)

-- ===========================================================================
-- CLASS REGISTRATION
-- ===========================================================================
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
