-- BRPlayerCharacterBase.lua
-- ULTIMATE Server-Safe Flash + Nuclear Anti-Stuck by @MXSIFAT30MX
-- + SAFE FLASH v2 + ESP V2 + iPad View + Magic Bullet

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
-- MOD SECTION  |  Author: @MXSIFAT30MX
-- ============================================================

local AUTHOR = "@MXSIFAT30MX"

local function Notify(msg)
  local s = "[" .. AUTHOR .. "] " .. tostring(msg)
  pcall(function() if _G.GTLModNotify then _G.GTLModNotify(s) end end)
  print(s)
end

-- Helper
local _slua = rawget(_G, "slua")
local function Valid(obj)
  if not obj then return false end
  if _slua and _slua.isValid then
    local ok, v = pcall(_slua.isValid, obj)
    if not ok or not v then return false end
  end
  return true
end

-- CONFIG (Flash + Plus + Safe Flash + ESP + iPad + Magic)
_G.GTLModConfig = _G.GTLModConfig or {
  -- Flash
  FlashEnabled = false,
  FlashSpeed = 400,
  FlashVelocityBoost = 3.5,
  -- Plus
  PlusEnabled = false,
  PlusSpeed = 500,
  PlusBoost = 4.5,
  FlashTimeDilation = 1.4,
  SmoothMode = true,
  AntiStuckMode = true,
  NuclearEscape = true,
  -- SAFE FLASH v2
  SafeFlashEnabled = false,
  SafeFlashSpeed = 400,
  SafeFlashBoost = 3.0,
  SafeFlashTimeDilation = 1.20,
  -- ESP V2
  EspV2Enabled = true,
  EspV2Counter = true,
  EspV2Name = true,
  EspV2Health = true,
  EspV2Bracket = true,
  EspV2SnapLine = false,
  EspV2Distance = true,
  EspV2Offscreen = true,
  EspRange = 250,
  EspMaxEnemies = 20,
  -- iPad View
  IpadView = false,
  IpadViewFOV = 120,
  -- Magic Bullet
  CustomMagicBullet = false,
  MagicHead = 1.0,
  MagicBody = 1.0,
  MagicLegs = 1.0,
}

-- Add new keys if config was already initialized by a previous mod
local _cfg = _G.GTLModConfig
if _cfg.EspV2Enabled == nil then _cfg.EspV2Enabled = true end
if _cfg.EspV2Counter == nil then _cfg.EspV2Counter = true end
if _cfg.EspV2Name == nil then _cfg.EspV2Name = true end
if _cfg.EspV2Health == nil then _cfg.EspV2Health = true end
if _cfg.EspV2Bracket == nil then _cfg.EspV2Bracket = true end
if _cfg.EspV2SnapLine == nil then _cfg.EspV2SnapLine = false end
if _cfg.EspV2Distance == nil then _cfg.EspV2Distance = true end
if _cfg.EspV2Offscreen == nil then _cfg.EspV2Offscreen = true end
if _cfg.EspRange == nil then _cfg.EspRange = 250 end
if _cfg.EspMaxEnemies == nil then _cfg.EspMaxEnemies = 20 end
if _cfg.IpadView == nil then _cfg.IpadView = false end
if _cfg.IpadViewFOV == nil then _cfg.IpadViewFOV = 120 end
if _cfg.CustomMagicBullet == nil then _cfg.CustomMagicBullet = false end
if _cfg.MagicHead == nil then _cfg.MagicHead = 1.0 end
if _cfg.MagicBody == nil then _cfg.MagicBody = 1.0 end
if _cfg.MagicLegs == nil then _cfg.MagicLegs = 1.0 end

_G.GTLModState = _G.GTLModState or { LoopToken = 0, MagicLastHash = "", MagicVersion = 0 }
if _G.GTLModState.MagicLastHash == nil then _G.GTLModState.MagicLastHash = "" end
if _G.GTLModState.MagicVersion == nil then _G.GTLModState.MagicVersion = 0 end

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
    if serverTime and serverTime > 1700000000 then currentTime = serverTime end
  end
end)
isExpired = (currentTime > limitTime)

-- ============================================================
--  MOVEMENT CORE  |  by @MXSIFAT30MX
-- ============================================================
local TXtime_ticker = require('common.time_ticker')

local CFG = { Enabled = false, Multiplier = 400.0, VelocityBoost = 3.5, DEBUG = true }
_G.XThrlen_Config = CFG
_G.XThrlen_Enabled = false
_G.XThrlen_PlusEnabled = false
_G.XThrlen_SafeEnabled = false

local S = {
    char = nil,
    lastAnyOn = false,
    toggleGraceUntil = 0,
    kickTicks = 0,
    velBuildStuckTimer = 0,
    stuckTimer = 0,
    lastEscapeTime = 0,
    escapeAttempt = 0,
    lastSentPos = nil,
    lastSentTime = 0,
    pullbackCooldown = 0,
    pullbackCount = 0,
    lastTeleportTime = 0,
    teleportCount = 0,
    sfPosHistory = {},
    sfStuckTimer = 0,
    sfLastEscape = 0,
    sfEscapeAttempt = 0,
    sfPullbackCooldown = 0,
    sfLastSentPos = nil,
    sfLastSentTime = 0,
    sfMatchGraceUntil = 0,
    velHistory = {},
}

local Orig = {
    loaded = false,
    char = nil,
    MaxAcceleration = nil,
    MaxWalkSpeed = nil,
    MaxSprintSpeed = nil,
    GroundFriction = nil,
    BrakingDecelerationWalking = nil,
    AirControl = nil,
    CustomTimeDilation = nil,
}

local function PLog(msg) print("[" .. AUTHOR .. "] " .. tostring(msg)) end

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

local function SaveOriginal(ch, cm)
    if Orig.loaded and Orig.char == ch then return end
    pcall(function()
        Orig.char = ch
        Orig.MaxAcceleration = cm.MaxAcceleration
        Orig.MaxWalkSpeed = cm.MaxWalkSpeed
        Orig.MaxSprintSpeed = cm.MaxSprintSpeed
        Orig.GroundFriction = cm.GroundFriction
        Orig.BrakingDecelerationWalking = cm.BrakingDecelerationWalking
        Orig.AirControl = cm.AirControl
        Orig.CustomTimeDilation = ch.CustomTimeDilation
        Orig.loaded = true
    end)
end

local function RestoreOriginal(ch, cm)
    if not Orig.loaded or Orig.char ~= ch then return end
    pcall(function()
        ch.CustomTimeDilation = Orig.CustomTimeDilation or 1.0
        if Orig.MaxAcceleration ~= nil then cm.MaxAcceleration = Orig.MaxAcceleration end
        if Orig.MaxWalkSpeed ~= nil then cm.MaxWalkSpeed = Orig.MaxWalkSpeed end
        if Orig.MaxSprintSpeed ~= nil then cm.MaxSprintSpeed = Orig.MaxSprintSpeed end
        if Orig.GroundFriction ~= nil then cm.GroundFriction = Orig.GroundFriction end
        if Orig.BrakingDecelerationWalking ~= nil then cm.BrakingDecelerationWalking = Orig.BrakingDecelerationWalking end
        if Orig.AirControl ~= nil then cm.AirControl = Orig.AirControl end
    end)
    Orig.loaded = false
    Orig.char = nil
end

local function NuclearEscape(ch, iX, iY)
    pcall(function()
        local loc = ch:K2_GetActorLocation()
        if not loc then return end
        local iMag = math.sqrt(iX*iX + iY*iY)
        if iMag < 0.1 then iX, iY, iMag = 1, 0, 1 end
        local ux, uy = iX/iMag, iY/iMag
        local attempts = {
            { ux, uy, 150 }, { ux, uy, 250 },
            { -uy, ux, 200 }, { uy, -ux, 200 },
        }
        for _, a in ipairs(attempts) do
            local dx, dy, dist = a[1], a[2], a[3]
            local newX = loc.X + dx * dist + (math.random() - 0.5) * 60
            local newY = loc.Y + dy * dist + (math.random() - 0.5) * 60
            local newZ = loc.Z + 80
            local ok = pcall(function()
                ch:K2_SetActorLocation(FVector(newX, newY, newZ), false, nil, true)
            end)
            if ok then
                S.lastTeleportTime = os.clock()
                S.teleportCount = S.teleportCount + 1
                S.posHistory = {}
                return
            end
        end
    end)
end

