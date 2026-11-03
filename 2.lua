-- ═══════════════════════════════════════════════════════════════════════════
-- BRPlayerCharacterBase.lua - PERFECT FORWARD SPEED HACK (FINAL CHECKED)
-- ═══════════════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════════════
-- SPEED HACK CONFIG
-- ═══════════════════════════════════════════════════════════════════════════
_G.SpeedHackConfig = _G.SpeedHackConfig or {
    Enabled = false,
    SpeedMultiplier = 5, -- ১ থেকে ১০০ এর মধ্যে যেকোনো সংখ্যা
}

_G.SpeedHackState = _G.SpeedHackState or {
    OrigWalk = nil,
    OrigAccel = nil,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- REAL FORWARD SPEED LOGIC (ACCELERATION & INPUT OVERRIDE)
-- ═══════════════════════════════════════════════════════════════════════════
local function ApplySpeedHack(localPlayer)
    if not slua.isValid(localPlayer) then return end
    
    pcall(function()
        local CM = localPlayer.CharacterMovement
        if not slua.isValid(CM) then return end
        
        local state = _G.SpeedHackState
        local config = _G.SpeedHackConfig
        
        -- প্রথমবার গেমের অরিজিনাল স্পিড সেভ করা
        if not state.OrigWalk then
            state.OrigWalk = CM.MaxWalkSpeed or 600
            state.OrigAccel = CM.MaxAcceleration or 2048
        end
        
        if config.Enabled then
            local mult = tonumber(config.SpeedMultiplier) or 5
            if mult < 1 then mult = 1 end
            
            -- ১. স্পিড এবং ত্বরণ (Acceleration) বাড়ানো
            CM.MaxWalkSpeed = (state.OrigWalk or 600) * mult
            CM.MaxAcceleration = (state.OrigAccel or 2048) * mult
            
            -- ২. সামনের দিকে জোরপূর্বক গতি বাড়ানোর জন্য সঠিক মেথড
            local currentVel = CM.Velocity
            if currentVel then
                -- যদি ক্যারেক্টার মুভ করে (সামনে বা পেছনে)
                local speed2D = math.sqrt(currentVel.X^2 + currentVel.Y^2)
                if speed2D > 10 then
                    local dirX = currentVel.X / speed2D
                    local dirY = currentVel.Y / speed2D
                    
                    -- নতুন গতি সেট করা (এটি সামনের দিকের জন্য কাজ করবে)
                    local newSpeed = (state.OrigWalk or 600) * mult
                    CM.Velocity = FVector(dirX * newSpeed, dirY * newSpeed, currentVel.Z)
                end
            end
        else
            -- টগল অফ হলে রিসেট
            CM.MaxWalkSpeed = state.OrigWalk or 600
            CM.MaxAcceleration = state.OrigAccel or 2048
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FAST LOOP (0.01s tick for instant force)
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
        ticker.AddTimerOnce(0.01, SpeedHackTick) -- ০.০১ সেকেন্ড পর পর ফোর্স
    end
end

pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(1.0, SpeedHackTick)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- MENU (SLIDER 1 TO 100)
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
            if type(id) == "string" and not tonumber(id) then return id end
            return old_get(id)
        end
        LocUtil._IsSpeedHackMenuHooked = true
    end
    
    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    
    if not SettingPageDefine.SpeedHackMenu then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
        
        local StackSpeedHack = {
            -- Main Toggle
            { Key = "ModMenu_Speed_Ex", UI = AliasMap.TitleSwitcher, 
              Text = "⚡ SPEED HACK (1X - 100X)", ExpandIndex = 0, 
              GetFunc = function() return _G.SpeedHackConfig.Enabled end, 
              SetFunc = function(c,v) _G.SpeedHackConfig.Enabled = v return true end },
            
            -- Slider
            { Key = "ModMenu_Speed_Value", UI = AliasMap.Slider, 
              Text = "   MULTIPLIER (1=Normal, 100=Max)", 
              ExpandHandle = "ModMenu_Speed_Ex", 
              MinValue = 1, MaxValue = 100, min = 1, max = 100,
              GetFunc = function() return math.floor(_G.SpeedHackConfig.SpeedMultiplier or 5) end, 
              SetFunc = function(c,v) 
                  local val = math.floor(v + 0.5)
                  if val < 1 then val = 1 end
                  if val > 100 then val = 100 end
                  _G.SpeedHackConfig.SpeedMultiplier = val
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
                            hasMenu = true; break
                        end
                    end
                    if not hasMenu then table.insert(catalog, SettingPageDefine.SpeedHackMenu) end
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
-- BASE METHODS (বাড়তি সব রিমুভ করা)
-- ═══════════════════════════════════════════════════════════════════════════
function BRPlayerCharacterBase:ctor() end
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
  if slua.isValid(self.STCharacterMovement) then self.STCharacterMovement.bPositiveBlowUp = true end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
  end
  if Client then GameplayData.AddCharacter(self.Object) else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
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

function BRPlayerCharacterBase:OnPawnStateChange(PawnState) end
function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState) end
function BRPlayerCharacterBase:OnLanded() end
function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason) 
    BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
    if Client then GameplayData.RemoveCharacter(self.Object) end
end
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
function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState) return self.Super:SwitchWeaponCheck(Slot, IgnoreState) end

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
