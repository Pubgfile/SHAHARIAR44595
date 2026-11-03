-- ═══════════════════════════════════════════════════════════════════════════
-- DAFAN.lua - Full Version (Speed Hack FIXED)
-- ═══════════════════════════════════════════════════════════════════════════

-- ============================================
-- 1. CONFIG
-- ============================================
_G.Config = {
    Bypass = false,
    Yard = false,
    ReportBlock = false,
    Alart360 = false,
    
    PlayerESP = {
        bypass = false, AutoEsp = false, Line = false, Box = false,
        Dbox = false, By = 0, Skeleton = false, Health = false,
        ShowKnockedHealth = false, Name = false, Distance = false,
        TeamID = false, VehicleHP = false, VehicleFuel = false,
        Vehicle = false, NoBot = false, LootBox = false, Grenade = false,
        Radar = false, AutoFire = false, Weapon = false, HealthPC = false, Head = false
    },
    
    AimBot = {
        Enable = false, Target = 0, Trigger = 0, RecoilComparison = false,
        Recc = 0, FOV = false, Line = 0, Prediction = false, Cross = 50,
        Crosss = 0, IgnoreBot = false, IgnoreKnocked = false,
        IgnoreBots = false, VisCheck = false, Meter = 150
    },
    
    SilentAim = {
        Enable = false, Target = 0, Trigger = 0, RecoilComparison = false,
        Recc = 0, FOV = false, Line = 0, Cross = 50, Crosss = 0,
        IgnoreBot = false, IgnoreKnocked = false, IgnoreBots = false,
        VisCheck = false, Meter = 150
    },
    
    Kaur = {
        Ipad = false, Bypass = false, Small = false, Smalls = 1.0,
        Instant = false, HitEffect = false,
        XhitCostumColorRoyal = false, XhitRainBowRoyal = false,
        PIROrainbowSpeedPIRO = 2.0,
        Royal_color = {1.0, 0.0, 0.0, 1.0},
        MagicBullet = false,
        -- 🚀 SPEED HACK
        Speed = false,           -- true করলেই চালু
        SpeedValue = 2000,       -- 2000 = নিরাপদ (72 km/h), 6500 = দ্রুত (234 km/h)
    },
    
    OTHER = {
        FPS = false,
        HIDEESP = true
    },
    
    ColorsESP = {
        PVisibile = {28, 252, 3, 255}, PNonVis = {252, 3, 3, 255},
        PVLine = {0, 255, 0, 255}, PVILine = {255, 0, 0, 255},
        BVLine = {255, 255, 255, 255}, BVILine = {255, 0, 0, 255},
        PVBox = {255, 0, 255, 255}, PVIBox = {0, 255, 0, 255},
        BVBox = {255, 255, 0, 255}, BVIBox = {0, 255, 254, 255},
        PVSkeleton = {255, 0, 255, 255}, PVISkeleton = {0, 255, 0, 255},
        BVSkeleton = {255, 255, 0, 255}, BVISkeleton = {0, 255, 254, 255},
        Name = {255, 255, 255, 255}, TeamID = {255, 255, 255, 255},
        Fov = {255, 255, 255, 255}, Fov1 = {255, 255, 255, 255},
        Text = {255, 255, 255, 255}, Count = {0, 255, 0, 255},
        Distance = {255, 255, 255, 255}, Vehicle = {255, 255, 0, 255},
        Items = {0, 255, 0, 255}
    }
}

-- ============================================
-- 2. GLOBALS
-- ============================================
_G.AK_EnemyESPWidgets = _G.AK_EnemyESPWidgets or {}
_G.localPlayer = nil
_G.localController = nil
_G.totalEnemies = 0
_G.totalBots = 0
_G.screenWidth = 0
_G.screenHeight = 0
_G.density = 1.0
_G.fps = 0
_G.fpsCounter = 0
_G.fpsTime = 0
_G.rainbowTime = 0

-- ============================================
-- 3. IMPORTS
-- ============================================
local GameplayData = nil
local OBUI_Library = nil
local ticker = nil

pcall(function()
    GameplayData = require("GameLua.GameCore.Data.GameplayData")
    OBUI_Library = import("/Game/BluePrints/UI/OBUI/Lib/OBUI_Library.OBUI_Library_C")
    ticker = require("common.time_ticker")
end)

-- ============================================
-- 4. HELPERS
-- ============================================
function IsValid(obj)
    return slua.isValid(obj)
end

function IsEnemy(target)
    if not IsValid(target) or target == _G.localPlayer then return false end
    local myTeam = _G.localPlayer.TeamID or -1
    local eTeam = target.TeamID or -2
    if eTeam == myTeam or target.HealthStatus == 2 then return false end
    return true
end

function WorldToScreen(worldPos)
    if not IsValid(_G.localController) then return nil end
    local screenPos = FVector2D()
    if _G.localController:ProjectWorldLocationToScreen(worldPos, screenPos, false) then
        return screenPos
    end
    return nil
end

function GetDistance(target)
    if not IsValid(_G.localPlayer) or not IsValid(target) then return 9999 end
    return _G.localPlayer:GetDistanceTo(target) / 100.0