local function TickInner(dt)
    local cfg = _G.GTLModConfig
    local flashOn = cfg.FlashEnabled == true
    local plusOn  = cfg.PlusEnabled == true
    local safeOn  = cfg.SafeFlashEnabled == true
    local anyOn = flashOn or plusOn or safeOn
    local now = os.clock()

    if anyOn ~= S.lastAnyOn then
        if not anyOn then
            if S.char then
                local cm = nil
                pcall(function() cm = S.char.STCharacterMovement or S.char.CharacterMovement end)
                if cm and slua.isValid(cm) then
                    RestoreOriginal(S.char, cm)
                    pcall(function()
                        if cm.Velocity then
                            local v = cm.Velocity
                            cm.Velocity = FVector(v.X * 0.5, v.Y * 0.5, v.Z)
                        end
                    end)
                end
                S.char = nil
                S.posHistory = {}
                S.sfPosHistory = {}
            end
        end
        S.lastAnyOn = anyOn
    end

    if not anyOn then return end

    local ch = GetMyChar()
    if not ch then S.char = nil return end

    if ch ~= S.char then
        if S.char and Orig.loaded and Orig.char == S.char then
            local oldCm = nil
            pcall(function() oldCm = S.char.STCharacterMovement or S.char.CharacterMovement end)
            if oldCm and slua.isValid(oldCm) then RestoreOriginal(S.char, oldCm) end
        end
        S.char = ch
        S.sfMatchGraceUntil = now + 3.0
        Orig.loaded = false
        Orig.char = nil
        S.posHistory = {}
        S.sfPosHistory = {}
        S.velHistory = {}
        S.stuckTimer = 0
        S.sfStuckTimer = 0
        S.escapeAttempt = 0
        S.sfEscapeAttempt = 0
        S.pullbackCooldown = 0
        S.sfPullbackCooldown = 0
        S.lastSentPos = nil
        S.sfLastSentPos = nil
        S.kickTicks = 3
        S.toggleGraceUntil = now + 0.15
        S.velBuildStuckTimer = 0
    end

    local cm = nil
    pcall(function() cm = ch.STCharacterMovement or ch.CharacterMovement end)
    if not cm or not slua.isValid(cm) then return end

    local inVeh = false
    pcall(function()
        local veh = ch.CurrentVehicle
        if veh and slua.isValid(veh) then inVeh = true end
    end)
    if inVeh then return end

    local vx, vy, vz = 0, 0, 0
    pcall(function()
        local v = cm.Velocity
        if v then
            vx = tonumber(v.X) or 0
            vy = tonumber(v.Y) or 0
            vz = tonumber(v.Z) or 0
        end
    end)
    local velMag = math.sqrt(vx * vx + vy * vy)

    local hasInput = false
    local iX, iY = 0, 0
    pcall(function()
        local acc = cm.Acceleration or cm.CurrentAcceleration
        if acc then
            local ax = tonumber(acc.X) or 0
            local ay = tonumber(acc.Y) or 0
            if math.abs(ax) > 1.0 or math.abs(ay) > 1.0 then
                hasInput = true
                iX, iY = ax, ay
            end
        end
    end)

    if not hasInput and velMag > 80 then
        table.insert(S.velHistory, velMag)
        if #S.velHistory > 12 then table.remove(S.velHistory, 1) end
        if #S.velHistory >= 12 then
            local vmin, vmax = S.velHistory[1], S.velHistory[1]
            for _, v in ipairs(S.velHistory) do
                if v < vmin then vmin = v end
                if v > vmax then vmax = v end
            end
            if (vmax - vmin) < 60 then
                hasInput = true
                iX, iY = vx, vy
            end
        end
    elseif hasInput then
        S.velHistory = {}
    end

    local isGrounded = false
    pcall(function()
        local mm = cm.MovementMode
        if mm == 1 or mm == 2 then isGrounded = true end
    end)

    local currentPos = nil
    pcall(function() currentPos = ch:K2_GetActorLocation() end)

    -- ============================================================
    -- SAFE FLASH v2
    -- ============================================================
    if safeOn then
        local td = tonumber(cfg.SafeFlashTimeDilation) or 1.20
        local smooth = (cfg.SmoothMode ~= false)
        local antiStuck = (cfg.AntiStuckMode ~= false)

        if not Orig.loaded or Orig.char ~= ch then
            pcall(function()
                Orig.char = ch
                Orig.CustomTimeDilation = ch.CustomTimeDilation
                Orig.loaded = true
            end)
        end

        pcall(function() ch.CustomTimeDilation = td end)

        if now < S.sfMatchGraceUntil then
            if currentPos then
                S.sfLastSentPos = { x = currentPos.X, y = currentPos.Y }
                S.sfLastSentTime = now
            end
            return
        end

        if currentPos and S.sfLastSentPos then
            local pdx = currentPos.X - S.sfLastSentPos.x
            local pdy = currentPos.Y - S.sfLastSentPos.y
            local pdist = math.sqrt(pdx*pdx + pdy*pdy)
            local timeDelta = now - S.sfLastSentTime
            if pdist > 350 and timeDelta < 0.3 and velMag > 250 then
                S.sfPullbackCooldown = now + 0.5
                S.sfPosHistory = {}
                S.sfLastSentPos = nil
                PLog("SAFE PULLBACK")
            end
        end
        if now < S.sfPullbackCooldown then return end

        if now < S.toggleGraceUntil then
            if S.kickTicks > 0 and hasInput then
                S.kickTicks = S.kickTicks - 1
                pcall(function()
                    local iMag = math.sqrt(iX*iX + iY*iY)
                    if iMag > 0.1 then
                        cm.Velocity = FVector(iX/iMag * 500, iY/iMag * 500, math.max(vz, 150))
                    end
                end)
            end
            return
        end

        if hasInput and velMag < 300 then
            local iMag = math.sqrt(iX*iX + iY*iY)
            if iMag > 0.5 then
                local ux, uy = iX/iMag, iY/iMag
                local targetSpd = 650
                local tvx, tvy = ux * targetSpd, uy * targetSpd
                pcall(function()
                    local lerp = math.min(1.0, dt * (smooth and 10.0 or 20.0))
                    cm.Velocity = FVector(
                        vx + (tvx - vx) * lerp,
                        vy + (tvy - vy) * lerp,
                        vz
                    )
                end)
            end
        end

        if antiStuck and hasInput and currentPos then
            table.insert(S.sfPosHistory, {
                x = currentPos.X, y = currentPos.Y,
                vx = vx, vy = vy, t = now
            })
            if #S.sfPosHistory > 18 then table.remove(S.sfPosHistory, 1) end

            if #S.sfPosHistory >= 12 then
                local oldest = S.sfPosHistory[1]
                local timeDelta = now - oldest.t
                if timeDelta > 0.3 and timeDelta < 2.0 then
                    local dx = currentPos.X - oldest.x
                    local dy = currentPos.Y - oldest.y
                    local actualDist = math.sqrt(dx*dx + dy*dy)
                    local avgVx = (vx + oldest.vx) * 0.5
                    local avgVy = (vy + oldest.vy) * 0.5
                    local avgVel = math.sqrt(avgVx*avgVx + avgVy*avgVy)
                    local expectedDist = avgVel * timeDelta

                    local isStuck = false
                    if expectedDist > 100 and actualDist < expectedDist * 0.4 then
                        isStuck = true
                    elseif expectedDist < 100 and actualDist < 12 then
                        isStuck = true
                    end

                    if isStuck then
                        S.sfStuckTimer = S.sfStuckTimer + dt
                        if S.sfStuckTimer > 0.35 and (now - S.sfLastEscape) > 1.0 then
                            S.sfEscapeAttempt = math.min(S.sfEscapeAttempt + 1, 3)
                            S.sfLastEscape = now
                            S.sfStuckTimer = 0
                            PLog("SAFE ESCAPE #" .. S.sfEscapeAttempt)
                            pcall(function()
                                local iMag = math.sqrt(iX*iX + iY*iY)
                                local ux, uy = iX, iY
                                if iMag < 0.1 then ux, uy, iMag = vx, vy, velMag end
                                if iMag < 0.1 then ux, uy, iMag = 1, 0, 1 end
                                ux, uy = ux/iMag, uy/iMag
                                local pushSpd = math.min(600 + S.sfEscapeAttempt * 80, 780)
                                local pushUp = math.min(200 + S.sfEscapeAttempt * 80, 400)
                                cm.Velocity = FVector(ux * pushSpd, uy * pushSpd, math.max(vz, pushUp))
                            end)
                            S.sfPosHistory = {}
                        end
                    else
                        S.sfStuckTimer = 0
                        if (now - S.sfLastEscape) > 2.5 then S.sfEscapeAttempt = 0 end
                    end
                end
            end

            S.sfLastSentPos = { x = currentPos.X, y = currentPos.Y }
            S.sfLastSentTime = now
        else
            S.sfStuckTimer = 0
            S.sfPosHistory = {}
        end
        return
    end

    -- ============================================================
    -- FLASH / PLUS (aggressive)
    -- ============================================================
    if not Orig.loaded or Orig.char ~= ch then
        SaveOriginal(ch, cm)
    end

    local plus = plusOn
    local mult, boost
    if plus then
        mult  = tonumber(cfg.PlusSpeed) or 500
        boost = tonumber(cfg.PlusBoost) or 4.5
    else
        mult  = tonumber(cfg.FlashSpeed) or 400
        boost = tonumber(cfg.FlashVelocityBoost) or 3.5
    end
    local td = tonumber(cfg.FlashTimeDilation) or 1.4
    local smooth = (cfg.SmoothMode ~= false)
    local antiStuck = (cfg.AntiStuckMode ~= false)
    local nuclear = (cfg.NuclearEscape ~= false)

    pcall(function() ch.CustomTimeDilation = td end)

    pcall(function()
        cm.MaxAcceleration = 2048.0
        cm.MaxWalkSpeed = 600.0
        cm.MaxSprintSpeed = 800.0
        cm.GroundFriction = 8.0
        cm.BrakingDecelerationWalking = 2048.0
        cm.AirControl = 0.05
    end)

    if currentPos and S.lastSentPos then
        local pdx = currentPos.X - S.lastSentPos.x
        local pdy = currentPos.Y - S.lastSentPos.y
        local pdist = math.sqrt(pdx*pdx + pdy*pdy)
        local timeDelta = now - S.lastSentTime
        if pdist > 300 and timeDelta < 0.3 and velMag > 200 then
            S.pullbackCount = S.pullbackCount + 1
            S.pullbackCooldown = now + 0.6
            S.posHistory = {}
            S.lastSentPos = nil
            PLog("PULLBACK (count=" .. S.pullbackCount .. ")")
        end
    end
    if now < S.pullbackCooldown then return end

    if now < S.toggleGraceUntil then
        if S.kickTicks > 0 and hasInput then
            S.kickTicks = S.kickTicks - 1
            pcall(function()
                local iMag = math.sqrt(iX*iX + iY*iY)
                if iMag > 0.1 then
                    cm.Velocity = FVector(iX/iMag * 600, iY/iMag * 600, math.max(vz, 300.0))
                end
            end)
        end
        return
    end

    if hasInput then
        local iMag = math.sqrt(iX * iX + iY * iY)
        if iMag > 0.5 then
            local ux, uy = iX / iMag, iY / iMag
            local speedFactor = (mult / 100.0) * boost
            if speedFactor < 1.0 then speedFactor = 1.0 end
            local targetSpeed = 600 * speedFactor
            local cap = 780.0
            if targetSpeed > cap then targetSpeed = cap end
            local tvx = ux * targetSpeed
            local tvy = uy * targetSpeed
            pcall(function()
                if smooth then
                    local lerp = math.min(1.0, dt * 20.0)
                    cm.Velocity = FVector(
                        vx + (tvx - vx) * lerp,
                        vy + (tvy - vy) * lerp,
                        vz
                    )
                else
                    cm.Velocity = FVector(tvx, tvy, vz)
                end
            end)
        end
    else
        if isGrounded and velMag > 5 then
            pcall(function()
                local damp = math.exp(-dt * 22.0)
                cm.Velocity = FVector(vx * damp, vy * damp, vz)
            end)
        end
    end

    if antiStuck and hasInput then
        if velMag < 100 then
            S.velBuildStuckTimer = S.velBuildStuckTimer + dt
            if S.velBuildStuckTimer > 0.15 then
                pcall(function()
                    local iMag = math.sqrt(iX*iX + iY*iY)
                    if iMag > 0.1 then
                        cm.Velocity = FVector(iX/iMag * 600, iY/iMag * 600, math.max(vz, 400.0))
                    end
                end)
                S.velBuildStuckTimer = 0
                S.posHistory = {}
            end
        else
            S.velBuildStuckTimer = 0
        end
    else
        S.velBuildStuckTimer = 0
    end

    if antiStuck and hasInput and currentPos then
        table.insert(S.posHistory, { x = currentPos.X, y = currentPos.Y })
        if #S.posHistory > 6 then table.remove(S.posHistory, 1) end

        local hStuck = false
        if #S.posHistory >= 6 then
            local oldest = S.posHistory[1]
            local hdx = currentPos.X - oldest.x
            local hdy = currentPos.Y - oldest.y
            hStuck = (math.sqrt(hdx*hdx + hdy*hdy) < 25.0)
        end

        if hStuck then
            S.stuckTimer = S.stuckTimer + dt
            if S.stuckTimer > 0.12 and (now - S.lastEscapeTime) > 0.15 then
                S.escapeAttempt = math.min(S.escapeAttempt + 1, 3)
                S.lastEscapeTime = now

                if S.escapeAttempt <= 2 then
                    pcall(function()
                        local iMag = math.sqrt(iX*iX + iY*iY)
                        local ux, uy = iX, iY
                        if iMag < 0.1 then ux, uy, iMag = vx, vy, velMag end
                        if iMag < 0.1 then ux, uy, iMag = 1, 0, 1 end
                        ux, uy = ux/iMag, uy/iMag
                        local px, py = -uy, ux
                        local side = (math.random() > 0.5) and 1 or -1
                        local fwd = (S.escapeAttempt == 1) and 700 or 900
                        local perp = (S.escapeAttempt == 1) and 400 or 600
                        cm.Velocity = FVector(
                            ux * fwd + px * side * perp,
                            uy * fwd + py * side * perp,
                            math.max(vz, 500.0)
                        )
                    end)
                    S.posHistory = {}
                    S.stuckTimer = 0
                end

                if S.escapeAttempt >= 3 and nuclear then
                    if (now - S.lastTeleportTime) > 0.4 then
                        PLog("NUCLEAR TELEPORT")
                        NuclearEscape(ch, iX, iY)
                        S.stuckTimer = 0
                        S.escapeAttempt = 0
                    end
                end
            end
        else
            S.stuckTimer = 0
            if (now - S.lastEscapeTime) > 1.0 then S.escapeAttempt = 0 end
        end

        S.lastSentPos = { x = currentPos.X, y = currentPos.Y }
        S.lastSentTime = now
    else
        S.stuckTimer = 0
        S.posHistory = {}
        if (now - S.lastEscapeTime) > 1.0 then S.escapeAttempt = 0 end
    end
end

local function Tick(dt) pcall(TickInner, dt) end

if TXtime_ticker then
    _G.XThrlen_TimerIndex = TXtime_ticker.AddTimerLoop(0, Tick, -1, 0)
    PLog('ULTIMATE Flash + Safe Flash v2 + ESP + iPad + Magic loaded by ' .. AUTHOR)
else
    PLog('ERROR: time_ticker Not Found')
end

function _G.XThrlen_Speed(mult)
    mult = tonumber(mult) or 400.0
    CFG.Multiplier = mult
    PLog(string.format('SPEED x%.1f', mult))
end

