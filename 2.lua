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

-- ============================================================
-- ESP ENEMY COUNTER (Player & Bot) - শুধুমাত্র এই কোডটুকু রাখা হলো
-- ============================================================

local ESP_Counter_State = {
    Canvas = nil,
    ImgPlayer = nil, ImgBot = nil,
    TxtPlayer = nil, TxtBot = nil,
    SlotPlayer = nil, SlotBot = nil,
    SlotTxtPlayer = nil, SlotTxtBot = nil,
    LastPlayerCount = -1, LastBotCount = -1,
    PlayerLoaded = false, BotLoaded = false,
    LastDownloadRetry = 0
}

local function ESP_IsValid(obj)
    if not obj then return false end
    if slua and slua.isValid then
        local ok, valid = pcall(slua.isValid, obj)
        return ok and valid == true
    end
    return true
end

local function ESP_GetMainCanvas()
    local uiTools = package.loaded["GameLua.Mod.BaseMod.Common.UI.InGameUITools"]
    if not uiTools then
        pcall(function() uiTools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
    end
    if not uiTools then return nil end

    local baseUI = nil
    if uiTools.GetMainControlBaseUI then
        baseUI = uiTools.GetMainControlBaseUI()
    end
    if not ESP_IsValid(baseUI) then return nil end

    if baseUI.CanvasPanel_0 and ESP_IsValid(baseUI.CanvasPanel_0) then
        return baseUI.CanvasPanel_0
    elseif baseUI.CanvasPanel_42 and ESP_IsValid(baseUI.CanvasPanel_42) then
        return baseUI.CanvasPanel_42
    end
    return nil
end

local function ESP_MakeImage(canvas, size)
    local img = CGame:NewObjectFromPath("/Script/UMG.Image", canvas)
    if not ESP_IsValid(img) then return nil, nil end
    img:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    local slot = canvas:AddChildToCanvas(img)
    if slot then
        slot:SetAutoSize(false)
        slot:SetSize(size)
        slot:SetZOrder(1005)
        slot:SetAlignment({X=0.0, Y=0.0})
    end
    return img, slot
end

local function ESP_MakeText(canvas, size, align)
    local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
    if not ESP_IsValid(txt) then return nil, nil end
    
    local font = txt.Font
    if font then
        font.Size = size
        font.TypefaceFontName = "Bold"
        if txt.SetFont then txt:SetFont(font) end
    end

    local FLinearColor = import("LinearColor")
    if FLinearColor then
        txt:SetColorAndOpacity(FLinearColor(1, 1, 1, 1))
    end
    txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    
    local slot = canvas:AddChildToCanvas(txt)
    if slot then
        slot:SetAutoSize(true)
        slot:SetZOrder(1010)
        slot:SetAlignment(align or {X=0.0, Y=0.5})
    end
    return txt, slot
end

local function ESP_LoadWidgetImage(imageWidget, filename, cacheKey)
    if not ESP_IsValid(imageWidget) then return end
    
    local baseDir = "/storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/"
    local paths = {
        baseDir .. filename,
        "/storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. filename,
        "/storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. filename,
    }

    for _, path in ipairs(paths) do
        local f = io.open(path, "r")
        if f then
            f:close()
            pcall(function()
                local assetUtil = require("common.asset_util")
                local texture = assetUtil.GetAssetSync(path)
                if texture and ESP_IsValid(texture) then
                    imageWidget:SetBrushFromTexture(texture, false)
                    imageWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    if cacheKey == "Player" then ESP_Counter_State.PlayerLoaded = true end
                    if cacheKey == "Bot" then ESP_Counter_State.BotLoaded = true end
                    return
                end
            end)
        end
    end
end

local function ESP_UpdateCounter()
    local canvas = ESP_GetMainCanvas()
    if not canvas then return end

    local pc = GameplayData.GetPlayerController and GameplayData.GetPlayerController()
    if not ESP_IsValid(pc) then return end
    local localPawn = pc:GetPlayerCharacterSafety()
    if not ESP_IsValid(localPawn) then return end

    local viewportSize = {X = 1920, Y = 1080}
    pcall(function()
        local ui_util = require("client.common.ui_util")
        local sz = ui_util and ui_util.GetViewportSize and ui_util.GetViewportSize()
        if sz and sz.X then viewportSize = sz end
    end)
    
    local centerX = viewportSize.X * 0.5
    local startY = 120

    if ESP_Counter_State.Canvas ~= canvas then
        if ESP_Counter_State.ImgPlayer and ESP_IsValid(ESP_Counter_State.ImgPlayer) then ESP_Counter_State.ImgPlayer:RemoveFromParent() end
        if ESP_Counter_State.ImgBot and ESP_IsValid(ESP_Counter_State.ImgBot) then ESP_Counter_State.ImgBot:RemoveFromParent() end
        if ESP_Counter_State.TxtPlayer and ESP_IsValid(ESP_Counter_State.TxtPlayer) then ESP_Counter_State.TxtPlayer:RemoveFromParent() end
        if ESP_Counter_State.TxtBot and ESP_IsValid(ESP_Counter_State.TxtBot) then ESP_Counter_State.TxtBot:RemoveFromParent() end
        
        ESP_Counter_State.Canvas = canvas
        ESP_Counter_State.ImgPlayer, ESP_Counter_State.SlotPlayer = ESP_MakeImage(canvas, {X=65, Y=36})
        ESP_Counter_State.ImgBot, ESP_Counter_State.SlotBot = ESP_MakeImage(canvas, {X=65, Y=36})
        ESP_Counter_State.TxtPlayer, ESP_Counter_State.SlotTxtPlayer = ESP_MakeText(canvas, 16, {X=0.0, Y=0.5})
        ESP_Counter_State.TxtBot, ESP_Counter_State.SlotTxtBot = ESP_MakeText(canvas, 16, {X=0.0, Y=0.5})
        
        ESP_Counter_State.PlayerLoaded = false
        ESP_Counter_State.BotLoaded = false
    end

    local startX = centerX - 65
    if ESP_Counter_State.SlotPlayer then ESP_Counter_State.SlotPlayer:SetPosition({X=startX, Y=startY}) end
    if ESP_Counter_State.SlotBot then ESP_Counter_State.SlotBot:SetPosition({X=startX + 65, Y=startY}) end
    if ESP_Counter_State.SlotTxtPlayer then ESP_Counter_State.SlotTxtPlayer:SetPosition({X=startX + 40, Y=startY + 18}) end
    if ESP_Counter_State.SlotTxtBot then ESP_Counter_State.SlotTxtBot:SetPosition({X=startX + 65 + 40, Y=startY + 18}) end

    if not ESP_Counter_State.PlayerLoaded then
        ESP_LoadWidgetImage(ESP_Counter_State.ImgPlayer, "ic_danger_enemy.png", "Player")
    end
    if not ESP_Counter_State.BotLoaded then
        ESP_LoadWidgetImage(ESP_Counter_State.ImgBot, "ic_clear_boot.png", "Bot")
    end

    local myTeam = localPawn.TeamID or 0
    local nPlayer, nBot = 0, 0
    
    local all = GameplayData.GetAllPlayerCharacters and GameplayData.GetAllPlayerCharacters() or {}
    for _, t in pairs(all) do
        if t and ESP_IsValid(t) and t ~= localPawn then
            local tTeam = t.TeamID or 0
            local alive = t.IsAlive and t:IsAlive() or true
            local hp = t.Health or 1
            
            if alive and hp > 0 and tTeam ~= myTeam then
                local isBot = false
                if t.bIsAI == true or t.IsAI == true then
                    isBot = true
                else
                    local ps = t.PlayerState or (t.GetPlayerState and t:GetPlayerState())
                    if ESP_IsValid(ps) and (ps.bIsABot == true or ps.bIsBot == true) then
                        isBot = true
                    end
                end
                
                if isBot then nBot = nBot + 1 else nPlayer = nPlayer + 1 end
            end
        end
    end

    if ESP_Counter_State.LastPlayerCount ~= nPlayer and ESP_IsValid(ESP_Counter_State.TxtPlayer) then
        ESP_Counter_State.TxtPlayer:SetText(tostring(nPlayer))
        ESP_Counter_State.LastPlayerCount = nPlayer
    end
    if ESP_Counter_State.LastBotCount ~= nBot and ESP_IsValid(ESP_Counter_State.TxtBot) then
        ESP_Counter_State.TxtBot:SetText(tostring(nBot))
        ESP_Counter_State.LastBotCount = nBot
    end

    local vis = UEnums.ESlateVisibility.SelfHitTestInvisible
    if ESP_IsValid(ESP_Counter_State.TxtPlayer) then ESP_Counter_State.TxtPlayer:SetWidgetVisibility(vis) end
    if ESP_IsValid(ESP_Counter_State.TxtBot) then ESP_Counter_State.TxtBot:SetWidgetVisibility(vis) end
    if ESP_IsValid(ESP_Counter_State.ImgPlayer) then ESP_Counter_State.ImgPlayer:SetWidgetVisibility(ESP_Counter_State.PlayerLoaded and vis or UEnums.ESlateVisibility.Collapsed) end
    if ESP_IsValid(ESP_Counter_State.ImgBot) then ESP_Counter_State.ImgBot:SetWidgetVisibility(ESP_Counter_State.BotLoaded and vis or UEnums.ESlateVisibility.Collapsed) end
end

local function ESP_StartCounterLoop()
    pcall(function()
        local ticker = require("common.time_ticker")
        local function Tick()
            pcall(ESP_UpdateCounter)
            ticker.AddTimerOnce(0.2, Tick)
        end
        ticker.AddTimerOnce(1.0, Tick)
    end)
end

if not _G._ESP_Counter_Started then
    _G._ESP_Counter_Started = true
    ESP_StartCounterLoop()
end

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