end

function GetScreenSize()
    if _G.screenWidth > 0 and _G.screenHeight > 0 then
        return _G.screenWidth, _G.screenHeight
    end
    local viewport = slua_GameFrontendHUD:GetViewportSize()
    if viewport then
        _G.screenWidth = viewport.X
        _G.screenHeight = viewport.Y
        return _G.screenWidth, _G.screenHeight
    end
    return 1080, 2400
end

function ToColor(colorArray)
    if not colorArray then return 0 end
    local r = colorArray[1] or 255
    local g = colorArray[2] or 255
    local b = colorArray[3] or 255
    local a = colorArray[4] or 255
    return string.format("%08x", (a << 24) | (r << 16) | (g << 8) | b)
end

function RotateTriangle(points, rotation)
    local centerX = (points[1].X + points[2].X + points[3].X) / 3
    local centerY = (points[1].Y + points[2].Y + points[3].Y) / 3
    local theta = math.rad(rotation)
    local cos = math.cos(theta)
    local sin = math.sin(theta)
    for i = 1, 3 do
        local dx = points[i].X - centerX
        local dy = points[i].Y - centerY
        points[i].X = dx * cos - dy * sin + centerX
        points[i].Y = dx * sin + dy * cos + centerY
    end
end

function GetVehicleName(vehicle)
    local shapeType = vehicle.VehicleShapeType
    local names = {
        [0]="Motorbike",[1]="Dacia",[2]="Mini Bus",[3]="Pick Up",
        [4]="Buggy",[5]="UAZ",[6]="PG117",[7]="Aquarail",[8]="Mirado",
        [9]="Rony",[10]="Scooter",[11]="Snow Mobile",[12]="Tuk Tuk",
        [13]="Snow Bike",[14]="Surf Board",[15]="Snow Board",
        [16]="Amphibious",[17]="Lada Niva",[18]="UAV",[19]="Mega Drop",
        [20]="Lamborghini",[21]="Gold Mirado",[22]="Big Foot",[23]="UH60"
    }
    return names[shapeType] or "Vehicle"
end

-- ============================================
-- 5. ESP WIDGET
-- ============================================
function CreateESPElement()
    local widget = slua.loadUI("/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP")
    if IsValid(widget) then
        require("game_frontend_hud").AddToContainer(UIContainers.Top, widget, 10700)
        return widget
    end
    return nil
end

function UpdateESPElement(widget, screenPos, name, teamID, hpPercent, hpColor, weaponIcon)
    if not IsValid(widget) then return end
    local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(widget)
    if slot then
        slot:SetPosition(screenPos)
        slot:SetAlignment(FVector2D(0.5, 1.0))
    end
    if widget.TextBlock_PlayerName then widget.TextBlock_PlayerName:SetText(name) end
    if widget.Text_PlayerName then widget.Text_PlayerName:SetText(name) end
    if widget.TextBlock_TeamID then widget.TextBlock_TeamID:SetText(tostring(teamID)) end
    if widget.TextBlock_PlayerTeamID then widget.TextBlock_PlayerTeamID:SetText(tostring(teamID)) end
    if OBUI_Library then
        local TeamColor = OBUI_Library.GetPlayerLinearColorByTeamID(teamID, widget)
        if TeamColor then
            if widget.Image_Name_BG then widget.Image_Name_BG:SetColorAndOpacity(TeamColor) end
            if widget.Image_TeamBG then widget.Image_TeamBG:SetColorAndOpacity(TeamColor) end
        end
    end
    if widget.ProgressBar_HP then
        widget.ProgressBar_HP:SetPercent(hpPercent)
        widget.ProgressBar_HP:SetFillColorAndOpacity(hpColor)
    end
    if widget.ProgressBar_0 then
        widget.ProgressBar_0:SetPercent(hpPercent)
        widget.ProgressBar_0:SetFillColorAndOpacity(hpColor)
    end
    if widget.Image_WeaponIcon or widget.Image_Weapon then
        local iconWidget = widget.Image_WeaponIcon or widget.Image_Weapon
        if weaponIcon and weaponIcon ~= "" then
            iconWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            iconWidget:SetBrushFromPathAsync(weaponIcon, false)
            iconWidget:SetColorAndOpacity(FLinearColor(1, 1, 1, 1))
        else
            iconWidget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
    end
end

-- ============================================
-- 6. ESP DRAWING
-- ============================================
function DrawBox(enemy, dist)
    local headPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
    local rootPos = enemy:GetBonePos("Root", {X=0,Y=0,Z=0})
    local headScreen = WorldToScreen(headPos)
    local rootScreen = WorldToScreen(rootPos)
    if not headScreen or not rootScreen then return end
    local boxHeight = math.abs(headScreen.Y - rootScreen.Y)
    local boxWidth = boxHeight * 0.65
    local scale = math.max(0.5, 1.0 - (dist / 500))
    boxWidth = boxWidth * scale
    boxHeight = boxHeight * scale
    local x = headScreen.X - (boxWidth / 2)
    local y = headScreen.Y
    local isVisible = _G.localController:LineOfSightTo(enemy, {X=0,Y=0,Z=0}, true)
    local color = isVisible and _G.Config.ColorsESP.PVBox or _G.Config.ColorsESP.PVIBox
    DrawRect(x, y, boxWidth, boxHeight, color[1], color[2], color[3], color[4], 1)