-- ============================================================
-- ESP V2 (CLEAR VISION)
-- ============================================================
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
    Gold        = Color(1.00, 0.84, 0.42, 1.00),
    GoldBright  = Color(1.00, 0.92, 0.62, 1.00),
    GoldSoft    = Color(1.00, 0.90, 0.56, 0.42),
    GoldDim     = Color(0.36, 0.25, 0.055, 0.96),
    White       = Color(0.98, 0.98, 0.98, 1.00),
    Dark2       = Color(0.045, 0.045, 0.055, 0.97),
    Gray        = Color(0.42, 0.42, 0.42, 1.00),
    RedBright   = Color(1.00, 0.28, 0.28, 1.00),
    RedSoft     = Color(1.00, 0.28, 0.28, 0.30),
    RedDim      = Color(0.25, 0.02, 0.02, 0.95),
    GreenBright = Color(0.38, 1.00, 0.50, 1.00),
    GreenSoft   = Color(0.38, 1.00, 0.50, 0.28),
    GreenDim    = Color(0.03, 0.20, 0.05, 0.96),
    BloodRed       = Color(0.84, 0.010, 0.018, 1.00),
    BloodRedBright = Color(1.00, 0.025, 0.040, 1.00),
    BloodRedSoft   = Color(1.00, 0.24, 0.22, 0.46),
    BloodRedDim    = Color(0.26, 0.002, 0.008, 0.98),
    BloodRedShade  = Color(0.10, 0.000, 0.004, 0.66),
    Yellow         = Color(1.00, 0.76, 0.000, 1.00),
    YellowBright   = Color(1.00, 0.96, 0.10, 1.00),
    YellowSoft     = Color(1.00, 0.88, 0.20, 0.48),
    YellowDim      = Color(0.48, 0.27, 0.000, 0.98),
    YellowShade    = Color(0.16, 0.075, 0.000, 0.66),
    BotRedText     = Color(0.94, 0.010, 0.020, 1.00),
  }

  local ClearVisionV2 = rawget(_G, "__CLEAR_VISION_ESP_V2")
  local CV2_BUILD = "cv-esp-v2-matchfix-r2-033"

  if type(ClearVisionV2) == "table" and ClearVisionV2.Build ~= CV2_BUILD
      and type(ClearVisionV2.Stop) == "function" then
    pcall(ClearVisionV2.Stop)
  end

  if type(ClearVisionV2) ~= "table" or ClearVisionV2.Build ~= CV2_BUILD then
    ClearVisionV2 = {
      Build = CV2_BUILD,
      Active = false,
      ESPCanvas = nil,
      Controller = nil,
      LocalPawn = nil,
      EnemyCache = {},
      EnemyWidgets = {},
      MaxEnemies = 20,
      RangeMeters = 250.0,
      ScanInterval = 1.0,
      DrawInterval = 0.0167,
      _CanvasScaleX = 1.0,
      _CanvasScaleY = 1.0,
      _CanvasOffsetX = 0.0,
      _CanvasOffsetY = 0.0,
      _CachedViewportW = 1920,
      _CachedViewportH = 1080,
      _CapsuleCache = setmetatable({}, {__mode="k"}),
      _ProjectionCache = {},
      EnemyMeta = {},
      RealEnemyCount = 0,
      BotEnemyCount = 0,
      Counter = nil,
      _FrameSerial = 0,
      _TransformEveryNFrames = 6,
      _CounterEveryNFrames = 6,
      _TimerGeneration = 0,
    }
    _G.__CLEAR_VISION_ESP_V2 = ClearVisionV2
  else
    ClearVisionV2.DrawInterval = 0.0167
    ClearVisionV2.ScanInterval = ClearVisionV2.ScanInterval or 1.0
    ClearVisionV2._FrameSerial = ClearVisionV2._FrameSerial or 0
    ClearVisionV2._TransformEveryNFrames = ClearVisionV2._TransformEveryNFrames or 6
    ClearVisionV2._CounterEveryNFrames = ClearVisionV2._CounterEveryNFrames or 6
    ClearVisionV2._TimerGeneration = ClearVisionV2._TimerGeneration or 0
  end

  local REF_W = 688.0
  local REF_H = 996.0
  local REF_BODY_TOP = 172.0
  local REF_BODY_BOTTOM = 900.0
  local REF_BODY_SPAN = REF_BODY_BOTTOM - REF_BODY_TOP

  local function SetVisible(widget, visible)
    if not IsValid(widget) then return false end
    local vis = visible and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed
    local ok = pcall(function() widget:SetWidgetVisibility(vis) end)
    return ok
  end

  local function SetTextColor(widget, linearColor)
    if not IsValid(widget) then return false end
    local ok = pcall(function()
      local FSlateColor = nil
      pcall(function()
        FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
      end)
      if FSlateColor then widget:SetColorAndOpacity(FSlateColor(linearColor))
      else widget:SetColorAndOpacity(linearColor) end
    end)
    return ok
  end

  local function SetFontSize(widget, size)
    if not IsValid(widget) then return false end
    local ok = pcall(function()
      if widget.Font then
        local f = widget.Font
        f.Size = math.max(5, math.floor(size + 0.5))
        widget:SetFont(f)
      end
    end)
    return ok
  end

  local function SetFontBold(widget)
    if not IsValid(widget) then return false end
    local ok = pcall(function()
      if widget.Font then
        local f = widget.Font
        pcall(function() f.TypefaceFontName = "Bold" end)
        pcall(function() f.FontName = "Bold" end)
        widget:SetFont(f)
      end
    end)
    return ok
  end

  local function DestroyWidget(widget)
    if not widget then return end
    pcall(function() widget:RemoveFromParent() end)
    pcall(function() widget:ConditionalBeginDestroy() end)
  end

  local function GetWorldSafe()
    local world=nil
    pcall(function()
      if slua and slua.getWorld then world=slua.getWorld() end
    end)
    return world
  end

  local function ResolveControllerFresh()
    local pc=nil
    pcall(function()
      if GameplayData and GameplayData.GetPlayerController then
        pc=GameplayData.GetPlayerController()
      end
    end)
    if not IsValid(pc) then
      pcall(function()
        if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
          pc=slua_GameFrontendHUD:GetPlayerController()
        end
      end)
    end
    return IsValid(pc) and pc or nil
  end

  local function GetController()
    local fresh=ResolveControllerFresh()
    if IsValid(fresh) then
      if ClearVisionV2.Controller~=fresh then
        ClearVisionV2.Controller=fresh
        ClearVisionV2.LocalPawn=nil
      end
      return fresh
    end
    local cached=ClearVisionV2.Controller
    return IsValid(cached) and cached or nil
  end

  local function ResolveLocalPawnFresh(pc)
    local pawn=nil
    pcall(function()
      if GameplayData and GameplayData.GetPlayerCharacter then
        pawn=GameplayData.GetPlayerCharacter()
      end
    end)
    if not IsValid(pawn) then
      pcall(function()
        if GameplayData and GameplayData.GetLocalCharacter then
          pawn=GameplayData.GetLocalCharacter()
        end
      end)
    end
    if not IsValid(pawn) and IsValid(pc) then
      pcall(function()
        if pc.GetPlayerCharacterSafety then pawn=pc:GetPlayerCharacterSafety() end
      end)
    end
    if not IsValid(pawn) and IsValid(pc) then
      pcall(function()
        if pc.GetPawn then pawn=pc:GetPawn() end
      end)
    end
    return IsValid(pawn) and pawn or nil
  end

  local function GetLocalPawn(pc)
    local fresh=ResolveLocalPawnFresh(pc)
    if IsValid(fresh) then
      ClearVisionV2.LocalPawn=fresh
      return fresh
    end
    local cached=ClearVisionV2.LocalPawn
    return IsValid(cached) and cached or nil
  end

  local function GetActorLocation(actor)
    if not IsValid(actor) then return nil end
    local loc = nil
    pcall(function()
      if actor.K2_GetActorLocation then loc = actor:K2_GetActorLocation()
      elseif actor.GetActorLocation then loc = actor:GetActorLocation() end
    end)
    return loc
  end

  local function DistanceMeters(a, b)
    if not a or not b then return math.huge end
    local dx = (a.X or 0) - (b.X or 0)
    local dy = (a.Y or 0) - (b.Y or 0)
    local dz = (a.Z or 0) - (b.Z or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz) / 100.0
  end

  local function GetPlayerState(character)
    if not IsValid(character) then return nil end
    local ps = nil
    pcall(function()
      if character.GetPlayerStateSafety then ps = character:GetPlayerStateSafety() end
    end)
    if not IsValid(ps) then pcall(function()
      if character.GetPlayerState then ps = character:GetPlayerState() end
    end) end
    if not IsValid(ps) then pcall(function() ps = character.PlayerState end) end
    return IsValid(ps) and ps or nil
  end

  local function GetTeamID(character)
    if not IsValid(character) then return nil end
    local team = nil
    pcall(function()
      if character.GetTeamID then team = character:GetTeamID() end
    end)
    if team == nil then
      local ps = GetPlayerState(character)
      if ps then
        pcall(function() if ps.GetTeamID then team = ps:GetTeamID() end end)
        if team == nil then pcall(function() team = ps.TeamID end) end
      end
    end
    if team == nil then pcall(function() team = character.TeamID end) end
    return team
  end

  local function IsAlive(character)
    if not IsValid(character) then return false end
    local ok, alive = pcall(function()
      if type(character.IsAlive) == "function" then return character:IsAlive() end
    end)
    if ok and type(alive) == "boolean" then return alive end
    local hp = nil
    pcall(function()
      if character.Health ~= nil then hp = character.Health
      elseif character.HP ~= nil then hp = character.HP
      elseif character.GetHealth then hp = character:GetHealth() end
    end)
    hp = tonumber(hp)
    return hp ~= nil and hp == hp and hp > 0
  end

  local function GetHealthPercent(character)
    local hp, maxHp = nil, nil
    pcall(function()
      if character.Health ~= nil then hp = character.Health
      elseif character.HP ~= nil then hp = character.HP
      elseif character.GetHealth then hp = character:GetHealth() end
      if character.MaxHealth ~= nil then maxHp = character.MaxHealth
      elseif character.HealthMax ~= nil then maxHp = character.HealthMax
      elseif character.MaxHP ~= nil then maxHp = character.MaxHP
      elseif character.GetHealthMax then maxHp = character:GetHealthMax()
      elseif character.GetMaxHealth then maxHp = character:GetMaxHealth() end
    end)
    hp = tonumber(hp) or 0
    maxHp = tonumber(maxHp) or 100
    if maxHp <= 0 then maxHp = 100 end
    local pct = hp / maxHp
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    return pct
  end

  local function GetPlayerKey(character)
    local key = nil
    pcall(function()
      if character.GetPlayerKey then key = character:GetPlayerKey() end
    end)
    if key == nil then pcall(function() key = character.PlayerKey end) end
    if key == nil then
      local ps = GetPlayerState(character)
      if ps then pcall(function() key = ps.PlayerKey end) end
    end
    return key
  end

  local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end

  local function GetPlayerName(character)
    if not IsValid(character) then return "ENEMY", false end
    local name = nil
    local function accept(value)
      if value == nil or value == false then return end
      local ok, txt = pcall(tostring, value)
      if ok and txt ~= "" and txt ~= "nil" and txt ~= "None" then name = txt end
    end
    pcall(function()
      if type(character.GetPlayerNameSafety) == "function" then accept(character:GetPlayerNameSafety()) end
    end)
    if not name then
      pcall(function()
        if type(character.GetPlayerName) == "function" then accept(character:GetPlayerName()) end
      end)
    end
    if not name then
      local ps = GetPlayerState(character)
      if ps then
        pcall(function()
          if type(ps.GetPlayerName) == "function" then accept(ps:GetPlayerName()) end
        end)
        if not name then pcall(function() accept(ps.PlayerName) end) end
        if not name then pcall(function() accept(ps.PlayerNamePrivate) end) end
      end
    end
    if name then return name, true end
    return "ENEMY", false
  end

  local function IsAI(character)
    if not IsValid(character) then return false end
    local isAI, hasSignal = false, false
    local function accept(v)
      if v == true or v == 1 then isAI, hasSignal = true, true
      elseif v == false or v == 0 then hasSignal = true end
    end
    local function field(obj, k)
      if not obj then return end
      pcall(function() accept(obj[k]) end)
    end
    local function method(obj, k)
      if not obj then return end
      pcall(function()
        local fn = obj[k]
        if type(fn) == "function" then accept(fn(obj)) end
      end)
    end
    pcall(function() if Game and Game.IsAI then accept(Game:IsAI(character)) end end)
    if not isAI then field(character, "bIsAI") end
    if not isAI then field(character, "IsAI") end
    if not isAI then method(character, "IsBot") end
    if not isAI then
      local ps = GetPlayerState(character)
      if ps then
        field(ps, "bIsABot")
        if not isAI then field(ps, "bIsBot") end
        if not isAI then field(ps, "bIsAI") end
        if not isAI then method(ps, "IsBot") end
      end
    end
    return isAI == true
  end

  local function GetViewportSize(pc)
    local w, h = 0, 0
    pcall(function()
      if pc and pc.GetViewportSize then
        local v = V2(0,0)
        pc:GetViewportSize(v)
        if v and type(v.X)=="number" and type(v.Y)=="number" then w,h=v.X,v.Y end
      end
    end)
    if w <= 200 then
      pcall(function()
        if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportSize then
          local v=WidgetLayoutLibrary.GetViewportSize(pc)
          if v and type(v.X)=="number" and type(v.Y)=="number" then w,h=v.X,v.Y end
        end
      end)
    end
    if w <= 200 then w,h=ClearVisionV2._CachedViewportW or 1920,ClearVisionV2._CachedViewportH or 1080 end
    ClearVisionV2._CachedViewportW,ClearVisionV2._CachedViewportH=w,h
    return w,h
  end

  local function GetCharacterBounds(character)
    if not IsValid(character) then return nil, nil end
    local center, halfHeight = nil, nil

    local capsule = ClearVisionV2._CapsuleCache[character]
    if not IsValid(capsule) then
      capsule = nil
      pcall(function()
        if character.GetCapsuleComponent then capsule = character:GetCapsuleComponent()
        elseif character.CapsuleComponent then capsule = character.CapsuleComponent end
      end)
      if IsValid(capsule) then ClearVisionV2._CapsuleCache[character] = capsule end
    end

    if IsValid(capsule) then
      pcall(function()
        if capsule.K2_GetComponentLocation then center = capsule:K2_GetComponentLocation()
        elseif capsule.GetComponentLocation then center = capsule:GetComponentLocation() end
        if capsule.GetScaledCapsuleHalfHeight then halfHeight = capsule:GetScaledCapsuleHalfHeight()
        elseif capsule.GetUnscaledCapsuleHalfHeight then halfHeight = capsule:GetUnscaledCapsuleHalfHeight()
        elseif capsule.CapsuleHalfHeight then halfHeight = capsule.CapsuleHalfHeight end
      end)
    end

    if not center then center = GetActorLocation(character) end
    if not center then return nil, nil end

    if type(halfHeight) ~= "number" or halfHeight < 10 or halfHeight > 200 then
      halfHeight = 85
      pcall(function()
        if character.bIsCrouched then halfHeight = 60 end
        if character.IsProne and character:IsProne() then halfHeight = 25 end
      end)
    end

    local head = {X=center.X, Y=center.Y, Z=center.Z + halfHeight}
    local feet = {X=center.X, Y=center.Y, Z=center.Z - halfHeight}
    return head, feet
  end

  local function ResolveCanvasFresh()
    local tools=nil
    pcall(function() tools=require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
    if not tools then return nil end
    local ui=nil
    pcall(function()
      if tools.GetMainControlBaseUI then ui=tools.GetMainControlBaseUI() end
    end)
    if not IsValid(ui) then return nil end
    local canvas=nil
    pcall(function()
      if IsValid(ui.CanvasPanel_0) then canvas=ui.CanvasPanel_0 end
    end)
    if not IsValid(canvas) then
      pcall(function()
        if IsValid(ui.CanvasPanel_42) then canvas=ui.CanvasPanel_42 end
      end)
    end
    return IsValid(canvas) and canvas or nil
  end

  function ClearVisionV2.InitCanvas(forceRefresh)
    local old=ClearVisionV2.ESPCanvas
    if IsValid(old) and not forceRefresh then return true end

    local canvas=ResolveCanvasFresh()
    if not IsValid(canvas) then return IsValid(old) end

    if canvas~=old then
      for key,data in pairs(ClearVisionV2.EnemyWidgets) do
        if data then
          if data.Root then DestroyWidget(data.Root) end
          if data.SnapLine and data.SnapLine.Widget then DestroyWidget(data.SnapLine.Widget) end
          if data.DistanceText and data.DistanceText.Widget then DestroyWidget(data.DistanceText.Widget) end
          if data.DistanceTextBack and data.DistanceTextBack.Widget then DestroyWidget(data.DistanceTextBack.Widget) end
        end
        ClearVisionV2.EnemyWidgets[key]=nil
      end
      if ClearVisionV2.Counter and ClearVisionV2.Counter.Root then DestroyWidget(ClearVisionV2.Counter.Root) end
      ClearVisionV2.Counter=nil
      ClearVisionV2._CounterVisible=nil
      ClearVisionV2._ProjectionCache={}
    end

    ClearVisionV2.ESPCanvas=canvas
    return true
  end

  function ClearVisionV2.UpdateCanvasTransform(pc)
    if not IsValid(ClearVisionV2.ESPCanvas) then return end
    local success = false

    pcall(function()
      local sbl = SlateBlueprintLibrary
      if sbl and sbl.AbsoluteToLocal then
        local geometry = ClearVisionV2.ESPCanvas:GetCachedGeometry()
        if geometry then
          local p0 = sbl.AbsoluteToLocal(geometry, V2(0,0))
          local p1 = sbl.AbsoluteToLocal(geometry, V2(100,100))
          if p0 and p1 and type(p0.X)=="number" and type(p0.Y)=="number"
              and type(p1.X)=="number" and type(p1.Y)=="number"
              and p1.X ~= p0.X and p1.Y ~= p0.Y then
            ClearVisionV2._CanvasScaleX = (p1.X-p0.X)/100.0
            ClearVisionV2._CanvasScaleY = (p1.Y-p0.Y)/100.0
            ClearVisionV2._CanvasOffsetX = p0.X
            ClearVisionV2._CanvasOffsetY = p0.Y
            success = true
          end
        end
      end
    end)

    if not success then
      local scale = 1.0
      pcall(function()
        if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
          local candidate = WidgetLayoutLibrary.GetViewportScale(pc)
          if type(candidate)=="number" and candidate > 0 then scale = candidate end
        end
      end)
      ClearVisionV2._CanvasScaleX = 1.0 / scale
      ClearVisionV2._CanvasScaleY = 1.0 / scale
      ClearVisionV2._CanvasOffsetX = 0
      ClearVisionV2._CanvasOffsetY = 0
    end
  end

  local function ScreenToCanvas(p)
    if not p then return nil end
    return {
      X = p.X * (ClearVisionV2._CanvasScaleX or 1.0) + (ClearVisionV2._CanvasOffsetX or 0.0),
      Y = p.Y * (ClearVisionV2._CanvasScaleY or 1.0) + (ClearVisionV2._CanvasOffsetY or 0.0)
    }
  end

  local function ProjectToCanvas(pc, worldLoc, cache)
    cache = cache or {}
    cache.Pix = cache.Pix or V2(0,0)
    local pix = cache.Pix
    pix.X, pix.Y = 0,0

    local okProjection = false
    pcall(function()
      local result = pc:ProjectWorldLocationToScreen(worldLoc, pix, true)
      okProjection = result == true or result == 1 or (pix.X ~= 0 or pix.Y ~= 0)
    end)
    if not okProjection then return false, nil end
    return true, ScreenToCanvas(pix)
  end

  local function NewWidget(path, outer)
    local obj = nil
    pcall(function() obj = CGame:NewObjectFromPath(path, outer) end)
    return IsValid(obj) and obj or nil
  end

  local function AddChild(parent, child, zOrder)
    if not IsValid(parent) or not IsValid(child) then return nil end
    local slot = nil
    pcall(function()
      slot = parent:AddChildToCanvas(child)
      if slot then
        slot:SetAutoSize(false)
        if zOrder then slot:SetZOrder(zOrder) end
      end
    end)
    return IsValid(slot) and slot or nil
  end

  local function CreateBorder(parent, color, z)
    local widget = NewWidget("/Script/UMG.Border", parent)
    if not widget then return nil end
    pcall(function()
      widget:SetBrushColor(color)
      widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      widget:SetRenderTransformPivot(V2(0.0,0.5))
    end)
    local slot = AddChild(parent, widget, z or 1)
    if not slot then DestroyWidget(widget) return nil end
    return {Widget=widget, Slot=slot}
  end

  local function CreateText(parent, value, color, fontSize, z)
    local widget = NewWidget("/Script/UMG.TextBlock", parent)
    if not widget then return nil end
    pcall(function()
      widget:SetText(tostring(value or ""))
      widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      if widget.SetJustification then widget:SetJustification(1) end
      if widget.SetAutoWrapText then widget:SetAutoWrapText(false) end
      if widget.SetClipping and UEnums and UEnums.EWidgetClipping and UEnums.EWidgetClipping.ClipToBounds then
        widget:SetClipping(UEnums.EWidgetClipping.ClipToBounds)
      end
    end)
    SetTextColor(widget, color or COLORS.White)
    SetFontSize(widget, fontSize or 12)
    local slot = AddChild(parent, widget, z or 5)
    if not slot then DestroyWidget(widget) return nil end
    return {Widget=widget, Slot=slot}
  end

  local function SetRect(item, x, y, w, h)
    if not item or not IsValid(item.Slot) then return false end
    local ok = pcall(function()
      item.Slot:SetPosition(V2(x,y))
      item.Slot:SetSize(V2(math.max(0.5,w), math.max(0.5,h)))
    end)
    return ok
  end

  local function SetLine(item, x1, y1, x2, y2, thickness)
    if not item or not IsValid(item.Widget) or not IsValid(item.Slot) then return false end
    local dx, dy = x2-x1, y2-y1
    local length = math.sqrt(dx*dx + dy*dy)
    if length < 0.2 then SetVisible(item.Widget, false) return false end
    local angle = ((math.atan2 and math.atan2(dy,dx)) or math.atan(dy,dx)) * 180.0 / math.pi
    local ok = pcall(function()
      item.Slot:SetPosition(V2(x1, y1-thickness*0.5))
      item.Slot:SetSize(V2(length, math.max(0.5,thickness)))
      item.Widget:SetRenderAngle(angle)
      item.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
    return ok
  end

  local function SetBorderColor(item, color)
    if item and IsValid(item.Widget) then
      pcall(function() item.Widget:SetBrushColor(color) end)
    end
  end

  local function SetTextValue(item, value)
    if item and IsValid(item.Widget) then
      pcall(function() item.Widget:SetText(tostring(value)) end)
    end
  end

  local function ApplyEnemyTheme(data, isAI)
    if not data then return end
    local stroke      = isAI and COLORS.YellowBright or COLORS.BloodRedBright
    local innerStroke = isAI and COLORS.Yellow       or COLORS.BloodRed
    local dim         = isAI and COLORS.YellowDim    or COLORS.BloodRedDim
    local topGlow     = isAI and COLORS.YellowSoft   or COLORS.BloodRedSoft
    local bottomShade = isAI and COLORS.YellowShade  or COLORS.BloodRedShade
    local textColor   = isAI and COLORS.BotRedText   or COLORS.White

    for _,item in ipairs(data.Arc or {}) do SetBorderColor(item, stroke) end
    for _,item in ipairs(data.PlateLines or {}) do SetBorderColor(item, stroke) end
    for _,item in ipairs(data.StatusOuter or {}) do SetBorderColor(item, stroke) end
    for _,item in ipairs(data.PlateCornerFill or {}) do SetBorderColor(item, dim) end

    if data.PlateBGCore then SetBorderColor(data.PlateBGCore, dim) end
    if data.PlateBGMid then SetBorderColor(data.PlateBGMid, innerStroke) end
    if data.PlateTopGlow then SetBorderColor(data.PlateTopGlow, topGlow) end
    if data.PlateBottomShade then SetBorderColor(data.PlateBottomShade, bottomShade) end

    if data.SnapLine then SetBorderColor(data.SnapLine, stroke) end
    if data.TitleText then SetTextColor(data.TitleText.Widget, textColor) end
    if data.DistanceText then SetTextColor(data.DistanceText.Widget, textColor) end
    if data.DistanceTextBack then SetTextColor(data.DistanceTextBack.Widget, textColor) end

    data.LastThemeAI = isAI == true
  end

  local function ApplyV2FeatureVisibility(data)
    if not data then return end
    local showBracket = CV2Flag("EspV2Bracket", true)
    local showName = CV2Flag("EspV2Name", true)
    local showHealth = CV2Flag("EspV2Health", true)

    if data._VisBracket ~= showBracket then
      data._VisBracket = showBracket
      for _,item in ipairs(data.Arc or {}) do
        if item and item.Widget then SetVisible(item.Widget, showBracket) end
      end
    end

    if data._VisName ~= showName then
      data._VisName = showName
      local nameItems = {
        data.PlateBGCore, data.PlateBGMid, data.PlateTopGlow, data.PlateBottomShade,
        data.TitleText
      }
      for _,item in ipairs(nameItems) do
        if item and item.Widget then SetVisible(item.Widget, showName) end
      end
      for _,item in ipairs(data.PlateLines or {}) do
        if item and item.Widget then SetVisible(item.Widget, showName) end
      end
      for _,item in ipairs(data.PlateCornerFill or {}) do
        if item and item.Widget then SetVisible(item.Widget, showName) end
      end
    end

    if data._VisHealth ~= showHealth then
      data._VisHealth = showHealth
      for _,item in ipairs(data.StatusOuter or {}) do
        if item and item.Widget then SetVisible(item.Widget, showHealth) end
      end
      for _,item in ipairs(data.StatusInner or {}) do
        if item and item.Widget then SetVisible(item.Widget, showHealth) end
      end
    end
  end

  local function SetRootVisible(data, visible)
    if not data or not data.Root or data._RootVisible == visible then return end
    data._RootVisible = visible
    SetVisible(data.Root, visible)
  end

  local function SetSnapVisible(data, visible)
    if not data or not data.SnapLine or not data.SnapLine.Widget or data._SnapVisible == visible then return end
    data._SnapVisible = visible
    SetVisible(data.SnapLine.Widget, visible)
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
    if not rootSlot then DestroyWidget(root) return nil end

    local data = {
      Root=root, RootSlot=rootSlot,
      Arc={}, PlateLines={}, PlateCornerFill={}, StatusOuter={}, StatusInner={},
      Key=key,
      LastScale=nil, LastX=nil, LastY=nil, LastDistance=nil, LastHealth=nil,
      LastName=nil, LastThemeAI=nil, LastDistanceFont=nil,
      LastDistanceRenderedText=nil, LastDistanceAppliedFont=nil,
      _RootVisible=nil, _SnapVisible=nil, _DistanceVisible=nil,
      _VisBracket=nil, _VisName=nil, _VisHealth=nil,
    }

    data.PlateBGCore = CreateBorder(root, COLORS.Dark2, 4)
    data.PlateBGMid = CreateBorder(root, COLORS.Dark2, 4)
    data.PlateTopGlow = CreateBorder(root, COLORS.GoldSoft, 5)
    data.PlateBottomShade = CreateBorder(root, Color(0.05,0.025,0.0,0.50), 5)
    data.TitleText = CreateText(root, "", COLORS.White, 22, 7)
    data.DistanceTextBack = CreateText(parent, "", COLORS.Gold, 20, 58)
    data.DistanceText = CreateText(parent, "", COLORS.Gold, 20, 59)
    SetFontBold(data.DistanceTextBack and data.DistanceTextBack.Widget)
    SetFontBold(data.DistanceText and data.DistanceText.Widget)

    for i=1,8 do data.PlateLines[i] = CreateBorder(root, COLORS.Gold, 6) end
    for i=1,4 do data.PlateCornerFill[i] = CreateBorder(root, COLORS.GoldDim, 4) end
    for i=1,4 do
      data.StatusOuter[i] = CreateBorder(root, COLORS.Gold, 6)
      data.StatusInner[i] = CreateBorder(root, COLORS.Gray, 7)
    end
    for i=1,22 do data.Arc[i] = CreateBorder(root, COLORS.Gold, 2) end
    data.SnapLine = CreateBorder(parent, COLORS.Gold, 1)

    if not data.PlateBGCore or not data.PlateBGMid or not data.PlateTopGlow or not data.PlateBottomShade or not data.TitleText or
       not data.DistanceText or not data.DistanceTextBack or not data.SnapLine then
      if data.SnapLine and data.SnapLine.Widget then DestroyWidget(data.SnapLine.Widget) end
      if data.DistanceText and data.DistanceText.Widget then DestroyWidget(data.DistanceText.Widget) end
      if data.DistanceTextBack and data.DistanceTextBack.Widget then DestroyWidget(data.DistanceTextBack.Widget) end
      DestroyWidget(root)
      return nil
    end

    ClearVisionV2.EnemyWidgets[key] = data
    return data
  end

  local function LayoutEnemy(data, s, displayName)
    if not data then return end
    local function X(v) return v*s end
    local function Y(v) return v*s end

    pcall(function() data.RootSlot:SetSize(V2(REF_W*s, REF_H*s)) end)

    local arcIndex = 1
    local cx, cy = 343, 550
    local rx, ry = 195.5, 356.0
    local function drawTaperedArc(a0, a1, segments)
      local px,py=nil,nil
      for i=0,segments do
        local t=i/segments
        local a=a0+(a1-a0)*t
        local xx=cx+math.cos(a)*rx
        local yy=cy+math.sin(a)*ry
        if px then
          local mid=(i-0.5)/segments
          local bell=math.sin(math.pi*mid)
          if bell<0 then bell=0 end
          local thin=Clamp(2.4*s,1.0,1.8)
          local thick=Clamp(12.5*s,3.0,6.0)
          local thickness=thin+(thick-thin)*(bell^1.45)
          SetLine(data.Arc[arcIndex],X(px),Y(py),X(xx),Y(yy),thickness)
          arcIndex=arcIndex+1
        end
        px,py=xx,yy
      end
    end
    drawTaperedArc(math.pi*0.56,math.pi*1.44,7)
    drawTaperedArc(-math.pi*0.44,math.pi*0.44,7)

    local innerRX,innerRY=166.0,296.0
    local function miniBracket(centerA, slot)
      local d=math.pi*0.030
      local p={}
      for j=-1,1 do
        local a=centerA+j*d
        p[#p+1]={cx+math.cos(a)*innerRX,cy+math.sin(a)*innerRY}
      end
      local t=Clamp(7.0*s,1.6,3.8)
      SetLine(data.Arc[slot],X(p[1][1]),Y(p[1][2]),X(p[2][1]),Y(p[2][2]),t)
      SetLine(data.Arc[slot+1],X(p[2][1]),Y(p[2][2]),X(p[3][1]),Y(p[3][2]),t)
    end
    miniBracket(math.pi*0.84,15)
    miniBracket(math.pi*1.16,17)
    miniBracket(-math.pi*0.16,19)
    miniBracket(math.pi*0.16,21)

    displayName=tostring(displayName or "ENEMY")
    local nameLen=#displayName
    pcall(function() if utf8 and utf8.len then nameLen=utf8.len(displayName) or nameLen end end)
    if nameLen < 1 then nameLen=1 end

    local maxPlateW=420.0
    local minPlateW=118.0
    local padding=24.0
    local nameFont=Clamp(58*s,13,44)
    local estimated=nameLen*nameFont*0.60
    if estimated+padding>maxPlateW then
      nameFont=math.max(9.0,(maxPlateW-padding)/(nameLen*0.60))
      estimated=nameLen*nameFont*0.60
    end
    local plateW=Clamp(estimated+padding,minPlateW,maxPlateW)
    local plateH=Clamp(nameFont*1.50,28,64)

    local q=Clamp(28*s,7,21)
    local gap=Clamp(8*s,3,8)
    local statusW=q*4+gap*3
    local headLocalY=REF_BODY_TOP*s
    local bodyGap=Clamp(18*s,8,18)
    local statusGap=Clamp(7*s,3,8)
    local statusY=headLocalY-bodyGap-q
    local plateY=statusY-statusGap-plateH
    local plateCX=X(343)
    local plateX=plateCX-plateW*0.5

    local cut=Clamp(plateH*0.24,6,16)
    local pts={
      {plateX+cut,plateY}, {plateX+plateW-cut,plateY},
      {plateX+plateW,plateY+cut}, {plateX+plateW,plateY+plateH-cut},
      {plateX+plateW-cut,plateY+plateH}, {plateX+cut,plateY+plateH},
      {plateX,plateY+plateH-cut}, {plateX,plateY+cut},
    }

    SetRect(data.PlateBGCore,plateX+cut,plateY,math.max(1,plateW-cut*2),plateH)
    SetRect(data.PlateBGMid,plateX,plateY+cut,plateW,math.max(1,plateH-cut*2))
    local bandInset=math.max(2.0,cut*0.60)
    local bandW=math.max(1,plateW-bandInset*2)
    local bandH=math.max(1,plateH*0.18)
    SetRect(data.PlateTopGlow,plateX+bandInset,plateY+plateH*0.12,bandW,bandH)
    SetRect(data.PlateBottomShade,plateX+bandInset,plateY+plateH*0.70,bandW,bandH)

    local fillT=math.max(1.0,cut*1.22)
    SetLine(data.PlateCornerFill[1],plateX,plateY+cut,plateX+cut,plateY,fillT)
    SetLine(data.PlateCornerFill[2],plateX+plateW-cut,plateY,plateX+plateW,plateY+cut,fillT)
    SetLine(data.PlateCornerFill[3],plateX+plateW,plateY+plateH-cut,plateX+plateW-cut,plateY+plateH,fillT)
    SetLine(data.PlateCornerFill[4],plateX+cut,plateY+plateH,plateX,plateY+plateH-cut,fillT)

    local textPad=math.max(6.0,cut*0.60)
    SetRect(data.TitleText,plateX+textPad,plateY+2,plateW-textPad*2,plateH-4)
    SetFontSize(data.TitleText.Widget,nameFont)

    for i=1,8 do
      local a=pts[i]
      local b=pts[(i%8)+1]
      SetLine(data.PlateLines[i],a[1],a[2],b[1],b[2],Clamp(3.1*s,1.2,2.8))
    end

    local statusX=plateCX-statusW*0.5
    for i=1,4 do
      local bx=statusX+(i-1)*(q+gap)
      SetRect(data.StatusOuter[i],bx,statusY,q,q)
      local inset=math.max(2,q*0.14)
      SetRect(data.StatusInner[i],bx+inset,statusY+inset,q-inset*2,q-inset*2)
    end

    data.LastScale=s
    data._VisName=nil
    data._VisBracket=nil
    data._VisHealth=nil
  end

  local function UpdateHealthSegments(data, pct, isAI)
    if not data then return end
    local themeColor=isAI and COLORS.YellowBright or COLORS.BloodRedBright
    local progress=math.max(0,math.min(1,pct or 0))*4.0
    for i=1,4 do
      local c
      if progress>=i then c=themeColor
      elseif progress>(i-1) then c=COLORS.White
      else c=COLORS.Gray end
      SetBorderColor(data.StatusInner[i],c)
    end
  end

  function ClearVisionV2.RemoveEnemy(key)
    local data = ClearVisionV2.EnemyWidgets[key]
    if data then
      if data.Root then DestroyWidget(data.Root) end
      if data.SnapLine and data.SnapLine.Widget then DestroyWidget(data.SnapLine.Widget) end
      if data.DistanceText and data.DistanceText.Widget then DestroyWidget(data.DistanceText.Widget) end
      if data.DistanceTextBack and data.DistanceTextBack.Widget then DestroyWidget(data.DistanceTextBack.Widget) end
    end
    ClearVisionV2.EnemyWidgets[key]=nil
    ClearVisionV2.EnemyCache[key]=nil
    ClearVisionV2.EnemyMeta[key]=nil
    ClearVisionV2._ProjectionCache[key]=nil
  end

  local function CreateCounterOverlay()
    if ClearVisionV2.Counter and IsValid(ClearVisionV2.Counter.Root) then return ClearVisionV2.Counter end
    if not ClearVisionV2.InitCanvas(false) then return nil end
    local parent=ClearVisionV2.ESPCanvas
    if not IsValid(parent) then return nil end

    local root=NewWidget("/Script/UMG.CanvasPanel",parent)
    if not root then return nil end
    local slot=AddChild(parent,root,60)
    if not slot then DestroyWidget(root) return nil end

    local c={
      Root=root,Slot=slot,
      LeftOuter={},RightOuter={},LeftInner={},RightInner={},
      LeftCornerFill={},RightCornerFill={},Diamond={},DiamondInner={},
      Crown={},Helmet={},
    }

    c.LeftCore=CreateBorder(root,COLORS.BloodRedDim,0)
    c.LeftMid=CreateBorder(root,COLORS.BloodRed,0)
    c.RightCore=CreateBorder(root,COLORS.YellowDim,0)
    c.RightMid=CreateBorder(root,COLORS.Yellow,0)
    c.LeftTopGlow=CreateBorder(root,COLORS.BloodRedSoft,1)
    c.LeftBottomShade=CreateBorder(root,COLORS.BloodRedShade,1)
    c.RightTopGlow=CreateBorder(root,COLORS.YellowSoft,1)
    c.RightBottomShade=CreateBorder(root,COLORS.YellowShade,1)
    c.CenterRedCore=CreateBorder(root,COLORS.RedDim,1)
    c.CenterRedGlow=CreateBorder(root,COLORS.RedSoft,2)
    c.CenterGreenCore=CreateBorder(root,COLORS.GreenDim,3)
    c.CenterGreenGlow=CreateBorder(root,COLORS.GreenSoft,4)
    c.PlayerText=CreateText(root,"PLAYER: 0",COLORS.White,20,8)
    c.BotText=CreateText(root,"BOT: 0",COLORS.BotRedText,20,8)

    for i=1,8 do c.LeftOuter[i]=CreateBorder(root,COLORS.BloodRedBright,4) end
    for i=1,8 do c.RightOuter[i]=CreateBorder(root,COLORS.YellowBright,4) end
    for i=1,8 do c.LeftInner[i]=CreateBorder(root,COLORS.BloodRed,3) end
    for i=1,8 do c.RightInner[i]=CreateBorder(root,COLORS.Yellow,3) end
    for i=1,4 do c.LeftCornerFill[i]=CreateBorder(root,COLORS.BloodRedDim,1) end
    for i=1,4 do c.RightCornerFill[i]=CreateBorder(root,COLORS.YellowDim,1) end
    for i=1,4 do c.Diamond[i]=CreateBorder(root,COLORS.RedBright,6) end
    for i=1,4 do c.DiamondInner[i]=CreateBorder(root,COLORS.GreenBright,7) end
    for i=1,7 do c.Crown[i]=CreateBorder(root,COLORS.BloodRedBright,7) end
    for i=1,9 do c.Helmet[i]=CreateBorder(root,COLORS.YellowBright,7) end
    c.LeftDivider=CreateBorder(root,COLORS.BloodRedBright,5)
    c.RightDivider=CreateBorder(root,COLORS.YellowBright,5)
    c.StarH=CreateBorder(root,COLORS.GoldBright,7)
    c.StarV=CreateBorder(root,COLORS.GoldBright,7)

    if not c.LeftCore or not c.LeftMid or not c.RightCore or not c.RightMid or
       not c.CenterRedCore or not c.CenterGreenCore or
       not c.PlayerText or not c.BotText or not c.StarH or not c.StarV then
      DestroyWidget(root)
      return nil
    end
    ClearVisionV2.Counter=c
    return c
  end

  local function UpdateCounterOverlay(pc)
    local c=CreateCounterOverlay()
    if not c then return end
    local viewW,viewH=GetViewportSize(pc)
    local screenW=Clamp(viewW*0.248,208,420)
    local screenH=Clamp(screenW*0.105,24,42)
    local top=Clamp(viewH*0.026,10,30)
    local topLeft=ScreenToCanvas({X=(viewW-screenW)*0.5,Y=top})
    local bottomRight=ScreenToCanvas({X=(viewW+screenW)*0.5,Y=top+screenH})
    local w=bottomRight.X-topLeft.X
    local h=bottomRight.Y-topLeft.Y
    if w<=0 or h<=0 then return end

    pcall(function()
      c.Slot:SetPosition(V2(topLeft.X,topLeft.Y))
      c.Slot:SetSize(V2(w,h))
    end)

    local half=w*0.5
    local centerGap=Clamp(h*0.76,14,30)
    local leftX0,leftX1=0,half-centerGap*0.5
    local rightX0,rightX1=half+centerGap*0.5,w
    local bevel=Clamp(h*0.22,5,10)
    local thick=Clamp(h*0.045,1.0,2.2)

    local function octagon(x0,x1,y0,y1,b)
      return {
        {x0+b,y0},{x1-b,y0},{x1,y0+b},{x1,y1-b},
        {x1-b,y1},{x0+b,y1},{x0,y1-b},{x0,y0+b},
      }
    end
    local function drawLoop(lines,pts,t)
      for i=1,8 do
        local a,b=pts[i],pts[(i%8)+1]
        SetLine(lines[i],a[1],a[2],b[1],b[2],t)
      end
    end

    local leftPts=octagon(leftX0,leftX1,0,h,bevel)
    local rightPts=octagon(rightX0,rightX1,0,h,bevel)
    drawLoop(c.LeftOuter,leftPts,thick)
    drawLoop(c.RightOuter,rightPts,thick)

    local inset=Clamp(h*0.105,2.2,4.6)
    local leftInner=octagon(leftX0+inset,leftX1-inset,inset,h-inset,math.max(2,bevel-inset*0.35))
    local rightInner=octagon(rightX0+inset,rightX1-inset,inset,h-inset,math.max(2,bevel-inset*0.35))
    drawLoop(c.LeftInner,leftInner,math.max(0.8,thick*0.62))
    drawLoop(c.RightInner,rightInner,math.max(0.8,thick*0.62))

    SetRect(c.LeftCore,leftX0+bevel,0,math.max(1,(leftX1-leftX0)-bevel*2),h)
    SetRect(c.LeftMid,leftX0,bevel,math.max(1,leftX1-leftX0),math.max(1,h-bevel*2))
    SetRect(c.RightCore,rightX0+bevel,0,math.max(1,(rightX1-rightX0)-bevel*2),h)
    SetRect(c.RightMid,rightX0,bevel,math.max(1,rightX1-rightX0),math.max(1,h-bevel*2))

    local fillT=math.max(1.0,bevel*1.28)
    SetLine(c.LeftCornerFill[1],leftX0,bevel,leftX0+bevel,0,fillT)
    SetLine(c.LeftCornerFill[2],leftX1-bevel,0,leftX1,bevel,fillT)
    SetLine(c.LeftCornerFill[3],leftX1,h-bevel,leftX1-bevel,h,fillT)
    SetLine(c.LeftCornerFill[4],leftX0+bevel,h,leftX0,h-bevel,fillT)
    SetLine(c.RightCornerFill[1],rightX0,bevel,rightX0+bevel,0,fillT)
    SetLine(c.RightCornerFill[2],rightX1-bevel,0,rightX1,bevel,fillT)
    SetLine(c.RightCornerFill[3],rightX1,h-bevel,rightX1-bevel,h,fillT)
    SetLine(c.RightCornerFill[4],rightX0+bevel,h,rightX0,h-bevel,fillT)

    local glowXPad=bevel+inset
    local bandH=math.max(1,h*0.18)
    SetRect(c.LeftTopGlow,leftX0+glowXPad,h*0.10,math.max(1,(leftX1-leftX0)-glowXPad*2),bandH)
    SetRect(c.LeftBottomShade,leftX0+glowXPad,h*0.71,math.max(1,(leftX1-leftX0)-glowXPad*2),bandH)
    SetRect(c.RightTopGlow,rightX0+glowXPad,h*0.10,math.max(1,(rightX1-rightX0)-glowXPad*2),bandH)
    SetRect(c.RightBottomShade,rightX0+glowXPad,h*0.71,math.max(1,(rightX1-rightX0)-glowXPad*2),bandH)

    local cx,cy=half,h*0.5
    local diamondR=h*0.60
    local innerR=diamondR*0.58
    local d={{cx,cy-diamondR},{cx+diamondR,cy},{cx,cy+diamondR},{cx-diamondR,cy}}
    local di={{cx,cy-innerR},{cx+innerR,cy},{cx,cy+innerR},{cx-innerR,cy}}
    for i=1,4 do SetLine(c.Diamond[i],d[i][1],d[i][2],d[(i%4)+1][1],d[(i%4)+1][2],math.max(thick,1.1)) end
    for i=1,4 do SetLine(c.DiamondInner[i],di[i][1],di[i][2],di[(i%4)+1][1],di[(i%4)+1][2],math.max(thick*0.78,1.0)) end

    SetRect(c.CenterRedCore,cx-diamondR*0.38,cy-diamondR*0.68,diamondR*0.76,diamondR*1.36)
    SetRect(c.CenterRedGlow,cx-diamondR*0.26,cy-diamondR*0.50,diamondR*0.52,diamondR*0.38)
    SetRect(c.CenterGreenCore,cx-innerR*0.34,cy-innerR*0.62,innerR*0.68,innerR*1.24)
    SetRect(c.CenterGreenGlow,cx-innerR*0.20,cy-innerR*0.40,innerR*0.40,innerR*0.28)

    SetBorderColor(c.CenterRedCore,COLORS.RedDim)
    SetBorderColor(c.CenterRedGlow,COLORS.RedSoft)
    SetBorderColor(c.CenterGreenCore,COLORS.GreenDim)
    SetBorderColor(c.CenterGreenGlow,COLORS.GreenSoft)
    SetLine(c.StarH,cx-h*0.10,cy,cx+h*0.10,cy,math.max(1.0,thick*0.80))
    SetLine(c.StarV,cx,cy-h*0.14,cx,cy+h*0.14,math.max(1.0,thick*0.80))
    if c.StarH then SetVisible(c.StarH.Widget,false) end
    if c.StarV then SetVisible(c.StarV.Widget,false) end

    local lcx=leftX0+(leftX1-leftX0)*0.14
    local ly=cy
    local rw=h*0.23
    local rh=h*0.24
    local crownPts={
      {lcx-rw,ly+rh*0.55},{lcx-rw*0.72,ly-rh*0.55},{lcx-rw*0.18,ly+rh*0.02},
      {lcx,ly-rh*0.78},{lcx+rw*0.20,ly+rh*0.02},{lcx+rw*0.72,ly-rh*0.55},{lcx+rw,ly+rh*0.55}
    }
    for i=1,6 do SetLine(c.Crown[i],crownPts[i][1],crownPts[i][2],crownPts[i+1][1],crownPts[i+1][2],math.max(1,thick*1.05)) end
    SetLine(c.Crown[7],lcx-rw,ly+rh*0.70,lcx+rw,ly+rh*0.70,math.max(1,thick*1.05))

    local rcx=rightX1-(rightX1-rightX0)*0.14
    local topY=ly-rh*0.75
    local botY=ly+rh*0.75
    local hw=rw*0.92
    local hp={
      {rcx-hw,ly-rh*0.40},{rcx-hw*0.62,topY},{rcx,topY-rh*0.10},{rcx+hw*0.62,topY},
      {rcx+hw,ly-rh*0.40},{rcx+hw*0.76,botY},{rcx+hw*0.18,ly+rh*0.28},
      {rcx,botY},{rcx-hw*0.18,ly+rh*0.28},{rcx-hw*0.76,botY}
    }
    for i=1,9 do SetLine(c.Helmet[i],hp[i][1],hp[i][2],hp[i+1][1],hp[i+1][2],math.max(1,thick*1.0)) end

    local leftDivX=leftX0+(leftX1-leftX0)*0.25
    local rightDivX=rightX1-(rightX1-rightX0)*0.25
    SetLine(c.LeftDivider,leftDivX,h*0.20,leftDivX,h*0.80,math.max(1,thick*0.85))
    SetLine(c.RightDivider,rightDivX,h*0.20,rightDivX,h*0.80,math.max(1,thick*0.85))

    local font=Clamp(h*0.42,10,19)
    SetRect(c.PlayerText,leftDivX+h*0.12,h*0.12,(leftX1-leftDivX)-h*0.20,h*0.76)
    SetRect(c.BotText,rightX0+h*0.12,h*0.12,(rightDivX-rightX0)-h*0.20,h*0.76)
    SetFontSize(c.PlayerText.Widget,font)
    SetFontSize(c.BotText.Widget,font)
    SetFontBold(c.PlayerText.Widget)
    SetFontBold(c.BotText.Widget)
    SetTextColor(c.PlayerText.Widget,COLORS.White)
    SetTextColor(c.BotText.Widget,COLORS.BotRedText)
    SetTextValue(c.PlayerText,"PLAYER: "..tostring(ClearVisionV2.RealEnemyCount or 0))
    SetTextValue(c.BotText,"BOT: "..tostring(ClearVisionV2.BotEnemyCount or 0))
  end

  local function AppendPawnCollection(out, seen, collection)
    if collection==nil then return end
    local addedByArray=false
    pcall(function()
      if type(collection.Num)=="function" and type(collection.Get)=="function" then
        local n=tonumber(collection:Num()) or 0
        for i=0,n-1 do
          local pawn=collection:Get(i)
          if IsValid(pawn) and not seen[pawn] then
            seen[pawn]=true
            out[#out+1]=pawn
          end
        end
        addedByArray=true
      end
    end)
    if addedByArray then return end
    pcall(function()
      for _,pawn in pairs(collection) do
        if IsValid(pawn) and not seen[pawn] then
          seen[pawn]=true
          out[#out+1]=pawn
        end
      end
    end)
  end

  local function CollectPlayerPawns()
    local out,seen={},{}
    pcall(function()
      if Game and Game.GetAllPlayerPawns then
        AppendPawnCollection(out,seen,Game:GetAllPlayerPawns())
      end
    end)
    pcall(function()
      if GameplayData and GameplayData.GetAllPlayerCharacters then
        AppendPawnCollection(out,seen,GameplayData.GetAllPlayerCharacters())
      end
    end)
    pcall(function()
      if GameplayData and GameplayData.GameCharacters then
        AppendPawnCollection(out,seen,GameplayData.GameCharacters)
      end
    end)
    return out
  end

  function ClearVisionV2.RefreshEnemies()
    if not ClearVisionV2.Active then return false end
    local pc = GetController()
    local me = GetLocalPawn(pc)
    if not IsValid(pc) or not IsValid(me) then return false end

    local myTeam = GetTeamID(me)
    local myLoc = GetActorLocation(me)
    if not myLoc then return false end

    local pawns=CollectPlayerPawns()
    if type(pawns)~="table" then return false end

    local candidates = {}
    local seen = {}

    pcall(function()
      for _,pawn in pairs(pawns) do
        if IsValid(pawn) and pawn ~= me and IsAlive(pawn) then
          local team=GetTeamID(pawn)
          local sameTeam=false
          if myTeam~=nil and team~=nil then
            local myNum,teamNum=tonumber(myTeam),tonumber(team)
            if myNum and teamNum then
              sameTeam=(myNum>0 and teamNum>0 and myNum==teamNum)
            else
              sameTeam=(tostring(myTeam)~="" and tostring(team)~="" and tostring(team)==tostring(myTeam))
            end
          end
          if not sameTeam then
            local loc = GetActorLocation(pawn)
            local d = DistanceMeters(myLoc,loc)
            if d <= ClearVisionV2.RangeMeters then
              local key = tostring(GetPlayerKey(pawn) or pawn)
              if not seen[key] then
                seen[key]=true
                local name,resolved=GetPlayerName(pawn)
                local bot=IsAI(pawn)
                candidates[#candidates+1]={Key=key,Pawn=pawn,Distance=d,Name=name,NameResolved=resolved,IsAI=bot}
              end
            end
          end
        end
      end
    end)

    table.sort(candidates,function(a,b) return a.Distance < b.Distance end)

    local selected, meta = {}, {}
    local realCount, botCount = 0,0
    local count = math.min(#candidates,ClearVisionV2.MaxEnemies)
    for i=1,count do
      local c=candidates[i]
      selected[c.Key]=c.Pawn
      meta[c.Key]={Name=c.Name,NameResolved=c.NameResolved,IsAI=c.IsAI}
      if c.IsAI then botCount=botCount+1 else realCount=realCount+1 end
    end

    local stale={}
    for key in pairs(ClearVisionV2.EnemyCache) do
      if selected[key]==nil or selected[key]~=ClearVisionV2.EnemyCache[key] then stale[#stale+1]=key end
    end
    for _,key in ipairs(stale) do ClearVisionV2.RemoveEnemy(key) end

    local countChanged=(ClearVisionV2.RealEnemyCount~=realCount) or (ClearVisionV2.BotEnemyCount~=botCount)
    ClearVisionV2.EnemyCache=selected
    ClearVisionV2.EnemyMeta=meta
    ClearVisionV2.RealEnemyCount=realCount
    ClearVisionV2.BotEnemyCount=botCount
    if CV2Flag("EspV2Counter", true) and (countChanged or not ClearVisionV2.Counter) then
      UpdateCounterOverlay(pc)
    end
    return true
  end

  local function GetCameraContext(pc)
    if not IsValid(pc) then return nil,nil end
    local camLoc,camYaw=nil,nil
    local mgr=nil
    pcall(function()
      if pc.GetPlayerCameraManager then mgr=pc:GetPlayerCameraManager() end
      if not IsValid(mgr) then mgr=pc.PlayerCameraManager end
    end)
    if IsValid(mgr) then
      pcall(function() if mgr.GetCameraLocation then camLoc=mgr:GetCameraLocation() end end)
      pcall(function()
        if mgr.GetCameraRotation then
          local r=mgr:GetCameraRotation()
          if r and r.Yaw~=nil then camYaw=math.rad(r.Yaw) end
        end
      end)
    end
    if camYaw==nil then
      pcall(function()
        if pc.GetControlRotation then
          local r=pc:GetControlRotation()
          if r and r.Yaw~=nil then camYaw=math.rad(r.Yaw) end
        end
      end)
    end
    if not camLoc then
      local pawn=GetLocalPawn(pc)
      camLoc=GetActorLocation(pawn)
    end
    return camLoc,camYaw
  end

  local function CanvasBounds(viewW,viewH)
    local a=ScreenToCanvas({X=0,Y=0})
    local b=ScreenToCanvas({X=viewW,Y=viewH})
    return math.min(a.X,b.X),math.max(a.X,b.X),math.min(a.Y,b.Y),math.max(a.Y,b.Y)
  end

  local function IsCanvasOnScreen(p,viewW,viewH,margin,bounds)
    if not p then return false end
    margin=margin or 2
    local minX,maxX,minY,maxY
    if bounds then
      minX,maxX,minY,maxY=bounds[1],bounds[2],bounds[3],bounds[4]
    else
      minX,maxX,minY,maxY=CanvasBounds(viewW,viewH)
    end
    return p.X>=minX+margin and p.X<=maxX-margin and p.Y>=minY+margin and p.Y<=maxY-margin
  end

  local function Get360Angle(pc,worldLoc,centerCanvas,camLoc,camYaw)
    if not worldLoc or not centerCanvas then return nil end
    local pix=V2(0,0)
    local projected=false
    pcall(function()
      local res=pc:ProjectWorldLocationToScreen(worldLoc,pix,true)
      projected=(res==true or res==1)
    end)
    if projected then
      local cp=ScreenToCanvas(pix)
      local dx,dy=cp.X-centerCanvas.X,cp.Y-centerCanvas.Y
      if math.abs(dx)>0.05 or math.abs(dy)>0.05 then
        return (math.atan2 and math.atan2(dy,dx)) or math.atan(dy,dx)
      end
    end
    if not camLoc or camYaw==nil then camLoc,camYaw=GetCameraContext(pc) end
    if not camLoc or camYaw==nil then return nil end
    local dx=(worldLoc.X or 0)-(camLoc.X or 0)
    local dy=(worldLoc.Y or 0)-(camLoc.Y or 0)
    local cy,sy=math.cos(camYaw),math.sin(camYaw)
    local forward=dx*cy+dy*sy
    local right=-dx*sy+dy*cy
    if math.abs(forward)<0.001 and math.abs(right)<0.001 then return nil end
    return (math.atan2 and math.atan2(-forward,right)) or math.atan(-forward,right)
  end

  local function GetEdgePosition(angle,centerCanvas,viewW,viewH,margin,bounds)
    if angle==nil then return nil end
    local minX,maxX,minY,maxY
    if bounds then
      minX,maxX,minY,maxY=bounds[1],bounds[2],bounds[3],bounds[4]
    else
      minX,maxX,minY,maxY=CanvasBounds(viewW,viewH)
    end
    margin=margin or 42
    local halfW=math.max(8,math.min(centerCanvas.X-minX,maxX-centerCanvas.X)-margin)
    local halfH=math.max(8,math.min(centerCanvas.Y-minY,maxY-centerCanvas.Y)-margin)
    local dx,dy=math.cos(angle),math.sin(angle)
    local ax,ay=math.abs(dx),math.abs(dy)
    local tx=ax>0.0001 and halfW/ax or 1e9
    local ty=ay>0.0001 and halfH/ay or 1e9
    local t=math.min(tx,ty)
    return {X=centerCanvas.X+dx*t,Y=centerCanvas.Y+dy*t}
  end

  local function PlaceDistanceText(data,text,font,x,y,color)
    if not data or not data.DistanceText or not data.DistanceTextBack then return end
    text=tostring(text or "--m")
    font=Clamp(font or 18,13,42)
    local width=Clamp(#text*font*0.72+12,46,180)
    local height=Clamp(font*1.35,24,58)
    local drawX=x-width*0.5
    local drawY=y-height*0.5

    SetRect(data.DistanceTextBack,drawX+1.0,drawY+1.0,width,height)
    SetRect(data.DistanceText,drawX,drawY,width,height)

    if not data.LastDistanceAppliedFont or math.abs(data.LastDistanceAppliedFont-font) > 0.49 then
      SetFontSize(data.DistanceTextBack.Widget,font)
      SetFontSize(data.DistanceText.Widget,font)
      data.LastDistanceAppliedFont=font
    end
    if data.LastDistanceRenderedText ~= text then
      SetTextValue(data.DistanceTextBack,text)
      SetTextValue(data.DistanceText,text)
      data.LastDistanceRenderedText=text
    end
    SetDistanceVisible(data,true)
  end

  function ClearVisionV2.Update()
    if not CV2Flag("EspV2Enabled", false) then
      if ClearVisionV2.Active then ClearVisionV2.Stop() end
      return false
    end
    if not ClearVisionV2.Active then return false end
    if not ClearVisionV2.InitCanvas(false) then return false end

    local pc=GetController()
    local me=GetLocalPawn(pc)
    if not IsValid(pc) or not IsValid(me) then return false end

    ClearVisionV2._FrameSerial=(ClearVisionV2._FrameSerial or 0)+1
    local frameSerial=ClearVisionV2._FrameSerial

    if frameSerial == 1 or (frameSerial % (ClearVisionV2._TransformEveryNFrames or 6)) == 0 then
      ClearVisionV2.UpdateCanvasTransform(pc)
    end
    if CV2Flag("EspV2Counter", true) then
      if not (ClearVisionV2.Counter and IsValid(ClearVisionV2.Counter.Root))
          or (frameSerial % (ClearVisionV2._CounterEveryNFrames or 6)) == 0 then
        UpdateCounterOverlay(pc)
      end
      if ClearVisionV2.Counter and ClearVisionV2.Counter.Root and ClearVisionV2._CounterVisible ~= true then
        SetVisible(ClearVisionV2.Counter.Root,true)
        ClearVisionV2._CounterVisible=true
      end
    elseif ClearVisionV2.Counter and ClearVisionV2.Counter.Root and ClearVisionV2._CounterVisible ~= false then
      SetVisible(ClearVisionV2.Counter.Root,false)
      ClearVisionV2._CounterVisible=false
    end
    local myLoc=GetActorLocation(me)
    if not myLoc then return false end

    local viewW,viewH=GetViewportSize(pc)
    local topOrigin=ScreenToCanvas({X=viewW*0.5,Y=0})
    local centerCanvas=ScreenToCanvas({X=viewW*0.5,Y=viewH*0.5})
    local frameBounds={CanvasBounds(viewW,viewH)}
    local camLoc,camYaw=GetCameraContext(pc)
    local camCos,camSin=nil,nil
    if camYaw~=nil then camCos,camSin=math.cos(camYaw),math.sin(camYaw) end

    for key,character in pairs(ClearVisionV2.EnemyCache) do
      if not IsValid(character) or not IsAlive(character) then
        ClearVisionV2.RemoveEnemy(key)
      else
        local headLoc,feetLoc=GetCharacterBounds(character)
        local worldLoc=nil
        if headLoc and feetLoc then
          worldLoc={
            X=((headLoc.X or 0)+(feetLoc.X or 0))*0.5,
            Y=((headLoc.Y or 0)+(feetLoc.Y or 0))*0.5,
            Z=((headLoc.Z or 0)+(feetLoc.Z or 0))*0.5,
          }
        end
        local data=ClearVisionV2.EnemyWidgets[key]
        if not data then data=CreateEnemyWidget(key) end

        if data and headLoc and feetLoc and worldLoc then
          local meta=ClearVisionV2.EnemyMeta[key] or {}
          local isAI=meta.IsAI==true
          if data.LastThemeAI~=isAI then ApplyEnemyTheme(data,isAI) end

          local proj=ClearVisionV2._ProjectionCache[key]
          if not proj then proj={Head={},Feet={}} ClearVisionV2._ProjectionCache[key]=proj end
          local headOK,head=ProjectToCanvas(pc,headLoc,proj.Head)
          local feetOK,feet=ProjectToCanvas(pc,feetLoc,proj.Feet)

          local headInside=headOK and IsCanvasOnScreen(head,viewW,viewH,0,frameBounds)
          local feetInside=feetOK and IsCanvasOnScreen(feet,viewW,viewH,0,frameBounds)
          local bodyH=(headOK and feetOK and head and feet) and (feet.Y-head.Y) or nil
          local inFront=true
          if camLoc and camYaw~=nil and worldLoc then
            local dx=(worldLoc.X or 0)-(camLoc.X or 0)
            local dy=(worldLoc.Y or 0)-(camLoc.Y or 0)
            inFront=(dx*(camCos or math.cos(camYaw))+dy*(camSin or math.sin(camYaw)))>0
          end
          local onScreen=inFront and headInside and feetInside and bodyH and bodyH>12 and bodyH<3000

          local distance=DistanceMeters(myLoc,worldLoc)
          local rounded=math.max(0,math.floor(distance+0.5))
          if data and data.LastDistanceRounded ~= rounded then
            data.LastDistanceRounded=rounded
            data.LastDistanceText=tostring(rounded).."m"
          end
          local distText=(data and data.LastDistanceText) or (tostring(rounded).."m")

          if onScreen then
            local s=bodyH/REF_BODY_SPAN
            local centerX=(head.X+feet.X)*0.5
            local rootX=centerX-(REF_W*s*0.5)
            local rootY=feet.Y-(REF_BODY_BOTTOM*s)

            local name=meta.Name
            if not name or name=="" then name=select(1,GetPlayerName(character)) end
            name=tostring(name or "ENEMY")

            if not data.LastScale or math.abs(data.LastScale-s)>0.003 or data.LastName~=name then
              LayoutEnemy(data,s,name)
              data.LastName=name
              ApplyEnemyTheme(data,isAI)
            end

            if not data.LastX or math.abs(data.LastX-rootX)>0.2 or not data.LastY or math.abs(data.LastY-rootY)>0.2 then
              pcall(function() data.RootSlot:SetPosition(V2(rootX,rootY)) end)
              data.LastX,data.LastY=rootX,rootY
            end

            if data.LastRenderedName~=name then
              SetTextValue(data.TitleText,name)
              data.LastRenderedName=name
            end

            ApplyV2FeatureVisibility(data)

            local health=GetHealthPercent(character)
            if data.LastHealth==nil or math.abs(data.LastHealth-health)>0.01 or data.LastHealthAI~=isAI then
              UpdateHealthSegments(data,health,isAI)
              data.LastHealth=health
              data.LastHealthAI=isAI
            end

            if data.SnapLine and topOrigin and CV2Flag("EspV2SnapLine", true) then
              SetLine(data.SnapLine,topOrigin.X,topOrigin.Y,head.X,head.Y,1.5)
              SetSnapVisible(data,true)
            elseif data.SnapLine then
              SetSnapVisible(data,false)
            end

            local distFont=Clamp(60*s,13,42)
            local distGap=Clamp(16*s,8,16)
            local distanceTextColor=isAI and COLORS.BotRedText or COLORS.White
            if CV2Flag("EspV2Distance", true) then
              PlaceDistanceText(data,distText,distFont,feet.X,feet.Y+distGap+distFont*0.58,distanceTextColor)
            else
              SetDistanceVisible(data,false)
            end
            data.LastDistanceFont=distFont
            SetRootVisible(data,true)
          else
            SetRootVisible(data,false)
            if data.SnapLine then SetSnapVisible(data,false) end
            local angle=Get360Angle(pc,worldLoc,centerCanvas,camLoc,camYaw)
            local edge=GetEdgePosition(angle,centerCanvas,viewW,viewH,48,frameBounds)
            if edge and CV2Flag("EspV2Distance", true) and CV2Flag("EspV2Offscreen", true) then
              local font=data.LastDistanceFont or 18
              local distanceTextColor=isAI and COLORS.BotRedText or COLORS.White
              PlaceDistanceText(data,distText,font,edge.X,edge.Y,distanceTextColor)
            else
              SetDistanceVisible(data,false)
            end
          end
        elseif data then
          SetRootVisible(data,false)
          if data.SnapLine then SetSnapVisible(data,false) end
          SetDistanceVisible(data,false)
        end
      end
    end
    return true
  end

  function ClearVisionV2.RemoveTimers()
    ClearVisionV2._TimerGeneration=(ClearVisionV2._TimerGeneration or 0)+1
    local owner = ClearVisionV2.TimerOwner
    if IsValid(owner) then
      if ClearVisionV2.ScanTimer then pcall(function() owner:RemoveGameTimer(ClearVisionV2.ScanTimer) end) end
      if ClearVisionV2.DrawTimer then pcall(function() owner:RemoveGameTimer(ClearVisionV2.DrawTimer) end) end
    end
    ClearVisionV2.ScanTimer=nil
    ClearVisionV2.DrawTimer=nil
    ClearVisionV2.TimerOwner=nil
  end

  function ClearVisionV2.Stop()
    ClearVisionV2.Active=false
    ClearVisionV2.RemoveTimers()
    for key,data in pairs(ClearVisionV2.EnemyWidgets) do
      if data then
        if data.Root then DestroyWidget(data.Root) end
        if data.SnapLine and data.SnapLine.Widget then DestroyWidget(data.SnapLine.Widget) end
        if data.DistanceText and data.DistanceText.Widget then DestroyWidget(data.DistanceText.Widget) end
        if data.DistanceTextBack and data.DistanceTextBack.Widget then DestroyWidget(data.DistanceTextBack.Widget) end
      end
      ClearVisionV2.EnemyWidgets[key]=nil
    end
    if ClearVisionV2.Counter and ClearVisionV2.Counter.Root then DestroyWidget(ClearVisionV2.Counter.Root) end
    ClearVisionV2.Counter=nil
    ClearVisionV2.EnemyCache={}
    ClearVisionV2.EnemyMeta={}
    ClearVisionV2._ProjectionCache={}
    ClearVisionV2.RealEnemyCount=0
    ClearVisionV2.BotEnemyCount=0
    ClearVisionV2._FrameSerial=0
    ClearVisionV2._CounterVisible=nil
    ClearVisionV2.Controller=nil
    ClearVisionV2.LocalPawn=nil
    ClearVisionV2.ESPCanvas=nil
    ClearVisionV2._SessionWorld=nil
    ClearVisionV2._SessionController=nil
    ClearVisionV2._SessionPawn=nil
    ClearVisionV2._SessionCanvas=nil

    local retryOwner=ClearVisionV2.StartRetryOwner
    local retryTimer=ClearVisionV2.StartRetryTimer
    ClearVisionV2.StartRetryOwner=nil
    ClearVisionV2.StartRetryTimer=nil
    if retryOwner and retryTimer and type(retryOwner.RemoveGameTimer)=="function" then
      pcall(function() retryOwner:RemoveGameTimer(retryTimer) end)
    end
    return true
  end

  function ClearVisionV2.Start()
    if not CV2Flag("EspV2Enabled", false) then return false end
    if ClearVisionV2.Active and ClearVisionV2.ScanTimer and ClearVisionV2.DrawTimer then return true end

    local pc=ResolveControllerFresh() or GetController()
    local me=ResolveLocalPawnFresh(pc) or GetLocalPawn(pc)
    if not IsValid(pc) or not IsValid(me) then return false end

    ClearVisionV2.Controller=pc
    ClearVisionV2.LocalPawn=me
    ClearVisionV2.ESPCanvas=nil
    if not ClearVisionV2.InitCanvas(true) then return false end
    if type(pc.AddGameTimer)~="function" then return false end

    ClearVisionV2.RemoveTimers()
    ClearVisionV2.Active=true
    ClearVisionV2.TimerOwner=pc
    ClearVisionV2._SessionWorld=GetWorldSafe()
    ClearVisionV2._SessionController=pc
    ClearVisionV2._SessionPawn=me
    ClearVisionV2._SessionCanvas=ClearVisionV2.ESPCanvas
    ClearVisionV2._FrameSerial=0
    ClearVisionV2._CounterVisible=nil
    ClearVisionV2._TimerGeneration=(ClearVisionV2._TimerGeneration or 0)+1
    local timerGeneration=ClearVisionV2._TimerGeneration

    pcall(ClearVisionV2.RefreshEnemies)
    pcall(ClearVisionV2.Update)

    local ok1,t1=pcall(function()
      return pc:AddGameTimer(ClearVisionV2.ScanInterval,true,function()
        if ClearVisionV2.Active and ClearVisionV2._TimerGeneration==timerGeneration then
          pcall(ClearVisionV2.RefreshEnemies)
        end
      end)
    end)
    local ok2,t2=pcall(function()
      return pc:AddGameTimer(ClearVisionV2.DrawInterval,true,function()
        if ClearVisionV2.Active and ClearVisionV2._TimerGeneration==timerGeneration then
          pcall(ClearVisionV2.Update)
        end
      end)
    end)

    if ok1 and t1 then ClearVisionV2.ScanTimer=t1 end
    if ok2 and t2 then ClearVisionV2.DrawTimer=t2 end

    if not ClearVisionV2.ScanTimer or not ClearVisionV2.DrawTimer then
      ClearVisionV2.Stop()
      return false
    end
    return true
  end

  function ClearVisionV2.SyncEnabled()
    if not CV2Flag("EspV2Enabled", false) then
      if ClearVisionV2.Active or ClearVisionV2.StartRetryTimer then
        ClearVisionV2.Stop()
      end
      return true
    end

    local cfg = rawget(_G, "GTLModConfig")
    if type(cfg) == "table" then
      if type(cfg.EspRange) == "number" and cfg.EspRange > 0 then
        ClearVisionV2.RangeMeters = cfg.EspRange
      end
      if type(cfg.EspMaxEnemies) == "number" and cfg.EspMaxEnemies > 0 then
        ClearVisionV2.MaxEnemies = math.floor(cfg.EspMaxEnemies)
      end
    end

    local currentWorld=GetWorldSafe()
    local currentPC=ResolveControllerFresh()
    local currentPawn=ResolveLocalPawnFresh(currentPC)
    local currentCanvas=ResolveCanvasFresh()

    if ClearVisionV2.Active then
      local stale=false
      if not IsValid(ClearVisionV2.TimerOwner) then stale=true end
      if IsValid(currentPC) and ClearVisionV2._SessionController~=currentPC then stale=true end
      if IsValid(currentPawn) and ClearVisionV2._SessionPawn~=currentPawn then stale=true end
      if IsValid(currentCanvas) and ClearVisionV2._SessionCanvas~=currentCanvas then stale=true end
      if currentWorld~=nil and ClearVisionV2._SessionWorld~=nil
          and currentWorld~=ClearVisionV2._SessionWorld then stale=true end
      if not stale then return true end
      ClearVisionV2.Stop()
    end

    if IsValid(currentPC) then ClearVisionV2.Controller=currentPC end
    if IsValid(currentPawn) then ClearVisionV2.LocalPawn=currentPawn end
    if IsValid(currentCanvas) then ClearVisionV2.ESPCanvas=currentCanvas end
    return ClearVisionV2.Start()
  end

  _G.ClearVisionV2Runtime = ClearVisionV2
  _G.ClearVisionV2Start = function() return ClearVisionV2.Start() end
  _G.ClearVisionV2Stop = function() return ClearVisionV2.Stop() end
  _G.ClearVisionV2Sync = function() return ClearVisionV2.SyncEnabled() end
  _G.ClearVisionV2Update = function() return ClearVisionV2.Update() end
end)
-- END ESP V2

-- ============================================================
-- iPad VIEW MODULE
-- ============================================================
local function ApplyIpadView(localPlayer)
  if not Valid(localPlayer) then return end
  pcall(function()
    local cam = localPlayer.ThirdPersonCameraComponent
    if not Valid(cam) then return end
    if localPlayer.bIsWeaponAiming then return end
    local cfg = _G.GTLModConfig
    local target = 80
    if cfg and cfg.IpadView then
      target = tonumber(cfg.IpadViewFOV) or 120
      if target < 80 then target = 80 end
      if target > 160 then target = 160 end
    end
    if cam.FieldOfView ~= target then
      cam.FieldOfView = target
    end
  end)
end

-- ============================================================
-- MAGIC BULLET MODULE
-- ============================================================
local MagicBullet = { _lastHash = "", _version = 0 }

local function MB_RefreshHash()
  local c = _G.GTLModConfig
  local h = "M_" .. tostring(c.MagicHead or 1) .. "_" .. tostring(c.MagicBody or 1) .. "_" .. tostring(c.MagicLegs or 1)
  if not c.CustomMagicBullet then h = "OFF" end
  if MagicBullet._lastHash ~= h then
    MagicBullet._lastHash = h
    MagicBullet._version = MagicBullet._version + 1
    _G.GTLModState.MagicVersion = MagicBullet._version
    _G.GTLModState.MagicLastHash = h
  end
end
_G.MagicBulletRefreshHash = MB_RefreshHash

local function ApplyMagicBullet(localPlayer, allCharacters)
  if not _G.GTLModConfig.CustomMagicBullet then return end
  MB_RefreshHash()
  local cfg = _G.GTLModConfig
  local mH = tonumber(cfg.MagicHead) or 1.0
  local mB = tonumber(cfg.MagicBody) or 1.0
  local mL = tonumber(cfg.MagicLegs) or 1.0
  local map = {
    ["head"] = mH, ["neck_01"] = mH,
    ["pelvis"] = mB, ["spine_01"] = mB, ["spine_02"] = mB, ["spine_03"] = mB,
    ["thigh_l"] = mL, ["thigh_r"] = mL, ["calf_l"] = mL, ["calf_r"] = mL,
    ["foot_l"] = mL, ["foot_r"] = mL,
  }
  local curHash = MagicBullet._lastHash
  for _, enemy in pairs(allCharacters) do
    if Valid(enemy) and enemy ~= localPlayer then
      pcall(function()
        local mesh = enemy.Mesh
        if not Valid(mesh) then return end
        local pa = mesh.PhysicsAssetOverride
        if not Valid(pa) and mesh.SkeletalMesh then pa = mesh.SkeletalMesh.PhysicsAsset end
        if not Valid(pa) or not pa.SkeletalBodySetups then return end
        local paName = "Default"
        pcall(function() paName = pa:GetName() end)
        _G.AK_ModdedPhysAssets = _G.AK_ModdedPhysAssets or {}
        _G.AK_OrigHitboxes = _G.AK_OrigHitboxes or {}
        if _G.AK_ModdedPhysAssets[paName] == curHash then return end
        _G.AK_OrigHitboxes[paName] = _G.AK_OrigHitboxes[paName] or {}
        local orig = _G.AK_OrigHitboxes[paName]
        local setups = pa.SkeletalBodySetups
        local n = type(setups.Num)=="function" and setups:Num() or #setups
        local lim = n > 50 and 50 or n
        for i = 1, lim do
          local bs = type(setups.Get)=="function" and setups:Get(i-1) or setups[i]
          if Valid(bs) then
            local bone = string.lower(tostring(bs.BoneName))
            local key = nil
            for k,_ in pairs(map) do if string.find(bone,k,1,true) then key=k break end end
            if key then
              local scale = map[key] or 1.0
              local agg = bs.AggGeom
              local boxes = agg and agg.BoxElems or bs.BoxElems
              local spheres = agg and agg.SphereElems or bs.SphereElems
              local sphyls = agg and agg.SphylElems or bs.SphylElems
              local function first(t)
                if t and type(t.Num)=="function" and t:Num()>0 then return t:Get(0) end
                if t and type(t)=="table" and #t>0 then return t[1] end
                return nil end
              local be = first(boxes); local se = first(spheres); local pe = first(sphyls)
              if not orig[key] then orig[key] = {Box=nil,Sphere=nil,Sphyl=nil}
                if be then orig[key].Box = {X=be.X,Y=be.Y,Z=be.Z} end
                if se then orig[key].Sphere = {R=se.Radius} end
                if pe then orig[key].Sphyl = {R=pe.Radius,L=pe.Length} end end
              local o = orig[key]
              if o.Box and be then be.X=o.Box.X*scale; be.Y=o.Box.Y*scale; be.Z=o.Box.Z*scale
                if type(boxes.Set)=="function" then boxes:Set(0,be) elseif boxes[1]~=nil then boxes[1]=be end
                if agg then agg.BoxElems=boxes; bs.AggGeom=agg else bs.BoxElems=boxes end end
              if o.Sphere and se then se.Radius=o.Sphere.R*scale
                if type(spheres.Set)=="function" then spheres:Set(0,se) elseif spheres[1]~=nil then spheres[1]=se end
                if agg then agg.SphereElems=spheres; bs.AggGeom=agg else bs.SphereElems=spheres end end
              if o.Sphyl and pe then pe.Radius=o.Sphyl.R*scale; pe.Length=o.Sphyl.L*scale
                if type(sphyls.Set)=="function" then sphyls:Set(0,pe) elseif sphyls[1]~=nil then sphyls[1]=pe end
                if agg then agg.SphylElems=sphyls; bs.AggGeom=agg else bs.SphylElems=sphyls end end
            end
          end
        end
        if mesh.SetPhysicsAsset then mesh:SetPhysicsAsset(pa) end
        mesh.PhysicsAssetOverride = pa
        _G.AK_ModdedPhysAssets[paName] = curHash
      end)
    end
  end
end

-- ============================================================
-- MENU  |  by @MXSIFAT30MX
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

    -- FLASH SPEED
    local StackFlash = {
      { Key = "ModMenu_Flash_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ FLASH SPEED (by " .. AUTHOR .. ")", ExpandIndex = 0,
        GetFunc = function() return _G.GTLModConfig.FlashEnabled == true end,
        SetFunc = function(c,v)
          _G.GTLModConfig.FlashEnabled = (v == true)
          _G.XThrlen_Enabled = (v == true)
          return true
        end },
      { Key = "ModMenu_Flash_Speed", UI = AliasMap.Slider, Text = "   Speed (200 - 700)", ExpandHandle = "ModMenu_Flash_Ex",
        MinValue = 200, MaxValue = 700, min = 200, max = 700,
        GetFunc = function() return math.floor(_G.GTLModConfig.FlashSpeed or 400) end,
        SetFunc = function(c,v) _G.GTLModConfig.FlashSpeed = math.floor(v); return true end },
      { Key = "ModMenu_Flash_Vel", UI = AliasMap.Slider, Text = "   Boost (1.0x - 6.0x)", ExpandHandle = "ModMenu_Flash_Ex",
        MinValue = 10, MaxValue = 60, min = 10, max = 60,
        GetFunc = function() return math.floor((_G.GTLModConfig.FlashVelocityBoost or 3.5) * 10) end,
        SetFunc = function(c,v) _G.GTLModConfig.FlashVelocityBoost = v / 10.0; return true end },
    }

    -- PLUS SPEED
    local StackPlus = {
      { Key = "ModMenu_Plus_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ➕ PLUS SPEED (by " .. AUTHOR .. ")", ExpandIndex = 0,
        GetFunc = function() return _G.GTLModConfig.PlusEnabled == true end,
        SetFunc = function(c,v)
          _G.GTLModConfig.PlusEnabled = (v == true)
          _G.XThrlen_PlusEnabled = (v == true)
          return true
        end },
      { Key = "ModMenu_Plus_Speed", UI = AliasMap.Slider, Text = "   Plus Speed (300 - 800)", ExpandHandle = "ModMenu_Plus_Ex",
        MinValue = 300, MaxValue = 800, min = 300, max = 800,
        GetFunc = function() return math.floor(_G.GTLModConfig.PlusSpeed or 500) end,
        SetFunc = function(c,v) _G.GTLModConfig.PlusSpeed = math.floor(v); return true end },
      { Key = "ModMenu_Plus_Boost", UI = AliasMap.Slider, Text = "   Plus Boost (2.0x - 7.0x)", ExpandHandle = "ModMenu_Plus_Ex",
        MinValue = 20, MaxValue = 70, min = 20, max = 70,
        GetFunc = function() return math.floor((_G.GTLModConfig.PlusBoost or 4.5) * 10) end,
        SetFunc = function(c,v) _G.GTLModConfig.PlusBoost = v / 10.0; return true end },
      { Key = "ModMenu_TimeDilation", UI = AliasMap.Slider, Text = "   Time Dilation (1.0x - 2.0x)", ExpandHandle = "ModMenu_Plus_Ex",
        MinValue = 10, MaxValue = 20, min = 10, max = 20,
        GetFunc = function() return math.floor((_G.GTLModConfig.FlashTimeDilation or 1.4) * 10) end,
        SetFunc = function(c,v) _G.GTLModConfig.FlashTimeDilation = v / 10.0; return true end },
      { Key = "ModMenu_Smooth", UI = AliasMap.Switch, Text = "   Smooth Movement", ExpandHandle = "ModMenu_Plus_Ex",
        GetFunc = function() return _G.GTLModConfig.SmoothMode ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.SmoothMode = (v == true); return true end },
      { Key = "ModMenu_AntiStuck", UI = AliasMap.Switch, Text = "   Ultra Anti-Stuck", ExpandHandle = "ModMenu_Plus_Ex",
        GetFunc = function() return _G.GTLModConfig.AntiStuckMode ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.AntiStuckMode = (v == true); return true end },
      { Key = "ModMenu_Nuclear", UI = AliasMap.Switch, Text = "   🔥 Nuclear Escape (Teleport)", ExpandHandle = "ModMenu_Plus_Ex",
        GetFunc = function() return _G.GTLModConfig.NuclearEscape ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.NuclearEscape = (v == true); return true end },
    }

    -- SAFE FLASH v2
    local StackSafe = {
      { Key = "ModMenu_Safe_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ 🛡️ SAFE FLASH v2 (by " .. AUTHOR .. ")", ExpandIndex = 0,
        GetFunc = function() return _G.GTLModConfig.SafeFlashEnabled == true end,
        SetFunc = function(c,v)
          _G.GTLModConfig.SafeFlashEnabled = (v == true)
          _G.XThrlen_SafeEnabled = (v == true)
          return true
        end },
      { Key = "ModMenu_Safe_TD", UI = AliasMap.Slider, Text = "   Speed (Time Dilation 1.0x - 1.5x)", ExpandHandle = "ModMenu_Safe_Ex",
        MinValue = 10, MaxValue = 15, min = 10, max = 15,
        GetFunc = function() return math.floor((_G.GTLModConfig.SafeFlashTimeDilation or 1.20) * 10) end,
        SetFunc = function(c,v) _G.GTLModConfig.SafeFlashTimeDilation = v / 10.0; return true end },
      { Key = "ModMenu_Safe_Speed", UI = AliasMap.Slider, Text = "   Assist Speed (300 - 600)", ExpandHandle = "ModMenu_Safe_Ex",
        MinValue = 300, MaxValue = 600, min = 300, max = 600,
        GetFunc = function() return math.floor(_G.GTLModConfig.SafeFlashSpeed or 400) end,
        SetFunc = function(c,v) _G.GTLModConfig.SafeFlashSpeed = math.floor(v); return true end },
    }

    -- ESP V2
    local StackESP = {
      { Key = "ModMenu_ESPV2_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ GTL ESP ✥", ExpandIndex = 0,
        GetFunc = function() return _G.GTLModConfig.EspV2Enabled == true end,
        SetFunc = function(c,v)
          _G.GTLModConfig.EspV2Enabled = (v == true)
          if _G.ClearVisionV2Sync then pcall(_G.ClearVisionV2Sync) end
          return true
        end },
      { Key = "ModMenu_ESPV2_Counter", UI = AliasMap.Switch, Text = "   PLAYER / BOT COUNTER", ExpandHandle = "ModMenu_ESPV2_Ex",
        GetFunc = function() return _G.GTLModConfig.EspV2Counter ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.EspV2Counter = (v == true); if _G.ClearVisionV2Update then pcall(_G.ClearVisionV2Update) end; return true end },
      { Key = "ModMenu_ESPV2_Name", UI = AliasMap.Switch, Text = "   PLAYER NAME", ExpandHandle = "ModMenu_ESPV2_Ex",
        GetFunc = function() return _G.GTLModConfig.EspV2Name ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.EspV2Name = (v == true); if _G.ClearVisionV2Update then pcall(_G.ClearVisionV2Update) end; return true end },
      { Key = "ModMenu_ESPV2_Health", UI = AliasMap.Switch, Text = "   HEALTH BLOCKS", ExpandHandle = "ModMenu_ESPV2_Ex",
        GetFunc = function() return _G.GTLModConfig.EspV2Health ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.EspV2Health = (v == true); if _G.ClearVisionV2Update then pcall(_G.ClearVisionV2Update) end; return true end },
      { Key = "ModMenu_ESPV2_Bracket", UI = AliasMap.Switch, Text = "   ESP / BOX", ExpandHandle = "ModMenu_ESPV2_Ex",
        GetFunc = function() return _G.GTLModConfig.EspV2Bracket ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.EspV2Bracket = (v == true); if _G.ClearVisionV2Update then pcall(_G.ClearVisionV2Update) end; return true end },
      { Key = "ModMenu_ESPV2_Snap", UI = AliasMap.Switch, Text = "   ESP LINE (MAY LAG!)", ExpandHandle = "ModMenu_ESPV2_Ex",
        GetFunc = function() return _G.GTLModConfig.EspV2SnapLine ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.EspV2SnapLine = (v == true); return true end },
      { Key = "ModMenu_ESPV2_Dist", UI = AliasMap.Switch, Text = "   DISTANCE", ExpandHandle = "ModMenu_ESPV2_Ex",
        GetFunc = function() return _G.GTLModConfig.EspV2Distance ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.EspV2Distance = (v == true); return true end },
      { Key = "ModMenu_ESPV2_Off", UI = AliasMap.Switch, Text = "   OFFSCREEN ALERT", ExpandHandle = "ModMenu_ESPV2_Ex",
        GetFunc = function() return _G.GTLModConfig.EspV2Offscreen ~= false end,
        SetFunc = function(c,v) _G.GTLModConfig.EspV2Offscreen = (v == true); return true end },
      { Key = "ModMenu_ESPV2_Range", UI = AliasMap.Slider, Text = "   ESP RANGE (m)", ExpandHandle = "ModMenu_ESPV2_Ex",
        MinValue = 50, MaxValue = 500, min = 50, max = 500,
        GetFunc = function() return _G.GTLModConfig.EspRange or 250 end,
        SetFunc = function(c,v)
          _G.GTLModConfig.EspRange = math.floor(v + 0.5)
          if _G.ClearVisionV2Runtime then _G.ClearVisionV2Runtime.RangeMeters = _G.GTLModConfig.EspRange end
          return true end },
      { Key = "ModMenu_ESPV2_Max", UI = AliasMap.Slider, Text = "   MAX ENEMIES", ExpandHandle = "ModMenu_ESPV2_Ex",
        MinValue = 1, MaxValue = 30, min = 1, max = 30,
        GetFunc = function() return _G.GTLModConfig.EspMaxEnemies or 20 end,
        SetFunc = function(c,v)
          _G.GTLModConfig.EspMaxEnemies = math.floor(v + 0.5)
          if _G.ClearVisionV2Runtime then _G.ClearVisionV2Runtime.MaxEnemies = _G.GTLModConfig.EspMaxEnemies end
          return true end },
    }

    -- iPad View
    local StackIpad = {
      { Key = "ModMenu_Ipad_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ iPad View", ExpandIndex = 0,
        GetFunc = function() return _G.GTLModConfig.IpadView == true end,
        SetFunc = function(c,v) _G.GTLModConfig.IpadView = (v == true); return true end },
      { Key = "ModMenu_Ipad_FOV", UI = AliasMap.Slider, Text = "   FOV Angle (80-160)", ExpandHandle = "ModMenu_Ipad_Ex",
        MinValue = 80, MaxValue = 160, min = 80, max = 160,
        GetFunc = function() return _G.GTLModConfig.IpadViewFOV or 120 end,
        SetFunc = function(c,v) _G.GTLModConfig.IpadViewFOV = math.floor(v + 0.5); return true end },
    }

    -- Magic Bullet
    local StackMagic = {
      { Key = "ModMenu_Magic_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ MAGIC BULLET (Hitbox)", ExpandIndex = 0,
        GetFunc = function() return _G.GTLModConfig.CustomMagicBullet == true end,
        SetFunc = function(c,v) _G.GTLModConfig.CustomMagicBullet = (v == true); pcall(MB_RefreshHash); return true end },
      { Key = "ModMenu_Magic_Head", UI = AliasMap.Slider, Text = "   Head Hitbox (1.0x - 5.0x)", ExpandHandle = "ModMenu_Magic_Ex",
        MinValue = 100, MaxValue = 500, min = 100, max = 500,
        GetFunc = function() return math.floor(((_G.GTLModConfig.MagicHead or 1.0) * 100) + 0.5) end,
        SetFunc = function(c,v) _G.GTLModConfig.MagicHead = math.max(1.0, math.min(5.0, v / 100.0)); pcall(MB_RefreshHash); return true end },
      { Key = "ModMenu_Magic_Body", UI = AliasMap.Slider, Text = "   Body Hitbox (1.0x - 5.0x)", ExpandHandle = "ModMenu_Magic_Ex",
        MinValue = 100, MaxValue = 500, min = 100, max = 500,
        GetFunc = function() return math.floor(((_G.GTLModConfig.MagicBody or 1.0) * 100) + 0.5) end,
        SetFunc = function(c,v) _G.GTLModConfig.MagicBody = math.max(1.0, math.min(5.0, v / 100.0)); pcall(MB_RefreshHash); return true end },
      { Key = "ModMenu_Magic_Legs", UI = AliasMap.Slider, Text = "   Legs Hitbox (1.0x - 5.0x)", ExpandHandle = "ModMenu_Magic_Ex",
        MinValue = 100, MaxValue = 500, min = 100, max = 500,
        GetFunc = function() return math.floor(((_G.GTLModConfig.MagicLegs or 1.0) * 100) + 0.5) end,
        SetFunc = function(c,v) _G.GTLModConfig.MagicLegs = math.max(1.0, math.min(5.0, v / 100.0)); pcall(MB_RefreshHash); return true end },
    }

    SettingPageDefine.ModMenu = {
      Key = "ModMenu",
      Text = "❏ " .. AUTHOR .. " MENU",
      UIKey = "Setting_Page_Privacy",
      Category = {
        { Key = "Cat_Flash_Speed",  Text = "➠ FLASH SPEED", Stack = StackFlash },
        { Key = "Cat_Plus_Speed",   Text = "➕ PLUS SPEED (ULTRA)", Stack = StackPlus },
        { Key = "Cat_Safe_Flash",   Text = "🛡️ SAFE FLASH v2 (NO STUCK)", Stack = StackSafe },
        { Key = "Cat_ESP_Visual",   Text = "➠ ESP LOCATION", Stack = StackESP },
        { Key = "Cat_Ipad_View",    Text = "➠ iPad VIEW", Stack = StackIpad },
        { Key = "Cat_Magic_Bullet", Text = "➠ MAGIC BULLET", Stack = StackMagic },
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
-- MAIN LOOP (ESP sync + iPad + Magic)
-- ============================================================
local function MainLoop()
  if isExpired then return end

  if _G.GTLModConfig and _G.GTLModConfig.EspV2Enabled and _G.ClearVisionV2Sync then
    pcall(_G.ClearVisionV2Sync)
  end

  local okData, GD = pcall(require, "GameLua.GameCore.Data.GameplayData")
  if not okData or not GD then return end
  local pc = GD.GetPlayerController()
  local me = nil
  if Valid(pc) then me = pc:GetPlayerCharacterSafety() end
  if not Valid(me) then return end

  pcall(function() ApplyIpadView(me) end)

  pcall(function()
    if _G.GTLModConfig.CustomMagicBullet then
      local allChars = {}
      if GD.GetAllPlayerCharacters then allChars = GD.GetAllPlayerCharacters()
      elseif GD.GameCharacters then
        for _, c in pairs(GD.GameCharacters) do table.insert(allChars, c) end
      end
      ApplyMagicBullet(me, allChars)
    end
  end)
end

_G.GTLModState.LoopToken = (_G.GTLModState.LoopToken or 0) + 1
local myToken = _G.GTLModState.LoopToken

local function FastTick()
  if isExpired then
    if not _G.GTLModNotifiedExpire then
      Notify("MOD HAS EXPIRED! CONTACT " .. AUTHOR .. " TO RENEW!")
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
  Notify("ULTIMATE Flash + SAFE FLASH v2 + ESP + iPad + Magic Loaded. Author: " .. AUTHOR)
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