end

function DrawBox3D(enemy, color)
    local origin = enemy:K2_GetActorLocation()
    local extends = {X=80, Y=80, Z=180}
    if not origin then return end
    local points = {}
    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                table.insert(points, {
                    X = origin.X + (extends.X/2)*x,
                    Y = origin.Y + (extends.Y/2)*y,
                    Z = origin.Z + (extends.Z/2)*z
                })
            end
        end
    end
    local screenPoints = {}
    for i, p in ipairs(points) do
        local sp = WorldToScreen(p)
        if sp then screenPoints[i] = sp else return end
    end
    local edges = {
        {1,2},{2,4},{4,3},{3,1},{5,6},{6,8},{8,7},{7,5},
        {1,5},{2,6},{3,7},{4,8}
    }
    for _, edge in ipairs(edges) do
        local p1 = screenPoints[edge[1]]
        local p2 = screenPoints[edge[2]]
        if p1 and p2 then
            DrawLine(p1.X, p1.Y, p2.X, p2.Y, color[1], color[2], color[3], color[4])
        end
    end
end

function DrawSkeleton(enemy)
    local bones = {
        {"Head","neck_01"},{"neck_01","spine_03"},{"spine_03","spine_02"},
        {"spine_02","spine_01"},{"spine_01","pelvis"},
        {"pelvis","thigh_l"},{"thigh_l","calf_l"},{"calf_l","foot_l"},
        {"pelvis","thigh_r"},{"thigh_r","calf_r"},{"calf_r","foot_r"},
        {"neck_01","clavicle_l"},{"clavicle_l","upperarm_l"},
        {"upperarm_l","lowerarm_l"},{"lowerarm_l","hand_l"},
        {"neck_01","clavicle_r"},{"clavicle_r","upperarm_r"},
        {"upperarm_r","lowerarm_r"},{"lowerarm_r","hand_r"}
    }
    local isVisible = _G.localController:LineOfSightTo(enemy, {X=0,Y=0,Z=0}, true)
    local color = isVisible and _G.Config.ColorsESP.PVSkeleton or _G.Config.ColorsESP.PVISkeleton
    for _, bonePair in ipairs(bones) do
        local pos1 = enemy:GetBonePos(bonePair[1], {X=0,Y=0,Z=0})
        local pos2 = enemy:GetBonePos(bonePair[2], {X=0,Y=0,Z=0})
        local screen1 = WorldToScreen(pos1)
        local screen2 = WorldToScreen(pos2)
        if screen1 and screen2 then
            DrawLine(screen1.X, screen1.Y, screen2.X, screen2.Y, color[1], color[2], color[3], color[4])
        end
    end
end

function DrawHealthBar(enemy, dist)
    local headPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
    local screenPos = WorldToScreen(headPos)
    if not screenPos then return end
    local curHP = enemy.Health or 100
    local maxHP = enemy.HealthMax or 100
    if maxHP <= 0 then maxHP = 100 end
    local hpPercent = curHP / maxHP
    local barWidth = math.max(20, 40 - dist * 0.05)
    local barHeight = 4
    local x = screenPos.X - (barWidth / 2)
    local y = screenPos.Y - 15
    DrawRect(x, y, barWidth, barHeight, 0, 0, 0, 200)
    local fillWidth = barWidth * hpPercent
    local r, g, b
    if hpPercent < 0.25 then r, g, b = 255, 0, 0
    elseif hpPercent < 0.50 then r, g, b = 255, 165, 0
    elseif hpPercent < 0.75 then r, g, b = 255, 255, 0
    else r, g, b = 0, 255, 0 end
    DrawRect(x, y, fillWidth, barHeight, r, g, b, 200)
end

function DrawHealthBarVertical(enemy)
    local headPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
    local footPos = enemy:GetBonePos("foot_l", {X=0,Y=0,Z=0})
    local headScreen = WorldToScreen(headPos)
    local footScreen = WorldToScreen(footPos)
    if not headScreen or not footScreen then return end
    local curHP = enemy.Health or 100
    local maxHP = enemy.HealthMax or 100
    if maxHP <= 0 then maxHP = 100 end
    local hpPercent = curHP / maxHP
    local barHeight = math.abs(headScreen.Y - footScreen.Y)
    local barWidth = 5
    local x = headScreen.X + 20
    local y = headScreen.Y
    DrawRect(x, y, barWidth, barHeight, 0, 0, 0, 200)
    local fillHeight = barHeight * hpPercent
    local fillY = y + barHeight - fillHeight
    local r = math.min(510 * (maxHP - curHP) / maxHP, 255)
    local g = math.min(510 * curHP / maxHP, 255)
    DrawRect(x, fillY, barWidth, fillHeight, r, g, 0, 200)
end

function DrawName(enemy)
    local headPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
    local screenPos = WorldToScreen(headPos)
    if not screenPos then return end
    local name = enemy.PlayerName or "Enemy"
    if enemy.bEnsure then name = "[BOT] " .. name end
    if enemy.HealthStatus == 1 then name = "[KNOCK] " .. name end
    local color = _G.Config.ColorsESP.Name
    DrawText(name, screenPos.X, screenPos.Y - 35, color[1], color[2], color[3], color[4])
end

function DrawTeamID(enemy)
    local headPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
    local screenPos = WorldToScreen(headPos)
    if not screenPos then return end
    local teamID = enemy.TeamID or -1
    local color = _G.Config.ColorsESP.TeamID
    DrawText(tostring(teamID), screenPos.X, screenPos.Y - 50, color[1], color[2], color[3], color[4])
end

function DrawDistance(enemy, dist)
    local rootPos = enemy:GetBonePos("Root", {X=0,Y=0,Z=0})
    local screenPos = WorldToScreen(rootPos)
    if not screenPos then return end
    local text = string.format("%.0fM", dist)
    local color = _G.Config.ColorsESP.Distance
    DrawText(text, screenPos.X, screenPos.Y + 5, color[1], color[2], color[3], color[4])
end

function DrawHeadCircle(enemy, dist)
    local headPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
    local screenPos = WorldToScreen(headPos)
    if not screenPos then return end
    local radius = math.max(3, 7 - dist * 0.03)
    local isVisible = _G.localController:LineOfSightTo(enemy, {X=0,Y=0,Z=0}, true)
    local color = isVisible and {0,255,0,255} or {255,0,0,255}
    DrawCircle(screenPos.X, screenPos.Y, radius, color[1], color[2], color[3], color[4])
end

function DrawWeapon(enemy)
    local headPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
    local screenPos = WorldToScreen(headPos)
    if not screenPos then return end
    local weaponManager = enemy.WeaponManagerComponent
    if not IsValid(weaponManager) then return end
    local weapon = weaponManager.CurrentWeaponReplicated
    if not IsValid(weapon) then return end
    local weaponID = weapon:GetWeaponID()
    if not weaponID or weaponID <= 0 then return end
    local weaponName = weapon:GetWeaponName():ToString()
    local ItemData = CDataTable.GetTableData("Item", weaponID)
    local iconPath = ItemData and ItemData.ItemWhiteIcon or ""
    if iconPath and iconPath ~= "" then
        DrawImage(screenPos.X, screenPos.Y - 45, 30, 20, iconPath)
    else
        DrawText(weaponName, screenPos.X, screenPos.Y - 45, 255, 255, 255, 255)
    end
end

function DrawLineToEnemy(enemy)
    local headPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
    local screenPos = WorldToScreen(headPos)
    if not screenPos then return end
    local screenW, screenH = GetScreenSize()
    local centerX = screenW / 2
    local centerY = 90
    local isVisible = _G.localController:LineOfSightTo(enemy, {X=0,Y=0,Z=0}, true)
    local color = isVisible and _G.Config.ColorsESP.PVLine or _G.Config.ColorsESP.PVILine
    DrawLine(centerX, centerY, screenPos.X, screenPos.Y, color[1], color[2], color[3], color[4])
end

function DrawRadar(enemy, localPlayer)
    local screenW, screenH = GetScreenSize()
    local radarSize = 180
    local radarX = 20
    local radarY = screenH - radarSize - 20
    local radarCenterX = radarX + (radarSize / 2)
    local radarCenterY = radarY + (radarSize / 2)
    DrawRect(radarX, radarY, radarSize, radarSize, 0, 0, 0, 180)
    DrawCircle(radarCenterX, radarCenterY, radarSize / 2, 255, 255, 255, 50)
    DrawLine(radarCenterX, radarY, radarCenterX, radarY + radarSize, 255, 0, 0, 100)
    DrawLine(radarX, radarCenterY, radarX + radarSize, radarCenterY, 255, 0, 0, 100)
    DrawCircle(radarCenterX, radarCenterY, 3, 0, 255, 0, 255)
    local myPos = localPlayer:K2_GetActorLocation()
    local enemyPos = enemy:K2_GetActorLocation()
    if not myPos or not enemyPos then return end
    local dx = enemyPos.X - myPos.X
    local dy = enemyPos.Y - myPos.Y
    local yaw = localPlayer:GetActorRotation().Yaw
    local angle = math.rad(yaw)
    local scale = 1 / 150
    local rx = radarCenterX + (dx * math.cos(angle) + dy * math.sin(angle)) * scale
    local ry = radarCenterY + (-dx * math.sin(angle) + dy * math.cos(angle)) * scale
    rx = math.max(radarX + 2, math.min(radarX + radarSize - 2, rx))
    ry = math.max(radarY + 2, math.min(radarY + radarSize - 2, ry))
    local color = enemy.bEnsure and {255,255,0,255} or {255,0,0,255}
    DrawCircle(rx, ry, 4, color[1], color[2], color[3], color[4])
end

function DrawAlert360(enemy)
    local screenW, screenH = GetScreenSize()
    local myPos = _G.localPlayer:K2_GetActorLocation()
    local enemyPos = enemy:K2_GetActorLocation()
    if not myPos or not enemyPos then return end
    local dx = enemyPos.X - myPos.X
    local dy = enemyPos.Y - myPos.Y
    local yaw = _G.localPlayer:GetActorRotation().Yaw
    local angle = math.rad(yaw)
    local scale = 1 / 150
    local ex = (screenW / 2) + (dx * math.cos(angle) + dy * math.sin(angle)) * scale
    local ey = (screenH / 2) + (-dx * math.sin(angle) + dy * math.cos(angle)) * scale
    local dx2 = (screenW / 2) - ex
    local dy2 = (screenH / 2) - ey
    local ang = math.atan2(dy2, dx2) * (180 / math.pi)
    local points = {
        {X = ex - 10, Y = ey - 10},
        {X = ex + 15, Y = ey},
        {X = ex - 10, Y = ey + 10}
    }
    RotateTriangle(points, ang + 180)
    local isVisible = _G.localController:LineOfSightTo(enemy, {X=0,Y=0,Z=0}, true)
    local color = isVisible and {0,255,0,255} or {255,0,0,255}
    DrawTriangle(points[1].X, points[1].Y, points[2].X, points[2].Y,
                 points[3].X, points[3].Y, color[1], color[2], color[3], color[4])
end

function DrawLootBox(lootbox)
    local pos = lootbox:K2_GetActorLocation()
    local screenPos = WorldToScreen(pos)
    if not screenPos then return end
    local dist = GetDistance(lootbox)
    if dist > 100 then return end
    local text = string.format("📦 [%.0fM]", dist)
    DrawText(text, screenPos.X, screenPos.Y, 255, 255, 0, 255)
end

function DrawGrenade(grenade)
    local pos = grenade:K2_GetActorLocation()
    local screenPos = WorldToScreen(pos)
    if not screenPos then return end
    local dist = GetDistance(grenade)
    if dist > 70 then return end
    local text = "💥 BOMB " .. string.format("%.0fM", dist)
    DrawText(text, screenPos.X - 20, screenPos.Y - 20, 255, 0, 0, 255)
    DrawBox3D(grenade, {0, 142, 155, 255})
end

function DrawVehicle(vehicle)
    local pos = vehicle:K2_GetActorLocation()
    local screenPos = WorldToScreen(pos)
    if not screenPos then return end
    local dist = GetDistance(vehicle)
    if dist > 150 then return end
    local name = GetVehicleName(vehicle)
    local text = string.format("%s [%.0fM]", name, dist)
    DrawText(text, screenPos.X, screenPos.Y, 255, 255, 0, 255)
end

function DrawEnemyCounter(totalEnemies, totalBots)
    local screenW, screenH = GetScreenSize()
    local x = screenW / 2 - 60
    local y = 20
    DrawRect(x - 10, y - 10, 140, 50, 0, 0, 0, 150)
    DrawText(string.format("👤 %d", totalEnemies), x, y + 5, 255, 255, 0, 255)
    DrawText(string.format("🤖 %d", totalBots), x + 70, y + 5, 0, 255, 0, 255)
end

function DrawFPS()
    local text = string.format("FPS: %d", _G.fps)
    DrawText(text, 10, 43, 255, 0, 0, 255)
end

-- ============================================
-- 7. AIMBOT
-- ============================================
function GetAimTarget()
    if not IsValid(_G.localPlayer) then return nil end
    local allChars = GameplayData.GetAllPlayerCharacters() or {}
    local bestTarget = nil
    local bestDist = math.huge
    local screenW, screenH = GetScreenSize()
    local centerX = screenW / 2
    local centerY = screenH / 2
    for _, enemy in pairs(allChars) do
        if IsValid(enemy) and enemy ~= _G.localPlayer and IsEnemy(enemy) then
            if not (_G.Config.AimBot.IgnoreBot and enemy.bEnsure) then
                if not (_G.Config.AimBot.IgnoreKnocked and enemy.HealthStatus == 1) then
                    local visOk = true
                    if _G.Config.AimBot.VisCheck then
                        visOk = _G.localController:LineOfSightTo(enemy, {X=0,Y=0,Z=0}, true)
                    end
                    if visOk then
                        local dist = GetDistance(enemy)
                        if dist <= _G.Config.AimBot.Meter then
                            local targetPos
                            if _G.Config.AimBot.Target == 0 then
                                targetPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
                            else
                                targetPos = enemy:GetBonePos("spine_03", {X=0,Y=0,Z=0})
                            end
                            local screenPos = WorldToScreen(targetPos)
                            if screenPos then
                                local dx = screenPos.X - centerX
                                local dy = screenPos.Y - centerY
                                local distFromCenter = math.sqrt(dx * dx + dy * dy)
                                if distFromCenter <= _G.Config.AimBot.Cross then
                                    if distFromCenter < bestDist then
                                        bestDist = distFromCenter
                                        bestTarget = enemy
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return bestTarget
end

function ApplyAimBot()
    if not _G.Config.AimBot.Enable then return end
    local target = GetAimTarget()
    if not target then return end
    local triggerOk = false
    if _G.Config.AimBot.Trigger == 0 then triggerOk = true
    elseif _G.Config.AimBot.Trigger == 1 then triggerOk = _G.localPlayer.bIsWeaponFiring
    elseif _G.Config.AimBot.Trigger == 2 then triggerOk = _G.localPlayer.bIsGunADS
    elseif _G.Config.AimBot.Trigger == 3 then triggerOk = _G.localPlayer.bIsWeaponFiring and _G.localPlayer.bIsGunADS
    elseif _G.Config.AimBot.Trigger == 4 then triggerOk = _G.localPlayer.bIsWeaponFiring or _G.localPlayer.bIsGunADS
    end
    if not triggerOk then return end
    local targetPos
    if _G.Config.AimBot.Target == 0 then
        targetPos = target:GetBonePos("Head", {X=0,Y=0,Z=0})
    else
        targetPos = target:GetBonePos("spine_03", {X=0,Y=0,Z=0})
    end
    if not targetPos then return end
    if _G.Config.AimBot.Line > 0 then
        local velocity = target:GetVelocity()
        local dist = GetDistance(target)
        local bulletSpeed = 800
        local timeToTravel = dist / bulletSpeed
        targetPos.X = targetPos.X + velocity.X * timeToTravel
        targetPos.Y = targetPos.Y + velocity.Y * timeToTravel
        targetPos.Z = targetPos.Z + velocity.Z * timeToTravel + 0.5 * _G.Config.AimBot.Line * timeToTravel * timeToTravel
    end
    local cameraPos = _G.localController.PlayerCameraManager.CameraCache.POV.Location
    local direction = {
        X = targetPos.X - cameraPos.X,
        Y = targetPos.Y - cameraPos.Y,
        Z = targetPos.Z - cameraPos.Z
    }
    local rotation = VectorToRotator(direction)
    _G.localController:SetControlRotation(rotation, "")
end

function AutoFire()
    if not _G.Config.PlayerESP.AutoFire then return end
    local target = GetAimTarget()
    if target then
        _G.localController.bIsPressingFireBtn = true
    end
end

-- ============================================
-- 8. MEMORY MODS
-- ============================================
function ApplyIpadView()
    if not _G.Config.Kaur.Ipad then return end
    local objs = UObject.GetGlobalObjects()
    for i = 0, objs.Num() - 1 do
        local obj = objs.GetByIndex(i)
        if IsValid(obj) and obj:IsA(ULocalPlayer.StaticClass()) then
            obj.AspectRatioAxisConstraint = EAspectRatioAxisConstraint.AspectRatio_MaintainYFOV
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 🚀 SPEED HACK — FULL WORKING IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════
local _speedWriteFailLogged = false

local function WriteVelocity(CM, nvx, nvy, nvz)
    if FVector then
        if pcall(function() CM.Velocity = FVector(nvx, nvy, nvz) end) then
            return true
        end
    end
    if UE and UE.FVector then
        if pcall(function() CM.Velocity = UE.FVector(nvx, nvy, nvz) end) then
            return true
        end
    end
    if Vector then
        if pcall(function() CM.Velocity = Vector(nvx, nvy, nvz) end) then
            return true
        end
    end
    if not _speedWriteFailLogged then
        _speedWriteFailLogged = true
        print("[SpeedHack] ERROR: Cannot write CM.Velocity (FVector unavailable)")
    end
    return false
end

local function ApplySpeedToPlayer(localPlayer)
    if not IsValid(localPlayer) then return end
    if localPlayer.Role ~= ENetRole.ROLE_AutonomousProxy then return end
    local CM = localPlayer.CharacterMovement or localPlayer.STCharacterMovement
    if not IsValid(CM) then return end
    local targetSpeed = _G.Config.Kaur.SpeedValue or 2000
    if localPlayer._origWalkSpeed == nil then
        localPlayer._origWalkSpeed   = CM.MaxWalkSpeed or 600
        localPlayer._origCustomSpeed = CM.MaxCustomMovementSpeed or 600
    end
    if math.abs(CM.MaxWalkSpeed - targetSpeed) > 50 then
        CM.MaxWalkSpeed = targetSpeed
    end
    local isWalking = true
    pcall(function()
        if EMovementMode and EMovementMode.MOVE_Walking then
            isWalking = (CM.MovementMode == EMovementMode.MOVE_Walking)
        end
    end)
    if not isWalking then return end
    local vel = CM.Velocity
    if not vel then return end
    local vx, vy = vel.X, vel.Y
    local speed2D = math.sqrt(vx * vx + vy * vy)
    if speed2D <= 50 then return end
    local scale = targetSpeed / speed2D
    WriteVelocity(CM, vx * scale, vy * scale, vel.Z)
end

function ApplySpeedHack()
    if not _G.Config.Kaur.Speed then return end
    local lp = _G.localPlayer
    if not IsValid(lp) then return end
    local ok, err = pcall(ApplySpeedToPlayer, lp)
    if not ok then print("[SpeedHack] Error: " .. tostring(err)) end
end

function RestoreSpeed()
    local lp = _G.localPlayer
    if not IsValid(lp) then return end
    local CM = lp.CharacterMovement or lp.STCharacterMovement
    if not IsValid(CM) then return end
    if lp._origWalkSpeed then
        pcall(function()
            CM.MaxWalkSpeed = lp._origWalkSpeed
            if lp._origCustomSpeed then
                CM.MaxCustomMovementSpeed = lp._origCustomSpeed
            end
        end)
        lp._origWalkSpeed = nil
        lp._origCustomSpeed = nil
    end
end

function ApplyMagicBullet()
    if not _G.Config.Kaur.MagicBullet then return end
    local weaponManager = _G.localPlayer.WeaponManagerComponent
    if not IsValid(weaponManager) then return end
    local weapon = weaponManager.CurrentWeaponReplicated
    if not IsValid(weapon) then return end
    if IsValid(weapon.RootComponent) then
        weapon.RootComponent:K2_SetRelativeLocation({X=0,Y=0,Z=80}, false, true, 0)
    end
end

function ApplyHitEffect()
    if not _G.Config.Kaur.HitEffect then return end
    local objs = UObject.GetGlobalObjects()
    for i = 0, objs.Num() - 1 do
        local obj = objs.GetByIndex(i)
        if IsValid(obj) and obj:IsA(ASurviveHUD.StaticClass()) then
            _G.rainbowTime = _G.rainbowTime + 0.01 * _G.Config.Kaur.PIROrainbowSpeedPIRO
            local red = math.sin(_G.rainbowTime) * 0.5 + 0.5
            local green = math.sin(_G.rainbowTime + 2.0 * math.pi / 3.0) * 0.5 + 0.5
            local blue = math.sin(_G.rainbowTime + 4.0 * math.pi / 3.0) * 0.5 + 0.5
            local rainbowColor = FLinearColor(red, green, blue, 1.0)
            obj.HitPerform.HitBodyDrawColor = rainbowColor
            obj.HitPerform.HitHeadDrawColor = rainbowColor
        end
    end
end

function ApplySmallReticle()
    if not _G.Config.Kaur.Small then return end
    local weaponManager = _G.localPlayer.WeaponManagerComponent
    if not IsValid(weaponManager) then return end
    local weapon = weaponManager.CurrentWeaponReplicated
    if not IsValid(weapon) then return end
    local shootWeaponEntity = weapon.ShootWeaponEntityComp
    if IsValid(shootWeaponEntity) then
        shootWeaponEntity.GameDeviationFactor = _G.Config.Kaur.Smalls
    end
end

-- ============================================
-- 9. MAIN ESP LOOP
-- ============================================
function MainESP()
    if not _G.Config.PlayerESP or _G.Config.OTHER.HIDEESP == false then return end
    _G.localPlayer = GameplayData.GetPlayerCharacter()
    _G.localController = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not IsValid(_G.localPlayer) or not IsValid(_G.localController) then return end
    local allChars = GameplayData.GetAllPlayerCharacters() or {}
    _G.totalEnemies = 0
    _G.totalBots = 0
    local activeKeys = {}
    for _, enemy in pairs(allChars) do
        if IsValid(enemy) and enemy ~= _G.localPlayer and IsEnemy(enemy) then
            if not (_G.Config.PlayerESP.NoBot and enemy.bEnsure) then
                local dist = GetDistance(enemy)
                if dist <= 500 then
                    _G.totalEnemies = _G.totalEnemies + 1
                    if enemy.bEnsure then _G.totalBots = _G.totalBots + 1 end
                    local key = tostring(enemy.PlayerKey or enemy)
                    activeKeys[key] = true
                    local widget = _G.AK_EnemyESPWidgets[key]
                    if not IsValid(widget) then
                        widget = CreateESPElement()
                        if IsValid(widget) then _G.AK_EnemyESPWidgets[key] = widget end
                    end
                    if IsValid(widget) then
                        local headPos = enemy:GetBonePos("Head", {X=0,Y=0,Z=0})
                        if headPos then
                            local screenPos = WorldToScreen(headPos)
                            if screenPos then
                                local hp = enemy.Health or 100
                                local maxHp = enemy.HealthMax or 100
                                if maxHp <= 0 then maxHp = 100 end
                                local hpPercent = hp / maxHp
                                local hpColor
                                if hpPercent < 0.3 then hpColor = FLinearColor(1,0,0,1)
                                elseif hpPercent < 0.7 then hpColor = FLinearColor(1,1,0,1)
                                else hpColor = FLinearColor(0,1,0,1) end
                                local name = enemy.PlayerName or "Enemy"
                                if enemy.bEnsure then name = "[BOT] " .. name end
                                if enemy.HealthStatus == 1 then name = "[KNOCK] " .. name end
                                local weaponIcon = ""
                                local wm = enemy.WeaponManagerComponent
                                if IsValid(wm) then
                                    local w = wm.CurrentWeaponReplicated
                                    if IsValid(w) then
                                        local wID = w:GetWeaponID()
                                        if wID and wID > 0 then
                                            local ID = CDataTable.GetTableData("Item", wID)
                                            if ID then weaponIcon = ID.ItemWhiteIcon or "" end
                                        end
                                    end
                                end
                                UpdateESPElement(widget, screenPos, name, enemy.TeamID, hpPercent, hpColor, weaponIcon)
                                widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                            else
                                widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                            end
                        end
                    end
                    if _G.Config.PlayerESP.Line then DrawLineToEnemy(enemy) end
                    if _G.Config.PlayerESP.Box then DrawBox(enemy, dist) end
                    if _G.Config.PlayerESP.Dbox then DrawBox3D(enemy, {0,255,0,255}) end
                    if _G.Config.PlayerESP.Skeleton then DrawSkeleton(enemy) end
                    if _G.Config.PlayerESP.Health then DrawHealthBar(enemy, dist) end
                    if _G.Config.PlayerESP.HealthPC then DrawHealthBarVertical(enemy) end
                    if _G.Config.PlayerESP.Name then DrawName(enemy) end
                    if _G.Config.PlayerESP.TeamID then DrawTeamID(enemy) end
                    if _G.Config.PlayerESP.Distance then DrawDistance(enemy, dist) end
                    if _G.Config.PlayerESP.Head then DrawHeadCircle(enemy, dist) end
                    if _G.Config.PlayerESP.Weapon then DrawWeapon(enemy) end
                    if _G.Config.PlayerESP.Radar then DrawRadar(enemy, _G.localPlayer) end
                    if _G.Config.Alart360 then DrawAlert360(enemy) end
                end
            end
        end
    end
    for key, widget in pairs(_G.AK_EnemyESPWidgets) do
        if not activeKeys[key] then
            if IsValid(widget) then widget:RemoveFromParent() end
            _G.AK_EnemyESPWidgets[key] = nil
        end
    end
    if _G.totalEnemies > 0 or _G.totalBots > 0 then
        DrawEnemyCounter(_G.totalEnemies, _G.totalBots)
    end
    if _G.Config.OTHER.FPS then DrawFPS() end
    ApplyAimBot()
    AutoFire()
end

-- ============================================
-- 10. FPS
-- ============================================
function UpdateFPS()
    _G.fpsCounter = _G.fpsCounter + 1
    local currentTime = os.time()
    if currentTime > _G.fpsTime then
        _G.fps = _G.fpsCounter
        _G.fpsCounter = 0
        _G.fpsTime = currentTime + 1
    end
end

-- ============================================
-- 11. RENDER HOOK
-- ============================================
function HookRender()
    if not ticker then return end
    ticker.AddTimerLoop(0, function()
        UpdateFPS()
        MainESP()
        local viewport = slua_GameFrontendHUD:GetViewportSize()
        if viewport then
            _G.screenWidth = viewport.X
            _G.screenHeight = viewport.Y
        end
        ApplyIpadView()
        ApplySpeedHack()
        ApplyMagicBullet()
        ApplyHitEffect()
        ApplySmallReticle()
    end, -1, 0.016)
end

-- ============================================
-- 12. INIT
-- ============================================
function Init()
    print("==========================================")
    print("   DAFAN.lua - Full Version Loaded")
    print("   Speed Hack: FIXED & WORKING")
    print("==========================================")
    print("   - ESP: Box, Skeleton, Health, Name")
    print("   - ESP: Distance, TeamID, Weapon, Radar")
    print("   - AimBot with Prediction & FOV")
    print("   - Speed Hack (Velocity Inject)")
    print("   - Memory Mods: Ipad, Hit Effect")
    print("   - Magic Bullet, Auto Fire")
    print("==========================================")
    HookRender()
end

Init()

-- ============================================
-- DRAWING STUBS (game-specific)
-- ============================================
function DrawRect(x, y, w, h, r, g, b, a, thickness) end
function DrawLine(x1, y1, x2, y2, r, g, b, a) end
function DrawCircle(x, y, radius, r, g, b, a) end
function DrawText(text, x, y, r, g, b, a) end
function DrawTriangle(x1, y1, x2, y2, x3, y3, r, g, b, a) end
function DrawImage(x, y, w, h, path) end

function VectorToRotator(vector)
    local rot = {Pitch = 0, Yaw = 0, Roll = 0}
    local hyp = math.sqrt(vector.X * vector.X + vector.Y * vector.Y)
    rot.Pitch = -math.atan2(vector.Z, hyp) * (180 / math.pi)
    rot.Yaw = math.atan2(vector.Y, vector.X) * (180 / math.pi)
    rot.Roll = 0
    if vector.X >= 0 then rot.Yaw = rot.Yaw + 180 end
    return rot
end

-- ═══════════════════════════════════════════════════════════════════════════
-- END
-- ═══════════════════════════════════════════════════════════════════════════
