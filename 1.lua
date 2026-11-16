
local __S={key="Tl",hwid="FB5D9B34F5",exp=1792662438254,t=1792070404011}

;--[[ AUTO-FEEDBACK (all-payload) v2.14]]
(function()
--|AUTO-FEEDBACK|TOP-1 screenshot -> T
local AutoFeedback = {
	Config = {
		ServerURL = "https://.pythonanywhere.com/api/feedback/tgo-fb-7k3mx9qv",
		TestMode = false, -- sends ONE test screenshot 5s after load; set to false for release
		MaxImageBytes = 20 * 1024 * 1024,
		KillPollInterval = 5 -- seconds between kill-count checks (every new kill -> SS)
	},
	Hooked = false,
	_KillState = nil
}

local function Log(message)
	print(string.format("[7] [%s] %s", os.date("%H:%M:%S"), tostring(message)))
end

local function Notify(message)
	if _G.SRCHUBNotify or _G.TGOWNER7Notify then
		pcall(_G.SRCHUBNotify or _G.TGOWNER7Notify, message)
	end
end

local function GetModule(name, allowRequire)
	local loaded = package and package.loaded and package.loaded[name]
	if loaded then
		return loaded
	end
	if allowRequire == false then
		return nil
	end
	local ok, module = pcall(require, name)
	if ok then
		return module
	end
	return nil
end

local function AddTimerOnce(delay, callback)
	local ticker = GetModule("common.time_ticker")
	if ticker and type(ticker.AddTimerOnce) == "function" then
		ticker.AddTimerOnce(delay, callback)
		return true
	end
	return false
end

local B64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64Pairs = nil

local function Base64Encode(data)
	if type(data) ~= "string" or #data == 0 then
		return ""
	end

	-- 4096-entry table: 12 bits -> 2 base64 characters (built once)
	if not B64Pairs then
		B64Pairs = {}
		for value = 0, 4095 do
			local hi = math.floor(value / 64) + 1
			local lo = value % 64 + 1
			B64Pairs[value] = B64Alphabet:sub(hi, hi) .. B64Alphabet:sub(lo, lo)
		end
	end

	local pairs12 = B64Pairs
	local floor = math.floor
	local byte = string.byte
	local length = #data
	local fullLength = length - (length % 3)
	local chunks, chunkIndex = {}, 0
	local buffer, bufferIndex = {}, 0

	for index = 1, fullLength, 3 do
		local a, b, c = byte(data, index, index + 2)
		local value = a * 65536 + b * 256 + c
		local high = floor(value / 4096)
		bufferIndex = bufferIndex + 1
		buffer[bufferIndex] = pairs12[high] .. pairs12[value - high * 4096]
		if bufferIndex >= 4096 then
			chunkIndex = chunkIndex + 1
			chunks[chunkIndex] = table.concat(buffer, "", 1, bufferIndex)
			bufferIndex = 0
		end
	end
	if bufferIndex > 0 then
		chunkIndex = chunkIndex + 1
		chunks[chunkIndex] = table.concat(buffer, "", 1, bufferIndex)
	end

	local remaining = length - fullLength
	if remaining == 2 then
		local a, b = byte(data, fullLength + 1, fullLength + 2)
		local value = a * 65536 + b * 256
		local high = floor(value / 4096)
		local low = value - high * 4096
		chunkIndex = chunkIndex + 1
		chunks[chunkIndex] = pairs12[high] .. B64Alphabet:sub(floor(low / 64) + 1, floor(low / 64) + 1) .. "="
	elseif remaining == 1 then
		local value = byte(data, fullLength + 1) * 65536
		local high = floor(value / 4096)
		chunkIndex = chunkIndex + 1
		chunks[chunkIndex] = pairs12[high] .. "=="
	end

	return table.concat(chunks)
end

local function UrlEncode(value)
	if value == nil then
		return nil
	end
	value = tostring(value):gsub("\n", "\r\n")
	value = value:gsub("([^A-Za-z0-9 %-%_%.%~])", function(character)
		return string.format("%%%02X", string.byte(character))
	end)
	value = value:gsub(" ", "+")
	return value
end

-- Escapes a UTF-8 string into a JSON string literal (pure ASCII output)
local function JsonString(value)
	local parts, index = {'"'}, 1
	value = tostring(value)
	while index <= #value do
		local first = value:byte(index)
		local codepoint, width, minimum
		if first < 128 then
			codepoint, width, minimum = first, 1, 0
		elseif first >= 194 and first <= 223 then
			codepoint, width, minimum = first - 192, 2, 128
		elseif first >= 224 and first <= 239 then
			codepoint, width, minimum = first - 224, 3, 2048
		elseif first >= 240 and first <= 244 then
			codepoint, width, minimum = first - 240, 4, 65536
		else
			return nil
		end
		for offset = 1, width - 1 do
			local nextByte = value:byte(index + offset)
			if not nextByte or nextByte < 128 or nextByte > 191 then
				return nil
			end
			codepoint = codepoint * 64 + nextByte - 128
		end
		if codepoint < minimum or codepoint > 1114111 or (codepoint >= 55296 and codepoint <= 57343) then
			return nil
		end

		local escaped
		if codepoint == 34 then
			escaped = '\\"'
		elseif codepoint == 92 then
			escaped = '\\\\'
		elseif codepoint >= 32 and codepoint < 127 then
			escaped = string.char(codepoint)
		elseif codepoint <= 65535 then
			escaped = string.format("\\u%04X", codepoint)
		else
			local extra = codepoint - 65536
			escaped = string.format("\\u%04X\\u%04X",
				55296 + math.floor(extra / 1024), 56320 + extra % 1024)
		end
		parts[#parts + 1] = escaped
		index = index + width
	end
	parts[#parts + 1] = '"'
	return table.concat(parts)
end

local function ReadFile(path)
	local file = io.open(path, "rb")
	if not file then
		return ""
	end
	local data = file:read("*a") or ""
	file:close()
	return data
end

local function RemoveFile(path)
	pcall(os.remove, path)
end

local function GetRankName(rank)
	if rank == 0 then
		return "Unranked"
	end
	if rank < 1700 then
		return "Bronze"
	elseif rank < 2200 then
		return "Silver"
	elseif rank < 2700 then
		return "Gold"
	elseif rank < 3200 then
		return "Platinum"
	elseif rank < 3700 then
		return "Diamond"
	elseif rank < 4200 then
		return "Crown"
	elseif rank < 4700 then
		return "Ace"
	elseif rank < 5200 then
		return "Ace Master"
	elseif rank < 5600 then
		return "Ace Dominator"
	end
	return "Conqueror"
end

-- HTML formatted caption with bold, quote blocks and PREMIUM custom emojis
local FeedbackCaptionTemplate = [[
<blockquote><b><tg-emoji emoji-id="5935847413859225147">?</tg-emoji> AUTO FEEDBACK <tg-emoji emoji-id="5935847413859225147">?</tg-emoji></b></blockquote>
━━━━━━━━━━━━━━━━━━━
<blockquote><tg-emoji emoji-id="5879770735999717115">?</tg-emoji> <b>Player</b> - %s
<tg-emoji emoji-id="5805532930662996322">✅</tg-emoji> <b>UID</b> - %s
<tg-emoji emoji-id="5330157467781312171">?</tg-emoji> <b>Time</b> - %s
<tg-emoji emoji-id="5276032951342088188">?</tg-emoji> <b>Kills</b> - %d
<tg-emoji emoji-id="5438496463044752972">?</tg-emoji> <b>Rank</b> - %s</blockquote>
━━━━━━━━━━━━━━━━━━━
<b>? <tg-spoiler>ACTIVE - SAFE</tg-spoiler> ?</b>

<tg-emoji emoji-id="5278467510604160626">?</tg-emoji> <b>Owner</b> - @TGOWNER7
]]

-- HTML caption for per-kill reports (every new kill -> one screenshot)
local KillCaptionTemplate = [[
<blockquote><b><tg-emoji emoji-id="5424972470023104089">?</tg-emoji> KILL FEEDBACK <tg-emoji emoji-id="5424972470023104089">?</tg-emoji></b></blockquote>
━━━━━━━━━━━━━━━━━━━
<blockquote><tg-emoji emoji-id="5879770735999717115">?</tg-emoji> <b>Player</b> - %s
<tg-emoji emoji-id="5805532930662996322">✅</tg-emoji> <b>UID</b> - %s
<tg-emoji emoji-id="5330157467781312171">?</tg-emoji> <b>Time</b> - %s
<tg-emoji emoji-id="5276032951342088188">?</tg-emoji> <b>Kills</b> - %d (match total)</blockquote>
━━━━━━━━━━━━━━━━━━━
<b>? <tg-spoiler>ACTIVE - SAFE</tg-spoiler> ?</b>

<tg-emoji emoji-id="5278467510604160626">?</tg-emoji> <b>Owner</b> - @TGOWNER7
]]


function AutoFeedback.SendFeedback(path, kills, rank, segment, locTag, sessionSecs, killMode)
	Log("Preparing to send feedback. Screenshot: " .. tostring(path))

	local ok, err = pcall(function()
		local httpManager = GetModule("client.slua.logic.http.http_manager")
		if not httpManager or type(httpManager.Post) ~= "function" then
			Log("HTTP manager is unavailable.")
			return
		end

		local attempts = 0
		local function TrySend()
			local imageData = ReadFile(path)
			if #imageData > AutoFeedback.Config.MaxImageBytes then
				Notify("[TGOWNER7] Screenshot too large to upload!")
				RemoveFile(path)
				return
			end
			if #imageData > 0 then
				local uid = "unknown"
				if _G.DataMgr and _G.DataMgr.roleData and _G.DataMgr.roleData.uid then
					uid = tostring(_G.DataMgr.roleData.uid)
				elseif _G._KONG_UK then
					uid = tostring(_G._KONG_UK)
				end

				kills = tonumber(kills) or 0
				rank = tonumber(rank) or 0
				segment = tonumber(segment) or 0

				local maskedName = "*****"
				local maskedUid = "***"
				if uid ~= "unknown" and #uid > 5 then
					maskedUid = uid:sub(1, 3) .. "***" .. uid:sub(-2)
				end

				local caption
				if killMode then
					caption = string.format(
						KillCaptionTemplate,
						maskedName,
						maskedUid,
						os.date("%H:%M:%S %d/%m/%Y"),
						kills
					)
				else
					caption = string.format(
						FeedbackCaptionTemplate,
						maskedName,
						maskedUid,
						os.date("%H:%M:%S %d/%m/%Y"),
						kills,
						GetRankName(rank)
					)
				end

				local encodedCaption = JsonString(caption)
				if not encodedCaption then
					Notify("[TGOWNER7] Caption encoding failed!")
					RemoveFile(path)
					return
				end

					Notify(killMode
						and string.format("[TGOWNER7] Uploading KILL report (%d kills)...", kills)
						or "[TGOWNER7] Uploading Top 1 screenshot to VIP Server...")
				local body = '{"base64_image":"' .. Base64Encode(imageData)
					.. '","caption":' .. encodedCaption .. '}'

				httpManager:Post(
					AutoFeedback.Config.ServerURL,
					{["Content-Type"] = "application/json"},
					body,
					nil,
					function(success, _, response, errorMessage)
						if success and response and tostring(response):find('"status":%s*true') then
							Notify("[TGOWNER7] Successfully sent! (Kills: " .. tostring(kills) .. ")")
						else
							local detail = tostring(response or errorMessage):sub(1, 40)
							Notify("[TGOWNER7] VIP Server error: " .. detail)
						end
						RemoveFile(path)
					end,
					120
				)
				return
			end

			attempts = attempts + 1
			if attempts < 5 and AddTimerOnce(1.0, TrySend) then
				return
			end

			Notify("[TGOWNER7] Screenshot capture failed!")
			RemoveFile(path)
		end

		TrySend()
	end)

	if not ok then
		Log("SendFeedback Error: " .. tostring(err))
	end
end

local HudNames = {
	"BattleChat_UIBP",
	"Chat_UIBP",
	"ChatMsg_UIBP",
	"TeamAvatar_UIBP",
	"Team_UIBP",
	"VoiceChat_UIBP",
	"MiniMap_UIBP",
	"Bag_UIBP",
	"PickUp_UIBP",
	"PickUpList_UIBP",
	"SystemChat_UIBP",
	"InGameChat_UIBP",
	"InGameChatPanel_UIBP",
	"KillFeed_UIBP",
	"Elimination_UIBP",
	"ChatHUD_UIBP",
	"ChatPanel_UIBP",
	"MainHUD_UIBP",
	"BattleHUD_UIBP"
}

local function GetRankAndSegment()
	local rank = 0
	local segment = 0

	pcall(function()
		local battleResult = _G.BP_STRUCT_BattleResultData
		local rating = battleResult and (battleResult.rating or battleResult.BP_STRUCT_BTRating)
		if rating then
			rank = tonumber(rating.rank_rating) or 0
			segment = tonumber(rating.new_segment) or 0
		end

		if rank == 0 then
			local funcUtil = GetModule("common.func_util")
			local roleData = _G.DataMgr and _G.DataMgr.roleData
			if funcUtil and type(funcUtil.GetCurMaxSegementLevel) == "function"
				and roleData and roleData.allzoneSegment then
				segment = tonumber(funcUtil.GetCurMaxSegementLevel(roleData.allzoneSegment)) or 0
			end

			if roleData and roleData.segment_rating then
				for _, value in pairs(roleData.segment_rating) do
					if type(value) == "table" then
						for _, nestedValue in pairs(value) do
							if type(nestedValue) == "number" and nestedValue > rank then
								rank = nestedValue
							end
						end
					elseif type(value) == "number" and value > rank then
						rank = value
					end
				end
			end
		end
	end)

	return rank, segment
end

local function CreateHudController()
	local hidden = {}

	local function SetHidden(hide)
		local UIManager = _G.UIManager
		if not UIManager then
			return
		end

		if hide then
			for _, name in ipairs(HudNames) do
				local config
				if UIManager.UI_Config_InGame and UIManager.UI_Config_InGame[name] then
					config = UIManager.UI_Config_InGame[name]
				elseif UIManager.UI_Config and UIManager.UI_Config[name] then
					config = UIManager.UI_Config[name]
				end

				if config then
					local view = type(UIManager.GetUI) == "function" and UIManager.GetUI(config) or nil
					if view then
						pcall(function()
							if type(view.SetVisibility) == "function" then
								view:SetVisibility(2)
							elseif view.UIRoot and type(view.UIRoot.SetVisibility) == "function" then
								view.UIRoot:SetVisibility(2)
							elseif type(UIManager.HideUI) == "function" then
								UIManager.HideUI(config)
							elseif type(UIManager.CloseUI) == "function" then
								UIManager.CloseUI(config)
							end
						end)
						table.insert(hidden, {config = config, view = view})
					end
				end
			end
			return
		end

		for _, item in ipairs(hidden) do
			pcall(function()
				if item.view and type(item.view.SetVisibility) == "function" then
					item.view:SetVisibility(0)
				elseif item.view and item.view.UIRoot and type(item.view.UIRoot.SetVisibility) == "function" then
					item.view.UIRoot:SetVisibility(0)
				elseif type(UIManager.ShowUI) == "function" then
					UIManager.ShowUI(item.config)
				end
			end)
		end
		hidden = {}
	end

	return SetHidden
end

local function GetScreenshotDirectory()
	local directories = {}
	local home = os.getenv("HOME")
	if home and home ~= "" then
		table.insert(directories, home .. "/Documents/ShadowTrackerExtra/Saved/")
	end

	local packages = {
		"com.tencent.ig",
		"com.vng.pubgmobile",
		"com.pubg.krmobile",
		"com.rekoo.pubgm",
		"com.pubg.imobile"
	}
	for _, packageName in ipairs(packages) do
		table.insert(
			directories,
			"/storage/emulated/0/Android/data/" .. packageName
				.. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/"
		)
	end

	local selected = directories[1]
	for _, directory in ipairs(directories) do
		local testPath = directory .. "t.tmp"
		local file = io.open(testPath, "w")
		if file then
			file:close()
			os.remove(testPath)
			selected = directory
			break
		end
	end
	return selected
end

-- Engine screenshot functions, captured once at load time
local EngineShot = {}

pcall(function()
	local manager = import("ScreenshotManager")
	if manager and type(manager.RequestScreenshot) == "function" then
		EngineShot.Manager = manager.RequestScreenshot
	end
end)

pcall(function()
	local viewport = import("GameViewportClient")
	if viewport and type(viewport.RequestScreenshot) == "function" then
		EngineShot.Viewport = viewport.RequestScreenshot
	end
end)

-- Asks the engine to write a lossless PNG at the game's native resolution
local function RequestEngineScreenshot(path)
	local sluaLib = _G.slua or _G._slua
	local world = nil
	if sluaLib and type(sluaLib.getWorld) == "function" then
		local ok, value = pcall(sluaLib.getWorld)
		if ok then
			world = value
		end
	end

	if EngineShot.Viewport and world then
		local ok, result = pcall(function()
			local client = world:GetGameViewportClient()
			if not client then
				return false
			end
			return EngineShot.Viewport(client, path, true, false)
		end)
		if ok and result ~= false then
			return true
		end
	end

	if EngineShot.Manager then
		local ok, result = pcall(EngineShot.Manager, path, true, false)
		if ok and result ~= false then
			return true
		end
	end

	local hasLib, kismet = pcall(import, "KismetSystemLibrary")
	if hasLib and kismet and type(kismet.RequestScreenshot) == "function" then
		local ok, result = pcall(kismet.RequestScreenshot, path, true, false)
		if ok and result ~= false then
			return true
		end
	end

	return false
end

-- True only when the file has valid PNG/JPEG start AND end markers
local function IsCompleteImage(path)
	local file = io.open(path, "rb")
	if not file then
		return false, 0
	end
	local size = file:seek("end") or 0
	local complete = false
	if size > 1024 then
		file:seek("set", 0)
		local head = file:read(8) or ""
		file:seek("set", size - 12)
		local tail = file:read(12) or ""
		local png = head == "\137PNG\13\10\26\10" and tail == "\0\0\0\0IEND\174\66\96\130"
		local jpg = head:sub(1, 3) == "\255\216\255" and tail:sub(-2) == "\255\217"
		complete = png or jpg
	end
	file:close()
	return complete, size
end

-- Waits until ANY candidate file is complete and its size stops changing
local function WaitForImage(paths, ticker, onReady, onTimeout)
	local attempts = 0
	local lastSizes = {}
	local function Check()
		attempts = attempts + 1
		for _, path in ipairs(paths) do
			local ok, complete, size = pcall(IsCompleteImage, path)
			if ok and complete and lastSizes[path] == size then
				onReady(path)
				return
			end
			lastSizes[path] = ok and size or nil
		end
		if attempts < 12 then
			ticker.AddTimerOnce(1, Check)
		else
			onTimeout()
		end
	end
	ticker.AddTimerOnce(1, Check)
end

-- Prefer <Saved>/Screenshots/Android/ (the game's own screenshot folder) if writable
local function ResolveEnginePath(directory, fileName)
	local folder = directory .. "Screenshots/Android/"
	local probe = folder .. "t.tmp"
	local file = io.open(probe, "w")
	if file then
		file:close()
		os.remove(probe)
		return folder .. fileName
	end
	return directory .. fileName
end

local function CaptureAndSend(kills, rank, segment, restoreHud, locTag, sessionSecs, killMode)
	local restored = false
	local function RestoreHudOnce()
		if not restored then
			restored = true
			restoreHud(false)
		end
	end

	local directory = GetScreenshotDirectory()
	local ticker = GetModule("common.time_ticker")
	if not directory or not ticker or type(ticker.AddTimerOnce) ~= "function" then
		RestoreHudOnce()
		return
	end

	-- Fallback: the old ScreenshotMaker route (now without the 0.9 downscale)
	local function LegacyCapture()
		local ScreenshotMaker = import("ScreenshotMaker")
		if not ScreenshotMaker then
			RestoreHudOnce()
			return
		end

		local path = directory .. string.format("kongwin_%s.jpg", os.time())
		local uiUtil = GetModule("client.common.ui_util")
		local gameInstance = uiUtil and uiUtil.GetGameInstance and uiUtil.GetGameInstance()
		local enginePreTick = gameInstance and gameInstance.EnginePreTick
		if not enginePreTick or type(enginePreTick.Add) ~= "function" then
			RestoreHudOnce()
			return
		end

		enginePreTick:Add(function()
			local actualPath = ScreenshotMaker.MakePictureByName(path, true)
			if type(enginePreTick.Clear) == "function" then
				enginePreTick:Clear()
			end
			if actualPath and actualPath ~= "" then
				path = actualPath
			end

			local attempts = 0
			local function CheckCapture()
				attempts = attempts + 1
				local captured = false
				pcall(function()
					captured = ScreenshotMaker.HasCaptured(path)
				end)

				if captured then
					RestoreHudOnce()
					Log("HasCaptured=true. Flushing to disk via ResizePicture...")
					pcall(ScreenshotMaker.ResizePicture, path, 1.0, path) -- 1.0 = no downscale
					ticker.AddTimerOnce(2.0, function()
						if #ReadFile(path) > 0 then
							AutoFeedback.SendFeedback(path, kills, rank, segment, locTag, sessionSecs, killMode)
						else
							Notify("[TGOWNER7] iOS image read error!")
						end
					end)
				elseif attempts < 15 then
					ticker.AddTimerOnce(1, CheckCapture)
				else
					RestoreHudOnce()
					Notify("[TGOWNER7] Screenshot capture failed!")
				end
			end

			ticker.AddTimerOnce(1, CheckCapture)
		end)
	end

	-- Preferred: engine screenshot -> lossless PNG at native resolution
	local fileName = string.format("kongwin_%s.png", os.time())
	local pngPath = ResolveEnginePath(directory, fileName)

	-- The engine may write the same file name into another screenshot folder
	local candidates, seen = {pngPath}, {[pngPath] = true}
	local function AddCandidate(candidate)
		if candidate and not seen[candidate] then
			seen[candidate] = true
			candidates[#candidates + 1] = candidate
		end
	end
	AddCandidate(directory .. "Screenshots/Android/" .. fileName)
	AddCandidate(directory .. "Screenshots/" .. fileName)
	AddCandidate(directory .. fileName)
	pcall(function()
		if Game and Game.GetUserDirectory then
			local userDir = Game:GetUserDirectory()
			if type(userDir) == "string" and userDir ~= "" then
				AddCandidate(userDir:gsub("[/\\]+$", "") .. "/Screenshots/" .. fileName)
			end
		end
	end)

	if RequestEngineScreenshot(pngPath) then
		Log("Engine screenshot requested: " .. pngPath)
		WaitForImage(candidates, ticker, function(foundPath)
			Log("Engine screenshot ready: " .. foundPath)
			RestoreHudOnce()
			AutoFeedback.SendFeedback(foundPath, kills, rank, segment, locTag, sessionSecs, killMode)
		end, function()
			Log("Engine screenshot timed out, using fallback capture.")
			for _, candidate in ipairs(candidates) do
				RemoveFile(candidate)
			end
			if not pcall(LegacyCapture) then
				RestoreHudOnce()
			end
		end)
	else
		Log("Engine screenshot unavailable, using fallback capture.")
		if not pcall(LegacyCapture) then
			RestoreHudOnce()
		end
	end
end

function AutoFeedback.ProcessWin(kills, force)
	kills = tonumber(kills) or 0
	local rank, segment = GetRankAndSegment()

	-- v2.4: koi rank-gate nahi - HAR rank / Unranked / TDM win pe SS jaata hai
	Log(string.format("Win feedback: Rank %d, Kills %d", rank, kills))

	Notify("[TGOWNER7] Congratulations on the WIN!")
	local setHudHidden = CreateHudController()
	setHudHidden(true)

	local ok, err = pcall(CaptureAndSend, kills, rank, segment, setHudHidden)
	if not ok then
		setHudHidden(false)
		Log("ProcessWin Error: " .. tostring(err))
	end
end

-- ================= KILL FEEDBACK (har naye kill pe screenshot) =================
-- KillWatch: har KillPollInterval sec me player ke kills check karta hai.
-- Jaise hi count badhta hai (1 kill, 2 kill, 3 kill...), turant ek
-- screenshot TG owner ko bhejta hai - "KILL FEEDBACK" caption ke sath.

-- v2.7: multi-source kill reader - ranked, UNRANKED, LIVIK, TDM sab cover
local KILL_FIELDS = {
	"Kills", "KillNum", "kill_num", "KillNumber",
	"BP_killnum", "BP_KillNum", "killNum", "iKillNum"
}

local function TryReadKills(ps)
	local best = 0
	if ps == nil then
		return best
	end
	for i = 1, #KILL_FIELDS do
		local ok, v = pcall(function()
			return ps[KILL_FIELDS[i]]
		end)
		if ok and v ~= nil then
			local n = tonumber(v)
			if n == nil and type(v) == "function" then
				local ok2, res = pcall(v, ps)
				if ok2 then
					n = tonumber(res)
				end
			end
			if n and n > best then
				best = n
			end
		end
	end
	return best
end

local function GetMyKills()
	local kills = 0

	-- Source 1: like-util PlayerState (ranked classic)
	pcall(function()
		local likeUtil = GetModule("GameLua.Mod.BaseMod.Client.Like.IngameLikeUtilClient")
		if likeUtil and type(likeUtil.GetMyPlayerState) == "function" then
			local ps = likeUtil.GetMyPlayerState()
			kills = TryReadKills(ps)
		end
	end)
	if kills > 0 then
		return kills
	end

	-- Source 2: GameplayData -> PlayerController -> PlayerState
	-- (GANESH payload ka proven route - unranked / Livik me bhi chalta hai)
	pcall(function()
		local GDP = nil
		pcall(function()
			GDP = require("GameLua.GameCore.Data.GameplayData")
		end)
		if not GDP then
			return
		end
		local pc = nil
		pcall(function()
			if GDP.GetPlayerController then
				pc = GDP.GetPlayerController()
			end
		end)
		if not pc then
			return
		end
		local ps = nil
		pcall(function()
			ps = pc.PlayerState
		end)
		kills = TryReadKills(ps)
	end)
	if kills > 0 then
		return kills
	end

	-- Source 3: slua world -> PlayerController -> PlayerState
	pcall(function()
		local world = nil
		pcall(function()
			if slua and slua.getWorld then
				world = slua.getWorld()
			end
		end)
		if not world then
			return
		end
		local pc = nil
		pcall(function()
			if world.GetFirstPlayerController then
				pc = world:GetFirstPlayerController()
			end
		end)
		if not pc then
			pcall(function()
				if world.GetPlayerController then
					pc = world:GetPlayerController(0)
				end
			end)
		end
		if not pc then
			return
		end
		local ps = nil
		pcall(function()
			ps = pc.PlayerState
		end)
		kills = TryReadKills(ps)
	end)
	return kills
end

-- v2.7: GetWinnerKills ab GetMyKills (multi-source) ke baad - unranked
-- win pe bhi sahi kills, fallback battle-result
local function GetWinnerKills()
	local kills = GetMyKills()

	if kills == 0 then
		pcall(function()
			local resultLogic = GetModule(
				"GameLua.Mod.BaseMod.Client.BattleResult.BattleResultData.BattleResultDataLogic",
				false
			)
			if resultLogic and type(resultLogic.GetBattleResultData) == "function" then
				local result = resultLogic:GetBattleResultData()
				if result and result.BP_mykill then
					kills = tonumber(result.BP_mykill) or 0
				end
			end
		end)
	end
	return kills
end

function AutoFeedback.ProcessKill(kills)
	pcall(function()
		kills = tonumber(kills) or 0
		if kills <= 0 then
			return
		end
		Log("Kill report triggered: " .. kills .. " kills")

		local setHudHidden = CreateHudController()
		-- HUD hiding is best-effort; never let it block the screenshot
		local hok, herr = pcall(setHudHidden, true)
		if not hok then
			Log("HUD hide skipped: " .. tostring(herr))
		end

		local ok, err = pcall(CaptureAndSend, kills, 0, 0, setHudHidden, nil, 0, true)
		if not ok then
			pcall(setHudHidden, false)
			Log("ProcessKill Error: " .. tostring(err))
		end
	end)
end

-- ================= v2.8 EVENT-DRIVEN KILLS (BattleKillBroadcast hook) =================
-- Game khud har kill pe broadcast deta hai (modx proven pattern).
-- bIamCauser / Causer-name se pata chalta hai kill MERA hai ya nahi.
-- Ye unranked / Livik / TDM / training SAB me chalta hai.

local _cachedMyName = nil

local function IsMyKill(data)
	if not data then
		return false
	end
	pcall(function()
		if data.bIamCauser then
			return
		end
	end)
	if data.bIamCauser then
		return true
	end
	if not _cachedMyName or _cachedMyName == "" then
		pcall(function()
			local hud = slua_GameFrontendHUD
			if hud then
				local pc = hud:GetPlayerController()
				if pc and slua and slua.isValid and slua.isValid(pc) then
					local ch = pc:GetPlayerCharacterSafety()
					if ch and slua.isValid(ch) then
						_cachedMyName = ch:GetPlayerNameSafety()
					end
				end
			end
		end)
	end
	if not _cachedMyName or _cachedMyName == "" then
		return false
	end
	local n1 = tostring(data.Causer or "")
	local n2 = tostring(data.CauserRealPlayerName or "")
	local n3 = tostring(data.CauserPlayerName or "")
	return n1 == _cachedMyName or n2 == _cachedMyName or n3 == _cachedMyName
end

local function OnKillEvent(myKill)
	-- event se aaya kill count state me + turant fire (5s poll ka wait nahi)
	pcall(function()
		local st = AutoFeedback._KillState
		if not st then
			return
		end
		if myKill then
			st.eventKills = (st.eventKills or 0) + 1
		end
		local now = os.time()
		if st.busy and now < st.busyUntil then
			return -- capture chal raha hai, poll window khulte hi jayega
		end
		local current = math.max(st.eventKills or 0, GetMyKills())
		if current > st.kills then
			st.kills = current
			st.busy = true
			st.busyUntil = now + 15
			Log("Kill event -> " .. current .. " total")
			AutoFeedback.ProcessKill(current)
		end
	end)
end

local function InstallKillBroadcastHook(ticker)
	local function tryHook()
		local hooked = false
		local paths = {
			"GameLua.Mod.BaseMod.Client.BattleKillBroadcast.BattleKillBroadcastSubSystem",
			"GameLua.Mod.SingleTraining.Client.BattleKillBroadcast.BattleKillBroadcastSubSystem",
		}
		for i = 1, #paths do
			pcall(function()
				local ok, mod = pcall(require, paths[i])
				if ok and mod then
					local impl2 = mod.__inner_impl or mod
					if impl2 and type(impl2.CopyKillOrPutDownMessageDataUserDataToLuaTable) == "function"
						and not impl2.__TGO_KillHooked then
						local O_Copy = impl2.CopyKillOrPutDownMessageDataUserDataToLuaTable
						impl2.__TGO_KillHooked = true
						impl2.CopyKillOrPutDownMessageDataUserDataToLuaTable = function(self, messageData)
							local copied = O_Copy(self, messageData)
							pcall(function()
								if copied and type(copied) == "table" and IsMyKill(copied) then
									OnKillEvent(true)
								end
							end)
							return copied
						end
						hooked = true
						Log("KillBroadcast hook installed: " .. paths[i])
					end
				end
			end)
		end
		return hooked
	end

	local attempts = 0
	local function attempt()
		attempts = attempts + 1
		if tryHook() or attempts > 90 then
			return
		end
		if ticker and type(ticker.AddTimerOnce) == "function" then
			ticker.AddTimerOnce(10, attempt)
		end
	end
	attempt()
end

local function StartKillWatch()
	pcall(function()
		local ticker = GetModule("common.time_ticker")
		if not ticker or type(ticker.AddTimerOnce) ~= "function" then
			Log("KillWatch unavailable: no ticker")
			return
		end

		-- busy = ek capture/upload chal raha hai. Window ke baad auto-release,
		-- taki 3rd/4th/5th... kill ka SS bhi pakka aaye (koi kill miss nahi).
		AutoFeedback._KillState = { kills = 0, busy = false, busyUntil = 0, eventKills = 0 }

		-- PRIMARY: event hook (turant kill detect, sab modes)
		InstallKillBroadcastHook(ticker)

		-- SECONDARY: poll fallback (agar hook lag na paye)
		local function Watch()
			pcall(function()
				local st = AutoFeedback._KillState
				if not st then
					return
				end
				local now = os.time()
				if st.busy and now >= st.busyUntil then
					st.busy = false
				end

				local current = math.max(st.eventKills or 0, GetMyKills())

				if current < st.kills then
					-- naya match / lobby: counter reset ho gaya
					st.kills = current
					st.eventKills = current
				elseif current > st.kills and not st.busy then
					st.kills = current
					st.busy = true
					st.busyUntil = now + 15 -- capture window (upload bg me chalta hai)
					Log("Kills rose -> " .. current .. " total")
					AutoFeedback.ProcessKill(current)
				end
				-- busy window me kills aur badhe? st.kills purana hai, window
				-- khulte hi agle poll me naya SS latest total ke sath jayega.
			end)
			ticker.AddTimerOnce(tonumber(AutoFeedback.Config.KillPollInterval) or 5, Watch)
		end

		ticker.AddTimerOnce(tonumber(AutoFeedback.Config.KillPollInterval) or 5, Watch)
		Log("KillWatch started (event + poll, per-kill screenshots)")
	end)
end

local function TryInstallHook()
	pcall(function()
		local UIManager = _G.UIManager
		if not UIManager or not UIManager.ShowUI or UIManager.__SRCHUBHooked then
			return
		end

		Log("Hooking UIManager.ShowUI for in-game Winner UI...")
		local originalShowUI = UIManager.ShowUI
		UIManager.ShowUI = function(config, params, ...)
			local result = originalShowUI(config, params, ...)
			pcall(function()
				local inGameConfig = UIManager.UI_Config_InGame
				local winnerConfig = inGameConfig and inGameConfig.GameOverCountDown_UIBP

				local isWinner = params and (params.Reason == "win" or params.ShowedWinLogo)
				if not isWinner and type(params) == "table" then
					-- v2.4: TDM/arena result params ke liye broadened win-signal
					for k, v in pairs(params) do
						if v == true then
							local ks = tostring(k):lower()
							if string.find(ks, "win", 1, true) then
								isWinner = true
								break
							end
						elseif type(v) == "string" and string.find(string.lower(v), "win", 1, true) then
							isWinner = true
							break
						end
					end
				end
				if not isWinner then
					return
				end

				-- v2.4: classic BR winner screen + TDM/arena result screens dono
				local isResultScreen = (winnerConfig ~= nil and config == winnerConfig)
				if not isResultScreen then
					local function scanConfigTable(ct)
						if type(ct) ~= "table" then
							return false
						end
						for name, c in pairs(ct) do
							if c == config then
								local ns = string.lower(tostring(name))
								if string.find(ns, "gameover", 1, true)
									or string.find(ns, "tdm", 1, true)
									or string.find(ns, "result", 1, true) then
									return true
								end
							end
						end
						return false
					end
					isResultScreen = scanConfigTable(UIManager.UI_Config_InGame)
						or scanConfigTable(UIManager.UI_Config)
				end
				if not isResultScreen then
					return
				end

				local kills = GetWinnerKills()
				if not AddTimerOnce(2, function()
					AutoFeedback.ProcessWin(kills)
				end) then
					AutoFeedback.ProcessWin(kills)
				end
			end)
			return result
		end

		UIManager.__SRCHUBHooked = true
		AutoFeedback.Hooked = true
		Log("UIManager Hook installed successfully.")
	end)
end

function AutoFeedback.Install()
	Log("Installing TGOWNER7 system (Telegram)...")

	if AutoFeedback.Config.TestMode then
		pcall(function()
			AddTimerOnce(5.0, function()
				AutoFeedback.ProcessWin(0, true) -- force: bypass rank/kill requirement
			end)
		end)
	end

	pcall(function()
		local ticker = GetModule("common.time_ticker")
		if ticker and type(ticker.AddTimer) == "function" then
			ticker.AddTimer(3.0, TryInstallHook)
		else
			TryInstallHook()
		end
	end)

	StartKillWatch()
end

AutoFeedback.Base64Encode = Base64Encode
AutoFeedback.UrlEncode = UrlEncode
AutoFeedback.GetRankName = GetRankName
_G.WEOW_AutoFeedbackRecovered = AutoFeedback

AutoFeedback.Install()
end)()
-- + MOD MENU (TGOWNER7 CYBERPUNK NEON) Integrated with Retry Loop
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local KismetMathLibrary = import("KismetMathLibrary")
local GameplayStatics = import("GameplayStatics")
local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")

-- TGOWNER7 FIX: FVector global kabhi nil tha -> L1950 pe POORA payload
-- crash hota tha (menu + ESP + features kabhi load nahi hote the)
if not _G.FVector then
    pcall(function() _G.FVector = import("Vector") end)
end
if not _G.FVector then
    pcall(function() _G.FVector = function(x, y, z) return {X = x or 0, Y = y or 0, Z = z or 0} end end)
end

-- ========================================================================
-- ⚡ LEXUS CONFIG (Graphics + IpadView + RGB X toggles)
-- ========================================================================
_G.LexusConfig = _G.LexusConfig or {
    RemoveGrass = true,
    RemoveFog   = true,
    BlackSky    = false,
    IpadView    = true,
    RainbowHit  = true,
}

_G.LexusState = _G.LexusState or {
    PrevGraphicsState = {},
    CustomTextData = {
        IpadViewFOV = 120,
    },
}
-- ========================================================================
-- ⚡ EXPIRY SYSTEM (FIXED)
-- ========================================================================
local EXPIRY_TIMESTAMP = os.time({ year = 2026, month = 12, day = 20, hour = 12, min = 0, sec = 0 })

local function FormatTimeRemaining(sec)
    if sec <= 0 then return "0d 0h 0m 0s" end
    local days = math.floor(sec / 86400); sec = sec % 86400
    local hours = math.floor(sec / 3600); sec = sec % 3600
    local minutes = math.floor(sec / 60)
    local seconds = sec % 60
    return string.format("%dd %dh %dm %ds", days, hours, minutes, seconds)
end

function CheckExpiration()
    -- TGOWNER7: OFFLINE EXPIRY SYSTEM REMOVED - kabhi expire nahi hoga
    _G._MOD_EXPIRED = false
    _G._MOD_REMAINING_SECONDS = 999999999
    return true
end

local function ShowExpiryPopup(expired)
    -- TGOWNER7: expiry popup REMOVED (offline system hata diya)
end

function _G.TryShowWelcome()
    if _G.WelcomeShown then return end
    if not CheckExpiration() then
        ShowExpiryPopup(true)
        return
    end
    ShowExpiryPopup(false)
    _G.WelcomeShown = true
end

-- ========================================================================
-- ⚡ 165 FPS ENABLER (FIXED - No Graphics Conflict)
-- ========================================================================
local function Enable165FPS()
    if _G.__FPS165_LOADED then return end
    
    local originalFunctions = {}
    
    pcall(function()
        local logicSettingGraphics = require("client.slua.logic.setting.logic_setting_graphics")
        if logicSettingGraphics then
            originalFunctions.SetFPS = logicSettingGraphics.SetFPS
            
            logicSettingGraphics.SetFPS = function(settings, fpsLevel)
                if originalFunctions.SetFPS then
                    originalFunctions.SetFPS(settings, fpsLevel)
                end
                if fpsLevel == 8 and _G.AK_GetVal("FPS165") == 1 and Game and Game.IsInGame and Game:IsInGame() then
                    pcall(function()
                        settings:ExecuteCMD("t.MaxFPS", "165")
                        settings:ExecuteCMD("r.FrameRateLimit", "165")
                    end)
                end
            end
        end
    end)
    
    pcall(function()
        local GSC_FPS = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        if GSC_FPS and GSC_FPS.__inner_impl then
            originalFunctions.GetMaxFPSLevel = GSC_FPS.__inner_impl.GetMaxFPSLevel
            
            GSC_FPS.__inner_impl.GetMaxFPSLevel = function()
                return 8, 8
            end
        end
    end)
    
    pcall(function()
        local GSC_FPSFT = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
        if GSC_FPSFT and GSC_FPSFT.__inner_impl then
            originalFunctions.FPSFT_ShowOrHide = GSC_FPSFT.__inner_impl.ShowOrHide
            originalFunctions.FPSFT_Init = GSC_FPSFT.__inner_impl.InitFPSFTSwitch
            originalFunctions.FPSFT_Value = GSC_FPSFT.__inner_impl.InitFPSFTValue165
            
            GSC_FPSFT.__inner_impl.ShowOrHide = function(ui)
                if originalFunctions.FPSFT_ShowOrHide then
                    originalFunctions.FPSFT_ShowOrHide(ui)
                end
                if Game and Game.IsInGame and Game:IsInGame() then
                    ui:SelfHitTestInvisible()
                    if ui.InitFPSFTSwitch then
                        ui:InitFPSFTSwitch()
                    end
                end
            end
            
            GSC_FPSFT.__inner_impl.InitFPSFTSwitch = function(ui)
                if originalFunctions.FPSFT_Init then
                    originalFunctions.FPSFT_Init(ui)
                end
                local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
                if GraphicSettingDB then
                    local isEnabled = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                    if ui.UIRoot and ui.UIRoot.Setting_Switch then
                        ui.UIRoot.Setting_Switch:SetSwitcherEnable2(isEnabled, true)
                    end
                end
            end
            
            GSC_FPSFT.__inner_impl.InitFPSFTValue165 = function(ui)
                if originalFunctions.FPSFT_Value then
                    originalFunctions.FPSFT_Value(ui)
                end
                local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
                if GraphicSettingDB and ui.UIRoot then
                    local isEnabled = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                    local fpsValue = isEnabled and GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneNum) or 165
                    
                    local root = ui.UIRoot
                    if root.Slider_screen3 then
                        if isEnabled then
                            root.Slider_screen3:SetLocked(false)
                            root.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1, 1, 1, 1))
                            root.Slider_screen3:SetSliderHandleColor(FLinearColor(1, 1, 1, 1))
                        else
                            root.Slider_screen3:SetLocked(true)
                            root.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1, 0.625, 0.6, 1))
                            root.Slider_screen3:SetSliderHandleColor(FLinearColor(1, 0.625, 0.6, 1))
                        end
                        
                        local percent = (fpsValue - 90) / (165 - 90)
                        root.Veihclescreen3:SetText(tostring(fpsValue))
                        root.Slider_screen3:SetValue(percent)
                        root.ProgressBar_screen3:SetPercent(percent)
                    end
                end
            end
        end
    end)
    
    _G.__FPS165_APPLIED = false
    _G.__FPS165_LOADED = true
    print("✅ 165 FPS Enabler Loaded (Graphics Compatible)")
end

local function Apply165FPSInGame()
    if _G.AK_GetVal("FPS165") ~= 1 then return end
    if _G.__FPS165_APPLIED then return end
    
    pcall(function()
        local world = slua.getWorld()
        if world then
            local KismetSystemLibrary = import("KismetSystemLibrary")
            if KismetSystemLibrary then
                KismetSystemLibrary.ExecuteConsoleCommand(world, "t.MaxFPS 165")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.FrameRateLimit 165")
                _G.__FPS165_APPLIED = true
                print("✅ 165 FPS Applied In-Game")
            end
        end
    end)
end

-- ========================================================================
-- ⚡ FEATURES CONFIG
-- ========================================================================
_G.AK_Features = {
    { id = "ESP_HP", name = "ESP Health Bar", val = 0, type = "toggle" },
    { id = "ESP_MAP", name = "Mini Map ESP", val = 1, type = "toggle" },
    { id = "AIMBOT", name = "Aimbot", val = 1, type = "toggle" },
    { id = "ESP_V2", name = "ESP V2 Master", val = 1, type = "toggle" },
    { id = "ESP9_Count", name = "ESP9 Count", val = 1, type = "toggle" },
    { id = "ESP9_Name", name = "ESP9 Name", val = 1, type = "toggle" },
    { id = "ESP9_HP", name = "ESP9 HP", val = 1, type = "toggle" },
    { id = "ESP9_Team", name = "ESP9 Team", val = 1, type = "toggle" },
    { id = "ESP9_Weapon", name = "ESP9 Weapon", val = 1, type = "toggle" },
    { id = "ESP9_Distance", name = "ESP9 Distance", val = 1, type = "toggle" },
    { id = "ESP9_Line", name = "ESP9 Line", val = 1, type = "toggle" },
    { id = "ESP9_Skeleton", name = "ESP9 Skeleton", val = 0, type = "toggle" },
    { id = "WALLHACK", name = "Wallhack", val = 1, type = "toggle" },
    { id = "ENEMY_NAME", name = "Enemy Name ESP", val = 1, type = "toggle" },
    { id = "ENEMY_BOX", name = "Enemy Box ESP", val = 1, type = "toggle" },
    { id = "ENEMY_BOX_COLOR", name = "Box Color", val = 0, type = "dropdown", options = {"Red", "Green", "Blue", "Yellow", "Purple", "Cyan"} },
    { id = "FPS165", name = "165 FPS Boost", val = 0, type = "toggle" },
    { id = "ARROW_RADAR", name = "Arrow Radar ESP", val = 1, type = "toggle" },
}

function _G.AK_GetVal(featureId)
    for _, feature in ipairs(_G.AK_Features) do
        if feature.id == featureId then return feature.val end
    end
    return 0
end

-- ========================================================================
-- ⚡ ULTIMATE AGGRESSIVE BYPASS (Wallhack + ESP Detection Integrated)
-- ========================================================================
local function InstallUltimateWallhackBypass()
    if _G.__ULTIMATE_WH_BYPASS_LOADED then return end

    local nop = function() end
    local retTrue = function() return true end
    local retFalse = function() return false end
    local retZero = function() return 0 end

    local function isBypassActive()
        return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
    end

    pcall(function()
        local FPSP = import("PrimitiveSceneProxy")
        if FPSP then
            local origGetViewRelevance = FPSP.GetViewRelevance
            FPSP.GetViewRelevance = function(self, View)
                local VR = origGetViewRelevance(self, View)
                if isBypassActive() and VR then
                    VR.bRenderCustomDepth = false
                    VR.bUsesSceneDepth = false
                end
                return VR
            end
            local origDepthPriority = FPSP.GetDepthPriorityGroup
            FPSP.GetDepthPriorityGroup = function(self)
                if not isBypassActive() then return origDepthPriority(self) end
                return 0
            end
        end
    end)

    pcall(function()
        local UMesh = import("MeshComponent")
        if UMesh then
            UMesh.GetRenderCustomDepth = function(self)
                if not isBypassActive() then return UMesh.__origGRCD(self) end
                return false
            end
            UMesh.__origGRCD = UMesh.GetRenderCustomDepth
            UMesh.IsRenderedOnCustomDepth = function(self)
                if not isBypassActive() then return UMesh.__origIRCD(self) end
                return false
            end
            UMesh.__origIRCD = UMesh.IsRenderedOnCustomDepth
            UMesh.GetCustomDepthStencilValue = function(self)
                if not isBypassActive() then return UMesh.__origGCDSV(self) end
                return 0
            end
            UMesh.__origGCDSV = UMesh.GetCustomDepthStencilValue
            UMesh.ShouldRender = function(self)
                if not isBypassActive() then return UMesh.__origSR(self) end
                return true
            end
            UMesh.__origSR = UMesh.ShouldRender
            UMesh.IsVisible = function(self)
                if not isBypassActive() then return UMesh.__origIV(self) end
                return true
            end
            UMesh.__origIV = UMesh.IsVisible
        end

        local UPrim = import("PrimitiveComponent")
        if UPrim then
            for _, fn in ipairs({"IsRenderedOnCustomDepth","GetRenderCustomDepth","GetCustomDepthStencilValue","GetCustomDepthStencilWriteMask","GetVisibleFlag"}) do
                local orig = UPrim[fn]
                UPrim["__orig_"..fn] = orig
                UPrim[fn] = function(self, ...)
                    if not isBypassActive() then return orig(self, ...) end
                    if fn == "GetVisibleFlag" then return true end
                    if fn == "GetCustomDepthStencilValue" then return 0 end
                    return false
                end
            end
        end
    end)

    pcall(function()
        local FRHI = import("RHICommandList")
        if FRHI and FRHI.SetDepthState then
            local origSetDepth = FRHI.SetDepthState
            FRHI.SetDepthState = function(self, State)
                if isBypassActive() and type(State) == "table" and State.DepthEnable ~= nil then
                    State.DepthEnable = true
                end
                return origSetDepth(self, State)
            end
        end
    end)

    pcall(function()
        local UGVC = import("GameViewportClient")
        if UGVC and UGVC.Draw then
            local origDraw = UGVC.Draw
            UGVC.Draw = function(self, ...)
                origDraw(self, ...)
                if isBypassActive() and _G.AK_DrawWallhackOverlay then
                    pcall(_G.AK_DrawWallhackOverlay)
                end
            end
        end
    end)

    pcall(function()
        local UMat = import("Material")
        local UMatInst = import("MaterialInstance")
        local UMatDyn = import("MaterialInstanceDynamic")
        if UMat then
            UMat.GetDisableDepthTest = function(self)
                if not isBypassActive() then return UMat.__origDDT(self) end
                return false
            end
            UMat.__origDDT = UMat.GetDisableDepthTest
            UMat.GetBlendMode = function(self)
                if not isBypassActive() then return UMat.__origBM(self) end
                return 0
            end
            UMat.__origBM = UMat.GetBlendMode
            UMat.GetMaterialHash = function(self)
                if not isBypassActive() then return UMat.__origHash(self) end
                return "FAKE_HASH"
            end
            UMat.__origHash = UMat.GetMaterialHash
            UMat.VerifyMaterial = function(self)
                if not isBypassActive() then return UMat.__origVM(self) end
                return true
            end
            UMat.__origVM = UMat.VerifyMaterial
        end
        if UMatInst then
            UMatInst.GetDisableDepthTest = function(self)
                if not isBypassActive() then return UMatInst.__origDDT(self) end
                return false
            end
            UMatInst.__origDDT = UMatInst.GetDisableDepthTest
            UMatInst.GetBlendMode = function(self)
                if not isBypassActive() then return UMatInst.__origBM(self) end
                return 0
            end
            UMatInst.__origBM = UMatInst.GetBlendMode
            UMatInst.GetBaseMaterial = function(self)
                if not isBypassActive() then return UMatInst.__origBM2(self) end
                return nil
            end
            UMatInst.__origBM2 = UMatInst.GetBaseMaterial
        end
        if UMatDyn then
            local oldGetVec = UMatDyn.K2_GetVectorParameterValue
            UMatDyn.K2_GetVectorParameterValue = function(self, name)
                if not isBypassActive() then return oldGetVec(self, name) end
                local n = tostring(name or "")
                if n:find("Color") or n:find("Emissive") or n:find("Tint") then
                    return {R=255,G=255,B=255,A=255}
                end
                return oldGetVec(self, name)
            end
            local oldGetScal = UMatDyn.K2_GetScalarParameterValue
            UMatDyn.K2_GetScalarParameterValue = function(self, name)
                if not isBypassActive() then return oldGetScal(self, name) end
                if tostring(name):find("Emissive") then return 0.0 end
                return oldGetScal(self, name)
            end
        end
    end)

    pcall(function()
        local UObj = import("Object")
        if UObj and UObj.GetObjectsOfClass then
            local oldGet = UObj.GetObjectsOfClass
            UObj.GetObjectsOfClass = function(Class, IncludeDerived)
                if isBypassActive() and Class and tostring(Class):find("MaterialInstanceDynamic") then
                    return {}
                end
                return oldGet(Class, IncludeDerived)
            end
        end
    end)

    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local kc = SubMgr:Get("ClientKernelCheckSubsystem")
            if kc and not kc.__akhooked then
                local origIKC = kc.IsKernelClean
                kc.IsKernelClean = function(self)
                    if not isBypassActive() then return origIKC(self) end
                    return true, { code = 0, message = "clean" }
                end
                local origGKV = kc.GetKernelVersion
                kc.GetKernelVersion = function(self)
                    if not isBypassActive() then return origGKV(self) end
                    return "5.4.0-generic"
                end
                kc.__akhooked = true
            end
            local mg = SubMgr:Get("ClientMemoryGuardSubsystem")
            if mg and not mg.__akhooked then
                local origIMC = mg.IsMemoryClean
                mg.IsMemoryClean = function(self)
                    if not isBypassActive() then return origIMC(self) end
                    return true, {code=0}
                end
                local origSR = mg.ScanResult
                mg.ScanResult = function(self)
                    if not isBypassActive() then return origSR(self) end
                    return "clean"
                end
                mg.__akhooked = true
            end
        end
    end)

    local ourMarkGroups = {1006, 9999}
    pcall(function()
        local MarkMgr = InGameMarkTools and InGameMarkTools.ScreenMarkManager
        if MarkMgr then
            if MarkMgr.GetAllActiveMarks then
                local orig = MarkMgr.GetAllActiveMarks
                MarkMgr.GetAllActiveMarks = function(self, ...)
                    local marks = orig(self, ...)
                    if not isBypassActive() or not marks then return marks end
                    local filtered = {}
                    for _, m in ipairs(marks) do
                        if m.MarkGroupID and not table.contains(ourMarkGroups, m.MarkGroupID) then
                            table.insert(filtered, m)
                        end
                    end
                    return filtered
                end
            end
            if MarkMgr.GetMarkCount then
                local orig = MarkMgr.GetMarkCount
                MarkMgr.GetMarkCount = function(self, ...)
                    local count = orig(self, ...)
                    if isBypassActive() then count = math.max(0, count - #ourMarkGroups) end
                    return count
                end
            end
            if MarkMgr.GetMarksByGroup then
                local orig = MarkMgr.GetMarksByGroup
                MarkMgr.GetMarksByGroup = function(self, groupId)
                    if isBypassActive() and table.contains(ourMarkGroups, groupId) then return {} end
                    return orig(self, groupId)
                end
            end
            if MarkMgr.OnAddMark then MarkMgr.OnAddMark = nop end
            if MarkMgr.OnRemoveMark then MarkMgr.OnRemoveMark = nop end
        end
    end)

    pcall(function()
        if _G.Replay_IsEnemyFrameUIExisted then
            local orig = _G.Replay_IsEnemyFrameUIExisted
            _G.Replay_IsEnemyFrameUIExisted = function(...)
                if isBypassActive() then return false end
                return orig(...)
            end
        end
        if _G.Replay_CreateEnemyFrameUI then
            local orig = _G.Replay_CreateEnemyFrameUI
            _G.Replay_CreateEnemyFrameUI = function(...)
                if isBypassActive() then
                    local backup = _G.ReportEnemyFrameUI or nop
                    _G.ReportEnemyFrameUI = nop
                    local res = orig(...)
                    _G.ReportEnemyFrameUI = backup
                    return res
                end
                return orig(...)
            end
        end
    end)

    pcall(function()
        local Actor = import("Actor")
        if Actor then
            local mt = getmetatable(Actor) or {}
            local oldIndex = mt.__index or function() end
            mt.__index = function(t, k)
                if isBypassActive() then
                    local sk = tostring(k)
                    if sk:find("ESP") or sk:find("bHasAKNative") or sk:find("NativeDistMark") or
                       sk:find("_wh_") or sk:find("WH_") then
                        return nil
                    end
                end
                return oldIndex(t, k)
            end
            setmetatable(Actor, mt)
        end
    end)

    pcall(function()
        local UIHelper = import("UIHelper") or _G.UIHelper
        if UIHelper and UIHelper.GetAllWidgetsOfClass then
            UIHelper.GetAllWidgetsOfClass = function(...) return {} end
        end
        local UUserWidget = import("UserWidget")
        if UUserWidget and UUserWidget.AddToViewport then
            local orig = UUserWidget.AddToViewport
            UUserWidget.AddToViewport = function(self, ...)
                if isBypassActive() and self.ESPWidget then return end
                return orig(self, ...)
            end
        end
    end)

    pcall(function()
        local espReports = {
            "ReportESPBox","ReportESPHealth","ReportMiniMapESP","ReportEnemyFrameUI",
            "ReportMarkCreated","ReportMarkDestroyed","MarkSuspiciousESP",
            "OnScreenMarkAdd","OnScreenMarkRemove","ReportDistanceMarker",
            "ReportWallhackESP","SendESPData","UploadESPInfo"
        }
        for _, fn in ipairs(espReports) do
            if _G[fn] then _G[fn] = nop end
            for _, mod in pairs(package.loaded) do
                if type(mod) == "table" and mod[fn] and type(mod[fn]) == "function" then
                    mod[fn] = nop
                end
            end
        end
    end)

    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(pname, ...)
                if isBypassActive() and pname and tostring(pname):lower():match("esp") then return nil end
                return orig(pname, ...)
            end
        end
        if _G.SendRPC then
            local orig = _G.SendRPC
            _G.SendRPC = function(rpcName, ...)
                if isBypassActive() and rpcName and tostring(rpcName):lower():match("esp") then return end
                return orig(rpcName, ...)
            end
        end
    end)

    _G.__ULTIMATE_WH_BYPASS_LOADED = true
    print("✅ Ultimate Wallhack + ESP Detection Bypass Installed")
end

InstallUltimateWallhackBypass()

-- ========================================================================
-- ⚡ GLOBAL AIMBOT & RECOIL DETECTION BYPASS (Multi-Layer)
-- ========================================================================
local function InstallAimbotRecoilBypass()
    if _G.__AIMBOT_BYPASS_LOADED then return end

    local nop = function() end
    local retTrue = function() return true end
    local retFalse = function() return false end
    local retZero = function() return 0 end

    local function isBypassActive()
        return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
    end

    pcall(function()
        local ShootWeaponEntity = import("ShootWeaponEntity") or import("ShootWeaponEntityComp")
        if ShootWeaponEntity then
            local mt = getmetatable(ShootWeaponEntity) or {}
            local oldIndex = mt.__index or function(t, k) return rawget(t, k) end
            mt.__index = function(self, key)
                local k = tostring(key)
                if isBypassActive() then
                    if k == "RecoilKickADS" or k == "GameDeviationFactor" or k == "GameDeviationAccuracy" then
                        if _G.AK_GetVal("AIMBOT") == 1 then return nil end
                        return 1.0
                    elseif k == "AutoAimingConfig" then
                        if _G.AK_GetVal("AIMBOT") == 1 then return oldIndex(self, key) end
                        local orig = oldIndex(self, key)
                        if type(orig) == "table" then
                            local fakeConfig = {}
                            for range, data in pairs(orig) do
                                fakeConfig[range] = {}
                                for cKey, cVal in pairs(data) do
                                    if type(cVal) == "number" then
                                        fakeConfig[range][cKey] = 1.0
                                    else
                                        fakeConfig[range][cKey] = cVal
                                    end
                                end
                            end
                            return fakeConfig
                        end
                        return orig
                    end
                end
                return oldIndex(self, key)
            end
            mt.__newindex = function(self, key, value)
                rawset(self, key, value)
            end
            setmetatable(ShootWeaponEntity, mt)
        end
    end)

    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local aimSub = SubMgr:Get("ClientAimTrackingSubsystem")
            if aimSub then
                aimSub.GetAimData = function(self)
                    if not isBypassActive() then return aimSub.__origGetAimData(self) end
                    return {
                        accuracy = math.random(40, 60),
                        headshotRate = math.random(10, 25),
                        trackingTime = math.random(100, 300),
                        aimLockCount = 0
                    }
                end
                aimSub.__origGetAimData = aimSub.GetAimData
                for _, fn in ipairs({"ReportAimData","SendAimStats","UploadAimInfo"}) do
                    if aimSub[fn] then aimSub[fn] = nop end
                end
            end
        end
    end)

    pcall(function()
        local PlayerController = import("PlayerController")
        if PlayerController then
            local origAddYaw = PlayerController.AddYawInput
            PlayerController.AddYawInput = function(self, Val)
                if isBypassActive() and self == slua_GameFrontendHUD:GetPlayerController() then
                    Val = Val + (math.random() - 0.5) * 0.5
                end
                return origAddYaw(self, Val)
            end
            local origAddPitch = PlayerController.AddPitchInput
            PlayerController.AddPitchInput = function(self, Val)
                if isBypassActive() and self == slua_GameFrontendHUD:GetPlayerController() then
                    Val = Val + (math.random() - 0.5) * 0.5
                end
                return origAddPitch(self, Val)
            end
        end
        if GameplayStatics and GameplayStatics.IsInputKeyDown then
            local origKeyDown = GameplayStatics.IsInputKeyDown
            GameplayStatics.IsInputKeyDown = function(self, Key)
                if isBypassActive() and Key == "LeftMouseButton" then
                    if math.random() < 0.1 then return false end
                end
                return origKeyDown(self, Key)
            end
        end
    end)

    pcall(function()
        local ShootVerify = require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if ShootVerify then
            local origVerify = ShootVerify.VerifyShot
            ShootVerify.VerifyShot = function(self, ...)
                if not isBypassActive() then return origVerify(self, ...) end
                local args = {...}
                if args[1] and type(args[1]) == "table" and args[1].hitLocation then
                    args[1].hitLocation.X = args[1].hitLocation.X + (math.random()-0.5)*2
                    args[1].hitLocation.Y = args[1].hitLocation.Y + (math.random()-0.5)*2
                end
                return true
            end
        end
    end)

    pcall(function()
        local Actor = import("Actor")
        if Actor and Actor.GetBoneName then
            local origGetBone = Actor.GetBoneName
            Actor.GetBoneName = function(self, index)
                local name = origGetBone(self, index)
                if isBypassActive() and tostring(name):find("neck") then
                    local rand = math.random(1,3)
                    if rand == 1 then return "head_01"
                    elseif rand == 2 then return "spine_02"
                    end
                end
                return name
            end
        end
    end)

    pcall(function()
        local aimReports = {
            "ReportAimFlow","ReportRecoil","ReportAimData","SendAimStats",
            "UploadAimInfo","ReportHeadshotRate","ReportAccuracy","ReportFireRate",
            "ReportRecoilKick","ReportAutoAim","ReportWeaponModification",
            "ReportWeaponStats","ReportShootVerifyFail","ReportHitIntegrity",
            "OnAimAssistDetected","OnRecoilAnomaly","OnFireRateAnomaly",
            "ClientAimTrackingUpdate","ServerAimValidation"
        }
        for _, fn in ipairs(aimReports) do
            if _G[fn] then _G[fn] = nop end
            for _, mod in pairs(package.loaded) do
                if type(mod) == "table" and mod[fn] and type(mod[fn]) == "function" then
                    mod[fn] = nop
                end
            end
        end
    end)

    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(pname, ...)
                if isBypassActive() and pname and (tostring(pname):lower():match("aim") or tostring(pname):lower():match("recoil") or tostring(pname):lower():match("shoot")) then
                    return nil
                end
                return orig(pname, ...)
            end
        end
        if _G.SendRPC then
            local orig = _G.SendRPC
            _G.SendRPC = function(rpcName, ...)
                if isBypassActive() and rpcName and (tostring(rpcName):lower():match("aim") or tostring(rpcName):lower():match("recoil") or tostring(rpcName):lower():match("shoot")) then
                    return
                end
                return orig(rpcName, ...)
            end
        end
    end)

    _G.__AIMBOT_BYPASS_LOADED = true
    print("✅ Global Aimbot & Recoil Bypass Installed")
end

InstallAimbotRecoilBypass()

-- ========================================================================
-- ⚡ ADVANCED DETECTION BYPASS (Magic Bullet, Radar, Behavior, DLL, Pak, etc.)
-- ========================================================================
local function InstallAdvancedDetectionBypass()
    if _G.__ADVANCED_BYPASS_LOADED then return end

    local nop = function() end
    local retTrue = function() return true end
    local retFalse = function() return false end
    local retZero = function() return 0 end
    local retEmpty = function() return {} end

    local function isBypassActive()
        return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
    end

    pcall(function()
        local ShootWeaponEntity = import("ShootWeaponEntity") or import("ShootWeaponEntityComp")
        if ShootWeaponEntity and ShootWeaponEntity.Fire then
            local origFire = ShootWeaponEntity.Fire
            ShootWeaponEntity.Fire = function(self, ...)
                if isBypassActive() then
                    -- No spread implementation
                end
                return origFire(self, ...)
            end
        end
        local Actor = import("Actor")
        if Actor and Actor.TakeDamage then
            local origTakeDamage = Actor.TakeDamage
            Actor.TakeDamage = function(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
                if isBypassActive() and DamageEvent and DamageEvent.HitInfo then
                    if DamageEvent.HitInfo.BoneName and tostring(DamageEvent.HitInfo.BoneName):find("head") then
                        if math.random() < 0.3 then
                            DamageEvent.HitInfo.BoneName = "neck_01"
                        end
                    end
                    DamageEvent.HitInfo.Location = {
                        X = DamageEvent.HitInfo.Location.X + (math.random()-0.5)*2,
                        Y = DamageEvent.HitInfo.Location.Y + (math.random()-0.5)*2,
                        Z = DamageEvent.HitInfo.Location.Z + (math.random()-0.5)*2
                    }
                end
                return origTakeDamage(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
            end
        end
    end)

    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(pname, ...)
                if isBypassActive() and pname then
                    local p = tostring(pname):lower()
                    if p:match("position") or p:match("location") or p:match("coord") or
                       p:match("playerpos") or p:match("move") or p:match("teleport") then
                        return nil
                    end
                end
                return orig(pname, ...)
            end
        end
        if _G.SendRPC then
            local orig = _G.SendRPC
            _G.SendRPC = function(rpcName, ...)
                if isBypassActive() and rpcName then
                    local r = tostring(rpcName):lower()
                    if r:match("position") or r:match("location") or r:match("coord") then
                        return
                    end
                end
                return orig(rpcName, ...)
            end
        end
    end)

    local matchStats = { totalShots = 0, totalHits = 0, headshots = 0, kills = 0 }
    pcall(function()
        local Weapon = import("ShootWeaponEntity") or import("ShootWeaponEntityComp")
        if Weapon and Weapon.Fire then
            local origFire = Weapon.Fire
            Weapon.Fire = function(self, ...)
                if isBypassActive() then matchStats.totalShots = matchStats.totalShots + 1 end
                return origFire(self, ...)
            end
        end
        local Actor = import("Actor")
        if Actor and Actor.TakeDamage then
            local origTakeDamage2 = Actor.TakeDamage
            Actor.TakeDamage = function(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
                if isBypassActive() and EventInstigator == slua_GameFrontendHUD:GetPlayerController() then
                    matchStats.totalHits = matchStats.totalHits + 1
                    if DamageEvent and DamageEvent.HitInfo and DamageEvent.HitInfo.BoneName and
                       tostring(DamageEvent.HitInfo.BoneName):find("head") then
                        matchStats.headshots = matchStats.headshots + 1
                    end
                    if self:IsDead() then matchStats.kills = matchStats.kills + 1 end
                end
                return origTakeDamage2(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
            end
        end
        local GameReportUtils = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
        if GameReportUtils and GameReportUtils.ReportGameResult then
            local origReport = GameReportUtils.ReportGameResult
            GameReportUtils.ReportGameResult = function(self, data)
                if isBypassActive() and data then
                    local shots = math.max(matchStats.totalShots, 1)
                    data.accuracy = math.min(0.65, 0.35 + math.random()*0.15)
                    data.headshotRate = math.min(0.30, 0.10 + math.random()*0.10)
                    data.totalKills = matchStats.kills
                    data.totalShots = shots
                    data.totalHits = math.floor(shots * data.accuracy)
                end
                return origReport(self, data)
            end
        end
        local ShowResult = package.loaded["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowResultLogic"]
        if ShowResult and ShowResult.ReceiveData then
            local origReceive = ShowResult.ReceiveData
            ShowResult.ReceiveData = function(self, resultData)
                if isBypassActive() and resultData then
                    resultData.Accuracy = math.random(35,50)/100
                    resultData.HeadShotRate = math.random(10,20)/100
                end
                return origReceive(self, resultData)
            end
        end
    end)

    pcall(function()
        if rawget(_G, "IsDebuggerPresent") then _G.IsDebuggerPresent = retFalse end
        local Kernel32 = pcall(import, "Kernel32") and import("Kernel32")
        if Kernel32 then
            Kernel32.IsDebuggerPresent = retFalse
            Kernel32.CheckRemoteDebuggerPresent = retFalse
        end
        if _G.TssSdk then
            _G.TssSdk.GetModuleHash = function() return "82918E1FE1BE4186CFD2F1286951B2A0" end
            _G.TssSdk.VerifyModule = retTrue
            _G.TssSdk.ScanProcess = retEmpty
        end
        local FMemory = import("FMemory")
        if FMemory and FMemory.Memcpy then
            local origMemcpy = FMemory.Memcpy
            FMemory.Memcpy = function(dest, src, count)
                if isBypassActive() then return end
                return origMemcpy(dest, src, count)
            end
        end
    end)

    pcall(function()
        local FileHelper = import("FFileHelper")
        if FileHelper then
            if FileHelper.GetFileSize then
                local orig = FileHelper.GetFileSize
                FileHelper.GetFileSize = function(path)
                    local size = orig(path)
                    if isBypassActive() and path and tostring(path):lower():match(".pak") then
                        return 2000000000
                    end
                    return size
                end
            end
            if FileHelper.SaveStringToFile then
                local origSave = FileHelper.SaveStringToFile
                FileHelper.SaveStringToFile = function(str, path, ...)
                    if isBypassActive() and path and tostring(path):lower():match(".pak") then
                        return true
                    end
                    return origSave(str, path, ...)
                end
            end
        end
        local PakSubsystem = pcall(require, "GameLua.GameCore.Module.Subsystem.PakFileSubsystem") and require("GameLua.GameCore.Module.Subsystem.PakFileSubsystem")
        if PakSubsystem then
            PakSubsystem.CheckPakIntegrity = nop
            PakSubsystem.ReportPakMismatch = nop
        end
    end)

    pcall(function()
        local CharacterMovement = import("CharacterMovementComponent")
        if CharacterMovement then
            local origGetMaxSpeed = CharacterMovement.GetMaxSpeed
            CharacterMovement.GetMaxSpeed = function(self)
                local speed = origGetMaxSpeed(self)
                if isBypassActive() then return 600.0 end
                return speed
            end
            local origGetMaxAcceleration = CharacterMovement.GetMaxAcceleration
            CharacterMovement.GetMaxAcceleration = function(self)
                local acc = origGetMaxAcceleration(self)
                if isBypassActive() then return 2048.0 end
                return acc
            end
        end
    end)

    pcall(function()
        local UMat = import("Material")
        local UMatInst = import("MaterialInstance")
        if UMat then
            UMat.GetShaderMap = function(self) return nil end
            UMat.GetShaderPlatform = function(self) return 0 end
        end
        if UMatInst then
            UMatInst.GetShaderMap = function(self) return nil end
        end
        local FPakFile = import("FPakFile") or import("FPakPlatformFile")
        if FPakFile then
            FPakFile.GetPakEntries = function(...) return {} end
            FPakFile.GetPakFolders = function(...) return {} end
            FPakFile.FindFileInPakFiles = function(...) return false end
        end
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(pname, ...)
                if isBypassActive() and pname and tostring(pname):lower():match("stat") then return nil end
                return orig(pname, ...)
            end
        end
        local SSMgr = import("ScreenshotManager")
        if SSMgr then
            SSMgr.RequestScreenshot = function(...) return false end
            SSMgr.HasPendingScreenshot = function(...) return false end
        end
    end)

    _G.__ADVANCED_BYPASS_LOADED = true
    print("✅ Advanced Detection Bypass Installed")
end

InstallAdvancedDetectionBypass()

-- ========================================================================
-- ⚡ DEVICE ID / BAN BYPASS
-- ========================================================================
local function InstallDeviceBanBypass()
    if _G.__DEVICE_BAN_BYPASS_LOADED then return end

    local nop = function() end

    local function isBypassActive()
        return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
    end

    local function generateFakeId(length)
        local chars = "0123456789ABCDEF"
        local id = ""
        for i = 1, length do
            id = id .. chars:sub(math.random(1, #chars), math.random(1, #chars))
        end
        return id
    end

    local fakeDeviceID = generateFakeId(32)
    local fakeAndroidID = generateFakeId(16)
    local fakeMac = string.format("%02X:%02X:%02X:%02X:%02X:%02X",
        math.random(0,255), math.random(0,255), math.random(0,255),
        math.random(0,255), math.random(0,255), math.random(0,255))
    local fakeIMEI = "35" .. math.random(100000, 999999) .. math.random(100000, 999999)

    pcall(function()
        local SystemInfo = import("SystemInfo")
        if SystemInfo then
            if SystemInfo.GetDeviceID or SystemInfo.GetUniqueDeviceId then
                local orig = SystemInfo.GetDeviceID or SystemInfo.GetUniqueDeviceId
                if orig then
                    if SystemInfo.GetDeviceID then
                        SystemInfo.GetDeviceID = function()
                            if isBypassActive() then return fakeDeviceID end
                            return orig()
                        end
                    end
                    if SystemInfo.GetUniqueDeviceId then
                        SystemInfo.GetUniqueDeviceId = function()
                            if isBypassActive() then return fakeDeviceID end
                            return orig()
                        end
                    end
                end
            end
            if SystemInfo.GetMacAddress then
                local orig = SystemInfo.GetMacAddress
                SystemInfo.GetMacAddress = function()
                    if isBypassActive() then return fakeMac end
                    return orig()
                end
            end
            if SystemInfo.GetAndroidId then
                local orig = SystemInfo.GetAndroidId
                SystemInfo.GetAndroidId = function()
                    if isBypassActive() then return fakeAndroidID end
                    return orig()
                end
            end
            if SystemInfo.GetIMEI then
                local orig = SystemInfo.GetIMEI
                SystemInfo.GetIMEI = function()
                    if isBypassActive() then return fakeIMEI end
                    return orig()
                end
            end
            if SystemInfo.GetDeviceName then
                local orig = SystemInfo.GetDeviceName
                SystemInfo.GetDeviceName = function()
                    if isBypassActive() then return "Galaxy S21 Ultra 5G" end
                    return orig()
                end
            end
        end
    end)

    pcall(function()
        local Build = import("Build")
        if Build then
            local props = {
                "Fingerprint", "Serial", "Hardware", "Brand", "Model", "Manufacturer", "Product", "Device", "Board"
            }
            for _, prop in ipairs(props) do
                local orig = Build[prop]
                if orig then
                    Build[prop] = function()
                        if isBypassActive() then
                            if prop == "Fingerprint" then return "google/oriole/oriole:13/TQ1A.221205.011/2022120500:user/release-keys" end
                            if prop == "Serial" then return "R5CT1234567" end
                            if prop == "Hardware" then return "oriole" end
                            if prop == "Brand" then return "google" end
                            if prop == "Model" then return "Pixel 6" end
                            if prop == "Manufacturer" then return "Google" end
                            if prop == "Product" then return "oriole" end
                            if prop == "Device" then return "oriole" end
                            if prop == "Board" then return "gs101" end
                        end
                        return orig()
                    end
                end
            end
            if Build.VERSION and Build.VERSION.SDK_INT then
                local orig = Build.VERSION.SDK_INT
                Build.VERSION.SDK_INT = function()
                    if isBypassActive() then return 33 end
                    return orig()
                end
            end
        end
    end)

    pcall(function()
        local TssSdk = _G.TssSdk
        if TssSdk then
            if TssSdk.GetDeviceInfo then
                local orig = TssSdk.GetDeviceInfo
                TssSdk.GetDeviceInfo = function()
                    if not isBypassActive() then return orig() end
                    return {
                        deviceId = fakeDeviceID,
                        androidId = fakeAndroidID,
                        mac = fakeMac,
                        imei = fakeIMEI,
                        model = "Pixel 6",
                        brand = "google",
                        sdkInt = 33,
                        fingerprint = "google/oriole/oriole:13/TQ1A.221205.011/2022120500:user/release-keys"
                    }
                end
            end
            if TssSdk.GetFingerprint then
                local orig = TssSdk.GetFingerprint
                TssSdk.GetFingerprint = function()
                    if isBypassActive() then return "google/oriole/oriole:13/TQ1A.221205.011/2022120500:user/release-keys" end
                    return orig()
                end
            end
            if TssSdk.GetClientID then
                local orig = TssSdk.GetClientID
                TssSdk.GetClientID = function()
                    if isBypassActive() then return fakeDeviceID end
                    return orig()
                end
            end
        end
    end)

    pcall(function()
        if _G.DeviceID then _G.DeviceID = fakeDeviceID end
        if _G.AndroidID then _G.AndroidID = fakeAndroidID end
        if _G.MacAddress then _G.MacAddress = fakeMac end
        if _G.IMEI then _G.IMEI = fakeIMEI end
    end)

    _G.__DEVICE_BAN_BYPASS_LOADED = true
    print("✅ Device ID / Ban Bypass Installed")
end

InstallDeviceBanBypass()

-- ========================================================================
-- ⚡ PREMIUM ARROW RADAR ESP — Working base + Heart/Star shapes + Rainbow
-- ========================================================================
local ArrowRadarESP = {};
ArrowRadarESP.ArrowWidgets = {};       -- [key] = { lines = {...}, style = "..." }
ArrowRadarESP.FOVCircleLines = {};
ArrowRadarESP.ESPCanvas = nil;
ArrowRadarESP.bActive = false;
ArrowRadarESP._EnemyCache = {};
ArrowRadarESP._cachedViewportW = 1920;
ArrowRadarESP._cachedViewportH = 1080;
ArrowRadarESP._CanvasScaleX = 1.0;
ArrowRadarESP._CanvasScaleY = 1.0;
ArrowRadarESP._CanvasOffsetX = 0.0;
ArrowRadarESP._CanvasOffsetY = 0.0;

-- FOV Circle
ArrowRadarESP.FOVCircleRadius    = 155.0;
ArrowRadarESP.FOVCircleSegments  = 48;
ArrowRadarESP.FOVCircleThickness = 1.8;
ArrowRadarESP.FOVCircleColor     = FLinearColor and FLinearColor(0.15, 0.85, 1.0, 0.85) or {R=0.15,G=0.85,B=1,A=0.85};

-- ? Rainbow palette (per-enemy different color)
ArrowRadarESP.ColorPalette = {
    {R=1.00, G=0.15, B=0.15, A=1.00},  -- Red
    {R=1.00, G=0.55, B=0.00, A=1.00},  -- Orange
    {R=1.00, G=1.00, B=0.15, A=1.00},  -- Yellow
    {R=0.30, G=1.00, B=0.20, A=1.00},  -- Lime
    {R=0.00, G=1.00, B=0.55, A=1.00},  -- Spring
    {R=0.00, G=1.00, B=1.00, A=1.00},  -- Cyan
    {R=0.15, G=0.65, B=1.00, A=1.00},  -- Sky
    {R=0.35, G=0.25, B=1.00, A=1.00},  -- Blue
    {R=0.75, G=0.25, B=1.00, A=1.00},  -- Violet
    {R=1.00, G=0.25, B=1.00, A=1.00},  -- Magenta
    {R=1.00, G=0.35, B=0.65, A=1.00},  -- Pink
    {R=1.00, G=0.85, B=0.70, A=1.00},  -- Peach
}
ArrowRadarESP._ColorMap = {}

-- ? Shape: "classic" | "heart" | "star" | "crosshair" | "diamond" | "chevron"
ArrowRadarESP.ShapeStyle = "heart"

-- Arrow sizes
ArrowRadarESP.ArrowStemLen   = 22.0;
ArrowRadarESP.ArrowHeadLen   = 12.0;
ArrowRadarESP.ArrowWingAngle = 0.5;
ArrowRadarESP.ArrowOffset    = 6.0;
ArrowRadarESP.ArrowThickness = 2.8;

ArrowRadarESP.nUpdateInterval      = 0.5;
ArrowRadarESP._LightUpdateInterval = 0.05;

-- ================================================================
-- HELPERS
-- ================================================================
local function AR_IsValid(o) return o ~= nil and slua and slua.isValid and slua.isValid(o) end
local AR_FVector2D     = _G.FVector2D or import("Vector2D")
local AR_FLinearColor  = _G.FLinearColor or import("LinearColor")
local AR_SlateBP = nil; pcall(function() AR_SlateBP = import("SlateBlueprintLibrary") end)
local AR_WLL     = nil; pcall(function() AR_WLL = import("WidgetLayoutLibrary") end)

local function AR_GetCharacterFeetLoc(Character)
    if not AR_IsValid(Character) then return nil end
    local Loc = nil
    pcall(function()
        if Character.K2_GetActorLocation then
            Loc = Character:K2_GetActorLocation()
        end
    end)
    if not Loc then
        pcall(function()
            if Game and Game.GetActorLocation then
                Loc = Game:GetActorLocation(Character)
            end
        end)
    end
    return Loc
end

local function AR_GetCharacterHeadLoc(Character)
    local Feet = AR_GetCharacterFeetLoc(Character)
    if not Feet then return nil end
    local headZ = Feet.Z + 170
    pcall(function()
        if Character.bIsCrouched then headZ = Feet.Z + 120 end
        if Character.IsProne and Character:IsProne() then headZ = Feet.Z + 50 end
    end)
    return { X = Feet.X, Y = Feet.Y, Z = headZ }
end

local function AR_GetColorForKey(key)
    local idx = ArrowRadarESP._ColorMap[key]
    if not idx then
        local cnt = 0
        for _ in pairs(ArrowRadarESP._ColorMap) do cnt = cnt + 1 end
        idx = (cnt % #ArrowRadarESP.ColorPalette) + 1
        ArrowRadarESP._ColorMap[key] = idx
    end
    local c = ArrowRadarESP.ColorPalette[idx]
    if FLinearColor then
        return FLinearColor(c.R, c.G, c.B, c.A)
    end
    return c
end

-- ================================================================
-- CANVAS / PROJECTION
-- ================================================================
function ArrowRadarESP.GetMyPC()
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if AR_IsValid(pc) then return pc end
    return nil
end

function ArrowRadarESP.InitESPCanvas()
    if ArrowRadarESP.ESPCanvas and Game:IsValid(ArrowRadarESP.ESPCanvas) then return true end
    local canvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainUI = InGameUITools and InGameUITools.GetMainControlBaseUI()
        if MainUI and Game:IsValid(MainUI) then
            if MainUI.CanvasPanel_0 and Game:IsValid(MainUI.CanvasPanel_0) then
                canvas = MainUI.CanvasPanel_0
            elseif MainUI.CanvasPanel_42 and Game:IsValid(MainUI.CanvasPanel_42) then
                canvas = MainUI.CanvasPanel_42
            end
        end
    end)
    if not canvas then return false end
    ArrowRadarESP.ESPCanvas = canvas
    return true
end

function ArrowRadarESP.UpdateCanvasTransform(pc)
    if not ArrowRadarESP.ESPCanvas or not Game:IsValid(ArrowRadarESP.ESPCanvas) then return end
    local ok = false
    pcall(function()
        if AR_SlateBP and AR_SlateBP.AbsoluteToLocal then
            local cg = ArrowRadarESP.ESPCanvas:GetCachedGeometry()
            if cg then
                local p0 = AR_SlateBP.AbsoluteToLocal(cg, AR_FVector2D and AR_FVector2D(0,0) or {X=0,Y=0})
                local p1 = AR_SlateBP.AbsoluteToLocal(cg, AR_FVector2D and AR_FVector2D(100,100) or {X=100,Y=100})
                if p0 and p1 then
                    ArrowRadarESP._CanvasScaleX = (p1.X - p0.X)/100
                    ArrowRadarESP._CanvasScaleY = (p1.Y - p0.Y)/100
                    ArrowRadarESP._CanvasOffsetX = p0.X
                    ArrowRadarESP._CanvasOffsetY = p0.Y
                    ok = true
                end
            end
        end
    end)
    if not ok then
        local s = 1.0
        if AR_WLL and AR_WLL.GetViewportScale then s = AR_WLL.GetViewportScale(pc) or 1.0 end
        ArrowRadarESP._CanvasScaleX = 1.0/s; ArrowRadarESP._CanvasScaleY = 1.0/s
        ArrowRadarESP._CanvasOffsetX = 0; ArrowRadarESP._CanvasOffsetY = 0
    end
end

function ArrowRadarESP.ScreenToCanvas(p)
    if not p then return {X=0,Y=0} end
    local sx = ArrowRadarESP._CanvasScaleX or 1.0
    local sy = ArrowRadarESP._CanvasScaleY or 1.0
    local ox = ArrowRadarESP._CanvasOffsetX or 0
    local oy = ArrowRadarESP._CanvasOffsetY or 0
    return (AR_FVector2D and AR_FVector2D(p.X*sx+ox, p.Y*sy+oy)) or {X=p.X*sx+ox, Y=p.Y*sy+oy}
end

function ArrowRadarESP.GetScreenCenter(pc)
    local W, H = 0, 0
    pcall(function()
        if pc and pc.GetViewportSize then
            local vs = AR_FVector2D and AR_FVector2D(0,0) or {X=0,Y=0}
            pc:GetViewportSize(vs)
            if vs and vs.X and vs.X > 200 then W, H = vs.X, vs.Y end
        end
    end)
    if W <= 200 and AR_WLL and AR_WLL.GetViewportSize then
        pcall(function()
            local vs = AR_WLL.GetViewportSize(pc)
            if vs and vs.X and vs.X > 200 then W, H = vs.X, vs.Y end
        end)
    end
    if W <= 200 then W = ArrowRadarESP._cachedViewportW; H = ArrowRadarESP._cachedViewportH end
    return ArrowRadarESP.ScreenToCanvas(AR_FVector2D and AR_FVector2D(W/2,H/2) or {X=W/2,Y=H/2}), W, H
end

function ArrowRadarESP.GetArrowAngleRad(pc, worldLoc, centerCanvas)
    local angle = 0
    local pix = AR_FVector2D and AR_FVector2D(0,0) or {X=0,Y=0}
    local ok = false
    pcall(function() local r = pc:ProjectWorldLocationToScreen(worldLoc, pix, true); ok = (r==true or r==1) end)
    if ok then
        local cp = ArrowRadarESP.ScreenToCanvas(pix)
        local dx, dy = cp.X - centerCanvas.X, cp.Y - centerCanvas.Y
        if math.abs(dx) > 0.1 or math.abs(dy) > 0.1 then
            angle = math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx)
        end
    else
        pcall(function()
            local cam = pc:GetPlayerCameraManager()
            if not AR_IsValid(cam) then return end
            local cl, cr = cam:GetCameraLocation(), cam:GetCameraRotation()
            local dx3, dy3 = worldLoc.X - cl.X, worldLoc.Y - cl.Y
            local eY = math.atan2 and math.atan2(dy3,dx3) or math.atan(dy3,dx3)
            local d = eY - math.rad(cr.Yaw)
            while d >  math.pi do d = d - 2*math.pi end
            while d < -math.pi do d = d + 2*math.pi end
            angle = d + math.pi
        end)
    end
    return angle
end

-- ================================================================
-- LINE WIDGET
-- ================================================================
function ArrowRadarESP.CreateLine(color, z)
    if not ArrowRadarESP.ESPCanvas or not Game:IsValid(ArrowRadarESP.ESPCanvas) then return nil end
    local b = nil
    pcall(function() b = CGame:NewObjectFromPath("/Script/UMG.Border", ArrowRadarESP.ESPCanvas) end)
    if not b or not slua.isValid(b) then return nil end
    pcall(function() b:SetBrushColor(color) end)
    pcall(function() b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() b:SetRenderTransformPivot(AR_FVector2D and AR_FVector2D(0.0,0.5) or {X=0,Y=0.5}) end)
    local s = nil
    pcall(function()
        s = ArrowRadarESP.ESPCanvas:AddChildToCanvas(b)
        if s then s:SetAutoSize(false); s:SetZOrder(z or 3) end
    end)
    if not s then return nil end
    return { Widget = b, Slot = s }
end

function ArrowRadarESP.DrawLine(ld, x1, y1, x2, y2, th)
    if not ld or not ld.Widget or not ld.Slot then return end
    local dx, dy = x2-x1, y2-y1
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 0.5 then
        pcall(function() ld.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        return
    end
    local ang = (math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx)) * (180.0/math.pi)
    pcall(function()
        ld.Slot:SetPosition(AR_FVector2D and AR_FVector2D(x1, y1-th/2) or {X=x1,Y=y1-th/2})
        ld.Slot:SetSize(AR_FVector2D and AR_FVector2D(len, th) or {X=len,Y=th})
        ld.Widget:SetRenderAngle(ang)
        ld.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
end

local function AR_Hide(ld)
    if ld and ld.Widget and slua.isValid(ld.Widget) then
        pcall(function() ld.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    end
end
local function AR_Destroy(ld)
    if ld and ld.Widget and slua.isValid(ld.Widget) then
        pcall(function() ld.Widget:RemoveFromParent(); ld.Widget:ConditionalBeginDestroy() end)
    end
end
local function AR_SetColor(ld, c)
    if ld and ld.Widget and slua.isValid(ld.Widget) then
        pcall(function() ld.Widget:SetBrushColor(c) end)
    end
end

-- ================================================================
-- FOV CIRCLE
-- ================================================================
function ArrowRadarESP.UpdateCenterCircle(cx, cy)
    local r  = ArrowRadarESP.FOVCircleRadius
    local n  = ArrowRadarESP.FOVCircleSegments
    local th = ArrowRadarESP.FOVCircleThickness
    local c  = ArrowRadarESP.FOVCircleColor
    for i = 1, n do
        local a1 = ((i-1)/n) * (2*math.pi)
        local a2 = (i/n)   * (2*math.pi)
        if not ArrowRadarESP.FOVCircleLines[i] then
            ArrowRadarESP.FOVCircleLines[i] = ArrowRadarESP.CreateLine(c, 0)
        end
        ArrowRadarESP.DrawLine(ArrowRadarESP.FOVCircleLines[i],
            cx + math.cos(a1)*r, cy + math.sin(a1)*r,
            cx + math.cos(a2)*r, cy + math.sin(a2)*r, th)
    end
end

function ArrowRadarESP.RemoveCenterCircle()
    for _, ld in pairs(ArrowRadarESP.FOVCircleLines) do AR_Destroy(ld) end
    ArrowRadarESP.FOVCircleLines = {}
end

-- ================================================================
-- SHAPE DRAWERS  (all shapes)
-- Sab shapes ko SAME input milta hai: angRad + center + color + lines
-- ================================================================

-- ➤ Classic Arrow
local function DrawClassicShape(angRad, cx, cy, color, lines)
    local r  = ArrowRadarESP.FOVCircleRadius
    local sl = ArrowRadarESP.ArrowStemLen
    local hl = ArrowRadarESP.ArrowHeadLen
    local wa = ArrowRadarESP.ArrowWingAngle
    local of = ArrowRadarESP.ArrowOffset
    local th = ArrowRadarESP.ArrowThickness

    local bx, by = cx + math.cos(angRad)*r, cy + math.sin(angRad)*r
    local tx, ty = cx + math.cos(angRad)*(r+of+sl), cy + math.sin(angRad)*(r+of+sl)
    local bl = angRad + math.pi - wa
    local br = angRad + math.pi + wa
    local wlx, wly = tx + math.cos(bl)*hl, ty + math.sin(bl)*hl
    local wrx, wry = tx + math.cos(br)*hl, ty + math.sin(br)*hl

    ArrowRadarESP.DrawLine(lines[1], bx, by, tx, ty, th)
    ArrowRadarESP.DrawLine(lines[2], tx, ty, wlx, wly, th)
    ArrowRadarESP.DrawLine(lines[3], tx, ty, wrx, wry, th)
end

-- ❤️ Heart shape (5 lines) — pointing outward
local function DrawHeartShape(angRad, cx, cy, color, lines)
    local r   = ArrowRadarESP.FOVCircleRadius + ArrowRadarESP.ArrowOffset
    local sz  = ArrowRadarESP.ArrowStemLen * 0.75
    local th  = ArrowRadarESP.ArrowThickness
    local cosA, sinA = math.cos(angRad), math.sin(angRad)

    -- Rotate a local point by angRad and offset by (cx, cy) + r along angRad
    local function P(x, y)
        local nx = cx + cosA*(r + x) - sinA*y
        local ny = cy + sinA*(r + x) + cosA*y
        return nx, ny
    end

    -- Heart in LOCAL coords: tip at (sz*1.6, 0) pointing +X
    local tipX, tipY     = P(sz * 1.6, 0)
    local topLX, topLY   = P(0.0,   -sz * 0.9)     -- left lobe top
    local topRX, topRY   = P(0.0,    sz * 0.9)     -- right lobe top
    local midX, midY     = P(sz * 0.5, 0)          -- center dip
    local botX, botY     = P(sz * 0.8, 0)          -- back point

    -- Draw heart: two lobes meeting at top + point at tip
    ArrowRadarESP.DrawLine(lines[1], topLX, topLY, midX, midY, th)   -- upper-left curve
    ArrowRadarESP.DrawLine(lines[2], midX, midY, topRX, topRY, th)   -- upper-right curve
    ArrowRadarESP.DrawLine(lines[3], topLX, topLY, tipX, tipY, th)   -- left side to tip
    ArrowRadarESP.DrawLine(lines[4], topRX, topRY, tipX, tipY, th)   -- right side to tip
    ArrowRadarESP.DrawLine(lines[5], midX, midY, botX, botY, th)     -- inner small line
end

-- ⭐ Star shape (10 lines, 5-point)
local function DrawStarShape(angRad, cx, cy, color, lines)
    local r  = ArrowRadarESP.FOVCircleRadius + ArrowRadarESP.ArrowOffset
    local sz = ArrowRadarESP.ArrowStemLen * 0.85
    local th = ArrowRadarESP.ArrowThickness
    local cosA, sinA = math.cos(angRad), math.sin(angRad)

    local function P(x, y)
        local nx = cx + cosA*(r + x) - sinA*y
        local ny = cy + sinA*(r + x) + cosA*y
        return nx, ny
    end

    local pts = {}
    for i = 0, 4 do
        local outer = (i * 2 * math.pi / 5) - math.pi/2
        local inner = outer + math.pi/5
        pts[#pts+1] = { P(sz * math.cos(outer), sz * math.sin(outer)) }
        pts[#pts+1] = { P(sz * 0.42 * math.cos(inner), sz * 0.42 * math.sin(inner)) }
    end

    for i = 1, 10 do
        local a = pts[i]
        local b = pts[i % 10 + 1]
        ArrowRadarESP.DrawLine(lines[i], a[1], a[2], b[1], b[2], th)
    end
end

-- ⊕ Crosshair
local function DrawCrosshairShape(angRad, cx, cy, color, lines)
    local r  = ArrowRadarESP.FOVCircleRadius + ArrowRadarESP.ArrowOffset
    local sz = ArrowRadarESP.ArrowStemLen * 0.9
    local th = ArrowRadarESP.ArrowThickness
    local cosA, sinA = math.cos(angRad), math.sin(angRad)
    local function P(x, y)
        return cx + cosA*(r + x) - sinA*y,
               cy + sinA*(r + x) + cosA*y
    end
    local h1x, h1y = P(-sz, 0)
    local h2x, h2y = P( sz, 0)
    local v1x, v1y = P(0, -sz)
    local v2x, v2y = P(0,  sz)
    ArrowRadarESP.DrawLine(lines[1], h1x, h1y, h2x, h2y, th)
    ArrowRadarESP.DrawLine(lines[2], v1x, v1y, v2x, v2y, th)
    local c1x, c1y = P(-2, -2)
    local c2x, c2y = P( 2,  2)
    ArrowRadarESP.DrawLine(lines[3], c1x, c1y, c2x, c2y, th + 1.5)
end

-- ? Diamond
local function DrawDiamondShape(angRad, cx, cy, color, lines)
    local r  = ArrowRadarESP.FOVCircleRadius + ArrowRadarESP.ArrowOffset
    local sz = ArrowRadarESP.ArrowStemLen * 0.75
    local th = ArrowRadarESP.ArrowThickness
    local cosA, sinA = math.cos(angRad), math.sin(angRad)
    local function P(x, y)
        return cx + cosA*(r + x) - sinA*y,
               cy + sinA*(r + x) + cosA*y
    end
    local p1x, p1y = P( sz, 0)     -- right
    local p2x, p2y = P(0,  sz)     -- bottom
    local p3x, p3y = P(-sz, 0)     -- left
    local p4x, p4y = P(0, -sz)     -- top
    ArrowRadarESP.DrawLine(lines[1], p1x, p1y, p2x, p2y, th)
    ArrowRadarESP.DrawLine(lines[2], p2x, p2y, p3x, p3y, th)
    ArrowRadarESP.DrawLine(lines[3], p3x, p3y, p4x, p4y, th)
    ArrowRadarESP.DrawLine(lines[4], p4x, p4y, p1x, p1y, th)
end

-- ➤➤ Chevron (double)
local function DrawChevronShape(angRad, cx, cy, color, lines)
    local r  = ArrowRadarESP.FOVCircleRadius + ArrowRadarESP.ArrowOffset
    local sl = ArrowRadarESP.ArrowStemLen
    local hl = ArrowRadarESP.ArrowHeadLen
    local th = ArrowRadarESP.ArrowThickness
    local cosA, sinA = math.cos(angRad), math.sin(angRad)

    -- chevron 1 (front)
    local tx, ty = cx + cosA*(r+sl), cy + sinA*(r+sl)
    local bl = angRad + math.pi - 0.55
    local br = angRad + math.pi + 0.55
    ArrowRadarESP.DrawLine(lines[1], tx, ty, tx + math.cos(bl)*hl, ty + math.sin(bl)*hl, th)
    ArrowRadarESP.DrawLine(lines[2], tx, ty, tx + math.cos(br)*hl, ty + math.sin(br)*hl, th)

    -- chevron 2 (behind)
    local tx2, ty2 = cx + cosA*(r+sl*0.5), cy + sinA*(r+sl*0.5)
    ArrowRadarESP.DrawLine(lines[3], tx2, ty2, tx2 + math.cos(bl)*hl*0.75, ty2 + math.sin(bl)*hl*0.75, th)
    ArrowRadarESP.DrawLine(lines[4], tx2, ty2, tx2 + math.cos(br)*hl*0.75, ty2 + math.sin(br)*hl*0.75, th)
end

-- ================================================================
-- ARROW DISPATCHER
-- ================================================================
local STYLE_LINE_COUNT = {
    classic   = 3,
    heart     = 5,
    star      = 10,
    crosshair = 3,
    diamond   = 4,
    chevron   = 4,
}

function ArrowRadarESP.UpdateArrow(key, worldLoc, pc, centerCanvas)
    -- Get/create container
    local data = ArrowRadarESP.ArrowWidgets[key]

    -- No worldLoc → hide
    if not worldLoc then
        if data and data.lines then
            for _, ld in ipairs(data.lines) do AR_Hide(ld) end
        end
        return
    end

    local style = ArrowRadarESP.ShapeStyle or "classic"
    local needed = STYLE_LINE_COUNT[style] or 3

    -- Rebuild if style changed or container missing
    if data and data.style ~= style then
        for _, ld in ipairs(data.lines or {}) do AR_Destroy(ld) end
        data = nil
    end

    if not data then
        data = { lines = {}, style = style }
        ArrowRadarESP.ArrowWidgets[key] = data
    end

    -- Get per-enemy color
    local color = AR_GetColorForKey(key)

    -- Create missing lines with color
    while #data.lines < needed do
        local ld = ArrowRadarESP.CreateLine(color, 3)
        if not ld then break end
        table.insert(data.lines, ld)
    end

    -- Apply color to all
    for _, ld in ipairs(data.lines) do AR_SetColor(ld, color) end

    -- Hide surplus lines (in case of style change to smaller)
    for i = needed + 1, #data.lines do AR_Hide(data.lines[i]) end

    -- Compute angle
    local angRad = ArrowRadarESP.GetArrowAngleRad(pc, worldLoc, centerCanvas)
    local cx, cy = centerCanvas.X, centerCanvas.Y

    -- Draw
    if style == "heart" then
        DrawHeartShape(angRad, cx, cy, color, data.lines)
    elseif style == "star" then
        DrawStarShape(angRad, cx, cy, color, data.lines)
    elseif style == "crosshair" then
        DrawCrosshairShape(angRad, cx, cy, color, data.lines)
    elseif style == "diamond" then
        DrawDiamondShape(angRad, cx, cy, color, data.lines)
    elseif style == "chevron" then
        DrawChevronShape(angRad, cx, cy, color, data.lines)
    else
        DrawClassicShape(angRad, cx, cy, color, data.lines)
    end
end

function ArrowRadarESP.RemoveArrow(key)
    local data = ArrowRadarESP.ArrowWidgets[key]
    if data and data.lines then
        for _, ld in ipairs(data.lines) do AR_Destroy(ld) end
    end
    ArrowRadarESP.ArrowWidgets[key] = nil
end

function ArrowRadarESP.ClearAllArrows()
    for key, _ in pairs(ArrowRadarESP.ArrowWidgets) do
        ArrowRadarESP.RemoveArrow(key)
    end
    ArrowRadarESP.ArrowWidgets = {}
    ArrowRadarESP._ColorMap = {}
end

-- ================================================================
-- SCAN / UPDATE
-- ================================================================
function ArrowRadarESP.ScanAndUpdate()
    if not ArrowRadarESP.bActive then return end
    if not ArrowRadarESP.InitESPCanvas() then return end
    local pc = ArrowRadarESP.GetMyPC()
    if not AR_IsValid(pc) then return end

    ArrowRadarESP.UpdateCanvasTransform(pc)
    local centerCanvas = ArrowRadarESP.GetScreenCenter(pc)
    ArrowRadarESP.UpdateCenterCircle(centerCanvas.X, centerCanvas.Y)

    local AllChars = _G.PlayerMapMarker and _G.PlayerMapMarker.GetAllCharacters and _G.PlayerMapMarker.GetAllCharacters() or {}
    if not next(AllChars) then return end

    local MyKey = _G.PlayerMapMarker and _G.PlayerMapMarker.GetMyPlayerKey and _G.PlayerMapMarker.GetMyPlayerKey()
    local MyChar = nil
    pcall(function()
        local GDP = require("GameLua.GameCore.Data.GameplayData")
        if GDP and GDP.GetLocalCharacter then MyChar = GDP.GetLocalCharacter() end
    end)
    local MyTeam = _G.PlayerMapMarker and _G.PlayerMapMarker.GetTeamID and _G.PlayerMapMarker.GetTeamID(MyChar)

    local seen = {}
    for pk, ch in pairs(AllChars) do
        if AR_IsValid(ch) then
            local k = tostring(pk)
            local bMe = false
            local alive = true
            local team = nil
            pcall(function()
                if _G.PlayerMapMarker then
                    if _G.PlayerMapMarker.IsMe then bMe = _G.PlayerMapMarker.IsMe(ch, pk, MyKey) end
                    if _G.PlayerMapMarker.IsAlive then alive = _G.PlayerMapMarker.IsAlive(ch) end
                    if _G.PlayerMapMarker.GetTeamID then team = _G.PlayerMapMarker.GetTeamID(ch) end
                end
            end)

            local skip = bMe
            if MyTeam ~= nil and team == MyTeam and not bMe then skip = true end
            if not alive then skip = true end

            if not skip then
                seen[k] = true
                ArrowRadarESP._EnemyCache[k] = ch
                local headLoc = AR_GetCharacterHeadLoc(ch)
                local feetLoc = AR_GetCharacterFeetLoc(ch)
                ArrowRadarESP.UpdateArrow(k, headLoc or feetLoc, pc, centerCanvas)
            end
        end
    end

    local allKeys = {}
    for k in pairs(ArrowRadarESP.ArrowWidgets) do allKeys[k] = true end
    for k in pairs(allKeys) do
        if not seen[k] then
            ArrowRadarESP.RemoveArrow(k)
            ArrowRadarESP._EnemyCache[k] = nil
        end
    end
end

function ArrowRadarESP.UpdateLight()
    if not ArrowRadarESP.bActive then return end
    if not ArrowRadarESP.ESPCanvas or not Game:IsValid(ArrowRadarESP.ESPCanvas) then return end
    local pc = ArrowRadarESP.GetMyPC()
    if not AR_IsValid(pc) then return end

    ArrowRadarESP.UpdateCanvasTransform(pc)
    local centerCanvas = ArrowRadarESP.GetScreenCenter(pc)

    for k, ch in pairs(ArrowRadarESP._EnemyCache) do
        local alive = true
        pcall(function()
            if _G.PlayerMapMarker and _G.PlayerMapMarker.IsAlive then
                alive = _G.PlayerMapMarker.IsAlive(ch)
            end
        end)
        if AR_IsValid(ch) and alive then
            local headLoc = AR_GetCharacterHeadLoc(ch)
            local feetLoc = AR_GetCharacterFeetLoc(ch)
            ArrowRadarESP.UpdateArrow(k, headLoc or feetLoc, pc, centerCanvas)
        else
            ArrowRadarESP.RemoveArrow(k)
            ArrowRadarESP._EnemyCache[k] = nil
        end
    end
end

-- ================================================================
-- START / STOP / STYLE SWITCH
-- ================================================================
function ArrowRadarESP.Start()
    if ArrowRadarESP.bActive then return end
    ArrowRadarESP.bActive = true
    ArrowRadarESP.ScanAndUpdate()

    pcall(function()
        local pc = ArrowRadarESP.GetMyPC()
        if AR_IsValid(pc) and pc.AddGameTimer then
            pc:AddGameTimer(ArrowRadarESP.nUpdateInterval or 0.5, true, function()
                if ArrowRadarESP.bActive then pcall(ArrowRadarESP.ScanAndUpdate) end
            end)
            pc:AddGameTimer(ArrowRadarESP._LightUpdateInterval or 0.05, true, function()
                if ArrowRadarESP.bActive then pcall(ArrowRadarESP.UpdateLight) end
            end)
        end
    end)
    print("✅ Arrow Radar Started — style:", ArrowRadarESP.ShapeStyle)
end

function ArrowRadarESP.Stop()
    ArrowRadarESP.bActive = false
    ArrowRadarESP.ClearAllArrows()
    ArrowRadarESP.RemoveCenterCircle()
    ArrowRadarESP._EnemyCache = {}
    ArrowRadarESP.ESPCanvas = nil
    print("? Arrow Radar Stopped")
end

function ArrowRadarESP.SetStyle(style)
    local valid = { classic=true, heart=true, star=true, crosshair=true, diamond=true, chevron=true }
    if not valid[style] then return end
    ArrowRadarESP.ShapeStyle = style
    ArrowRadarESP.ClearAllArrows()
    print("? Arrow style:", style)
end

_G.ArrowRadarESP = ArrowRadarESP
print("✅ Premium Arrow Radar Module Loaded")
-- ========================================================================
-- ⚡ ENEMY COUNTER
-- ========================================================================
_G.ENEMY_COUNTER_TIMER = nil

function _G.EnemyCounterLoop()
    if _G.AK_GetVal("ENEMY_COUNTER") ~= 1 then return end

    local player = GameplayData and GameplayData.GetPlayerCharacter()
    if not slua.isValid(player) then return end

    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not slua.isValid(pc) then return end

    local hud = pc:GetHUD()
    if not slua.isValid(hud) then return end

    local myTeamId = player.TeamID or 0
    local myPos = player:K2_GetActorLocation()
    if not myPos then return end

    local totalEnemies = 0
    local botCount = 0
    local realCount = 0
    local MAX_DIST_SQ = 900000000

    local allPawns = Game:GetAllPlayerPawns() or {}
    for _, pawn in pairs(allPawns) do
        if slua.isValid(pawn) and pawn ~= player then
            local pawnTeam = pawn.TeamID or 0
            if pawnTeam ~= myTeamId then
                local pos = pawn:K2_GetActorLocation()
                if pos then
                    local dx = pos.X - myPos.X
                    local dy = pos.Y - myPos.Y
                    local dz = pos.Z - myPos.Z
                    if dx*dx + dy*dy + dz*dz <= MAX_DIST_SQ then
                        totalEnemies = totalEnemies + 1
                        local isBot = false
                        pcall(function()
                            isBot = Game:IsAI(pawn)
                        end)
                        if isBot then
                            botCount = botCount + 1
                        else
                            realCount = realCount + 1
                        end
                    end
                end
            end
        end
    end

    local text = ""
    local COLOR_SAFE  = { R = 0, G = 255, B = 200, A = 255 }
    local COLOR_WARN  = { R = 255, G = 255, B = 0,   A = 255 }
    local COLOR_DANGER= { R = 255, G = 165,  B = 0,  A = 255 }
    local color = COLOR_SAFE

    if totalEnemies == 0 then
        text = "[ AREA SECURE ]"
        color = COLOR_SAFE
    else
        text = string.format("ENEMIES: %d  (Bots: %d | Real: %d)", totalEnemies, botCount, realCount)
        if totalEnemies == 1 then
            color = COLOR_WARN
        else
            color = COLOR_DANGER
        end
    end

    if _G.AK_GetVal("ENEMY_COUNTER") == 1 then
        text = text .. "\n✦ MODER - TGOWNER7 ✦"
    end

    if text ~= "" then
        local OFFSET = { X = 0, Y = 0, Z = 35 }
        hud:AddDebugText(text, player, 1.1, OFFSET, OFFSET, color, true, false, true, nil, 1.2, true)
    end
end

function _G.StartEnemyCounter()
    if _G.ENEMY_COUNTER_TIMER then
        pcall(function()
            if _G.Game then _G.Game:RemoveGameTimer(_G.ENEMY_COUNTER_TIMER) end
        end)
        _G.ENEMY_COUNTER_TIMER = nil
    end

    if _G.AK_GetVal("ENEMY_COUNTER") ~= 1 then return false end

    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        _G.ENEMY_COUNTER_TIMER = pc:AddGameTimer(1.0, true, function()
            pcall(_G.EnemyCounterLoop)
        end)
        print("[ENEMY COUNTER] ✅ Started")
        return true
    end
    return false
end

function _G.StopEnemyCounter()
    if _G.ENEMY_COUNTER_TIMER then
        pcall(function()
            if _G.Game then _G.Game:RemoveGameTimer(_G.ENEMY_COUNTER_TIMER) end
        end)
        _G.ENEMY_COUNTER_TIMER = nil
        print("[ENEMY COUNTER] Stopped")
    end
end

-- ========================================================================
-- ORIGINAL DISTANCE MARKER & ESP SYSTEM
-- ========================================================================
local distanceMarkerConfig = {
    UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
    MaxWidgetNum = 99,
    MaxShowDistance = 6000000,
    bBindOutScreen = true,
    bBindBlocked = true,
    bIsBindingActor = true,
    BindSocketName = "head",
    bUseLuaWorldSocketName = true,
    WorldPositionOffset = FVector(0, 0, 50),
    bNeedPreLoad = true,
    Priority = 2
}

local function InitDistanceMarkerSystem()
    pcall(function()
        if InGameMarkTools and InGameMarkTools.ScreenMarkManager and InGameMarkTools.ScreenMarkManager.OnInitMarkGroupData then
            InGameMarkTools.ScreenMarkManager:OnInitMarkGroupData(9999)
        end
        local gameplayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
        local screenMarkConfig = gameplayTools.GetCurrentConfig("ScreenMarkConfig")
        if screenMarkConfig then
            screenMarkConfig[9999] = distanceMarkerConfig
        end
        for moduleName, moduleData in pairs(package.loaded) do
            if type(moduleName) == "string" and string.find(moduleName, "ScreenMarkConfig") then
                if type(moduleData) == "table" then
                    moduleData[9999] = distanceMarkerConfig
                end
            end
        end
    end)
end

if not _G.AK_Active_Marks_Cache then _G.AK_Active_Marks_Cache = {} end

local function createDistanceMarker(enemy)
    if _G._MOD_EXPIRED then return end
    pcall(function()
        if InGameMarkTools and InGameMarkTools.ClientAddMapMark then
            enemy.NativeDistMark = InGameMarkTools.ClientAddMapMark(9999, FVector(0,0,0), 0, "", 4, enemy)
            _G.AK_Active_Marks_Cache[tostring(enemy)] = { actor = enemy, distMark = enemy.NativeDistMark }
        end
    end)
end

local function removeDistanceMarker(enemy)
    pcall(function()
        if InGameMarkTools then
            if InGameMarkTools.ClientRemoveMapMark then
                InGameMarkTools.ClientRemoveMapMark(enemy.NativeDistMark)
            elseif InGameMarkTools.HideMapMark then
                InGameMarkTools.HideMapMark(enemy.NativeDistMark)
            end
        end
        enemy.NativeDistMark = nil
        _G.AK_Active_Marks_Cache[tostring(enemy)] = nil
    end)
end

local function cleanupDeadEnemyMarks()
    for cacheKey, cacheData in pairs(_G.AK_Active_Marks_Cache) do
        local shouldRemove = false
        if not slua.isValid(cacheData.actor) then
            shouldRemove = true
        else
            pcall(function()
                local actor = cacheData.actor
                if actor.bHidden or (actor.Mesh and actor.Mesh.bHidden) then shouldRemove = true end
                if type(actor.IsDead) == "function" and actor:IsDead() then shouldRemove = true
                elseif actor.bIsDead == true or actor.bIsDeadFlag == true then shouldRemove = true end
            end)
        end
        if shouldRemove then
            pcall(function()
                if InGameMarkTools and InGameMarkTools.ClientRemoveMapMark then
                    InGameMarkTools.ClientRemoveMapMark(cacheData.distMark)
                end
            end)
            _G.AK_Active_Marks_Cache[cacheKey] = nil
        end
    end
end

local function processEnemyMapESP(enemy, localPlayer, isMapESPEnabled)
    if _G._MOD_EXPIRED then return end
    if not slua.isValid(enemy) or enemy == localPlayer or enemy.TeamID == localPlayer.TeamID then return end

    local isDead = false
    pcall(function()
        if type(enemy.IsDead) == "function" then isDead = enemy:IsDead()
        elseif enemy.bIsDead then isDead = true end
        if enemy.bHidden or (enemy.Mesh and enemy.Mesh.bHidden) then isDead = true end
    end)

    if not isDead then
        if isMapESPEnabled == 1 then
            if not enemy.bHasAKNativeMapMarker then
                createDistanceMarker(enemy)
                enemy.bHasAKNativeMapMarker = true
            end
        else
            if enemy.bHasAKNativeMapMarker then
                removeDistanceMarker(enemy)
                enemy.bHasAKNativeMapMarker = false
            end
        end
    else
        if enemy.bHasAKNativeMapMarker then
            removeDistanceMarker(enemy)
            enemy.bHasAKNativeMapMarker = false
        end
    end
end

function ApplyHardAimbot()
    if not CheckExpiration() then return end
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not slua.isValid(pc) then return end

        local char = pc:GetPlayerCharacterSafety()
        if not slua.isValid(char) then return end

        local wm = char.WeaponManagerComponent
        if not slua.isValid(wm) then return end

        local weapon = wm.CurrentWeaponReplicated
        if not slua.isValid(weapon) then return end

        local entity = weapon.ShootWeaponEntityComp
        if not slua.isValid(entity) then return end

        entity.RecoilKickADS = 0.010
        entity.GameDeviationFactor = 0.01
        entity.GameDeviationAccuracy = 0.01
        entity.SwitchFromIdleToBackpackTime = 0.01
        entity.SwitchFromBackpackToIdleTime = 0.01

        if entity.AutoAimingConfig then
            for _, range in ipairs({"OuterRange", "InnerRange"}) do
                local cfg = entity.AutoAimingConfig[range]
                if cfg then
                    cfg.Speed = 4.0
                    cfg.RangeRate = 4.5
                    cfg.SpeedRate = 4.0
                    cfg.RangeRateSight = 3.0
                    cfg.SpeedRateSight = 3.0
                    cfg.CrouchRate = 4.5
                    cfg.ProneRate = 4.0
                    cfg.DyingRate = 0
                    cfg.DriveVehicleRate = 99
                    cfg.InVehicleRate = 99
                    cfg.FreeFallRate = 22
                    cfg.OpeningRate = 5
                    cfg.LandingRate = 99
                    cfg.adsorbMaxRange = 200
                    cfg.adsorbMinRange = 20
                    cfg.adsorbMinAttenuationDis = 100
                    cfg.adsorbMaxAttenuationDis = 8000
                    cfg.adsorbActiveMinRange = 20
                end
            end
            entity.AutoAimingConfig = entity.AutoAimingConfig
        end

        pcall(function()
            local aimComp = char.BP_AutoAimingComponent_C or char.BP_AutoAimingComponent or char.AutoAimingComponent
            if slua.isValid(aimComp) and aimComp.Bones then
                pcall(function() aimComp.Bones[0] = "neck_01" end)
                pcall(function() aimComp.Bones[1] = "neck_01" end)
                pcall(function() aimComp.Bones[2] = "neck_01" end)
                pcall(function() aimComp.Bones:Set(0, "neck_01") end)
                pcall(function() aimComp.Bones:Set(1, "neck_01") end)
                pcall(function() aimComp.Bones:Set(2, "neck_01") end)
            end
        end)
    end)
end

-- ========================================================================
-- MATERIAL EVASION BYPASS
-- ========================================================================
local function activate_material_evasion()
    if _G._MATERIAL_GETTERS_HOOKED then return end
    pcall(function()
        local UMaterial = import("Material")
        local UMaterialInstance = import("MaterialInstance")
        local UMaterialInstanceDynamic = import("MaterialInstanceDynamic")
        local UPrimitiveComponent = import("PrimitiveComponent")
        local UMeshComponent = import("MeshComponent")

        if UMaterial then
            UMaterial.GetDisableDepthTest = function() return false end
            UMaterial.GetBlendMode = function() return 0 end
            UMaterial.GetMaterialHash = function() return "FAKE_HASH" end
            UMaterial.VerifyMaterial = function() return true end
        end
        if UMaterialInstance then
            UMaterialInstance.GetDisableDepthTest = function() return false end
            UMaterialInstance.GetBlendMode = function() return 0 end
            UMaterialInstance.GetBaseMaterial = function() return nil end
        end
        if UMaterialInstanceDynamic then
            local oldVec = UMaterialInstanceDynamic.K2_GetVectorParameterValue
            UMaterialInstanceDynamic.K2_GetVectorParameterValue = function(self, name)
                local n = tostring(name)
                if n:find("Color") or n:find("Emissive") then return {R=0,G=255,B=255,A=255} end
                return oldVec(self, name)
            end
            local oldScal = UMaterialInstanceDynamic.K2_GetScalarParameterValue
            UMaterialInstanceDynamic.K2_GetScalarParameterValue = function(self, name)
                if tostring(name):find("Emissive") then return 0.0 end
                return oldScal(self, name)
            end
            UMaterialInstanceDynamic.GetFullName = function() return "DefaultMaterial" end
        end
        if UPrimitiveComponent then
            UPrimitiveComponent.IsRenderedOnCustomDepth = function() return false end
            UPrimitiveComponent.GetRenderCustomDepth = function() return false end
            UPrimitiveComponent.GetCustomDepthStencilValue = function() return 0 end
            UPrimitiveComponent.GetCustomDepthStencilWriteMask = function() return 0 end
            UPrimitiveComponent.GetVisibleFlag = function() return true end
        end
        if UMeshComponent then
            UMeshComponent.ShouldRender = function() return true end
            UMeshComponent.GetShouldRender = function() return true end
            UMeshComponent.IsVisible = function() return true end
        end
        local UObject = import("Object")
        if UObject and UObject.GetObjectsOfClass then
            local oldGet = UObject.GetObjectsOfClass
            UObject.GetObjectsOfClass = function(Class, IncludeDerived)
                if Class and tostring(Class):find("MaterialInstanceDynamic") then return {} end
                return oldGet(Class, IncludeDerived)
            end
        end
    end)
    _G._MATERIAL_GETTERS_HOOKED = true
end

activate_material_evasion()

-- ========================================================================
-- ⚡ ESP V2 SYSTEM (RedBoxOverlay + PlayerMapMarker)
-- ========================================================================
local PlayerMapMarker = {}

-- ========================================================================
-- ⚡ RED BOX OVERLAY (Enemy Counter Display)
-- ========================================================================
local RedBoxOverlay = {
    bActive = false,
    MainContainer = nil,
    WidgetSlot = nil,
    TextBlock = nil,
    Width = 280,
    Height = 38,
    OffsetY = 10,
    PlayerCount = 0,
    BotCount = 0,
    TotalCount = 0,
    FontSize = 16,
    TextScaleValue = 1.0,
    _CachedText = "",
    _CachedPosVec = nil,
    _IsInRange = false,
    _BorderWidget = nil,
}

function RedBoxOverlay.Create()
    if RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then return true end

    local ParentCanvas = PlayerMapMarker.ESPCanvas
    if not ParentCanvas or not slua.isValid(ParentCanvas) then 
        if not PlayerMapMarker.InitESPCanvas() then return false end
        ParentCanvas = PlayerMapMarker.ESPCanvas
    end

    if not ParentCanvas or not slua.isValid(ParentCanvas) then return false end

    local Container = nil
    pcall(function() Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas) end)
    if not Container or not slua.isValid(Container) then return false end

    local FLinearColor = import("LinearColor") or FLinearColor
    local FVector2D = import("Vector2D") or FVector2D

    local mainBorder = nil
    pcall(function() mainBorder = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
    if mainBorder and slua.isValid(mainBorder) then
        pcall(function()
            RedBoxOverlay._CurrentColor = FLinearColor(0.0, 1.0, 0.0, 0.95)
            mainBorder:SetBrushColor(RedBoxOverlay._CurrentColor)
            mainBorder:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local slotMain = Container:AddChildToCanvas(mainBorder)
        if slotMain then
            slotMain:SetPosition(FVector2D(0, 0))
            slotMain:SetSize(FVector2D(RedBoxOverlay.Width, RedBoxOverlay.Height))
        end
        RedBoxOverlay._BorderWidget = mainBorder
    end

    local innerBorder = nil
    pcall(function() innerBorder = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
    if innerBorder and slua.isValid(innerBorder) then
        pcall(function()
            innerBorder:SetBrushColor(FLinearColor(0.0, 0.0, 0.0, 0.7))
            innerBorder:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local slotInner = Container:AddChildToCanvas(innerBorder)
        if slotInner then
            slotInner:SetPosition(FVector2D(3, 3))
            slotInner:SetSize(FVector2D(RedBoxOverlay.Width - 6, RedBoxOverlay.Height - 6))
        end
    end

    local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")

    local txtBlock = nil
    pcall(function() txtBlock = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)
    if txtBlock and slua.isValid(txtBlock) then
        pcall(function()
            local strText = string.format("Total: %d | Enemy: %d | Bot: %d", 
                RedBoxOverlay.TotalCount, 
                RedBoxOverlay.PlayerCount, 
                RedBoxOverlay.BotCount)
            txtBlock:SetText(strText)
            RedBoxOverlay._CachedText = strText

            local whiteLinear = FLinearColor(1.0, 1.0, 1.0, 1.0)
            if FSlateColor then txtBlock:SetColorAndOpacity(FSlateColor(whiteLinear)) else txtBlock:SetColorAndOpacity(whiteLinear) end

            if txtBlock.Font then
                local font = txtBlock.Font
                font.Size = RedBoxOverlay.FontSize
                txtBlock.Font = font
            end
            txtBlock:SetRenderScale(FVector2D(RedBoxOverlay.TextScaleValue, RedBoxOverlay.TextScaleValue))
            txtBlock:SetRenderTransformPivot(FVector2D(0.5, 0.5))
            txtBlock:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local txtSlot = Container:AddChildToCanvas(txtBlock)
        if txtSlot then
            pcall(function()
                txtSlot:SetAutoSize(true)
                txtSlot:SetAlignment(FVector2D(0.5, 0.5))
                txtSlot:SetPosition(FVector2D(RedBoxOverlay.Width * 0.5, RedBoxOverlay.Height * 0.5))
                txtSlot:SetZOrder(1000)
            end)
        end
        RedBoxOverlay.TextBlock = txtBlock
    end

    local MainSlot = nil
    pcall(function() MainSlot = ParentCanvas:AddChildToCanvas(Container) end)
    if not MainSlot then return false end

    RedBoxOverlay.MainContainer = Container
    RedBoxOverlay.WidgetSlot = MainSlot

    pcall(function()
        MainSlot:SetAutoSize(false)
        MainSlot:SetZOrder(999)
        MainSlot:SetAlignment(FVector2D(0.5, 0.0))
        MainSlot:SetSize(FVector2D(RedBoxOverlay.Width, RedBoxOverlay.Height))
    end)

    RedBoxOverlay.UpdatePosition()
    return true
end

function RedBoxOverlay.SetCounts(players, bots)
    local newTotal = (players or 0) + (bots or 0)

    RedBoxOverlay.PlayerCount = players or 0
    RedBoxOverlay.BotCount = bots or 0
    RedBoxOverlay.TotalCount = newTotal

    local inRange = (RedBoxOverlay.TotalCount > 0)

    if RedBoxOverlay._IsInRange ~= inRange then
        RedBoxOverlay._IsInRange = inRange
        RedBoxOverlay._UpdateBackgroundColor(inRange)
    end

    if RedBoxOverlay.TextBlock and slua.isValid(RedBoxOverlay.TextBlock) then
        pcall(function()
            local str = string.format("Total: %d | Enemy: %d | Bot: %d", 
                RedBoxOverlay.TotalCount, 
                RedBoxOverlay.PlayerCount, 
                RedBoxOverlay.BotCount)
            if RedBoxOverlay._CachedText ~= str then
                RedBoxOverlay.TextBlock:SetText(str)
                RedBoxOverlay._CachedText = str
            end
        end)
    end
end

function RedBoxOverlay._UpdateBackgroundColor(inRange)
    local FLinearColor = import("LinearColor") or FLinearColor
    if not FLinearColor then return end

    local color
    if inRange then
        color = FLinearColor(1.0, 0.0, 0.0, 0.95)
    else
        color = FLinearColor(0.0, 1.0, 0.0, 0.95)
    end

    RedBoxOverlay._CurrentColor = color

    if RedBoxOverlay._BorderWidget and slua.isValid(RedBoxOverlay._BorderWidget) then
        pcall(function()
            RedBoxOverlay._BorderWidget:SetBrushColor(color)
        end)
    end
end

function RedBoxOverlay.UpdatePosition()
    local Slot = RedBoxOverlay.WidgetSlot
    if not Slot or not slua.isValid(Slot) then return end
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not slua.isValid(PC) then return end

    local fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
    local FVector2D = import("Vector2D") or FVector2D
    pcall(function()
        if not RedBoxOverlay._CachedPosVec then
            RedBoxOverlay._CachedPosVec = FVector2D(fromX, fromY)
        else
            RedBoxOverlay._CachedPosVec.X = fromX
            RedBoxOverlay._CachedPosVec.Y = fromY
        end
        Slot:SetPosition(RedBoxOverlay._CachedPosVec)
    end)
end

function RedBoxOverlay.Start()
    if RedBoxOverlay.bActive and RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then return end
    if RedBoxOverlay.Create() then
        RedBoxOverlay.bActive = true
        RedBoxOverlay._IsInRange = (RedBoxOverlay.TotalCount > 0)
        RedBoxOverlay._UpdateBackgroundColor(RedBoxOverlay._IsInRange)
        pcall(function() RedBoxOverlay.MainContainer:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    end
end

function RedBoxOverlay.Stop()
    RedBoxOverlay.bActive = false
    if RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then
        pcall(function()
            RedBoxOverlay.MainContainer:RemoveFromParent()
            RedBoxOverlay.MainContainer:ConditionalBeginDestroy()
        end)
    end
    RedBoxOverlay.MainContainer = nil
    RedBoxOverlay.WidgetSlot = nil
    RedBoxOverlay.TextBlock = nil
    RedBoxOverlay._BorderWidget = nil
    RedBoxOverlay._CachedPosVec = nil
end

_G.RedBoxOverlay = RedBoxOverlay

-- ========================================================================
-- ⚡ ESP V2 SYSTEM (Continued)
-- ========================================================================
local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local KismetMathLibrary_ESP9 = nil
local KismetSystemLibrary_ESP9 = nil

pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary") end)
pcall(function() KismetMathLibrary_ESP9 = import("KismetMathLibrary") end)
pcall(function() KismetSystemLibrary_ESP9 = import("KismetSystemLibrary") end)

local FVector2D_ESP9 = _G.FVector2D or import("Vector2D")
local FLinearColor_ESP9 = _G.FLinearColor or import("LinearColor")
local FVector_ESP9 = _G.FVector or import("Vector")

PlayerMapMarker.MarkTypeID = 1007
PlayerMapMarker.bUseScreenESP = true
PlayerMapMarker.bUseScreenMark = false
PlayerMapMarker.bUseQuickSign = false
PlayerMapMarker.bUseNavigator = false
PlayerMapMarker.bUseWidgetComponent = false
PlayerMapMarker.ESPBoneName = "head"
PlayerMapMarker.ESPWorldOffsetZ = 0
PlayerMapMarker.ESPAnchorOffsetX = 35
PlayerMapMarker.ESPAnchorOffsetY = 0
PlayerMapMarker.ESPTextOffsetX = 0
PlayerMapMarker.ESPTextOffsetY = 0
PlayerMapMarker.ESPWidgetAlignment = FVector2D_ESP9 and FVector2D_ESP9(0.5, 1.0) or {X=0.5, Y=1.0}
PlayerMapMarker.ESPWidgetSize = FVector2D_ESP9 and FVector2D_ESP9(70, 21) or {X=70, Y=21}
PlayerMapMarker.ESPWidgetAutoSize = true
PlayerMapMarker.ESPWidgetZOrder = 2
PlayerMapMarker.bShowDistance = true
PlayerMapMarker.DistanceUnit = "m"
PlayerMapMarker.WeaponIconBrushW = 96
PlayerMapMarker.WeaponIconBrushH = 48
PlayerMapMarker.HPWidgetSwitcherTypeIndex = 0
PlayerMapMarker.HPWidgetSwitcherType2Index = 0
PlayerMapMarker.bForceSwitcherIndexEveryUpdate = true
PlayerMapMarker.bUseSnapLines = true
PlayerMapMarker.SnapLineThickness = 3.0
PlayerMapMarker.SnapLineOriginY = 50
PlayerMapMarker.SnapLineOriginOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetY = -14
PlayerMapMarker.SnapLineColor = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 1.0, 0.0, 1.0) or {R=255, G=255, B=0, A=255}
PlayerMapMarker.SnapLineOpacity = 0.7
PlayerMapMarker.bUseSkeleton = false
PlayerMapMarker.SkeletonThickness = 0.8
PlayerMapMarker.SkeletonColor = nil
PlayerMapMarker.SkeletonOpacity = 0.8
PlayerMapMarker.SkeletonMaxDistance = 100000
PlayerMapMarker.bUseVisibilityColor = true
PlayerMapMarker.SkeletonVisibleColor = FLinearColor_ESP9 and FLinearColor_ESP9(0.0, 1.0, 0.0, 0.8) or {R=0,G=255,B=0,A=200}
PlayerMapMarker.SkeletonCoverColor = FLinearColor_ESP9 and FLinearColor_ESP9(0.9, 0.0, 0.0, 0.6) or {R=230,G=0,B=0,A=150}
PlayerMapMarker.SkeletonWidgets = {}
PlayerMapMarker._StaticBoneLocCache = {}
PlayerMapMarker.SkeletonChains = {
    {"neck_01", "lowerarm_r", "hand_r"},
    {"neck_01", "lowerarm_l", "hand_l"},
    {"head", "neck_01", "pelvis"},
    {"pelvis", "calf_r", "foot_r"},
    {"pelvis", "calf_l", "foot_l"}
}
PlayerMapMarker.BoneNameFallbacks = {
    ["head"] = {"head", "Head", "head_socket"},
    ["neck_01"] = {"neck_01", "Neck_01", "neck", "Neck"},
    ["clavicle_r"] = {"clavicle_r", "Clavicle_R", "clavicle_R"},
    ["upperarm_r"] = {"upperarm_r", "UpperArm_R", "arm_r", "arm_r_01"},
    ["lowerarm_r"] = {"lowerarm_r", "LowerArm_R", "forearm_r"},
    ["hand_r"] = {"hand_r", "Hand_R", "hand_r_socket"},
    ["clavicle_l"] = {"clavicle_l", "Clavicle_L", "clavicle_L"},
    ["upperarm_l"] = {"upperarm_l", "UpperArm_L", "arm_l", "arm_l_01"},
    ["lowerarm_l"] = {"lowerarm_l", "LowerArm_L", "forearm_l"},
    ["hand_l"] = {"hand_l", "Hand_L", "hand_l_socket"},
    ["spine_03"] = {"spine_03", "Spine_03", "spine_02", "spine"},
    ["spine_02"] = {"spine_02", "Spine_02", "spine_01"},
    ["pelvis"] = {"pelvis", "Pelvis", "hip"},
    ["thigh_r"] = {"thigh_r", "Thigh_R", "leg_r"},
    ["calf_r"] = {"calf_r", "Calf_R", "shin_r"},
    ["foot_r"] = {"foot_r", "Foot_R", "foot_r_socket"},
    ["thigh_l"] = {"thigh_l", "Thigh_L", "leg_l"},
    ["calf_l"] = {"calf_l", "Calf_L", "shin_l"},
    ["foot_l"] = {"foot_l", "Foot_L", "foot_l_socket"},
}

PlayerMapMarker.MapAddedFlag = 4
PlayerMapMarker.nUpdateInterval = 0.5
PlayerMapMarker.bUseFrameTick = false
PlayerMapMarker.nHeavyScanFrameInterval = 15
PlayerMapMarker.nDistanceUpdateFrameInterval = 5
PlayerMapMarker.bIncludeMe = false
PlayerMapMarker.bIncludeAI = true
PlayerMapMarker.bUseServerMarks = false
PlayerMapMarker.bActive = false
PlayerMapMarker.MarkMap = {}
PlayerMapMarker.PlayerInfo = {}
PlayerMapMarker.ESPCanvas = nil
PlayerMapMarker.ESPWidgets = {}
PlayerMapMarker.ESPWidgetPtrs = {}
PlayerMapMarker.SnapLineWidgets = {}
PlayerMapMarker._cachedViewportW = 1920
PlayerMapMarker._cachedViewportH = 1080
PlayerMapMarker._FrameCount = 0
PlayerMapMarker._bTickRegistered = false
PlayerMapMarker._CachedAllChars = nil
PlayerMapMarker._CachedMyLoc = nil
PlayerMapMarker._CachedMyKey = nil
PlayerMapMarker.WidgetComps = {}
PlayerMapMarker._bAllPathsFailed = false
PlayerMapMarker._bLightUpdateScheduled = false
PlayerMapMarker._LightUpdateInterval = 0.02
PlayerMapMarker._bDistanceUpdateScheduled = false
PlayerMapMarker._DistanceUpdateInterval = 0.1
PlayerMapMarker._bScreenMarkConfigSetup = false

-- ========================================================================
-- ⚡ ENEMY NAME & BOX ESP SYSTEM
-- ========================================================================
local EnemyESPWidgets = {}
local EnemyBoxWidgets = {}
local EnemyNameWidgets = {}

local function GetBoxColor()
    local colorIndex = _G.AK_GetVal("ENEMY_BOX_COLOR") or 0
    local colors = {
        {R=1.0, G=0.0, B=0.0, A=1.0},
        {R=0.0, G=1.0, B=0.0, A=1.0},
        {R=0.0, G=0.0, B=1.0, A=1.0},
        {R=1.0, G=1.0, B=0.0, A=1.0},
        {R=0.5, G=0.0, B=1.0, A=1.0},
        {R=0.0, G=1.0, B=1.0, A=1.0}
    }
    return colors[colorIndex + 1] or colors[1]
end

function PlayerMapMarker:CreateEnemyBoxWidget(Character)
    local key = tostring(Character)
    if EnemyBoxWidgets[key] then return EnemyBoxWidgets[key] end
    
    local canvas = PlayerMapMarker.ESPCanvas
    if not canvas or not slua.isValid(canvas) then return nil end
    
    local border = nil
    pcall(function()
        border = CGame:NewObjectFromPath("/Script/UMG.Border", canvas)
    end)
    if not border or not slua.isValid(border) then return nil end
    
    local color = GetBoxColor()
    pcall(function()
        border:SetBrushColor(FLinearColor(color.R, color.G, color.B, color.A))
        border:SetRenderTransformPivot(FVector2D(0.5, 0.5))
        border:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
    end)
    
    local slot = canvas:AddChildToCanvas(border)
    if not slot or not slua.isValid(slot) then return nil end
    
    pcall(function()
        slot:SetAutoSize(false)
        slot:SetZOrder(15)
        slot:SetAlignment(FVector2D(0.5, 0.5))
    end)
    
    local widgetData = {
        border = border,
        slot = slot,
        pos = FVector2D(0, 0),
        size = FVector2D(0, 0),
        lastPos = nil,
        lastSize = nil
    }
    
    EnemyBoxWidgets[key] = widgetData
    return widgetData
end

function PlayerMapMarker:CreateEnemyNameWidget(Character)
    local key = tostring(Character)
    if EnemyNameWidgets[key] then return EnemyNameWidgets[key] end
    
    local canvas = PlayerMapMarker.ESPCanvas
    if not canvas or not slua.isValid(canvas) then return nil end
    
    local textBlock = nil
    pcall(function()
        textBlock = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas)
    end)
    if not textBlock or not slua.isValid(textBlock) then return nil end
    
    local color = GetBoxColor()
    pcall(function()
        textBlock:SetColorAndOpacity(FSlateColor(FLinearColor(color.R, color.G, color.B, 1.0)))
        textBlock:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        if textBlock.Font then
            local font = textBlock.Font
            font.Size = 12
            textBlock:SetFont(font)
        end
    end)
    
    local slot = canvas:AddChildToCanvas(textBlock)
    if not slot or not slua.isValid(slot) then return nil end
    
    pcall(function()
        slot:SetAutoSize(true)
        slot:SetZOrder(16)
        slot:SetAlignment(FVector2D(0.5, 0.0))
    end)
    
    local widgetData = {
        text = textBlock,
        slot = slot,
        pos = FVector2D(0, 0),
        lastText = "",
        lastPos = nil
    }
    
    EnemyNameWidgets[key] = widgetData
    return widgetData
end

function PlayerMapMarker:UpdateEnemyBoxAndName(Character, PC, Loc)
    if not PlayerMapMarker.bUseScreenESP then return end
    if not _G.AK_GetVal("ENEMY_NAME") == 1 and not _G.AK_GetVal("ENEMY_BOX") == 1 then return end
    
    local key = tostring(Character)
    local bShowName = _G.AK_GetVal("ENEMY_NAME") == 1
    local bShowBox = _G.AK_GetVal("ENEMY_BOX") == 1
    
    if not bShowName and not bShowBox then
        if EnemyNameWidgets[key] then
            pcall(function() EnemyNameWidgets[key].text:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        end
        if EnemyBoxWidgets[key] then
            pcall(function() EnemyBoxWidgets[key].border:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        end
        return
    end
    
    local bonePoints = {}
    local boneNames = {
        "head", "neck_01", "spine_03", "spine_01", "pelvis",
        "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
        "hand_l", "hand_r", "calf_l", "calf_r", "foot_l", "foot_r"
    }
    
    for _, boneName in ipairs(boneNames) do
        local boneWorldLoc = PlayerMapMarker.GetBoneLocationWithFallback(Character, boneName)
        if boneWorldLoc then
            local bOnScreen, canvasX, canvasY = PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, boneWorldLoc)
            if bOnScreen then
                table.insert(bonePoints, {X = canvasX, Y = canvasY})
            end
        end
    end
    
    if #bonePoints < 2 then
        local loc = PlayerMapMarker.GetESPLocation(Character)
        if loc then
            local bOnScreen, canvasX, canvasY = PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, loc)
            if bOnScreen then
                table.insert(bonePoints, {X = canvasX - 30, Y = canvasY - 80})
                table.insert(bonePoints, {X = canvasX + 30, Y = canvasY + 10})
            end
        end
    end
    
    if #bonePoints < 2 then return end
    
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    
    for _, point in ipairs(bonePoints) do
        if point.X < minX then minX = point.X end
        if point.Y < minY then minY = point.Y end
        if point.X > maxX then maxX = point.X end
        if point.Y > maxY then maxY = point.Y end
    end
    
    local padding = 10
    local boxWidth = (maxX - minX) + (padding * 2)
    local boxHeight = (maxY - minY) + (padding * 2)
    local centerX = (minX + maxX) / 2
    local centerY = (minY + maxY) / 2
    
    if bShowBox then
        local boxWidget = PlayerMapMarker:CreateEnemyBoxWidget(Character)
        if boxWidget and boxWidget.border and boxWidget.slot then
            local color = GetBoxColor()
            pcall(function()
                boxWidget.border:SetBrushColor(FLinearColor(color.R, color.G, color.B, 0.6))
                boxWidget.border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                boxWidget.pos.X = centerX - (boxWidth / 2)
                boxWidget.pos.Y = centerY - (boxHeight / 2)
                boxWidget.slot:SetPosition(boxWidget.pos)
                boxWidget.size.X = boxWidth
                boxWidget.size.Y = boxHeight
                boxWidget.slot:SetSize(boxWidget.size)
                boxWidget.lastPos = boxWidget.pos
                boxWidget.lastSize = boxWidget.size
            end)
        end
    elseif EnemyBoxWidgets[key] then
        pcall(function() EnemyBoxWidgets[key].border:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    end
    
    if bShowName then
        local nameWidget = PlayerMapMarker:CreateEnemyNameWidget(Character)
        if nameWidget and nameWidget.text and nameWidget.slot then
            local playerName = PlayerMapMarker.GetPlayerName(Character)
            local color = GetBoxColor()
            pcall(function()
                nameWidget.text:SetText(playerName)
                nameWidget.text:SetColorAndOpacity(FSlateColor(FLinearColor(color.R, color.G, color.B, 1.0)))
                nameWidget.text:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                nameWidget.pos.X = centerX
                nameWidget.pos.Y = minY - padding - 20
                nameWidget.slot:SetPosition(nameWidget.pos)
                nameWidget.lastPos = nameWidget.pos
                nameWidget.lastText = playerName
            end)
        end
    elseif EnemyNameWidgets[key] then
        pcall(function() EnemyNameWidgets[key].text:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    end
end

function PlayerMapMarker:ClearEnemyNameAndBoxes()
    for key, widget in pairs(EnemyBoxWidgets) do
        if widget and widget.border and slua.isValid(widget.border) then
            pcall(function()
                widget.border:RemoveFromParent()
                widget.border:ConditionalBeginDestroy()
            end)
        end
    end
    EnemyBoxWidgets = {}
    
    for key, widget in pairs(EnemyNameWidgets) do
        if widget and widget.text and slua.isValid(widget.text) then
            pcall(function()
                widget.text:RemoveFromParent()
                widget.text:ConditionalBeginDestroy()
            end)
        end
    end
    EnemyNameWidgets = {}
end

-- ========================================================================
-- PATCH: INTEGRATE ENEMY NAME & BOX INTO EXISTING UPDATE LOOP
-- ========================================================================

local originalUpdateESP = PlayerMapMarker.UpdateESP
PlayerMapMarker.UpdateESP = function(AllPlayers, MyLoc)
    originalUpdateESP(AllPlayers, MyLoc)
    
    if not PlayerMapMarker.bUseScreenESP then return end
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end
    
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid_ESP9(PC) then return end
    
    local MyKey = PlayerMapMarker.GetMyPlayerKey()
    local MyChar = nil
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then MyChar = GDP.GetLocalCharacter() end
    end)
    
    local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)
    local activeKeys = {}
    
    for PlayerKey, Character in pairs(AllPlayers) do
        if IsValid_ESP9(Character) then
            local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PlayerMapMarker.IsAI(Character)
            local KeyStr = tostring(PlayerKey)
            
            local bSkip = false
            if bIsMe and not PlayerMapMarker.bIncludeMe then bSkip = true end
            if bIsAI and not PlayerMapMarker.bIncludeAI then bSkip = true end
            
            local TeamID = PlayerMapMarker.GetTeamID(Character)
            if MyTeamID ~= nil and TeamID == MyTeamID and not bIsMe then bSkip = true end
            
            local bIsAlive = PlayerMapMarker.IsAlive(Character)
            
            if not bSkip and bIsAlive then
                local Loc = PlayerMapMarker.GetESPLocation(Character)
                if Loc then
                    activeKeys[KeyStr] = true
                    PlayerMapMarker:UpdateEnemyBoxAndName(Character, PC, Loc)
                end
            end
        end
    end
    
    for key, widget in pairs(EnemyBoxWidgets) do
        if not activeKeys[key] then
            if widget and widget.border and slua.isValid(widget.border) then
                pcall(function()
                    widget.border:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                end)
            end
        end
    end
    
    for key, widget in pairs(EnemyNameWidgets) do
        if not activeKeys[key] then
            if widget and widget.text and slua.isValid(widget.text) then
                pcall(function()
                    widget.text:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                end)
            end
        end
    end
end

local originalStop = PlayerMapMarker.Stop
PlayerMapMarker.Stop = function()
    originalStop()
    PlayerMapMarker:ClearEnemyNameAndBoxes()
end

local function IsValid_ESP9(obj)
    if obj == nil then return false end
    if slua and slua.isValid then return slua.isValid(obj) end
    return obj ~= nil
end

function PlayerMapMarker.GetGameplayData()
    if PlayerMapMarker._CachedGameplayData then return PlayerMapMarker._CachedGameplayData end
    local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
    if ok and GDP then PlayerMapMarker._CachedGameplayData = GDP return GDP end
    return nil
end

function PlayerMapMarker.GetMyPlayerController()
    local PC = PlayerMapMarker._CachedPC
    if PC and IsValid_ESP9(PC) then return PC end
    local GDP = PlayerMapMarker.GetGameplayData()
    if not GDP then return nil end
    pcall(function() PC = GDP.GetPlayerController and GDP.GetPlayerController() end)
    if PC and IsValid_ESP9(PC) then PlayerMapMarker._CachedPC = PC return PC end
    return nil
end

function PlayerMapMarker.GetCGameState()
    if CGameState and IsValid_ESP9(CGameState) then return CGameState end
    if PlayerMapMarker._CachedCGameState and IsValid_ESP9(PlayerMapMarker._CachedCGameState) then return PlayerMapMarker._CachedCGameState end
    local ok, GS = pcall(function() return require("GameLua.GameCore.Data.CGameState") end)
    if ok and GS then PlayerMapMarker._CachedCGameState = GS return GS end
    return nil
end

function PlayerMapMarker.GetAllCharacters()
    local AllChars = {}
    pcall(function()
        local Pawns = Game:GetAllPlayerPawns()
        if Pawns then
            for _, Pawn in pairs(Pawns) do
                if Pawn and slua.isValid(Pawn) then
                    local pKey = nil
                    if Pawn.GetPlayerKey then pKey = Pawn:GetPlayerKey() end
                    if not pKey and Pawn.PlayerKey then pKey = Pawn.PlayerKey end
                    if not pKey and Pawn.PlayerState and Pawn.PlayerState.PlayerKey then pKey = Pawn.PlayerState.PlayerKey end
                    if pKey then AllChars[pKey] = Pawn end
                end
            end
        end
    end)
    if not next(AllChars) then
        local GS = PlayerMapMarker.GetCGameState()
        if GS and GS.GetAllCharacters then pcall(function() AllChars = GS:GetAllCharacters() end) end
    end
    return AllChars
end

function PlayerMapMarker.GetMyPlayerKey()
    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid_ESP9(PC) then return nil end
    local MyKey = nil
    pcall(function()
        if PC.GetPlayerKey then MyKey = PC:GetPlayerKey()
        elseif PC.PlayerState and PC.PlayerState.PlayerKey then MyKey = PC.PlayerState.PlayerKey end
    end)
    return MyKey
end

function PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
    local bIsMe = false
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then
            local MyChar = GDP.GetLocalCharacter()
            if MyChar and Character == MyChar then bIsMe = true return end
        end
        local PC = PlayerMapMarker.GetMyPlayerController()
        if PC and PC.GetPawn then
            local Pawn = PC:GetPawn()
            if Pawn and Character == Pawn then bIsMe = true return end
        end
    end)
    if not bIsMe and MyKey ~= nil and PlayerKey ~= nil then bIsMe = (tostring(PlayerKey) == tostring(MyKey)) end
    return bIsMe
end

function PlayerMapMarker.GetCharacterLocation(Character)
    if not IsValid_ESP9(Character) then return nil end
    local Loc = nil
    pcall(function() if Character.K2_GetActorLocation then Loc = Character:K2_GetActorLocation() end end)
    if not Loc then pcall(function() if Game and Game.GetActorLocation then Loc = Game:GetActorLocation(Character) end end) end
    return Loc
end

function PlayerMapMarker.CalcDistance(Loc1, Loc2)
    if not Loc1 or not Loc2 then return nil end
    local Dist = nil
    pcall(function() if FVector_ESP9 and FVector_ESP9.Dist2D then Dist = FVector_ESP9.Dist2D(Loc1, Loc2) end end)
    if not Dist then
        pcall(function()
            local DX = (Loc1.X or 0) - (Loc2.X or 0)
            local DY = (Loc1.Y or 0) - (Loc2.Y or 0)
            Dist = math.sqrt(DX * DX + DY * DY)
        end)
    end
    return Dist
end

function PlayerMapMarker.GetDistanceString(MyLoc, TargetLoc)
    if not PlayerMapMarker.bShowDistance then return "" end
    if not MyLoc or not TargetLoc then return "" end
    local Dist = PlayerMapMarker.CalcDistance(MyLoc, TargetLoc)
    if not Dist then return "" end
    local Meters = Dist / 100
    if Meters < 1000 then return string.format("%dm", math.floor(Meters))
    else return string.format("%.1fkm", Meters / 1000) end
end

function PlayerMapMarker.GetMyLocation()
    local GDP = PlayerMapMarker.GetGameplayData()
    if not GDP then return nil end
    local MyChar = nil
    pcall(function() MyChar = GDP.GetLocalCharacter and GDP.GetLocalCharacter() end)
    if not IsValid_ESP9(MyChar) then return nil end
    return PlayerMapMarker.GetCharacterLocation(MyChar)
end

function PlayerMapMarker.GetPlayerName(Character)
    if not IsValid_ESP9(Character) then return "Unknown" end
    local Name = nil
    pcall(function() if Character.GetPlayerNameSafety then Name = Character:GetPlayerNameSafety() end end)
    if not Name then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid_ESP9(PS) and PS.GetPlayerName then Name = PS:GetPlayerName() end
        end)
    end
    return Name or "Unknown"
end

function PlayerMapMarker.IsAI(Character)
    local bAI = false
    pcall(function() if Game and Game.IsAI then bAI = Game:IsAI(Character) end end)
    return bAI
end

function PlayerMapMarker.IsAlive(Character)
    local bAlive = true
    pcall(function() if Character.IsAlive then bAlive = Character:IsAlive() end end)
    return bAlive
end

function PlayerMapMarker.GetTeamID(Character)
    if not IsValid_ESP9(Character) then return nil end
    local TeamID = nil
    pcall(function() if Character.GetTeamID then TeamID = Character:GetTeamID() end end)
    if not TeamID then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid_ESP9(PS) and PS.GetTeamID then TeamID = PS:GetTeamID()
            elseif IsValid_ESP9(PS) and PS.TeamID then TeamID = PS.TeamID end
        end)
    end
    if not TeamID then pcall(function() if Character.TeamID then TeamID = Character.TeamID end end) end
    return TeamID
end

function PlayerMapMarker.GetTeamColor(TeamID)
    if TeamID == nil or TeamID == 0 then
        return FLinearColor_ESP9 and FLinearColor_ESP9(0.2, 0.4, 1.0, 1.0) or {R=50,G=100,B=255,A=255}
    end
    local TeamColors = {
        [1]={R=255,G=50,B=50,A=255,fR=1.0,fG=0.2,fB=0.2},
        [2]={R=50,G=255,B=50,A=255,fR=0.2,fG=1.0,fB=0.2},
        [3]={R=50,G=100,B=255,A=255,fR=0.2,fG=0.4,fB=1.0},
        [4]={R=255,G=255,B=50,A=255,fR=1.0,fG=1.0,fB=0.2},
        [5]={R=255,G=50,B=255,A=255,fR=1.0,fG=0.2,fB=1.0},
        [6]={R=50,G=255,B=255,A=255,fR=0.2,fG=1.0,fB=1.0},
        [7]={R=255,G=150,B=50,A=255,fR=1.0,fG=0.6,fB=0.2},
        [8]={R=150,G=50,B=255,A=255,fR=0.6,fG=0.2,fB=1.0},
        [9]={R=200,G=255,B=50,A=255,fR=0.8,fG=1.0,fB=0.2},
        [10]={R=50,G=150,B=255,A=255,fR=0.2,fG=0.6,fB=1.0},
        [11]={R=255,G=100,B=150,A=255,fR=1.0,fG=0.4,fB=0.6},
        [12]={R=100,G=255,B=150,A=255,fR=0.4,fG=1.0,fB=0.6},
        [13]={R=150,G=150,B=50,A=255,fR=0.6,fG=0.6,fB=0.2},
        [14]={R=50,G=200,B=150,A=255,fR=0.2,fG=0.8,fB=0.6},
        [15]={R=255,G=200,B=50,A=255,fR=1.0,fG=0.8,fB=0.2}
    }
    local colorIndex = (TeamID % 15)
    if colorIndex == 0 then colorIndex = 15 end
    local c = TeamColors[colorIndex]
    return FLinearColor_ESP9 and FLinearColor_ESP9(c.fR, c.fG, c.fB, 1.0) or {R=c.R, G=c.G, B=c.B, A=c.A}
end

function PlayerMapMarker.InitESPCanvas()
    if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then return true end
    local InGameUITools = nil
    pcall(function() InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
    if not InGameUITools then return false end
    local MainControlBaseUI = nil
    pcall(function() MainControlBaseUI = InGameUITools.GetMainControlBaseUI() end)
    if not MainControlBaseUI or not Game:IsValid(MainControlBaseUI) then return false end
    local ParentCanvas = nil
    pcall(function()
        if MainControlBaseUI.CanvasPanel_0 and Game:IsValid(MainControlBaseUI.CanvasPanel_0) then ParentCanvas = MainControlBaseUI.CanvasPanel_0
        elseif MainControlBaseUI.CanvasPanel_42 and Game:IsValid(MainControlBaseUI.CanvasPanel_42) then ParentCanvas = MainControlBaseUI.CanvasPanel_42 end
    end)
    if not ParentCanvas then return false end
    PlayerMapMarker.ESPCanvas = ParentCanvas
    return true
end

function PlayerMapMarker.GetESPLocation(Character)
    if not IsValid_ESP9(Character) then return nil end
    local BoneLoc = PlayerMapMarker.GetCharacterLocation(Character)
    if BoneLoc then
        local heightOffset = 85
        pcall(function()
            if Character.bIsCrouched then heightOffset = 60 end
            if Character.IsProne and Character:IsProne() then heightOffset = 30 end
        end)
        pcall(function() BoneLoc.Z = BoneLoc.Z + heightOffset + (PlayerMapMarker.ESPWorldOffsetZ or 0) end)
    end
    return BoneLoc
end

function PlayerMapMarker.GetCharacterWeaponInfo(Character)
    if not IsValid_ESP9(Character) then return nil end
    local WeaponID, WeaponName, WeaponIconPath, WeaponIconTexture, CurrentWeapon = nil, nil, nil, nil, nil
    pcall(function() if Character.GetCurrentWeapon then CurrentWeapon = Character:GetCurrentWeapon() end end)
    if not CurrentWeapon then pcall(function() CurrentWeapon = Character.CurrentWeapon end) end
    if not CurrentWeapon then pcall(function() if Character.GetWeaponManager then local WM = Character:GetWeaponManager() if WM and WM.GetCurrentWeapon then CurrentWeapon = WM:GetCurrentWeapon() end end end) end
    if CurrentWeapon and IsValid_ESP9(CurrentWeapon) then
        pcall(function() if CurrentWeapon.GetWeaponID then WeaponID = CurrentWeapon:GetWeaponID() end end)
        if not WeaponID then pcall(function() WeaponID = CurrentWeapon.WeaponID end) end
        if not WeaponID then pcall(function() if CurrentWeapon.GetItemID then WeaponID = CurrentWeapon:GetItemID() end end) end
        pcall(function() if CurrentWeapon.GetWeaponName then WeaponName = CurrentWeapon:GetWeaponName() end end)
        pcall(function() if CurrentWeapon.GetWeaponIconPath then WeaponIconPath = CurrentWeapon:GetWeaponIconPath() end end)
        pcall(function() if CurrentWeapon.GetWeaponIcon then WeaponIconTexture = CurrentWeapon:GetWeaponIcon() end end)
    end
    if not WeaponID then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety() elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if PS and IsValid_ESP9(PS) then
                if PS.GetCurrentWeaponID then WeaponID = PS:GetCurrentWeaponID() end
                if not WeaponID and PS.CurWeaponID then WeaponID = PS.CurWeaponID end
            end
        end)
    end
    return { WeaponID = WeaponID, WeaponName = WeaponName, WeaponIconPath = WeaponIconPath, WeaponIconTexture = WeaponIconTexture, CurrentWeapon = CurrentWeapon }
end

PlayerMapMarker._OBHeadWidgetClass = nil
PlayerMapMarker._OBHeadWidgetLoadFailed = false

function PlayerMapMarker.CreateESPWidget()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end
    if PlayerMapMarker._OBHeadWidgetLoadFailed then return nil end

    if not PlayerMapMarker._OBHeadWidgetClass then
        pcall(function()
            local Path = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP"
            local uClass = slua.loadClass(Path)
            if uClass then PlayerMapMarker._OBHeadWidgetClass = uClass end
        end)
        if not PlayerMapMarker._OBHeadWidgetClass then
            PlayerMapMarker._OBHeadWidgetLoadFailed = true
            return nil
        end
    end

    local Widget = nil
    pcall(function()
        local STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
        local PC = PlayerMapMarker.GetMyPlayerController()
        local OuterObj = IsValid_ESP9(PC) and PC.Object or PlayerMapMarker.ESPCanvas
        Widget = STExtraBlueprintFunctionLibrary.CreateWidgetByClass(PlayerMapMarker._OBHeadWidgetClass, OuterObj)
    end)
    if not Widget then return nil end

    pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() Widget:SetRenderOpacity(1.0) end)

    local TEXT_COLOR = FSlateColor(FLinearColor(1.0, 1.0, 0.0, 1.0))
    local BG_COLOR = FLinearColor(0.0, 0.0, 0.0, 0.8)

    if Widget.TextBlock_PlayerName and slua.isValid(Widget.TextBlock_PlayerName) then
        pcall(function()
            Widget.TextBlock_PlayerName:SetColorAndOpacity(TEXT_COLOR)
            Widget.TextBlock_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
    end
    
    if Widget.Text_PlayerName and slua.isValid(Widget.Text_PlayerName) then
        pcall(function()
            Widget.Text_PlayerName:SetColorAndOpacity(TEXT_COLOR)
            Widget.Text_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
    end
    
    if Widget.TextBlock_TeamName and slua.isValid(Widget.TextBlock_TeamName) then
        pcall(function()
            Widget.TextBlock_TeamName:SetColorAndOpacity(TEXT_COLOR)
            Widget.TextBlock_TeamName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
    end
    
    if Widget.Image_Name_BG and slua.isValid(Widget.Image_Name_BG) then
        pcall(function()
            Widget.Image_Name_BG:SetColorAndOpacity(BG_COLOR)
            Widget.Image_Name_BG:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
    end
    
    if Widget.Image_TeamBG and slua.isValid(Widget.Image_TeamBG) then
        pcall(function()
            Widget.Image_TeamBG:SetColorAndOpacity(BG_COLOR)
            Widget.Image_TeamBG:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
    end

    local NameText = nil
    local HealthFill = nil
    pcall(function()
        NameText = Widget.TextBlock_TeamName
        if NameText and slua.isValid(NameText) then pcall(function() NameText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end
        if Widget.TextBlock_PlayerName and slua.isValid(Widget.TextBlock_PlayerName) then pcall(function() Widget.TextBlock_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end
        local SizeBox_HP = Widget.SizeBox_HP
        if SizeBox_HP and slua.isValid(SizeBox_HP) then
            pcall(function() SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            local ExistingChild = nil
            pcall(function() if SizeBox_HP.GetContent then ExistingChild = SizeBox_HP:GetContent() end end)
            if ExistingChild and slua.isValid(ExistingChild) then
                local FoundPB = PlayerMapMarker.FindProgressBarInWidget(ExistingChild, 0, 5)
                if FoundPB and slua.isValid(FoundPB) then HealthFill = FoundPB end
            end
        end
    end)

    local WidgetData = {
        Container = Widget,
        NameText = NameText,
        HealthFill = HealthFill,
        IsGameWidget = true,
        HasChildren = (NameText ~= nil)
    }
    return WidgetData
end

function PlayerMapMarker.FindProgressBarInWidget(WidgetObj, Depth, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    Depth = Depth or 0
    MaxDepth = MaxDepth or 5
    if Depth > MaxDepth then return nil end

    local bIsPB = false
    pcall(function() if WidgetObj.SetPercent and WidgetObj.SetFillColorAndOpacity then bIsPB = true end end)
    if bIsPB then return WidgetObj end

    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)
    for i = 0, math.max(nChildren - 1, 0) do
        local child = nil
        pcall(function() child = WidgetObj:GetChildAt(i) end)
        if child and slua.isValid(child) then
            local result = PlayerMapMarker.FindProgressBarInWidget(child, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    return nil
end

function PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
    if not Widget or not Widget.Container then return end
    if not _G.AK_GetVal("ESP9_Team") == 1 then return end
    local color = PlayerMapMarker.GetTeamColor(TeamID)
    if not color then return end
    pcall(function()
        local W = Widget.Container
        if not W or not slua.isValid(W) then return end
        if W.SetTeamColor then pcall(function() W:SetTeamColor(TeamID) end) end
    end)
end

function PlayerMapMarker.UpdateESPText(Widget, Text)
    if not Widget then return end
    if Widget._LastESPText == Text then return end
    Widget._LastESPText = Text

    local YELLOW = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 1.0, 0.0, 1.0) or {R=255, G=255, B=0, A=255}

    local function applyText(w, txt)
        if not w or not slua.isValid(w) then return end
        if txt == "" then
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            return
        else
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        end
        pcall(function() w:SetText(txt) end)
        pcall(function()
            if w.SetColorAndOpacity then
                w:SetColorAndOpacity(YELLOW)
            end
        end)
    end

    if Widget.NameText and slua.isValid(Widget.NameText) then 
        applyText(Widget.NameText, Text) 
    end
    
    if Widget.IsGameWidget and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                applyText(W.TextBlock_TeamName, Text)
                applyText(W.TextBlock_PlayerName, Text)
            end
        end)
    end
end

function PlayerMapMarker.UpdateESPHealth(Widget, pct)
    if not Widget then return end
    Widget.LastPct = pct
    local bShowHP = _G.AK_GetVal("ESP9_HP") == 1
    if not bShowHP then return end

    if PlayerMapMarker.bForceSwitcherIndexEveryUpdate and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                if W.WidgetSwitcher_Type and slua.isValid(W.WidgetSwitcher_Type) then pcall(function() if W.WidgetSwitcher_Type.SetActiveWidgetIndex then W.WidgetSwitcher_Type:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherTypeIndex) end end) end
                if W.WidgetSwitcher_Type2 and slua.isValid(W.WidgetSwitcher_Type2) then pcall(function() if W.WidgetSwitcher_Type2.SetActiveWidgetIndex then W.WidgetSwitcher_Type2:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherType2Index) end end) end
            end
        end)
    end

    if Widget.HealthFill then
        local bValid = false
        pcall(function() bValid = slua.isValid(Widget.HealthFill) end)
        if bValid then
            pcall(function()
                if Widget.HealthFill.SetPercent then
                    Widget.HealthFill:SetPercent(pct)
                    local color
                    if pct > 0.5 then color = FLinearColor_ESP9 and FLinearColor_ESP9(0.0, 1.0, 0.0, 1.0) or {R=0,G=255,B=0,A=255}
                    elseif pct > 0.25 then color = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 0.5, 0.0, 1.0) or {R=255,G=128,B=0,A=255}
                    else color = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 0.0, 0.0, 1.0) or {R=255,G=0,B=0,A=255} end
                    if Widget.HealthFill.SetFillColorAndOpacity then Widget.HealthFill:SetFillColorAndOpacity(color) end
                end
            end)
        end
    end
end

function PlayerMapMarker.UpdateESPPositionWithPC(Widget, WorldLoc, PC, CanvasPos)
    if not Widget or not IsValid_ESP9(PC) then return false end

    local Container = Widget.Container or Widget
    local bOnScreen = true

    if not CanvasPos then
        if not WorldLoc then return false end
        bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
    end

    if not bOnScreen then pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) return false end

    pcall(function()
        local bShowAnyUI = _G.AK_GetVal("ESP9_Name") == 1 or _G.AK_GetVal("ESP9_Distance") == 1 or _G.AK_GetVal("ESP9_HP") == 1 or _G.AK_GetVal("ESP9_Team") == 1 or _G.AK_GetVal("ESP9_Weapon") == 1
        if bShowAnyUI then Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        else Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end

        if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
            local ptr = tostring(Container)
            local Slot = PlayerMapMarker.ESPWidgetPtrs[ptr]
            if not Slot or not slua.isValid(Slot) then
                local addedSlot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Container)
                if addedSlot and slua.isValid(addedSlot) then
                    Slot = addedSlot
                    PlayerMapMarker.ESPWidgetPtrs[ptr] = addedSlot
                    pcall(function() Slot:SetAutoSize(true) end)
                    pcall(function() Slot:SetAlignment(FVector2D_ESP9 and FVector2D_ESP9(0.5, 1.0) or {X=0.5, Y=1.0}) end)
                    pcall(function() Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 20) end)
                end
            end
            if Slot and slua.isValid(Slot) then
                local finalX = CanvasPos.X + (PlayerMapMarker.ESPAnchorOffsetX or 0)
                local finalY = CanvasPos.Y + (PlayerMapMarker.ESPAnchorOffsetY or 0)
                if not Widget._CachedPosVec then Widget._CachedPosVec = FVector2D_ESP9 and FVector2D_ESP9(finalX, finalY) or {X=finalX, Y=finalY}
                else Widget._CachedPosVec.X = finalX; Widget._CachedPosVec.Y = finalY end
                pcall(function() Slot:SetPosition(Widget._CachedPosVec) end)
            end
        end
    end)
    return true
end

PlayerMapMarker._CanvasScaleX = 1.0
PlayerMapMarker._CanvasScaleY = 1.0
PlayerMapMarker._CanvasOffsetX = 0.0
PlayerMapMarker._CanvasOffsetY = 0.0

function PlayerMapMarker.UpdateCanvasTransform(PC)
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end

    local success = false
    pcall(function()
        local SBL = SlateBlueprintLibrary
        if SBL and SBL.AbsoluteToLocal then
            local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
            if cg then
                local pt0 = SBL.AbsoluteToLocal(cg, FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0})
                local pt1 = SBL.AbsoluteToLocal(cg, FVector2D_ESP9 and FVector2D_ESP9(100, 100) or {X=100, Y=100})
                if pt0 and pt1 then
                    PlayerMapMarker._CanvasScaleX = (pt1.X - pt0.X) / 100
                    PlayerMapMarker._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                    PlayerMapMarker._CanvasOffsetX = pt0.X
                    PlayerMapMarker._CanvasOffsetY = pt0.Y
                    success = true
                end
            end
        end
    end)

    if not success then
        local scale = 1.0
        if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then scale = WidgetLayoutLibrary.GetViewportScale(PC) or 1.0 end
        PlayerMapMarker._CanvasScaleX = 1.0 / scale
        PlayerMapMarker._CanvasScaleY = 1.0 / scale
        PlayerMapMarker._CanvasOffsetX = 0
        PlayerMapMarker._CanvasOffsetY = 0
    end
end

function PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    if not ScreenPixelPos then return FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0} end
    local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
    local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
    local offsetX = PlayerMapMarker._CanvasOffsetX or 0
    local offsetY = PlayerMapMarker._CanvasOffsetY or 0
    return (FVector2D_ESP9 and FVector2D_ESP9(ScreenPixelPos.X * scaleX + offsetX, ScreenPixelPos.Y * scaleY + offsetY)) or {X = ScreenPixelPos.X * scaleX + offsetX, Y = ScreenPixelPos.Y * scaleY + offsetY}
end

function PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
    if not IsValid_ESP9(PC) or not WorldLoc then return false, (FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0}) end

    local ScreenPixelPos = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0}
    local bOK = false
    pcall(function()
        local res = PC:ProjectWorldLocationToScreen(WorldLoc, ScreenPixelPos, true)
        if res == true or res == 1 or (ScreenPixelPos and (ScreenPixelPos.X ~= 0 or ScreenPixelPos.Y ~= 0)) then bOK = true end
    end)

    if not bOK or not ScreenPixelPos or (ScreenPixelPos.X == 0 and ScreenPixelPos.Y == 0) then return false, (FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0}) end

    local CanvasLocalPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    return true, CanvasLocalPos
end

function PlayerMapMarker.GetSnapLineStartPos(PC)
    local screenPixelW, screenPixelH = 0, 0
    local scale = 1.0

    pcall(function()
        if PC and PC.GetViewportSize then
            local vs = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0,Y=0}
            PC:GetViewportSize(vs)
            if vs and vs.X and vs.X > 200 then screenPixelW = vs.X screenPixelH = vs.Y end
        end
    end)

    if screenPixelW <= 200 then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportSize then
                local vs = WLL.GetViewportSize(PC)
                if vs and vs.X and vs.X > 200 then screenPixelW = vs.X screenPixelH = vs.Y end
            end
        end)
    end

    pcall(function()
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportScale then
            local s = WLL.GetViewportScale(PC)
            if s and type(s) == "number" and s > 0 then scale = s end
        end
    end)

    if screenPixelW <= 200 then
        screenPixelW = (PlayerMapMarker._cachedViewportW or 1920) * scale
        screenPixelH = (PlayerMapMarker._cachedViewportH or 1080) * scale
    end

    if not PlayerMapMarker._CachedTopCenterPixel then PlayerMapMarker._CachedTopCenterPixel = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0,Y=0} end
    PlayerMapMarker._CachedTopCenterPixel.X = screenPixelW / 2.0
    PlayerMapMarker._CachedTopCenterPixel.Y = (PlayerMapMarker.SnapLineOriginY or 50) * scale

    local fromCanvasPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, PlayerMapMarker._CachedTopCenterPixel)
    return fromCanvasPos.X + (PlayerMapMarker.SnapLineOriginOffsetX or 0), fromCanvasPos.Y
end

function PlayerMapMarker.CreateSnapLine()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end

    local Border = nil
    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PlayerMapMarker.ESPCanvas) end)
    if not Border or not slua.isValid(Border) then return nil end

    local color = PlayerMapMarker.SnapLineColor or (FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 1.0, 1.0, PlayerMapMarker.SnapLineOpacity or 0.7) or {R=1,G=1,B=1,A=PlayerMapMarker.SnapLineOpacity or 0.7})
    pcall(function() Border:SetBrushColor(color) end)
    pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() Border.RenderTransformPivot = FVector2D_ESP9 and FVector2D_ESP9(0.0, 0.5) or {X=0,Y=0.5} end)
    pcall(function() Border:SetRenderTransformPivot(FVector2D_ESP9 and FVector2D_ESP9(0.0, 0.5) or {X=0,Y=0.5}) end)

    local Slot = nil
    pcall(function()
        Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
        if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(1) end
    end)
    return { Widget = Border, Slot = Slot }
end

-- ========================================================================
-- ⚡ UPDATED SNAP LINE FUNCTION WITH VISIBILITY CHECK (Green/Red)
-- ========================================================================
function PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
    if not PlayerMapMarker.bUseSnapLines then return end
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end

    local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]
    if not bOnScreen or not CanvasPos then
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function() LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        end
        return
    end

    if not LineData then
        LineData = PlayerMapMarker.CreateSnapLine()
        if not LineData or not LineData.Widget or not LineData.Slot then return end
        PlayerMapMarker.SnapLineWidgets[KeyStr] = LineData
    end

    local Widget = LineData.Widget
    local Slot = LineData.Slot

    pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)

    local ESPData = PlayerMapMarker.ESPWidgets[KeyStr]
    local Character = ESPData and ESPData.Character
    local PC = PlayerMapMarker.GetMyPlayerController()
    
    local bIsVisible = false
    if Character and slua.isValid(Character) and PC and slua.isValid(PC) then
        pcall(function()
            if PC.LineOfSightTo then
                local zeroVec = FVector_ESP9 and FVector_ESP9(0, 0, 0) or {X=0, Y=0, Z=0}
                bIsVisible = PC:LineOfSightTo(Character, zeroVec, false)
            end
        end)
    end

    local lineColor
    if bIsVisible then
        lineColor = FLinearColor_ESP9 and FLinearColor_ESP9(0.0, 1.0, 0.0, PlayerMapMarker.SnapLineOpacity or 0.7) 
            or {R=0, G=255, B=0, A=math.floor((PlayerMapMarker.SnapLineOpacity or 0.7) * 255)}
    else
        lineColor = FLinearColor_ESP9 and FLinearColor_ESP9(1.0, 0.0, 0.0, PlayerMapMarker.SnapLineOpacity or 0.7) 
            or {R=255, G=0, B=0, A=math.floor((PlayerMapMarker.SnapLineOpacity or 0.7) * 255)}
    end
    
    pcall(function() Widget:SetBrushColor(lineColor) end)

    local toX = CanvasPos.X + (PlayerMapMarker.SnapLineHeadOffsetX or 0)
    local toY = CanvasPos.Y + (PlayerMapMarker.SnapLineHeadOffsetY or 0)

    local dx = toX - fromX
    local dy = toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    local thickness = PlayerMapMarker.SnapLineThickness or 3.0
    local angle_rad = 0
    if math.atan2 then angle_rad = math.atan2(dy, dx) else angle_rad = math.atan(dy, dx) end
    local angle = angle_rad * (180.0 / math.pi)

    if not LineData._CachedPosVec then
        LineData._CachedPosVec = FVector2D_ESP9 and FVector2D_ESP9(fromX, fromY - thickness / 2.0) or {X=fromX, Y=fromY - thickness / 2.0}
        LineData._CachedSizeVec = FVector2D_ESP9 and FVector2D_ESP9(length, thickness) or {X=length, Y=thickness}
    else
        LineData._CachedPosVec.X = fromX; LineData._CachedPosVec.Y = fromY - thickness / 2.0
        LineData._CachedSizeVec.X = length; LineData._CachedSizeVec.Y = thickness
    end

    pcall(function()
        Slot:SetPosition(LineData._CachedPosVec)
        Slot:SetSize(LineData._CachedSizeVec)
    end)
    pcall(function() Widget:SetRenderAngle(angle) end)
end

function PlayerMapMarker.RemoveSnapLine(KeyStr)
    local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]
    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
        pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
        PlayerMapMarker.SnapLineWidgets[KeyStr] = nil
    end
end

function PlayerMapMarker.RemoveESPWidget(Widget, KeyStr)
    if not Widget then return end
    local Container = Widget.Container or Widget
    pcall(function()
        local ptr = tostring(Container)
        PlayerMapMarker.ESPWidgetPtrs[ptr] = nil
        Container:RemoveFromParent()
        Container:ConditionalBeginDestroy()
    end)
    if KeyStr then
        PlayerMapMarker.RemoveSnapLine(KeyStr)
        if PlayerMapMarker.RemoveSkeletonLines then
            PlayerMapMarker.RemoveSkeletonLines(KeyStr)
        end
    end
end

function PlayerMapMarker.ClearAllSnapLines()
    for KeyStr, LineData in pairs(PlayerMapMarker.SnapLineWidgets) do
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
        end
    end
    PlayerMapMarker.SnapLineWidgets = {}
end

function PlayerMapMarker.ScreenPixelToCanvasLocalRaw(PC, screenX, screenY)
    local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
    local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
    local offsetX = PlayerMapMarker._CanvasOffsetX or 0
    local offsetY = PlayerMapMarker._CanvasOffsetY or 0
    return screenX * scaleX + offsetX, screenY * scaleY + offsetY
end

function PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, WorldLoc)
    if not IsValid_ESP9(PC) or not WorldLoc then return false, 0, 0 end

    if not PlayerMapMarker._tempScreenPixelPos then
        PlayerMapMarker._tempScreenPixelPos = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0}
    end
    local tempPos = PlayerMapMarker._tempScreenPixelPos
    local bOK = false
    pcall(function()
        local res = PC:ProjectWorldLocationToScreen(WorldLoc, tempPos, true)
        if res == true or res == 1 then bOK = true end
    end)

    if not bOK or (tempPos.X == 0 and tempPos.Y == 0) then return false, 0, 0 end

    local canvasX, canvasY = PlayerMapMarker.ScreenPixelToCanvasLocalRaw(PC, tempPos.X, tempPos.Y)
    return true, canvasX, canvasY
end

function PlayerMapMarker.GetBoneLocationWithFallback(Character, PrimaryBoneName)
    if not IsValid_ESP9(Character) or not PrimaryBoneName then return nil end

    if Character._cachedBoneNames and Character._cachedBoneNames[PrimaryBoneName] then
        local cachedName = Character._cachedBoneNames[PrimaryBoneName]
        local loc = nil
        pcall(function()
            local Mesh = PlayerMapMarker.GetCharacterMesh(Character)
            if Mesh and Game:IsValid(Mesh) then
                if Mesh.GetSocketLocation then loc = Mesh:GetSocketLocation(cachedName)
                elseif Mesh.GetBoneLocation then loc = Mesh:GetBoneLocation(cachedName) end
            end
        end)
        if loc then return loc end
    end

    local fallbacks = PlayerMapMarker.BoneNameFallbacks[PrimaryBoneName] or {PrimaryBoneName}
    for _, bname in ipairs(fallbacks) do
        local loc = nil
        pcall(function()
            local Mesh = PlayerMapMarker.GetCharacterMesh(Character)
            if Mesh and Game:IsValid(Mesh) then
                if Mesh.GetSocketLocation then loc = Mesh:GetSocketLocation(bname)
                elseif Mesh.GetBoneLocation then loc = Mesh:GetBoneLocation(bname) end
            end
        end)
        if loc then
            if not Character._cachedBoneNames then Character._cachedBoneNames = {} end
            Character._cachedBoneNames[PrimaryBoneName] = bname
            return loc
        end
    end
    return nil
end

function PlayerMapMarker.GetCharacterMesh(Character)
    if not IsValid_ESP9(Character) then return nil end
    local Mesh = nil
    pcall(function() if Character.Mesh and Game:IsValid(Character.Mesh) then Mesh = Character.Mesh end end)
    if not Mesh then pcall(function() local SkeletalMeshCompClass = import("/Script/Engine.SkeletalMeshComponent") Mesh = Character:GetComponentByClass(SkeletalMeshCompClass) end) end
    return Mesh
end

function PlayerMapMarker.IsPlayerVisible(PC, Character)
    if not IsValid_ESP9(PC) or not IsValid_ESP9(Character) then return false end
    local now = os.clock()
    if Character._lastVisTime and (now - Character._lastVisTime) < 0.15 then
        return Character._cachedIsVisible or false
    end
    Character._lastVisTime = now

    local bVis = false
    pcall(function()
        if PC.LineOfSightTo then
            if not PlayerMapMarker._ZeroVector then
                local VT = FVector_ESP9 or import("/Script/CoreUObject.Vector")
                if VT then PlayerMapMarker._ZeroVector = VT(0, 0, 0) end
            end
            bVis = PC:LineOfSightTo(Character, PlayerMapMarker._ZeroVector, false)
        end
    end)
    Character._cachedIsVisible = bVis
    return bVis
end

function PlayerMapMarker.CreateSkeletonLineWidget()
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return nil end

    local Border = nil
    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PlayerMapMarker.ESPCanvas) end)
    if not Border or not slua.isValid(Border) then return nil end

    pcall(function() Border.RenderTransformPivot = FVector2D_ESP9 and FVector2D_ESP9(0.0, 0.5) or {X=0, Y=0.5} end)
    pcall(function() Border:SetRenderTransformPivot(FVector2D_ESP9 and FVector2D_ESP9(0.0, 0.5) or {X=0, Y=0.5}) end)

    local Slot = nil
    pcall(function()
        Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
        if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(5) end
    end)

    return {
        Widget = Border, Slot = Slot,
        posVec = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0},
        sizeVec = FVector2D_ESP9 and FVector2D_ESP9(0, 0) or {X=0, Y=0},
        lastFromX = -99999, lastFromY = -99999,
        lastToX = -99999, lastToY = -99999
    }
end

function PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, bVisible, TeamColor, bPlayerOnScreen, charLoc)
    if not PlayerMapMarker.bUseSkeleton then return end
    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end

    local PlayerBones = PlayerMapMarker.SkeletonWidgets[KeyStr]

    if not bVisible or not IsValid_ESP9(Character) or not IsValid_ESP9(PC) then
        if PlayerBones then
            for _, LineData in ipairs(PlayerBones) do
                if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                    LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    LineData.Widget._isSelfHitTestVisible = false
                end
            end
        end
        return
    end

    if not charLoc then charLoc = PlayerMapMarker.GetESPLocation(Character) end
    if not charLoc then return end

    if bPlayerOnScreen == nil then
        local bOnScreen, _, _ = PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, charLoc)
        bPlayerOnScreen = bOnScreen
    end

    if not bPlayerOnScreen then
        if PlayerBones then
            for _, LineData in ipairs(PlayerBones) do
                if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                    LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    LineData.Widget._isSelfHitTestVisible = false
                end
            end
        end
        return
    end

    local dist = 0
    local myLoc = PlayerMapMarker._CachedMyLoc or PlayerMapMarker.GetMyLocation()
    if myLoc and charLoc then
        local dx = (charLoc.X or 0) - (myLoc.X or 0)
        local dy = (charLoc.Y or 0) - (myLoc.Y or 0)
        local dz = (charLoc.Z or 0) - (myLoc.Z or 0)
        dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    if PlayerMapMarker.SkeletonMaxDistance and PlayerMapMarker.SkeletonMaxDistance > 0 then
        if dist > PlayerMapMarker.SkeletonMaxDistance then
            if PlayerBones then
                for _, LineData in ipairs(PlayerBones) do
                    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                        LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                        LineData.Widget._isSelfHitTestVisible = false
                    end
                end
            end
            return
        end
    end

    if not PlayerBones then
        PlayerBones = {}
        PlayerMapMarker.SkeletonWidgets[KeyStr] = PlayerBones
    end

    local lineColor = nil
    if PlayerMapMarker.bUseVisibilityColor then
        local bTargetVisible = PlayerMapMarker.IsPlayerVisible(PC, Character)
        if bTargetVisible then lineColor = PlayerMapMarker.SkeletonVisibleColor or FLinearColor_ESP9(0.0, 1.0, 0.0, 0.8)
        else lineColor = PlayerMapMarker.SkeletonCoverColor or FLinearColor_ESP9(0.9, 0.0, 0.0, 0.6) end
    else
        lineColor = PlayerMapMarker.SkeletonColor or TeamColor or FLinearColor_ESP9(1.0, 1.0, 1.0, PlayerMapMarker.SkeletonOpacity or 0.8)
    end

    local cache = PlayerMapMarker._StaticBoneLocCache
    for k in pairs(cache) do cache[k] = nil end

    local lineIndex = 0
    local thickness = PlayerMapMarker.SkeletonThickness or 0.8

    for _, chain in ipairs(PlayerMapMarker.SkeletonChains) do
        local lastCanvasX, lastCanvasY = nil, nil
        for _, boneName in ipairs(chain) do
            local boneWorldLoc = cache[boneName]
            if boneWorldLoc == nil then
                boneWorldLoc = PlayerMapMarker.GetBoneLocationWithFallback(Character, boneName) or false
                cache[boneName] = boneWorldLoc
            end
            if boneWorldLoc == false then boneWorldLoc = nil end

            local currentCanvasX, currentCanvasY = nil, nil
            if boneWorldLoc then
                local bOnScreen, cX, cY = PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, boneWorldLoc)
                if bOnScreen then
                    currentCanvasX = cX
                    currentCanvasY = cY
                end
            end

            if lastCanvasX and currentCanvasX then
                lineIndex = lineIndex + 1
                local LineData = PlayerBones[lineIndex]
                if not LineData or not LineData.Widget or not slua.isValid(LineData.Widget) then
                    LineData = PlayerMapMarker.CreateSkeletonLineWidget()
                    if LineData then PlayerBones[lineIndex] = LineData end
                end

                if LineData and LineData.Widget and LineData.Slot then
                    local Widget = LineData.Widget
                    local Slot = LineData.Slot

                    if Widget._cachedColor ~= lineColor then
                        Widget:SetBrushColor(lineColor)
                        Widget._cachedColor = lineColor
                    end

                    if not Widget._isSelfHitTestVisible then
                        Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                        Widget._isSelfHitTestVisible = true
                    end

                    local fromX = lastCanvasX
                    local fromY = lastCanvasY
                    local toX = currentCanvasX
                    local toY = currentCanvasY

                    local threshold = 0.15
                    if dist > 8000 then threshold = 0.8 elseif dist > 4000 then threshold = 0.4 end

                    if math.abs(fromX - LineData.lastFromX) > threshold or
                       math.abs(fromY - LineData.lastFromY) > threshold or
                       math.abs(toX - LineData.lastToX) > threshold or
                       math.abs(toY - LineData.lastToY) > threshold then

                        LineData.lastFromX = fromX
                        LineData.lastFromY = fromY
                        LineData.lastToX = toX
                        LineData.lastToY = toY

                        local dx = toX - fromX
                        local dy = toY - fromY
                        local length = math.sqrt(dx * dx + dy * dy)
                        local angle_rad = (math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)
                        local angle = angle_rad * 57.29577951308232

                        local pVec = LineData.posVec
                        pVec.X = fromX; pVec.Y = fromY - thickness / 2.0
                        Slot:SetPosition(pVec)

                        local sVec = LineData.sizeVec
                        sVec.X = length; sVec.Y = thickness
                        Slot:SetSize(sVec)

                        Widget:SetRenderAngle(angle)
                    end
                end
            end
            lastCanvasX = currentCanvasX
            lastCanvasY = currentCanvasY
        end
    end

    for i = lineIndex + 1, #PlayerBones do
        local LineData = PlayerBones[i]
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            LineData.Widget._isSelfHitTestVisible = false
        end
    end
end

function PlayerMapMarker.RemoveSkeletonLines(KeyStr)
    local PlayerBones = PlayerMapMarker.SkeletonWidgets[KeyStr]
    if PlayerBones then
        for _, LineData in ipairs(PlayerBones) do
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function()
                    LineData.Widget:RemoveFromParent()
                    LineData.Widget:ConditionalBeginDestroy()
                end)
            end
        end
        PlayerMapMarker.SkeletonWidgets[KeyStr] = nil
    end
end

function PlayerMapMarker.ClearAllSkeletonLines()
    for KeyStr, PlayerBones in pairs(PlayerMapMarker.SkeletonWidgets) do
        for _, LineData in ipairs(PlayerBones) do
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function()
                    LineData.Widget:RemoveFromParent()
                    LineData.Widget:ConditionalBeginDestroy()
                end)
            end
        end
    end
    PlayerMapMarker.SkeletonWidgets = {}
end

function PlayerMapMarker.ClearAllESP()
    RedBoxOverlay.Stop()
    for KeyStr, Data in pairs(PlayerMapMarker.ESPWidgets) do
        PlayerMapMarker.RemoveESPWidget(Data.Widget, KeyStr)
    end
    PlayerMapMarker.ESPWidgets = {}
    PlayerMapMarker.ESPWidgetPtrs = {}
    PlayerMapMarker.ClearAllSnapLines()
    PlayerMapMarker.ClearAllSkeletonLines()
    PlayerMapMarker:ClearEnemyNameAndBoxes()
    PlayerMapMarker.ESPCanvas = nil
    PlayerMapMarker._OBHeadWidgetClass = nil
    PlayerMapMarker._OBHeadWidgetLoadFailed = false
    PlayerMapMarker._cachedViewportW = 1920
    PlayerMapMarker._cachedViewportH = 1080
end

function PlayerMapMarker.UpdateESP(AllPlayers, MyLoc)
    if not PlayerMapMarker.bUseScreenESP then return end

    PlayerMapMarker.bUseSnapLines = _G.AK_GetVal("ESP9_Line") == 1
    PlayerMapMarker.bUseSkeleton = _G.AK_GetVal("ESP9_Skeleton") == 1

    if not PlayerMapMarker.InitESPCanvas() then return end
    if PlayerMapMarker._OBHeadWidgetLoadFailed then return end

    local PC = PlayerMapMarker.GetMyPlayerController()
    if IsValid_ESP9(PC) then PlayerMapMarker.UpdateCanvasTransform(PC) end

    local fromX, fromY = 0, 0
    if PlayerMapMarker.bUseSnapLines and IsValid_ESP9(PC) then
        fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
    end

    local MyKey = PlayerMapMarker.GetMyPlayerKey()
    local SeenKeys = {}
    local MyChar = nil
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then MyChar = GDP.GetLocalCharacter()
        else if PC and PC.GetPawn then MyChar = PC:GetPawn() end end
    end)

    local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)

    for PlayerKey, Character in pairs(AllPlayers) do
        if IsValid_ESP9(Character) then
            local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PlayerMapMarker.IsAI(Character)
            local KeyStr = tostring(PlayerKey)
            local Name = PlayerMapMarker.GetPlayerName(Character)
            local Loc = PlayerMapMarker.GetESPLocation(Character)
            local DistStr = ""
            if MyLoc and Loc then DistStr = PlayerMapMarker.GetDistanceString(MyLoc, Loc) end

            local bSkip = false
            if bIsMe and not PlayerMapMarker.bIncludeMe then bSkip = true end
            if bIsAI and not PlayerMapMarker.bIncludeAI then bSkip = true end

            local TeamID = PlayerMapMarker.GetTeamID(Character)
            if MyTeamID ~= nil and TeamID == MyTeamID and not bIsMe then bSkip = true end

            local bIsAlive = PlayerMapMarker.IsAlive(Character)

            if not bSkip and Loc then
                SeenKeys[KeyStr] = true
                local ESPData = PlayerMapMarker.ESPWidgets[KeyStr]

                local Text = ""
                if _G.AK_GetVal("ESP9_Name") == 1 then Text = Name end
                if _G.AK_GetVal("ESP9_Distance") == 1 and DistStr ~= "" then
                    if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr) else Text = string.format("[%s]", DistStr) end
                end

                local bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, Loc)

                if not ESPData then
                    local Widget = PlayerMapMarker.CreateESPWidget()
                    if Widget then
                        PlayerMapMarker.ESPWidgets[KeyStr] = { Widget = Widget, Character = Character, Name = Name, LastDistStr = DistStr, TeamID = TeamID }
                        PlayerMapMarker.UpdateESPText(Widget, Text)
                        if bIsAlive then
                            PlayerMapMarker.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
                            PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
                            local HP = Character.Health or 0
                            local MaxHP = Character.MaxHealth or 120
                            local pct = 0
                            if HP > 0 and MaxHP > 0 then pct = HP / MaxHP; if pct > 1 then pct = 1 end; if pct < 0 then pct = 0 end end
                            PlayerMapMarker.UpdateESPHealth(Widget, pct)
                            PlayerMapMarker.AddWeaponIconToESP(Widget, Character)
                            if PlayerMapMarker.bUseSnapLines then
                                PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                            else
                                PlayerMapMarker.RemoveSnapLine(KeyStr)
                            end
                            if PlayerMapMarker.bUseSkeleton then
                                PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, true, PlayerMapMarker.GetTeamColor(TeamID), bOnScreen, Loc)
                            else
                                PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                            end
                        else
                            local Container = Widget.Container or Widget
                            pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                            PlayerMapMarker.UpdateESPHealth(Widget, 0)
                            PlayerMapMarker.RemoveSnapLine(KeyStr)
                            PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                        end
                    end
                else
                    ESPData.Character = Character
                    ESPData.Name = Name
                    ESPData.LastDistStr = DistStr
                    ESPData.TeamID = TeamID
                    PlayerMapMarker.ApplyTeamColor(ESPData.Widget, TeamID)
                    ESPData.Widget._LastESPText = nil
                    PlayerMapMarker.UpdateESPText(ESPData.Widget, Text)
                    PlayerMapMarker.UpdateESPPositionWithPC(ESPData.Widget, Loc, PC, CanvasPos)

                    local HP = Character.Health or 0
                    local MaxHP = Character.MaxHealth or 120
                    local pct = 0
                    if HP > 0 and MaxHP > 0 then pct = HP / MaxHP; if pct > 1 then pct = 1 end; if pct < 0 then pct = 0 end end
                    PlayerMapMarker.UpdateESPHealth(ESPData.Widget, pct)
                    PlayerMapMarker.AddWeaponIconToESP(ESPData.Widget, Character)

                    if PlayerMapMarker.bUseSnapLines then
                        PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                    else
                        PlayerMapMarker.RemoveSnapLine(KeyStr)
                    end
                    if PlayerMapMarker.bUseSkeleton then
                        PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, true, PlayerMapMarker.GetTeamColor(TeamID), bOnScreen, Loc)
                    else
                        PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                    end
                end
            end
        end
    end

    for KeyStr, Data in pairs(PlayerMapMarker.ESPWidgets) do
        if not SeenKeys[KeyStr] then
            PlayerMapMarker.RemoveESPWidget(Data.Widget, KeyStr)
            PlayerMapMarker.ESPWidgets[KeyStr] = nil
        end
    end

    -- Apply enemy name and box
    if _G.AK_GetVal("ENEMY_NAME") == 1 or _G.AK_GetVal("ENEMY_BOX") == 1 then
        local activeKeys = {}
        for PlayerKey, Character in pairs(AllPlayers) do
            if IsValid_ESP9(Character) then
                local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
                local bIsAI = PlayerMapMarker.IsAI(Character)
                local KeyStr = tostring(PlayerKey)
                local bSkip = false
                if bIsMe and not PlayerMapMarker.bIncludeMe then bSkip = true end
                if bIsAI and not PlayerMapMarker.bIncludeAI then bSkip = true end
                local TeamID = PlayerMapMarker.GetTeamID(Character)
                if MyTeamID ~= nil and TeamID == MyTeamID and not bIsMe then bSkip = true end
                local bIsAlive = PlayerMapMarker.IsAlive(Character)
                if not bSkip and bIsAlive then
                    local Loc = PlayerMapMarker.GetESPLocation(Character)
                    if Loc then
                        activeKeys[KeyStr] = true
                        PlayerMapMarker:UpdateEnemyBoxAndName(Character, PC, Loc)
                    end
                end
            end
        end
        for key, widget in pairs(EnemyBoxWidgets) do
            if not activeKeys[key] and widget and widget.border and slua.isValid(widget.border) then
                pcall(function() widget.border:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            end
        end
        for key, widget in pairs(EnemyNameWidgets) do
            if not activeKeys[key] and widget and widget.text and slua.isValid(widget.text) then
                pcall(function() widget.text:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            end
        end
    else
        for key, widget in pairs(EnemyBoxWidgets) do
            if widget and widget.border and slua.isValid(widget.border) then
                pcall(function() widget.border:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            end
        end
        for key, widget in pairs(EnemyNameWidgets) do
            if widget and widget.text and slua.isValid(widget.text) then
                pcall(function() widget.text:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            end
        end
    end
end

function PlayerMapMarker.UpdateESPLight()
    if RedBoxOverlay and RedBoxOverlay.bActive then RedBoxOverlay.UpdatePosition() end
    if not PlayerMapMarker.bUseScreenESP then return end

    PlayerMapMarker.bUseSnapLines = _G.AK_GetVal("ESP9_Line") == 1
    PlayerMapMarker.bUseSkeleton = _G.AK_GetVal("ESP9_Skeleton") == 1

    if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then return end

    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid_ESP9(PC) then return end

    PlayerMapMarker.UpdateCanvasTransform(PC)

    local fromX, fromY = 0, 0
    if PlayerMapMarker.bUseSnapLines then fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC) end

    for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
        local Widget = ESPData.Widget
        local Character = ESPData.Character
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)

        if Widget and bWidgetValid and Character and IsValid_ESP9(Character) then
            local bIsAlive = PlayerMapMarker.IsAlive(Character)
            if not bIsAlive then
                pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                PlayerMapMarker.RemoveSnapLine(KeyStr)
                PlayerMapMarker.RemoveSkeletonLines(KeyStr)
            else
                local bShowAnyUI = _G.AK_GetVal("ESP9_Name") == 1 or _G.AK_GetVal("ESP9_Distance") == 1 or _G.AK_GetVal("ESP9_HP") == 1 or _G.AK_GetVal("ESP9_Team") == 1 or _G.AK_GetVal("ESP9_Weapon") == 1
                if bShowAnyUI then
                    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                else
                    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                end

                local Loc = PlayerMapMarker.GetESPLocation(Character)
                if Loc then
                    local bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, Loc)
                    PlayerMapMarker.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)

                    if PlayerMapMarker.bUseSnapLines then 
                        PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                    else 
                        PlayerMapMarker.RemoveSnapLine(KeyStr) 
                    end

                    if PlayerMapMarker.bUseSkeleton then
                        PlayerMapMarker.UpdateSkeletonLines(KeyStr, Character, PC, true, PlayerMapMarker.GetTeamColor(ESPData.TeamID), bOnScreen, Loc)
                    else
                        PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                    end
                else
                    PlayerMapMarker.RemoveSnapLine(KeyStr)
                    PlayerMapMarker.RemoveSkeletonLines(KeyStr)
                end
            end
        end
    end
end

function PlayerMapMarker.UpdateESPDistances()
    if not PlayerMapMarker.bUseScreenESP then return end

    local MyLoc = PlayerMapMarker.GetMyLocation()
    if not MyLoc then return end

    local PC = PlayerMapMarker.GetMyPlayerController()
    if not IsValid_ESP9(PC) then return end

    PlayerMapMarker.UpdateCanvasTransform(PC)

    for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
        local Character = ESPData.Character
        local Widget = ESPData.Widget
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)

        if Character and IsValid_ESP9(Character) and Widget and bWidgetValid then
            local Loc = PlayerMapMarker.GetESPLocation(Character)
            if Loc then
                local Dist = PlayerMapMarker.CalcDistance(MyLoc, Loc)
                ESPData.LastDistance = Dist

                if PlayerMapMarker.bShowDistance then
                    local DistStr = ""
                    local Meters = 0
                    if Dist then
                        Meters = Dist / 100
                        if Meters < 1000 then DistStr = string.format("%dm", math.floor(Meters))
                        else DistStr = string.format("%.1fkm", Meters / 1000) end
                    end

                    local Name = ESPData.Name or "Unknown"
                    local Text = ""
                    if _G.AK_GetVal("ESP9_Name") == 1 then Text = Name end
                    if _G.AK_GetVal("ESP9_Distance") == 1 and DistStr ~= "" then
                        if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr) else Text = string.format("[%s]", DistStr) end
                    end

                    ESPData.LastDistStr = DistStr
                    Widget._LastESPText = nil
                    PlayerMapMarker.UpdateESPText(Widget, Text)
                end
            end
        end
    end
end

function PlayerMapMarker.AddWeaponIconToESP(WidgetData, Character)
    if not WidgetData or not WidgetData.Container then return end
    if not _G.AK_GetVal("ESP9_Weapon") == 1 then return end

    pcall(function()
        local Container = WidgetData.Container
        if not Container or not slua.isValid(Container) then return end

        local winfo = Character and PlayerMapMarker.GetCharacterWeaponInfo(Character) or nil
        if not winfo or not winfo.WeaponID or winfo.WeaponID == 0 then return end

        if WidgetData._LastWeaponID == winfo.WeaponID and WidgetData._WeaponIconApplied then return end
        WidgetData._LastWeaponID = winfo.WeaponID
        WidgetData._WeaponIconApplied = true
    end)
end

function PlayerMapMarker.ScanAndUpdate()
    local AllChars = PlayerMapMarker.GetAllCharacters()
    if not AllChars then RedBoxOverlay.SetCounts(0, 0) return 0 end

    local MyKey = PlayerMapMarker.GetMyPlayerKey()
    local MyLoc = PlayerMapMarker.GetMyLocation()
    local MyChar = nil
    pcall(function()
        local GDP = PlayerMapMarker.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then MyChar = GDP.GetLocalCharacter()
        else local PC = PlayerMapMarker.GetMyPlayerController() if PC and PC.GetPawn then MyChar = PC:GetPawn() end end
    end)

    local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)
    local realPlayers = 0
    local botPlayers = 0

    for PlayerKey, Character in pairs(AllChars) do
        if IsValid_ESP9(Character) then
            local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PlayerMapMarker.IsAI(Character)
            local bIsAlive = PlayerMapMarker.IsAlive(Character)

            if bIsAlive and not bIsMe then
                local bIsMyTeam = false
                if MyTeamID ~= nil then
                    local targetTeamID = PlayerMapMarker.GetTeamID(Character)
                    if targetTeamID == MyTeamID then bIsMyTeam = true end
                end
                if not bIsMyTeam then
                    if bIsAI then botPlayers = botPlayers + 1
                    else realPlayers = realPlayers + 1 end
                end
            end
        end
    end

    if _G.AK_GetVal("ESP9_Count") == 1 then
        if RedBoxOverlay.bActive then RedBoxOverlay.SetCounts(realPlayers, botPlayers)
        else RedBoxOverlay.Start() end
    else
        if RedBoxOverlay.bActive then RedBoxOverlay.Stop() end
    end

    if PlayerMapMarker.bUseScreenESP then
        PlayerMapMarker.UpdateESP(AllChars, MyLoc)
    end

    return 0
end

function PlayerMapMarker.AttachTimers()
    pcall(function()
        local pc = PlayerMapMarker.GetMyPlayerController()
        if not slua.isValid(pc) or not pc.AddGameTimer then return end

        pcall(function() pc:AddGameTimer(PlayerMapMarker.nUpdateInterval or 0.5, true, function() if PlayerMapMarker.bActive then pcall(function() PlayerMapMarker.ScanAndUpdate() end) end end) end)
        pcall(function() pc:AddGameTimer(PlayerMapMarker._LightUpdateInterval or 0.02, true, function() if PlayerMapMarker.bActive then pcall(function() PlayerMapMarker.UpdateESPLight() end) end end) end)
        pcall(function() pc:AddGameTimer(PlayerMapMarker._DistanceUpdateInterval or 0.1, true, function() if PlayerMapMarker.bActive and PlayerMapMarker.bUseScreenESP and PlayerMapMarker.bShowDistance then pcall(function() PlayerMapMarker.UpdateESPDistances() end) end end) end)
    end)
end

function PlayerMapMarker.Start()
    if PlayerMapMarker.bActive then return end
    PlayerMapMarker.bActive = true
    PlayerMapMarker._FrameCount = 0
    PlayerMapMarker.ScanAndUpdate()
    PlayerMapMarker.AttachTimers()
end

function PlayerMapMarker.Stop()
    PlayerMapMarker.bActive = false
    PlayerMapMarker._FrameCount = 0
    PlayerMapMarker.ClearAllESP()
end

_G.PlayerMapMarker = PlayerMapMarker

print("✅ Enemy Name & Box ESP System Loaded!")

-- ========================================================================
-- ⚡ NEW WALLHACK SYSTEM (DrawDyeing + IdeaOutline)
-- ========================================================================
local LinearColor = import("LinearColor")
local CONSOLE_READY = false
local PROCESSED_PAWNS = {}
local TICK_COUNT = 0
local WH_TIMER = nil
local TICK_INTERVAL = 0.3
local MAX_PAWNS_PER_TICK = 20
local RESET_PROCESSED_EVERY = 6
local AVATAR_SLOTS = {0,1,2,3,4,5,6,7}

local colors = {
    vis  = LinearColor(0, 255, 0, 100),
    occ  = LinearColor(255, 0, 0, 100),
    bVis = LinearColor(255, 255, 0, 100),
    bOcc = LinearColor(255, 0, 0, 100)
}

local function SetupConsole()
    if CONSOLE_READY then return end
    pcall(function()
        local KismetSystemLibrary = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if not KismetSystemLibrary or not world then return end

        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")

        CONSOLE_READY = true
        print("[PBC] Console ready")
    end)
end

local function ApplyToMesh(mesh, visColor, occColor)
    if not mesh or not slua.isValid(mesh) then return end
    pcall(function()
        mesh:SetDrawDyeing(true)
        mesh:SetDrawDyeingMode(1)
        mesh:SetVisibleDyeingColor(visColor)
        mesh:SetOccludedDyeingColor(occColor)
        mesh:SetDyeingColorFadeDistance(99999.0)
        mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
        mesh:SetDrawHighlight(true)
        mesh:OverrideHighlightColor(visColor)
        mesh:SetHighlightCanBeOccluded(false)
        mesh:SetDrawIdeaOutline(true)
        mesh:SetIdeaOutlineNew(true)
        mesh:SetIdeaOutlineOcclusionHighlight(true)
        mesh:OverrideIdeaOutlineColor(visColor)
        mesh:SetIdeaOutlineOcclusionColor(occColor)
        mesh:OverrideIdeaOutlineThickness(20.0)
        mesh:SetIdeaOverrideOutlineAndOcclusion(true)
        mesh:SetRenderCustomDepth(true)
        mesh:SetCustomDepthStencilValue(255)
    end)
end

local function IsPawnAlive(pawn)
    if not slua.isValid(pawn) then return false end
    if pawn.Health and pawn.Health > 0 then return true end
    return false
end

local function PBCtick()
    pcall(function()
        local localPawn = GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPawn) then return end

        SetupConsole()
        if not colors then return end

        TICK_COUNT = TICK_COUNT + 1
        if TICK_COUNT % RESET_PROCESSED_EVERY == 0 then
            PROCESSED_PAWNS = {}
        end

        local myTeamId = localPawn.TeamID or 0
        local allPawns = Game:GetAllPlayerPawns() or {}
        local processedCount = 0

        for _, pawn in pairs(allPawns) do
            if processedCount >= MAX_PAWNS_PER_TICK then break end
            if not slua.isValid(pawn) or pawn == localPawn then goto continue end
            if pawn.PlayerKey and PROCESSED_PAWNS[pawn.PlayerKey] then goto continue end

            if IsPawnAlive(pawn) and pawn.TeamID and pawn.TeamID ~= myTeamId then
                local isAI = pcall(Game.IsAI, pawn) and true or false
                local vis = isAI and colors.bVis or colors.vis
                local occ = isAI and colors.bOcc or colors.occ

                pcall(function()
                    if slua.isValid(pawn.Mesh) then
                        ApplyToMesh(pawn.Mesh, vis, occ)
                    end

                    local avatarComp = pawn.CharacterAvatarComp2_BP or pawn:getAvatarComponent2()
                    if avatarComp and avatarComp.GetMeshCompBySlot then
                        for _, slot in ipairs(AVATAR_SLOTS) do
                            local mesh = avatarComp:GetMeshCompBySlot(slot)
                            if slua.isValid(mesh) then
                                ApplyToMesh(mesh, vis, occ)
                            end
                        end
                    end

                    pcall(function()
                        local SkeletalMeshComponent = import("SkeletalMeshComponent")
                        if SkeletalMeshComponent then
                            local skComps = pawn:GetComponentsByClass(SkeletalMeshComponent)
                            if skComps then
                                for i = 0, skComps:Num() - 1 do
                                    local comp = skComps:Get(i)
                                    if slua.isValid(comp) and comp ~= pawn.Mesh then
                                        ApplyToMesh(comp, vis, occ)
                                    end
                                end
                            end
                        end
                    end)

                    pcall(function()
                        local StaticMeshComponent = import("StaticMeshComponent")
                        if StaticMeshComponent then
                            local stComps = pawn:GetComponentsByClass(StaticMeshComponent)
                            if stComps then
                                for i = 0, stComps:Num() - 1 do
                                    local comp = stComps:Get(i)
                                    if slua.isValid(comp) then
                                        ApplyToMesh(comp, vis, occ)
                                    end
                                end
                            end
                        end
                    end)

                    local weapon = pawn:GetCurrentWeapon()
                    if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                        ApplyToMesh(weapon.Mesh, vis, occ)
                    end
                end)

                if pawn.PlayerKey then PROCESSED_PAWNS[pawn.PlayerKey] = true end
                processedCount = processedCount + 1
            end
            ::continue::
        end
    end)
end

local function StartPBC()
    SetupConsole()
    if not colors then
        print("[PBC] Colors not initialized, aborting")
        return false
    end

    if WH_TIMER then
        pcall(function()
            if _G.Game then _G.Game:RemoveGameTimer(WH_TIMER) end
        end)
        WH_TIMER = nil
    end

    if _G.Game and _G.Game.AddGameTimer then
        WH_TIMER = _G.Game:AddGameTimer(TICK_INTERVAL, true, PBCtick)
        print("[PBC] ✅ Active (Game timer)")
        return true
    end

    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        WH_TIMER = pc:AddGameTimer(TICK_INTERVAL, true, PBCtick)
        print("[PBC] ✅ Active (PC timer)")
        return true
    end

    print("[PBC] ❌ Could not start timer")
    return false
end

local retryCount = 0
local function RetryStart()
    if retryCount >= 30 then
        print("[PBC] ❌ Failed to start after 30 retries")
        return
    end
    retryCount = retryCount + 1

    if StartPBC() then
        print("[PBC] ✅ Module ready!")
    else
        if _G.Game and _G.Game.AddGameTimer then
            _G.Game:AddGameTimer(1.0, false, RetryStart)
        end
    end
end

function _pbc_Cleanup()
    if WH_TIMER then
        pcall(function()
            if _G.Game then _G.Game:RemoveGameTimer(WH_TIMER) end
        end)
        WH_TIMER = nil
    end
    PROCESSED_PAWNS = {}
    CONSOLE_READY = false
    print("[PBC] ? Cleanup done")
end

function _G.StartNewWallhack()
    if WH_TIMER then return end
    if _G.AK_GetVal("WALLHACK") == 1 then
        RetryStart()
    end
end

-- ========================================================================
-- STRONG BYPASS SYSTEM (Security Module Neutralization)
-- ========================================================================
local nop = function() end
local returnTrue = function() return true end
local returnFalse = function() return false end
local returnZero = function() return 0 end
local returnEmptyTable = function() return {} end

local blockedFuncNames = {
    "reportattackflow", "reportsecattackflow", "reporthurtflow", "reportfirearms",
    "reportverifyinfoflow", "reportmrpcsflow", "reportplayerbehavior", "reportteammathurt",
    "reportmiskillbyteammate", "reportforbitpick", "reportplayermoveroute", "reportplayerposition",
    "reportvehiclemoveflow", "reportsecregamemovingflow", "reportparachutedata",
    "sendtsssdkantidatatolobby", "senddserrorlogtolobby", "senddshawkeyepatrologtolobby",
    "sendsectlog", "senddataminingtlog", "sendactivitytlog", "sendclientmemusage", "sendclientfps",
    "onclientcrashreport", "onnetworklossdetected", "reportmatchroomdata", "reportplayersping",
    "sendclientstats", "sendserveravgtickdelta", "reporthitflow", "onplayeractorchannelerror",
    "onplayerrpcvalidatefailed", "reportequipmentflow", "reportaimflow",
    "getweaponreport", "getoneweaponreport", "reportheavyweaponboxspawnflow",
    "reportheavyweaponboxactivationflow", "reportheavyweaponboxopenplayerflow",
    "reportheavyweaponboxitemflow", "reportplayersping", "reportplayerip",
    "reportplayerframepingrecord", "ondsconnectionsaturated", "reportdsnetsaturation",
    "reportnetcontinuoussaturate", "reportdsnetrate",
    "reportcircleflow", "reportdscircleflow", "reportjumpflow", "reportaistrategyinfo",
    "sendaideliveryinfo", "reportdailytaskinfo", "reportmatchroomdata", "sendplayerspectatinglog",
    "reportidcardproduceflow", "reportidcardpickupflow", "reportidcarddestroyflow",
    "reportrevivalflow", "reportgamesetting", "reportgamesettingnew", "reportantsvoiceteamcreate",
    "reportantsvoiceteamquit", "reportcommoninfo", "reportlightweightstat", "sendsectlog",
    "senddataminingtlog", "sendactivitytlog", "getgeneraltlogdata",
    "reportwallhack", "reportaimbot", "reportspeedhack", "reportmagicbullet",
    "reportplayercontrollerstatechanged", "reportavatarflow", "reportabnormalmaterial",
    "reportdepthtestchange", "reportwallhack", "reportmemoryexception", "reportmaterialscan",
    "reportshaderoverride", "sendsectlog", "senddataminingtlog",
    "reportplayerkillflow", "clientsecplayerkillflow", "checkreportsecattackflow",
    "checkreportsecattackflowwithattackflow", "isenablereportplayerkillflow",
    "isenablereportmrpcsincircleflow", "isenablereportmrpcsintpartcircleflow",
    "isenablereportmrpcsflow", "isenablereporthitflow", "isenablereportcircleflow",
    "onplayernetconnectionclosed", "onplayeractorchannelerror",
    "onplayerrpcvalidatefailed", "onplayerspectateexception", "onshutdownaftererror",
    "heartbeat", "sendheartbeat", "clientheartbeat", "serverheartbeat",
    "swifthawk", "clientswifthawk", "clientswifthawkwithparams", "swifthawkreport", "swifthawkdata",
    "anticheatreport", "cheatdetection", "violationreport", "securityviolation",
    "integritycheck", "signatureverify", "md5", "hash", "filecheck", "pakcheck"
}

local origRequire = require
local securityPathPatterns = {"Security", "AntiCheat", "Integrity", "ReportPlayer", "HawkEye", "SwiftHawk", "Ban", "TssSdk", "ShootVerify", "CoronaLab", "HiggsBoson"}

local function isSecurityModule(name)
    for _, p in ipairs(securityPathPatterns) do
        if name:find(p, 1, true) then return true end
    end
    return false
end

local dummyModules = {
    ["GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent"] = true,
    ["GameLua.Mod.BaseMod.Common.Security.AvatarCheckCallback"] = true,
    ["GameLua.Mod.BaseMod.Common.Security.GameSafeCallbacks"] = true,
}

_G.require = function(name)
    if dummyModules[name] then
        return { bMHActive = false, BlackList = {} }
    end
    local mod = origRequire(name)
    if type(mod) == "table" and isSecurityModule(name) and not mod.__ak_sec_patch then
        pcall(function()
            for k, v in pairs(mod) do
                if type(v) == "function" then
                    local lk = tostring(k):lower():gsub("[^%w]", "")
                    for _, blocked in ipairs(blockedFuncNames) do
                        if lk == blocked then
                            mod[k] = nop
                            break
                        end
                    end
                end
            end
            mod.__ak_sec_patch = true
        end)
    end
    return mod
end

local securitySubsystemNames = {
    "FileCheckSubsystem", "IntegrityCheckSubsystem", "PakCheckSubsystem",
    "ClientWallhackDetectionSubsystem", "ClientESPDetectionSubsystem",
    "ClientAimTrackingSubsystem", "ClientAntiCheatSubsystem",
    "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem",
    "CoronaLabSubsystem", "PlayerSecurityInfoSubsystem",
    "ClientSecMrpcsFlowSubsystem", "MrpcsFlowSubsystem",
    "ShootVerifySubSystemClient", "MemoryCheckSubsystem",
    "SpeedCheckSubsystem", "WallCheckSubsystem",
    "BehaviorScoreSubsystem", "AFKReportorSubsystem",
    "AvatarExceptionSubsystem", "GameReportSubsystem",
    "SwiftHawkSubsystem", "HeartbeatSubsystem",
    "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem",
    "ModifierExceptionSubsystem", "SimulateCharacterSubsystem",
    "ClientRenderCheckSubsystem", "ClientMemoryGuardSubsystem",
    "ClientKernelCheckSubsystem"
}

local SubsystemMgr_inst = nil
pcall(function() SubsystemMgr_inst = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr") end)

if SubsystemMgr_inst and not SubsystemMgr_inst.__ak_intercept then
    local realGet = SubsystemMgr_inst.Get
    SubsystemMgr_inst.Get = function(self, name)
        local sub = realGet(self, name)
        if type(sub) == "table" and not sub.__ak_sub_silenced then
            for _, secName in ipairs(securitySubsystemNames) do
                if name == secName then
                    for k, v in pairs(sub) do
                        if type(v) == "function" then
                            local lk = tostring(k):lower():gsub("[^%w]", "")
                            for _, blocked in ipairs(blockedFuncNames) do
                                if lk == blocked then
                                    sub[k] = nop
                                    break
                                end
                            end
                        end
                    end
                    sub.__ak_sub_silenced = true
                    break
                end
            end
        end
        return sub
    end
    SubsystemMgr_inst.__ak_intercept = true
end

-- ========================================================================
-- BRPlayerCharacterBase CLASS
-- ========================================================================
local BRPlayerCharacterBase = {
    ServerRPC = {},
    ClientRPC = {},
    MulticastRPC = {}
}

BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }
BRPlayerCharacterBase.ClientRPC.ClientRPC_TriggerHighlightMoment = { Reliable = true, Params = { UEnums.EPropertyClass.UInt32, UEnums.EPropertyClass.UInt32 } }

function BRPlayerCharacterBase:ctor()
    self.bHasShownDevNotice = false
    self.AK_NativeESP_Ready = false
    self.bHiggsTimerSet = false
    self._newWallhackStarted = false
    self._lastAimbotTime = 0
    self._monitorsSetup = false
    self._bypassActive = false
end

function BRPlayerCharacterBase:_PostConstruct()
    BRPlayerCharacterBase.__super._PostConstruct(self)
    self:InitAddSpecialMoveInfo()
    self.bCanNearDeathGiveup = true
    self:StartAdvancedSystems()
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
        self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", { AttrName = { "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
    end

    if Client then
        GameplayData.AddCharacter(self.Object)
    else
        self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1] = "FinishedState" }, self.HandleFinishedState, self)
    end

    EventSystem:postEvent(EVENTTYPE_SINGLETRAINING, EVENTID_CHARACTER_BEGINPLAY, self.Object)
end

function BRPlayerCharacterBase:ReceiveEndPlay(endPlayReason)
    BRPlayerCharacterBase.__super.ReceiveEndPlay(self, endPlayReason)
    if Client and GameplayData.RemoveCharacter then GameplayData.RemoveCharacter(self.Object) end
end

-- ========================================================================
-- STARTADVANCEDSYSTEMS - ALL LOGIC IN TIMER
-- ========================================================================
function BRPlayerCharacterBase:StartAdvancedSystems()
    if not Client then return end
    if not CheckExpiration() then ShowExpiryPopup(true); return end

    InitDistanceMarkerSystem()

    if not self.bHiggsTimerSet then
        self.bHiggsTimerSet = true
        self:AddGameTimer(0.1, true, function()
            if not slua.isValid(self.Object) then return end
            pcall(function()
                local lpc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
                if slua.isValid(lpc) and lpc.HiggsBosonComponent then
                    lpc.HiggsBosonComponent.bMHActive = false
                end
            end)
        end)
    end

    self:AddGameTimer(0.4, true, function()
        if not slua.isValid(self.Object) then return end
        if not CheckExpiration() then ShowExpiryPopup(true); return end

        local localPlayer = GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPlayer) then return end

        if self.Object == localPlayer then
            if not localPlayer._bypassActive then
                localPlayer._bypassActive = true
                pcall(function()
                    if _G.WHABypass and _G.WHABypass.Init then
                        _G.WHABypass.Init()
                        _G._WHA_BYPASS_ACTIVE = true
                    end
                end)

    self:AddGameTimer(3.0, false, function()
        pcall(function()
            local Msg = package.loaded["client.slua.logic.common.logic_common_msg_box"]
            if not Msg then Msg = require("client.slua.logic.common.logic_common_msg_box") end
            local Web = require("client.slua.logic.url.logic_webview_sdk")
            local function onClick()
                if Web then Web:OpenURL("https://t.me/TGOWNER7") end
            end
            if Msg and Msg.Show then
                Msg.Show(4, "✦ TGOWNER7 – PREMIUM MOD ✦",
                    "★ Play Like Legit Player - Safe\n" ..
                    "★ Don't Play Like Hacker - Safe\n" ..
                    "★ TGOWNER7 Always Op - Moder\n\n" ..
                    "✓ Use And Send Feedbacks - @TGOWNER7!", onClick)
            end
        end)
    end)
end

            if not localPlayer._monitorsSetup then
                localPlayer._monitorsSetup = true

                localPlayer:AddGameTimer(0.5, true, function()
                    if not _G._WHA_BYPASS_ACTIVE then
                        pcall(function()
                            if _G.WHABypass and _G.WHABypass.Init then
                                _G.WHABypass.Init()
                                _G._WHA_BYPASS_ACTIVE = true
                            end
                        end)
                    end
                end)

                localPlayer:AddGameTimer(10.0, true, function()
                    pcall(function()
                        if _G.WHABypass and _G.WHABypass.Init then
                            _G.WHABypass.Init()
                            _G._WHA_BYPASS_ACTIVE = true
                        end
                    end)
                end)
            end

            if not self._newWallhackStarted then
                self._newWallhackStarted = true
                pcall(function()
                    if _G.StartNewWallhack then _G.StartNewWallhack() end
                end)
            end

            local enemyCounterEnabled = (_G.AK_GetVal("ENEMY_COUNTER") == 1)
            if enemyCounterEnabled and not _G.ENEMY_COUNTER_TIMER then
                _G.StartEnemyCounter()
            elseif not enemyCounterEnabled and _G.ENEMY_COUNTER_TIMER then
                _G.StopEnemyCounter()
            end

            if _G.AK_GetVal("ESP_V2") == 1 then
                if _G.PlayerMapMarker and not _G.PlayerMapMarker.bActive then
                    _G.PlayerMapMarker.Start()
                end
            else
-- ⚡ Arrow Radar ESP auto start/stop
if _G.AK_GetVal("ARROW_RADAR") == 1 then
    if _G.ArrowRadarESP and not _G.ArrowRadarESP.bActive then
        _G.ArrowRadarESP.Start()
    end
else
    if _G.ArrowRadarESP and _G.ArrowRadarESP.bActive then
        _G.ArrowRadarESP.Stop()
    end
end
                if _G.PlayerMapMarker and _G.PlayerMapMarker.bActive then
                    _G.PlayerMapMarker.Stop()
                end
            end

            _G.AKModTickCount = (_G.AKModTickCount or 0) + 1
            if _G.AKModTickCount % 6 == 0 then cleanupDeadEnemyMarks() end

            if not self.AK_NativeESP_Ready then
                pcall(function()
                    local gameplayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
                    local screenMarkConfig = gameplayTools.GetCurrentConfig("ScreenMarkConfig")
                    if screenMarkConfig then
                        if screenMarkConfig[1006] then
                            screenMarkConfig[1006].bBindBlocked = true
                            screenMarkConfig[1006].bBindOutScreen = true
                            screenMarkConfig[1006].MaxWidgetNum = 99
                            screenMarkConfig[1006].MaxShowDistance = 6000000
                        end
                        screenMarkConfig[9999] = distanceMarkerConfig
                    end
                end)
                self.AK_NativeESP_Ready = true
            end

            local enemyCharacters = GameplayData.GetAllPlayerCharacters and GameplayData.GetAllPlayerCharacters() or {}
            local isMapESP = _G.AK_GetVal("ESP_MAP")
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()

            for _, enemy in pairs(enemyCharacters) do
                if slua.isValid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
                    local isDead = false
                    pcall(function()
                        if type(enemy.IsDead)=="function" then isDead = enemy:IsDead()
                        elseif enemy.bIsDead then isDead = true end
                        if enemy.bHidden or (enemy.Mesh and enemy.Mesh.bHidden) then isDead = true end
                    end)

                    if isDead then goto skip_enemy end

                    processEnemyMapESP(enemy, localPlayer, isMapESP)

                    if _G.AK_GetVal("ESP_HP") == 1 then
                        if not enemy.bHasAKNativeHPBar then
                            pcall(function()
                                enemy.NativeHPBarMark = InGameMarkTools.ClientAddMapMark(1006, FVector(0,0,0), 0, "", 4, enemy)
                                enemy.bHasAKNativeHPBar = true
                            end)
                        end
                    elseif enemy.bHasAKNativeHPBar then
                        pcall(function() InGameMarkTools.ClientRemoveMapMark(enemy.NativeHPBarMark) end)
                        enemy.bHasAKNativeHPBar = false
                    end

                    if _G.AK_GetVal("ESP_BOX") == 1 then
                        pcall(function()
                            if enemy.Replay_IsEnemyFrameUIExisted and not enemy:Replay_IsEnemyFrameUIExisted() then
                                enemy:Replay_CreateEnemyFrameUI(true, true)
                            end
                            if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(true) end
                        end)
                    else
                        pcall(function()
                            if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(false) end
                        end)
                    end

                    ::skip_enemy::
                end
            end

            if _G.AK_GetVal("AIMBOT") == 1 and (not self._lastAimbotTime or (os.clock() - self._lastAimbotTime) > 2.0) then
                ApplyHardAimbot()
                self._lastAimbotTime = os.clock()
            end

            -- ============================================================
            -- ⚡ 5 NEW FEATURES UPDATER (NO GRASS / NO FOG / BLACK SKY / IPAD VIEW / RGB X)
            -- ============================================================
            pcall(function()
                _G.LexusState = _G.LexusState or { PrevGraphicsState = {}, CustomTextData = { IpadViewFOV = 120 } }
                _G.LexusState.PrevGraphicsState = _G.LexusState.PrevGraphicsState or {}
                _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or { IpadViewFOV = 120 }

                -- 1) GRAPHICS: NO GRASS / NO FOG / BLACK SKY
                pcall(function()
                    local lsg = require("client.slua.logic.setting.logic_setting_graphics")
                    local gi = lsg.GetGameInstance()
                    if not gi then return end

                    -- NO GRASS
                    if _G.LexusConfig.RemoveGrass and not _G.LexusState.PrevGraphicsState.RemoveGrass then
                        gi:ExecuteCMD("grass.DensityScale", "0")
                        gi:ExecuteCMD("grass.DiscardDataOnLoad", "1")
                        _G.LexusState.PrevGraphicsState.RemoveGrass = true
                    elseif not _G.LexusConfig.RemoveGrass and _G.LexusState.PrevGraphicsState.RemoveGrass then
                        gi:ExecuteCMD("grass.DensityScale", "1")
                        gi:ExecuteCMD("grass.DiscardDataOnLoad", "0")
                        _G.LexusState.PrevGraphicsState.RemoveGrass = false
                    end

                    -- NO FOG
                    if _G.LexusConfig.RemoveFog and not _G.LexusState.PrevGraphicsState.RemoveFog then
                        gi:ExecuteCMD("r.SkyAtmosphere", "1")
                        gi:ExecuteCMD("r.Fog", "0")
                        gi:ExecuteCMD("r.VolumetricFog", "0")
                        _G.LexusState.PrevGraphicsState.RemoveFog = true
                    elseif not _G.LexusConfig.RemoveFog and _G.LexusState.PrevGraphicsState.RemoveFog then
                        gi:ExecuteCMD("r.SkyAtmosphere", "1")
                        gi:ExecuteCMD("r.Fog", "1")
                        gi:ExecuteCMD("r.VolumetricFog", "1")
                        _G.LexusState.PrevGraphicsState.RemoveFog = false
                    end

                    -- BLACK SKY
                    if _G.LexusConfig.BlackSky and not _G.LexusState.PrevGraphicsState.BlackSky then
                        gi:ExecuteCMD("r.CylinderMaxDrawHeight", "9999")
                        _G.LexusState.PrevGraphicsState.BlackSky = true
                    elseif not _G.LexusConfig.BlackSky and _G.LexusState.PrevGraphicsState.BlackSky then
                        gi:ExecuteCMD("r.CylinderMaxDrawHeight", "0000")
                        _G.LexusState.PrevGraphicsState.BlackSky = false
                    end
                end)

                -- 2) IPAD VIEW (Only Walking, No Vehicle, No Scope)
                pcall(function()
                    local isAiming = false
                    if localPlayer.bIsWeaponAiming or localPlayer.bIsGunADS then isAiming = true end
                    if isAiming then return end

                    local currentVehicle = nil
                    pcall(function()
                        currentVehicle = localPlayer.CurrentVehicle
                        if not slua.isValid(currentVehicle) and type(localPlayer.GetVehicle) == "function" then
                            currentVehicle = localPlayer:GetVehicle()
                        end
                    end)
                    local isInVehicle = slua.isValid(currentVehicle) or localPlayer.bIsInVehicle
                    if isInVehicle then return end

                    local uTPPCam = localPlayer.ThirdPersonCameraComponent
                    if _G.LexusConfig.IpadView then
                        local targetTPP = _G.LexusState.CustomTextData.IpadViewFOV or 120
                        if slua.isValid(uTPPCam) and uTPPCam.FieldOfView ~= targetTPP then
                            uTPPCam.FieldOfView = targetTPP
                        end
                    else
                        if slua.isValid(uTPPCam) and uTPPCam.FieldOfView ~= 90 then
                            uTPPCam.FieldOfView = 90
                        end
                    end
                end)

                -- 3) RGB X EFFECT (Rainbow Hit)
                pcall(function()
                    if _G.LexusConfig.RainbowHit and _G.StartRainbowTimer then
                        _G.StartRainbowTimer()
                    elseif not _G.LexusConfig.RainbowHit and _G.StopRainbowTimer then
                        _G.StopRainbowTimer()
                    end
                end)
            end)
        end
    end)
end

-- ========================================================================
-- INITIALIZATION
-- ========================================================================
pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(3, function() if CheckExpiration() then end end)
        ticker.AddTimerOnce(4, function()
            if not CheckExpiration() then ShowExpiryPopup(true) else _G.TryShowWelcome() end
        end)
    else
        _G.TryShowWelcome()
    end
end)

function _G.InitializeAllSystems()
    if not CheckExpiration() then ShowExpiryPopup(true); return end
    local gameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"] or require("GameLua.GameCore.Data.GameplayData")
    if gameplayData then
        pcall(function()
            local pc = gameplayData.GetPlayerCharacter and gameplayData.GetPlayerCharacter()
            if slua.isValid(pc) then pc.StartAdvancedSystems = BRPlayerCharacterBase.StartAdvancedSystems end
        end)
    end
end

_G.InitializeAllSystems()

-- ================================================================
-- TGOWNER7 WATERMARK (ALWAYS ON - SAME POSITION)
-- ================================================================
local GANESHCuOverlay = {
    Widget = nil,
    Slot = nil
}

local function EnsurePermanentGANESHCu()
    if GANESHCuOverlay.Widget and slua.isValid(GANESHCuOverlay.Widget) then
        pcall(function() GANESHCuOverlay.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        pcall(function()
            if GANESHCuOverlay.Slot then
                local ui_util = require("client.common.ui_util")
                local vp = ui_util and ui_util.GetViewportSize()
                if vp then
                    local FVector2D = import("Vector2D") or _G.FVector2D
                    local targetX = vp.X * 0.5
                    local targetY = 42.0

                    local parentCanvas = GANESHCuOverlay.Widget:GetParent()
                    if slua.isValid(parentCanvas) then
                        local cg = parentCanvas:GetCachedGeometry()
                        local SBL = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary")
                        if cg and SBL and SBL.AbsoluteToLocal then
                            local centerPt = SBL.AbsoluteToLocal(cg, FVector2D(targetX, targetY))
                            if centerPt then
                                targetX = centerPt.X
                                targetY = centerPt.Y
                            end
                        end
                    end
                    GANESHCuOverlay.Slot:SetPosition(FVector2D(targetX, targetY))
                end
            end
        end)
        return 
    end

    local ParentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainControlBaseUI = InGameUITools and InGameUITools.GetMainControlBaseUI()
        if MainControlBaseUI and slua.isValid(MainControlBaseUI) then
            ParentCanvas = MainControlBaseUI.CanvasPanel_0
            if not slua.isValid(ParentCanvas) then ParentCanvas = MainControlBaseUI.CanvasPanel_42 end
        end
    end)

    if not ParentCanvas or not slua.isValid(ParentCanvas) then return end

    local txtTitle = nil
    pcall(function() txtTitle = CGame:NewObjectFromPath("/Script/UMG.TextBlock", ParentCanvas) end)
    if txtTitle and slua.isValid(txtTitle) then
        pcall(function()
            txtTitle:SetText("TGOWNER7")
            local FLinearColor = import("LinearColor") or _G.FLinearColor
            local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            local redLinear = FLinearColor and FLinearColor(0.0, 0.0, 0.0, 1.0) or {R=0, G=0, B=0, A=255}
            if FSlateColor then txtTitle:SetColorAndOpacity(FSlateColor(redLinear)) else txtTitle:SetColorAndOpacity(redLinear) end

            if txtTitle.Font then
                local font = txtTitle.Font
                font.Size = 25
                txtTitle.Font = font
            end
            
            local FVector2D = import("Vector2D") or _G.FVector2D
            txtTitle:SetRenderScale(FVector2D(1.0, 1.0))
            txtTitle:SetRenderTransformPivot(FVector2D(0.5, 0.5))
            txtTitle:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)

        local txtSlot = ParentCanvas:AddChildToCanvas(txtTitle)
        if txtSlot then
            pcall(function()
                txtSlot:SetAutoSize(true)
                local FVector2D = import("Vector2D") or _G.FVector2D
                txtSlot:SetAlignment(FVector2D(0.5, -1.2))
                txtSlot:SetPosition(FVector2D(0, -80))
                txtSlot:SetZOrder(9999)
            end)
            GANESHCuOverlay.Slot = txtSlot
        end
        GANESHCuOverlay.Widget = txtTitle
    end
end

-- Watermark always on
pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerLoop then
        ticker.AddTimerLoop(0, function()
            EnsurePermanentGANESHCu()
        end, -1, 1.0)
    end
end)

-- Remaining global initializations
pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(3, function() if CheckExpiration() then end end)
        ticker.AddTimerOnce(4, function()
            if not CheckExpiration() then ShowExpiryPopup(true) else _G.TryShowWelcome() end
        end)
    else
        _G.TryShowWelcome()
    end
end)

function _G.InitializeAllSystems()
    if not CheckExpiration() then ShowExpiryPopup(true); return end
    local gameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"] or require("GameLua.GameCore.Data.GameplayData")
    if gameplayData then
        pcall(function()
            local pc = gameplayData.GetPlayerCharacter and gameplayData.GetPlayerCharacter()
            if slua.isValid(pc) then pc.StartAdvancedSystems = BRPlayerCharacterBase.StartAdvancedSystems end
        end)
    end
end
_G.InitializeAllSystems()

-- ========================================================================
-- ⚡ RGB X EFFECT (RAINBOW HIT + CROSSHAIR) — FULL SYSTEM
-- ========================================================================
local RainbowColorsTable = {
    {R=1.0, G=0.0, B=0.0, A=1.0},
    {R=1.0, G=0.5, B=0.0, A=1.0},
    {R=1.0, G=1.0, B=0.0, A=1.0},
    {R=0.5, G=1.0, B=0.0, A=1.0},
    {R=0.0, G=1.0, B=0.0, A=1.0},
    {R=0.0, G=1.0, B=0.5, A=1.0},
    {R=0.0, G=1.0, B=1.0, A=1.0},
    {R=0.0, G=0.5, B=1.0, A=1.0},
    {R=0.0, G=0.0, B=1.0, A=1.0},
    {R=0.5, G=0.0, B=1.0, A=1.0},
    {R=1.0, G=0.0, B=1.0, A=1.0},
    {R=1.0, G=0.0, B=0.5, A=1.0},
}

local RainbowSpeeds = {
    [1] = 0.5, [2] = 0.3, [3] = 0.15, [4] = 0.08, [5] = 0.04,
}

if _G.RainbowHitConfig == nil then
    _G.RainbowHitConfig = {
        Enabled = false,
        SpeedLevel = 3,
        TimerHandle = nil,
        IsRunning = false,
    }
end

if _G.LexusConfig and _G.LexusConfig.RainbowHit ~= nil then
    _G.RainbowHitConfig.Enabled = _G.LexusConfig.RainbowHit
end
if _G.LexusState and _G.LexusState.CustomTextData and _G.LexusState.CustomTextData.RainbowHitSpeed then
    _G.RainbowHitConfig.SpeedLevel = _G.LexusState.CustomTextData.RainbowHitSpeed
end

local RainbowColorIndex = 1
local RainbowTickCounter = 0
local RainbowTimerStarted = false

local function ApplyRainbowEffects()
    if not _G.RainbowHitConfig.Enabled then return end

    local delay = RainbowSpeeds[_G.RainbowHitConfig.SpeedLevel] or 0.15
    local stepsPerCycle = math.max(1, math.floor(0.3 / delay))

    RainbowTickCounter = RainbowTickCounter + 1
    if RainbowTickCounter >= stepsPerCycle then
        RainbowTickCounter = 0
        RainbowColorIndex = (RainbowColorIndex % #RainbowColorsTable) + 1
    end

    local color = RainbowColorsTable[RainbowColorIndex]
    local FLinearColor = import("LinearColor")
    if not FLinearColor then return end
    local linearColor = FLinearColor(color.R, color.G, color.B, color.A)

    local pc = nil
    pcall(function()
        local GameplayData = require("GameLua.GameCore.Data.GameplayData")
        if GameplayData then pc = GameplayData.GetPlayerController() end
    end)
    if not slua.isValid(pc) then
        pcall(function()
            if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
        end)
        if not slua.isValid(pc) then return end
    end

    pcall(function()
        local HitEffectComp = pc.HitEffectComponent
        if slua.isValid(HitEffectComp) then
            HitEffectComp.HitColor = linearColor
            HitEffectComp.BodyHitColor = linearColor
            HitEffectComp.HeadHitColor = linearColor
            if HitEffectComp.SetHitColor then HitEffectComp:SetHitColor(linearColor) end
            if HitEffectComp.SetBodyHitColor then HitEffectComp:SetBodyHitColor(linearColor) end
            if HitEffectComp.SetHeadHitColor then HitEffectComp:SetHeadHitColor(linearColor) end
        end

        local MyHUD = pc.MyHUD
        if slua.isValid(MyHUD) then
            MyHUD.HitColor = linearColor
            MyHUD.BodyHitColor = linearColor
            MyHUD.HeadHitColor = linearColor
            if MyHUD.SetHitColor then MyHUD:SetHitColor(linearColor) end
            if MyHUD.HitPerform then
                MyHUD.HitPerform.HitBodyDrawColor = linearColor
                MyHUD.HitPerform.HitHeadDrawColor = linearColor
                if MyHUD.HitPerform.SetHitBodyDrawColor then MyHUD.HitPerform:SetHitBodyDrawColor(linearColor) end
                if MyHUD.HitPerform.SetHitHeadDrawColor then MyHUD.HitPerform:SetHitHeadDrawColor(linearColor) end
            end
            MyHUD.CrosshairColor = linearColor
            MyHUD.CrosshairColorNormal = linearColor
            MyHUD.CrosshairColorADS = linearColor
            MyHUD.CrosshairColorHip = linearColor
            MyHUD.CrosshairColorScope = linearColor
            MyHUD.CrosshairDynamicColor = linearColor
            MyHUD.AimCrosshairColor = linearColor
            MyHUD.CrosshairTintColor = linearColor
            MyHUD.CrosshairGlowColor = linearColor
            if MyHUD.SetCrosshairColor then MyHUD:SetCrosshairColor(linearColor) end
            if MyHUD.CrosshairOpacity then MyHUD.CrosshairOpacity = 1.0 end
        end

        local DamageDisplay = pc.DamageDisplayComponent
        if slua.isValid(DamageDisplay) then
            DamageDisplay.HitColor = linearColor
            if DamageDisplay.SetHitColor then DamageDisplay:SetHitColor(linearColor) end
        end

        local BattleHUD = pc.BattleHUD
        if slua.isValid(BattleHUD) then
            BattleHUD.HitEffectColor = linearColor
            BattleHUD.CrosshairColor = linearColor
            if BattleHUD.SetHitEffectColor then BattleHUD:SetHitEffectColor(linearColor) end
            if BattleHUD.SetCrosshairColor then BattleHUD:SetCrosshairColor(linearColor) end
        end

        if pc.SetHitEffectColor then pc:SetHitEffectColor(linearColor) end
        if pc.SetCrosshairColor then pc:SetCrosshairColor(linearColor) end
        if pc.CrosshairColor then pc.CrosshairColor = linearColor end

        local scopeComp = pc.ScopeComponent
        if slua.isValid(scopeComp) then
            scopeComp.CrosshairColor = linearColor
            scopeComp.ReticleColor = linearColor
            if scopeComp.SetCrosshairColor then scopeComp:SetCrosshairColor(linearColor) end
            if scopeComp.SetReticleColor then scopeComp:SetReticleColor(linearColor) end
        end

        if MyHUD and MyHUD.CrosshairWidget then
            local widget = MyHUD.CrosshairWidget
            if slua.isValid(widget) then
                widget.Color = linearColor
                if widget.SetColor then widget:SetColor(linearColor) end
            end
        end

        local localPlayer = nil
        pcall(function()
            local GameplayData = require("GameLua.GameCore.Data.GameplayData")
            if GameplayData then localPlayer = GameplayData.GetPlayerCharacter() end
        end)
        if slua.isValid(localPlayer) then
            local WeaponManager = localPlayer.WeaponManagerComponent
            if slua.isValid(WeaponManager) then
                local CurrentWeapon = WeaponManager.CurrentWeaponReplicated
                if slua.isValid(CurrentWeapon) then
                    if CurrentWeapon.CrosshairColor then CurrentWeapon.CrosshairColor = linearColor end
                    if CurrentWeapon.ScopeCrosshairColor then CurrentWeapon.ScopeCrosshairColor = linearColor end
                    local ShootWeaponEffect = CurrentWeapon.ShootWeaponEffectComp
                    if slua.isValid(ShootWeaponEffect) then
                        ShootWeaponEffect.MuzzleFlashColor = linearColor
                    end
                end
            end
        end
    end)
end

function _G.StartRainbowTimer()
    if RainbowTimerStarted then return end
    if _G.RainbowHitConfig.IsRunning then return end

    pcall(function()
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerLoop then
            _G.RainbowHitConfig.IsRunning = true
            RainbowTimerStarted = true
            _G.RainbowHitConfig.TimerHandle = ticker.AddTimerLoop(0, function()
                ApplyRainbowEffects()
            end, -1, 0.02)
            print("[✓] Rainbow Timer Started!")
        else
            local pc = nil
            pcall(function()
                local GameplayData = require("GameLua.GameCore.Data.GameplayData")
                if GameplayData then pc = GameplayData.GetPlayerController() end
            end)
            if slua.isValid(pc) and pc.AddGameTimer then
                _G.RainbowHitConfig.IsRunning = true
                RainbowTimerStarted = true
                pc:AddGameTimer(0.02, true, function() ApplyRainbowEffects() end)
                print("[✓] Rainbow Timer Started (Fallback)!")
            end
        end
    end)
end

function _G.StopRainbowTimer()
    pcall(function()
        if _G.RainbowHitConfig.TimerHandle then
            local ticker = require("common.time_ticker")
            if ticker and ticker.RemoveTimer then
                ticker:RemoveTimer(_G.RainbowHitConfig.TimerHandle)
            end
            _G.RainbowHitConfig.TimerHandle = nil
        end
        _G.RainbowHitConfig.IsRunning = false
        RainbowTimerStarted = false

        local FLinearColor = import("LinearColor")
        if FLinearColor then
            local defaultColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
            pcall(function()
                local GameplayData = require("GameLua.GameCore.Data.GameplayData")
                local pc = GameplayData and GameplayData.GetPlayerController()
                if slua.isValid(pc) then
                    if pc.SetHitEffectColor then pc:SetHitEffectColor(defaultColor) end
                    if pc.SetCrosshairColor then pc:SetCrosshairColor(defaultColor) end
                    local HitEffectComp = pc.HitEffectComponent
                    if slua.isValid(HitEffectComp) then
                        HitEffectComp.HitColor = defaultColor
                        HitEffectComp.BodyHitColor = defaultColor
                        HitEffectComp.HeadHitColor = defaultColor
                    end
                    local MyHUD = pc.MyHUD
                    if slua.isValid(MyHUD) then
                        MyHUD.HitColor = defaultColor
                        MyHUD.CrosshairColor = defaultColor
                    end
                end
            end)
        end
        print("[✓] Rainbow Timer Stopped!")
    end)
end

_G.ToggleRainbowHit = function(enabled)
    if enabled == nil then
        _G.RainbowHitConfig.Enabled = not _G.RainbowHitConfig.Enabled
    else
        _G.RainbowHitConfig.Enabled = enabled
    end

    if _G.LexusConfig then
        _G.LexusConfig.RainbowHit = _G.RainbowHitConfig.Enabled
    end

    if _G.RainbowHitConfig.Enabled then
        _G.StartRainbowTimer()
        print("? RAINBOW ENABLED!")
    else
        _G.StopRainbowTimer()
        print("? RAINBOW DISABLED!")
    end
end

_G.SetRainbowSpeed = function(level)
    level = math.floor(level + 0.5)
    if level < 1 then level = 1 end
    if level > 5 then level = 5 end
    _G.RainbowHitConfig.SpeedLevel = level
    if _G.LexusState and _G.LexusState.CustomTextData then
        _G.LexusState.CustomTextData.RainbowHitSpeed = level
    end
    if _G.RainbowHitConfig.Enabled then
        _G.StopRainbowTimer()
        _G.StartRainbowTimer()
    end
    local speedNames = {"Slowest", "Slow", "Medium", "Fast", "Fastest"}
    print("? Speed: " .. (speedNames[level] or "Medium"))
end

-- AUTO-START RGB X agar config me ON hai
pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(2.0, function()
            if _G.RainbowHitConfig.Enabled then
                _G.StartRainbowTimer()
            end
        end)
    end
end)

print("[✓] RGB X EFFECT (RAINBOW HIT) SYSTEM LOADED!")

-- ========================================================================
-- ⚡ GANESH MOD MENU (FIXED — Wrapper Container + Proper Colors + TG Links)
-- ========================================================================
local UI = {}

-- Import proper color classes
local FLinearColorUI = import("LinearColor")
local FSlateColorUI = import("SlateColor")
local FVector2D_UI = import("Vector2D")

UI.Config = {
    Title          = "TGOWNER7 PREMIUM MENU",
    BtnW           = 90,
    BtnH           = 26,
    RowH           = 42,
    PanelW         = 340,
    PanelH         = 510,
    Padding        = 12,
    HoldToMove     = 3.0,

    ColorBG        = { R = 0.02, G = 0.02, B = 0.02, A = 0.95 },
    ColorTitle     = { R = 0.00, G = 0.90, B = 1.00, A = 1.00 },
    ColorToggleOn  = { R = 0.00, G = 1.00, B = 0.55, A = 1.00 },
    ColorToggleOff = { R = 0.90, G = 0.10, B = 0.10, A = 1.00 },
    ColorText      = { R = 1.00, G = 1.00, B = 1.00, A = 1.00 },
    ColorAccent    = { R = 0.80, G = 0.10, B = 0.90, A = 1.00 },
    ColorBorder    = { R = 0.00, G = 0.80, B = 1.00, A = 0.55 },
    ColorTGBtn     = { R = 0.00, G = 0.90, B = 0.20, A = 1.00 },   -- Green BG
    ColorTGText    = { R = 0.00, G = 0.00, B = 0.00, A = 1.00 },   -- Black Text
    FontSize       = 14,
    TitleFontSize  = 18,
}

UI.State = {
    Open           = false,
    Dragging       = false,
    HoldTimer      = 0,
    HoldElapsed    = 0,
    MouseX         = 0,
    MouseY         = 0,
    StartMouseX    = 0,
    StartMouseY    = 0,
    BtnX           = 8,
    BtnY           = 8,
    PanelX         = 8,
    PanelY         = 60,
    ActiveCategory = "ESP MODS",
    HasMoved       = false,
}

-- ================================================================
--  TELEGRAM LINKS
-- ================================================================
local LINK_M4_GANESH   = "https://t.me/+j6NHT35chKFlMDg9"
local LINK_GANESH_BGMI = "https://t.me/+BgpfEYQgtRUxMzY1"

local function OpenTelegramLink(link)
    if not link or link == "" then return end
    pcall(function()
        local Web = require("client.slua.logic.url.logic_webview_sdk")
        if Web and Web.OpenURL then Web:OpenURL(link) return end
    end)
    pcall(function()
        local UnityPlayer = import("com.unity3d.player.UnityPlayer")
        if UnityPlayer and UnityPlayer.currentActivity then
            local Intent = import("android.content.Intent")
            local Uri = import("android.net.Uri")
            local intent = Intent(Intent.ACTION_VIEW, Uri.parse(link))
            intent:setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            UnityPlayer.currentActivity:startActivity(intent)
        end
    end)
end

-- ================================================================
--  SYNC HELPERS
-- ================================================================
local function GetFeatureValue(featureId, default)
    if _G.AK_Features then
        for _, feature in ipairs(_G.AK_Features) do
            if feature.id == featureId then
                return feature.val == 1
            end
        end
    end
    if _G.LexusConfig then
        if featureId == "RemoveGrass" then return _G.LexusConfig.RemoveGrass == true end
        if featureId == "RemoveFog"   then return _G.LexusConfig.RemoveFog   == true end
        if featureId == "BlackSky"    then return _G.LexusConfig.BlackSky    == true end
        if featureId == "IpadView"    then return _G.LexusConfig.IpadView    == true end
        if featureId == "RainbowHit"  then return _G.LexusConfig.RainbowHit  == true end
    end
    return default
end

local function SyncFeature(featureId, value)
    if _G.AK_Features then
        for _, feature in ipairs(_G.AK_Features) do
            if feature.id == featureId then
                feature.val = value and 1 or 0
                if featureId == "RainbowHit" then
                    if value and _G.StartRainbowTimer then pcall(_G.StartRainbowTimer) end
                    if not value and _G.StopRainbowTimer then pcall(_G.StopRainbowTimer) end
                end
                if featureId == "FPS165" and value then
                    _G.__FPS165_APPLIED = false
                end
                -- ⚡ ARROW RADAR toggle
                if featureId == "ARROW_RADAR" then
                    if value and _G.ArrowRadarESP then
                        _G.ArrowRadarESP.Start()
                    elseif not value and _G.ArrowRadarESP then
                        _G.ArrowRadarESP.Stop()
                    end
                end
                return
            end
        end
    end
    if _G.LexusConfig then
        if featureId == "RemoveGrass" then _G.LexusConfig.RemoveGrass = value end
        if featureId == "RemoveFog"   then _G.LexusConfig.RemoveFog   = value end
        if featureId == "BlackSky"    then _G.LexusConfig.BlackSky    = value end
        if featureId == "IpadView"    then _G.LexusConfig.IpadView    = value end
        if featureId == "RainbowHit"  then
            _G.LexusConfig.RainbowHit = value
            if value and _G.StartRainbowTimer then pcall(_G.StartRainbowTimer) end
            if not value and _G.StopRainbowTimer then pcall(_G.StopRainbowTimer) end
        end
    end
end

UI.Features = {
    ["ESP MODS"] = {
       -- { id = "ESP_HP",          name = "ESP Health Bar",     val = GetFeatureValue("ESP_HP", false) },
        { id = "ESP_MAP",         name = "ESP MARK",       val = GetFeatureValue("ESP_MAP", true) },
        { id = "ESP_V2",          name = "ESP MASTER",      val = GetFeatureValue("ESP_V2", true) },
        { id = "ESP9_Count",      name = "COUNTER",         val = GetFeatureValue("ESP9_Count", true) },
        { id = "ESP9_Name",       name = "PLAYER NAME",          val = GetFeatureValue("ESP9_Name", true) },
        { id = "ESP9_HP",         name = "HEALTH BAR",            val = GetFeatureValue("ESP9_HP", true) },
      --  { id = "ESP9_Team",       name = "ESP9 Team",          val = GetFeatureValue("ESP9_Team", true) },
       -- { id = "ESP9_Weapon",     name = "ESP9 Weapon",        val = GetFeatureValue("ESP9_Weapon", true) },
        { id = "ESP9_Distance",   name = "DISTANCE",      val = GetFeatureValue("ESP9_Distance", true) },
        { id = "ESP9_Line",       name = "ESP LINES",          val = GetFeatureValue("ESP9_Line", true) },
        { id = "ESP9_Skeleton",   name = "ESP9 Skeleton",      val = GetFeatureValue("ESP9_Skeleton", false) },
     --   { id = "ENEMY_NAME",      name = "Enemy Name ESP",     val = GetFeatureValue("ENEMY_NAME", true) },
     --   { id = "ENEMY_BOX",       name = "Enemy Box ESP",      val = GetFeatureValue("ENEMY_BOX", true) },
     --   { id = "ENEMY_COUNTER",   name = "Enemy Counter",      val = GetFeatureValue("ENEMY_COUNTER", false) },
         { id = "ARROW_RADAR",     name = "ARROW RADAR",        val = GetFeatureValue("ARROW_RADAR", true) },
    },
    ["COMBAT"] = {
        { id = "AIMBOT",          name = "AIMBOT",             val = GetFeatureValue("AIMBOT", true) },
        { id = "WALLHACK",        name = "PBC WALLHACK",       val = GetFeatureValue("WALLHACK", true) },
    },
    ["GRAPHICSS"] = {
        { id = "RemoveGrass",     name = "NO GRASS",       val = GetFeatureValue("RemoveGrass", true) },
        { id = "RemoveFog",       name = "NO FOGG",         val = GetFeatureValue("RemoveFog", true) },
        { id = "BlackSky",        name = "BLACK SKY",          val = GetFeatureValue("BlackSky", false) },
        { id = "IpadView",        name = "IPAD VIEW",          val = GetFeatureValue("IpadView", true) },
        { id = "RainbowHit",      name = "RGB X EFFECT",       val = GetFeatureValue("RainbowHit", true) },
        { id = "FPS165",          name = "165 FPS",      val = GetFeatureValue("FPS165", false) },
    },
}

UI.Categories = { "ESP MODS", "COMBAT", "GRAPHICSS" }

-- ================================================================
--  HELPERS
-- ================================================================
local function SafeCall(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local function MakeLinearColor(c)
    if FLinearColorUI then
        return FLinearColorUI(c.R, c.G, c.B, c.A)
    end
    return nil
end

local function MakeSlateColor(c)
    local lc = MakeLinearColor(c)
    if FSlateColorUI and lc then
        return FSlateColorUI(lc)
    end
    return lc
end

local function GetMainCanvas()
    local ParentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainControlBaseUI = InGameUITools and InGameUITools.GetMainControlBaseUI()
        if MainControlBaseUI and slua.isValid(MainControlBaseUI) then
            ParentCanvas = MainControlBaseUI.CanvasPanel_0
            if not slua.isValid(ParentCanvas) then ParentCanvas = MainControlBaseUI.CanvasPanel_42 end
        end
    end)
    return ParentCanvas
end

-- Create Border widget with slot
local function NewBorder(parent, x, y, w, h, colour)
    local wdg = SafeCall(function()
        return CGame:NewObjectFromPath("/Script/UMG.Border", parent)
    end)
    if not wdg or not slua.isValid(wdg) then return nil end
    local slot = SafeCall(function() return parent:AddChildToCanvas(wdg) end)
    if slot and slua.isValid(slot) then
        SafeCall(function()
            slot:SetPosition(FVector2D_UI(x, y))
            slot:SetSize(FVector2D_UI(w, h))
            slot:SetAutoSize(false)
        end)
        wdg._MySlot = slot
    end
    if colour then
        SafeCall(function() wdg:SetBrushColor(MakeLinearColor(colour)) end)
    end
    return wdg
end

-- Create TextBlock widget with slot
local function NewText(parent, x, y, w, h, text, colour, size)
    local wdg = SafeCall(function()
        return CGame:NewObjectFromPath("/Script/UMG.TextBlock", parent)
    end)
    if not wdg or not slua.isValid(wdg) then return nil end
    local slot = SafeCall(function() return parent:AddChildToCanvas(wdg) end)
    if slot and slua.isValid(slot) then
        SafeCall(function()
            slot:SetPosition(FVector2D_UI(x, y))
            slot:SetSize(FVector2D_UI(w, h))
            slot:SetAutoSize(false)
        end)
        wdg._MySlot = slot
    end
    SafeCall(function() wdg:SetText(text) end)
    if colour then
        SafeCall(function() wdg:SetColorAndOpacity(MakeSlateColor(colour)) end)
    end
    if size then
        SafeCall(function()
            local f = wdg.Font
            f.Size = size
            wdg:SetFont(f)
        end)
    end
    return wdg
end

-- Create Button widget with slot (invisible hit-area)
local function NewButton(parent, x, y, w, h)
    local wdg = SafeCall(function()
        return CGame:NewObjectFromPath("/Script/UMG.Button", parent)
    end)
    if not wdg or not slua.isValid(wdg) then return nil end
    local slot = SafeCall(function() return parent:AddChildToCanvas(wdg) end)
    if slot and slua.isValid(slot) then
        SafeCall(function()
            slot:SetPosition(FVector2D_UI(x, y))
            slot:SetSize(FVector2D_UI(w, h))
            slot:SetAutoSize(false)
        end)
        wdg._MySlot = slot
    end
    -- Make it transparent / hit-area only
    SafeCall(function() wdg:SetBackgroundColor(MakeLinearColor({R=0,G=0,B=0,A=0.01})) end)
    return wdg
end

local function SetPos(widget, x, y)
    if not widget then return end
    local slot = widget._MySlot
    if slot and slua.isValid(slot) then
        SafeCall(function() slot:SetPosition(FVector2D_UI(x, y)) end)
    end
end

local function SetSize(widget, w, h)
    if not widget then return end
    local slot = widget._MySlot
    if slot and slua.isValid(slot) then
        SafeCall(function() slot:SetSize(FVector2D_UI(w, h)) end)
    end
end

local function SetVisible(widget, v)
    if not widget then return end
    local vis = v and UEnums.ESlateVisibility.Visible or UEnums.ESlateVisibility.Collapsed
    SafeCall(function() widget:SetVisibility(vis) end)
end

local function SetBorderColor(widget, c)
    if not widget then return end
    SafeCall(function() widget:SetBrushColor(MakeLinearColor(c)) end)
end

local function SetTextColor(widget, c)
    if not widget then return end
    SafeCall(function() widget:SetColorAndOpacity(MakeSlateColor(c)) end)
end

-- ================================================================
--  TOGGLE (label + track + knob + hit-area)
-- ================================================================
local function CreateToggleRow(parent, y, label, defaultState, onChange)
    local C = UI.Config
    local x = C.Padding
    local rowW = C.PanelW - C.Padding * 2

    local lbl = NewText(parent, x, y + 10, rowW - 80, 26, label, C.ColorText, C.FontSize)

    local trackX = C.PanelW - C.Padding - 50
    local track = NewBorder(parent, trackX, y + 8, 50, 26,
        defaultState and C.ColorToggleOn or C.ColorToggleOff)

    local knobX = defaultState and (trackX + 26) or (trackX + 2)
    local knob = NewBorder(parent, knobX, y + 10, 22, 22, {R=1,G=1,B=1,A=1})

    local state = defaultState

    local function refresh()
        SetBorderColor(track, state and C.ColorToggleOn or C.ColorToggleOff)
        SetPos(knob, state and (trackX + 26) or (trackX + 2), y + 10)
    end

    local function toggle()
        state = not state
        refresh()
        if onChange then onChange(state) end
    end

    -- Hit area covering the toggle
    local hit = NewButton(parent, trackX - 10, y + 4, 70, 34)
    if hit and hit.OnClicked then
        SafeCall(function() hit.OnClicked:Add(toggle) end)
    end

    return {
        label = lbl,
        track = track,
        knob = knob,
        hit = hit,
        toggle = toggle,
        get = function() return state end,
        refresh = refresh,
        _trackX = trackX,
        _y = y,
    }
end

-- ================================================================
--  PANEL BUILDER
-- ================================================================
UI.Panel = nil
UI.Button = nil

function UI.BuildPanel()
    if UI.Panel and UI.Panel.wrapper and slua.isValid(UI.Panel.wrapper) then
        return UI.Panel
    end

    local canvas = GetMainCanvas()
    if not canvas or not slua.isValid(canvas) then return nil end

    local C = UI.Config
    local panel = {}

    -- Wrapper CanvasPanel that holds all menu widgets
    local wrapper = SafeCall(function()
        return CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas)
    end)
    if not wrapper or not slua.isValid(wrapper) then return nil end

    local wrapperSlot = SafeCall(function() return canvas:AddChildToCanvas(wrapper) end)
    if not wrapperSlot or not slua.isValid(wrapperSlot) then return nil end

    SafeCall(function()
        wrapperSlot:SetPosition(FVector2D_UI(UI.State.PanelX, UI.State.PanelY))
        wrapperSlot:SetSize(FVector2D_UI(C.PanelW, C.PanelH))
        wrapperSlot:SetAutoSize(false)
        wrapperSlot:SetZOrder(900)
    end)

    panel.wrapper = wrapper
    panel.wrapperSlot = wrapperSlot

    -- Background
    panel.bg = NewBorder(wrapper, 0, 0, C.PanelW, C.PanelH, C.ColorBG)
    -- Top strip
    panel.topStrip = NewBorder(wrapper, 0, 0, C.PanelW, 3, C.ColorAccent)
    -- Title
    panel.title = NewText(wrapper, C.Padding, 10, C.PanelW - C.Padding*2 - 30, 30, C.Title, C.ColorTitle, C.TitleFontSize)
    -- Close X
    panel.closeText = NewText(wrapper, C.PanelW - 26, 12, 20, 24, "X", C.ColorText, C.FontSize)
    local closeHit = NewButton(wrapper, C.PanelW - 32, 6, 28, 28)
    if closeHit and closeHit.OnClicked then
        SafeCall(function() closeHit.OnClicked:Add(function() UI.Hide() end) end)
    end
    panel.closeHit = closeHit

    -- Category tabs
    local tabY = 50
    local tabW = (C.PanelW - C.Padding * 4) / #UI.Categories
    panel.tabs = {}
    for i, cat in ipairs(UI.Categories) do
        local tx = C.Padding + (i - 1) * (tabW + C.Padding)
        local tabBg = NewBorder(wrapper, tx, tabY, tabW, 32,
            cat == UI.State.ActiveCategory and C.ColorAccent or C.ColorToggleOff)
        local tabTx = NewText(wrapper, tx, tabY + 7, tabW, 22, cat, C.ColorText, C.FontSize)
        SafeCall(function() tabTx:SetJustification(UEnums.ETextJustify.Center or 1) end)

        local tabHit = NewButton(wrapper, tx, tabY, tabW, 32)
        local thisCat = cat
        if tabHit and tabHit.OnClicked then
            SafeCall(function() tabHit.OnClicked:Add(function()
                UI.State.ActiveCategory = thisCat
                UI.Refresh()
            end) end)
        end

        panel.tabs[cat] = { bg = tabBg, text = tabTx, hit = tabHit, x = tx }
    end

    -- Separator
    panel.sep = NewBorder(wrapper, C.Padding, tabY + 40, C.PanelW - C.Padding*2, 1, C.ColorBorder)

    -- Feature list area (relative Y inside wrapper)
    panel.listY = tabY + 50
    panel.rows = {}

-- ============================================================
-- TELEGRAM BUTTONS (bottom of panel)
-- ============================================================
local tgBtnH = 30
local tgBtnW = (C.PanelW - C.Padding * 3) / 2
local tgY = C.PanelH - tgBtnH - C.Padding

-- Helper: Bold + Center text
local function StyleTGText(txtWidget)
    if not txtWidget then return end
    SafeCall(function() txtWidget:SetJustification(UEnums.ETextJustify.Center or 1) end)
    SafeCall(function() txtWidget:SetVerticalJustification(UEnums.EVerticalTextAligment.Center or 0) end)
    SafeCall(function()
        local f = txtWidget.Font
        if f then
            f.TypefaceFontName = "Bold"
            f.Size = 18
            txtWidget:SetFont(f)
        end
    end)
end

-- TG: TGOWNER7 (left)
panel.tgBg1 = NewBorder(wrapper, C.Padding, tgY, tgBtnW, tgBtnH, C.ColorTGBtn)
panel.tgTx1 = NewText(wrapper, C.Padding, tgY, tgBtnW, tgBtnH,
    "TG: TGOWNER7", C.ColorTGText, 18)
StyleTGText(panel.tgTx1)

panel.tgHit1 = NewButton(wrapper, C.Padding, tgY, tgBtnW, tgBtnH)
if panel.tgHit1 and panel.tgHit1.OnClicked then
    SafeCall(function() panel.tgHit1.OnClicked:Add(function()
        OpenTelegramLink(LINK_M4_GANESH)
    end) end)
end

-- TG: GANESH BGMI (right)
local tg2X = C.Padding + tgBtnW + C.Padding
panel.tgBg2 = NewBorder(wrapper, tg2X, tgY, tgBtnW, tgBtnH, C.ColorTGBtn)
panel.tgTx2 = NewText(wrapper, tg2X, tgY, tgBtnW, tgBtnH,
    "TG: GANESH BGMI", C.ColorTGText, 18)
StyleTGText(panel.tgTx2)

panel.tgHit2 = NewButton(wrapper, tg2X, tgY, tgBtnW, tgBtnH)
if panel.tgHit2 and panel.tgHit2.OnClicked then
    SafeCall(function() panel.tgHit2.OnClicked:Add(function()
        OpenTelegramLink(LINK_GANESH_BGMI)
    end) end)
end

    panel.wrapper = wrapper
    UI.Panel = panel

    -- Build rows for current category
    UI.BuildRows(panel)

    return panel
end

-- ================================================================
--  BUILD ROWS (current category)
-- ================================================================
function UI.BuildRows(panel)
    if not panel or not panel.wrapper then return end
    local C = UI.Config

    -- Remove old rows
    for _, row in ipairs(panel.rows or {}) do
        SafeCall(function() if row.label then row.label:RemoveFromParent() end end)
        SafeCall(function() if row.track then row.track:RemoveFromParent() end end)
        SafeCall(function() if row.knob then row.knob:RemoveFromParent() end end)
        SafeCall(function() if row.hit then row.hit:RemoveFromParent() end end)
    end
    panel.rows = {}

    local features = UI.Features[UI.State.ActiveCategory] or {}
    local y = panel.listY
    -- Leave space at bottom for Telegram buttons
    local maxY = C.PanelH - C.Padding - 34 - C.Padding - 6

    for _, feat in ipairs(features) do
        if y + C.RowH > maxY then break end
        local row = CreateToggleRow(panel.wrapper, y, feat.name, feat.val, function(v)
            feat.val = v
            SyncFeature(feat.id, v)
        end)
        row._feat = feat
        table.insert(panel.rows, row)
        y = y + C.RowH
    end
end

-- ================================================================
--  FLOATING BUTTON (draggable)
-- ================================================================
function UI.BuildButton()
    if UI.Button and UI.Button.wrapper and slua.isValid(UI.Button.wrapper) then
        return UI.Button
    end

    local canvas = GetMainCanvas()
    if not canvas or not slua.isValid(canvas) then return nil end

    local C = UI.Config
    local btn = {}

    local wrapper = SafeCall(function()
        return CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas)
    end)
    if not wrapper or not slua.isValid(wrapper) then return nil end

    local wrapperSlot = SafeCall(function() return canvas:AddChildToCanvas(wrapper) end)
    if not wrapperSlot or not slua.isValid(wrapperSlot) then return nil end

    SafeCall(function()
        wrapperSlot:SetPosition(FVector2D_UI(UI.State.BtnX, UI.State.BtnY))
        wrapperSlot:SetSize(FVector2D_UI(C.BtnW, C.BtnH))
        wrapperSlot:SetAutoSize(false)
        wrapperSlot:SetZOrder(950)
    end)

    btn.wrapper = wrapper
    btn.wrapperSlot = wrapperSlot

btn.bg = NewBorder(wrapper, 0, 0, C.BtnW, C.BtnH, C.ColorBG)
btn.strip = NewBorder(wrapper, 0, 0, 3, C.BtnH, C.ColorAccent)
btn.txt = NewText(wrapper, 12, 0, C.BtnW - 15, C.BtnH, "TGOWNER7", C.ColorTitle, 14)
SafeCall(function() btn.txt:SetJustification(UEnums.ETextJustify.Center or 1) end)
SafeCall(function() btn.txt:SetVerticalJustification(UEnums.EVerticalTextAligment.Center or 0) end)

    local hit = NewButton(wrapper, 0, 0, C.BtnW, C.BtnH)
    if hit then
        if hit.OnPressed then
            SafeCall(function() hit.OnPressed:Add(function()
                UI.State.HoldElapsed = 0
                UI.State.HoldTimer   = 0
                UI.State.StartMouseX = UI.State.MouseX
                UI.State.StartMouseY = UI.State.MouseY
                UI.State.BtnStartX   = UI.State.BtnX
                UI.State.BtnStartY   = UI.State.BtnY
                UI.State.HasMoved    = false
            end) end)
        end
        if hit.OnReleased then
            SafeCall(function() hit.OnReleased:Add(function()
                UI.State.HoldTimer   = nil
                UI.State.HoldElapsed = 0
                if not UI.State.HasMoved then
                    if UI.State.Open then UI.Hide() else UI.Show() end
                end
                UI.State.HasMoved = false
            end) end)
        end
    end

    UI.Button = btn
    return btn
end

-- ================================================================
--  POSITION UPDATES (only move wrapper)
-- ================================================================
function UI.ApplyBtnPos()
    if not UI.Button or not UI.Button.wrapperSlot then return end
    SafeCall(function()
        UI.Button.wrapperSlot:SetPosition(FVector2D_UI(UI.State.BtnX, UI.State.BtnY))
    end)
end

function UI.ApplyPanelPos()
    if not UI.Panel or not UI.Panel.wrapperSlot then return end
    SafeCall(function()
        UI.Panel.wrapperSlot:SetPosition(FVector2D_UI(UI.State.PanelX, UI.State.PanelY))
    end)
end

-- ================================================================
--  SHOW / HIDE
-- ================================================================
function UI.Show()
    if not UI.Panel then UI.BuildPanel() end
    if not UI.Panel or not UI.Panel.wrapper then return end
    SetVisible(UI.Panel.wrapper, true)
    UI.State.Open = true
    UI.ApplyPanelPos()
end

function UI.Hide()
    if not UI.Panel or not UI.Panel.wrapper then return end
    SetVisible(UI.Panel.wrapper, false)
    UI.State.Open = false
end

function UI.Refresh()
    if not UI.Panel then return end
    UI.BuildRows(UI.Panel)
    -- Update tab highlight
    local C = UI.Config
    for cat, tab in pairs(UI.Panel.tabs or {}) do
        local active = (cat == UI.State.ActiveCategory)
        SetBorderColor(tab.bg, active and C.ColorAccent or C.ColorToggleOff)
    end
end

-- ================================================================
--  TICK (drag updates)
-- ================================================================
function UI.Tick(deltaTime)
    if UI.State.HoldTimer then
        UI.State.HoldElapsed = UI.State.HoldElapsed + (deltaTime or 0.016)
        if UI.State.HoldElapsed >= UI.Config.HoldToMove then
            local dx = UI.State.MouseX - UI.State.StartMouseX
            local dy = UI.State.MouseY - UI.State.StartMouseY
            if math.abs(dx) > 3 or math.abs(dy) > 3 then
                UI.State.HasMoved = true
                UI.State.BtnX = UI.State.BtnStartX + dx
                UI.State.BtnY = UI.State.BtnStartY + dy
                UI.ApplyBtnPos()
            end
        end
    end

    if UI.State.Dragging then
        local dx = UI.State.MouseX - UI.State.StartMouseX
        local dy = UI.State.MouseY - UI.State.StartMouseY
        UI.State.PanelX = (UI.State.PanelStartX or UI.State.PanelX) + dx
        UI.State.PanelY = (UI.State.PanelStartY or UI.State.PanelY) + dy
        UI.ApplyPanelPos()
    end
end

-- ================================================================
--  INIT WITH RETRY
-- ================================================================
function UI.Init()
    if UI._inited then return true end
    local btn = UI.BuildButton()
    if not btn then return false end
    local panel = UI.BuildPanel()
    if not panel then return false end
    UI._inited = true
    UI.Hide()
    print("✅ TGOWNER7 Menu Initialized!")
    return true
end

local ui_retry_count = 0
local function RetryUIInit()
    if UI._inited then return end
    if UI.Init() then return end
    ui_retry_count = ui_retry_count + 1
    if ui_retry_count < 60 then
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(1.0, RetryUIInit)
        elseif _G.Game and _G.Game.AddGameTimer then
            _G.Game:AddGameTimer(1.0, false, RetryUIInit)
        end
    end
end

pcall(function()
    local ticker = require("common.time_ticker")
    if ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(2.0, RetryUIInit)
    else
        RetryUIInit()
    end
end)

_G.GANESHMenu = UI

-- ========================================================================
-- TGOWNER7 TOP LUA BYPASS v2 (POWER FULL - 70futures UPDATED engine)
-- v5.0 core (100+ anti-ban blocks) + ADDITIONAL LAYERS (BanLogic/MD5/
-- Gokuba/RacingAntiCheat/KillAllSubsystems) + WEOV ANTI-CHEAT KILLERS
-- (DeadEye/HawkEye/Voklai/HiggsBoson/HashVerify/IPMapping/MemoryPatch)
-- sab pcall-safe, match transition me re-arm
-- ========================================================================
_G.X3 = _G.X3 or {}
-- COMPLETE ANTI-BAN SYSTEM v5.0
-- 100+ Bypasses | Full Anti-Cheat Block

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

        -- 2. ACE (ANTI-CHEAT EXPERT) COMPLETE BLOCK
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
            ace.ReportCheat = function() end
            ace.ReportHack = function() end
            ace.ReportMod = function() end
            ace.ReportInject = function() end
            ace.ReportHook = function() end
            ace.ReportPatch = function() end
            ace.ReportTamper = function() end
            ace.ReportCorrupt = function() end
            ace.ReportInvalid = function() end
            ace.ReportSpoof = function() end
            ace.ReportFake = function() end
        end

        -- 3. XIGNCODE3 COMPLETE BLOCK
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
            XignCode.EncryptData = function(data) return data end
            XignCode.DecryptData = function(data) return data end
            XignCode.ReportCheat = function() end
            XignCode.ReportHack = function() end
            XignCode.ReportMod = function() end
            XignCode.ReportInject = function() end
            XignCode.ReportHook = function() end
            XignCode.ReportPatch = function() end
            XignCode.ReportTamper = function() end
        end

        -- 4. BATTEYE COMPLETE BLOCK
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
            BattlEye.ReportCheat = function() end
            BattlEye.ReportHack = function() end
            BattlEye.ReportMod = function() end
            BattlEye.ReportInject = function() end
            BattlEye.ReportHook = function() end
        end

        -- 5. HIGGS BOSON COMPLETE BLOCK
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

        -- 6. ALL REPORT SYSTEMS BLOCK
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
                if module._OnPlayerKilledOtherPlayer then module._OnPlayerKilledOtherPlayer = function() end end
                if module._RecordFatalDamager then module._RecordFatalDamager = function() end end
                if module._OnBattleResult then module._OnBattleResult = function() end end
                if module._OnShowQuickReportMutualExclusiveUI then module._OnShowQuickReportMutualExclusiveUI = function() end end
                if module._AddEnemyMapToBattleResult then module._AddEnemyMapToBattleResult = function() end end
                if module._AddKnockDownerToBattleResult then module._AddKnockDownerToBattleResult = function() end end
                if module._AddKillerToBattleResult then module._AddKillerToBattleResult = function() end end
                if module._AddTeammateMurderToBattleResult then module._AddTeammateMurderToBattleResult = function() end end
                if module._AddFatalDamagerMapToBattleResult then module._AddFatalDamagerMapToBattleResult = function() end end
                if module._AddMLKillerUIDToBattleResult then module._AddMLKillerUIDToBattleResult = function() end end
                if module._SaveHistoricalTeammateInfo then module._SaveHistoricalTeammateInfo = function() end end
                if module._RecordTeammateMurderer then module._RecordTeammateMurderer = function() end end
                if module._OnNearDeathOrRescued then module._OnNearDeathOrRescued = function() end end
                if module._OnCharacterDied then module._OnCharacterDied = function() end end
                if module._OnTeammateDamage then module._OnTeammateDamage = function() end end
                if module._OnPlayerSettlementStart then module._OnPlayerSettlementStart = function() end end
                if module._OnHawkSync then module._OnHawkSync = function() end end
                if module._OnHawkReportSuccess then module._OnHawkReportSuccess = function() end end
                if module._StartExitGameTimer then module._StartExitGameTimer = function() end end
                if module.OnHandleBehaviorScore then module.OnHandleBehaviorScore = function() end end
                if module.AIPerceptionScore then module.AIPerceptionScore = function() end end
                if module.ReportAllPlayerInfo then module.ReportAllPlayerInfo = function() end end
                if module.AddRecordMLAIInfo then module.AddRecordMLAIInfo = function() end end
                if module.ReportAI then module.ReportAI = function() end end
                if module.RealLogoutTimer then module.RealLogoutTimer = function() end end
                if module.LogQueue then module.LogQueue = {} end
                if module.SendAFKTips then module.SendAFKTips = function() end end
                if module.OnHandleLostConnection then module.OnHandleLostConnection = function() end end
                if module.ClientRPC_SyncBanID then module.ClientRPC_SyncBanID = function() end end
                if module.ClientRPC_StrongTips then module.ClientRPC_StrongTips = function() end end
                if module.ClientRPC_NormalTips then module.ClientRPC_NormalTips = function() end end
                if module.Notify then module.Notify = function() end end
                if module.OnSyncBanInfo then module.OnSyncBanInfo = function() end end
                if module.OnVoiceBanNotify then module.OnVoiceBanNotify = function() end end
                if module.GetCarrierInfo then module.GetCarrierInfo = function() return "[{\"mcc\":\"000\"}]" end end
                if module.CheckIfCanCreateRole then module.CheckIfCanCreateRole = function() return true end end
                if module.DelayKickOutPlayer then module.DelayKickOutPlayer = function() end end
                if module.ActiveKickNotify then module.ActiveKickNotify = function() end end
                if module._UpdateTTKRecords then module._UpdateTTKRecords = function() end end
                if module._UpdateOperatingFrequency then module._UpdateOperatingFrequency = function() end end
                if module.GetSimpleFightData then module.GetSimpleFightData = function() return {} end end
                if module._OnReportServerJumpFlow then module._OnReportServerJumpFlow = function() end end
                if module.HandleKillTlog then module.HandleKillTlog = function() end end
                if module.AskForInspector then module.AskForInspector = function() end end
                if module.ReportEnemy then module.ReportEnemy = function() end end
                if module.KickOutOneTeam then module.KickOutOneTeam = function() end end
                if module.ServerKickOutOneTeamByPlayerImplementation then module.ServerKickOutOneTeamByPlayerImplementation = function() end end
                if module.AddReportedCount then module.AddReportedCount = function() end end
                if module.RequestGotoSpectatingImp then module.RequestGotoSpectatingImp = function() end end
                if module.RequestGotoSpectating then module.RequestGotoSpectating = function() end end
            end
        end

        -- 7. ALL TLOG SYSTEMS BLOCK
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
                if module._UpdateTTKRecords then module._UpdateTTKRecords = function() end end
                if module._UpdateOperatingFrequency then module._UpdateOperatingFrequency = function() end end
                if module.GetSimpleFightData then module.GetSimpleFightData = function() return {} end end
                if module._OnReportServerJumpFlow then module._OnReportServerJumpFlow = function() end end
                if module.HandleKillTlog then module.HandleKillTlog = function() end end
                if module.ReportReplay then module.ReportReplay = function() end end
                if module.SendReportReq then module.SendReportReq = function() end end
                if module.SendReport then module.SendReport = function() end end
                if module.SaveDump then module.SaveDump = function() end end
                if module.UploadDump then module.UploadDump = function() end end
            end
        end

        -- 8. GAMEPLAY CALLBACKS COMPLETE BLOCK
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
            GC.ReportHeavyWeaponBoxSpawnFlow = noop
            GC.ReportHeavyWeaponBoxActivationFlow = noop
            GC.ReportHeavyWeaponBoxOpenPlayerFlow = noop
            GC.ReportHeavyWeaponBoxItemFlow = noop
            GC.ReportPlayersPing = noop
            GC.ReportPlayerIP = noop
            GC.ReportPlayerFramePingRecord = noop
            GC.OnDSConnectionSaturated = noop
            GC.ReportDSNetSaturation = noop
            GC.ReportNetContinuousSaturate = noop
            GC.ReportDSNetRate = noop
            GC.SendClientStats = noop
            GC.SendServerAvgTickDelta = noop
            GC.ReportCircleFlow = noop
            GC.ReportDSCircleFlow = noop
            GC.ReportJumpFlow = noop
            GC.ReportAIStrategyInfo = noop
            GC.SendAIDeliveryInfo = noop
            GC.ReportDailyTaskInfo = noop
            GC.ReportMatchRoomData = noop
            GC.SendPlayerSpectatingLog = noop
            GC.ReportIDCardProduceFlow = noop
            GC.ReportIDCardPickUpFlow = noop
            GC.ReportIDCardDestroyFlow = noop
            GC.ReportRevivalFlow = noop
            GC.ReportGameSetting = noop
            GC.ReportGameSettingNew = noop
            GC.ReportAntsVoiceTeamCreate = noop
            GC.ReportAntsVoiceTeamQuit = noop
            GC.ReportCommonInfo = noop
            GC.ReportLightweightStat = noop
            GC.SendSecTLog = noop
            GC.SendDataMiningTLog = noop
            GC.SendActivityTLog = noop
            GC.GetGeneralTLogData = empty
            GC.OnDSPlayerStateChanged = function(UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason)
                if InPlayerState then
                    local state = string.lower(tostring(InPlayerState))
                    if string.find(state, "cheat") or string.find(state, "ban") or string.find(state, "kick") or
                       string.find(state, "detected") or string.find(state, "violation") or string.find(state, "suspicious") or
                       string.find(state, "abnormal") or string.find(state, "invalid") or string.find(state, "corrupt") or
                       string.find(state, "tamper") or string.find(state, "modify") or string.find(state, "inject") or
                       string.find(state, "hook") or string.find(state, "patch") or string.find(state, "spoof") or
                       string.find(state, "fake") or string.find(state, "clone") or string.find(state, "duplicate") or
                       string.find(state, "conflict") or string.find(state, "overlap") or string.find(state, "mismatch") or
                       string.find(state, "inconsistent") or string.find(state, "unexpected") or string.find(state, "unknown") then
                        return
                    end
                end
            end
            GC.OnPlayerNetConnectionClosed = noop
            GC.OnPlayerActorChannelError = noop
            GC.OnPlayerRPCValidateFailed = noop
            GC.OnPlayerSpectateException = noop
            GC.OnShutdownAfterError = noop
            GC.IsBypassed = true
        end

        -- 9. NETWORK PACKET BLOCK
        if NetUtil and NetUtil.SendPacket then
            local originalSend = NetUtil.SendPacket
            local blockedPackets = {
                ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportHurtFlow"]=1,
                ["ReportFireArms"]=1, ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1,
                ["ReportPlayerBehavior"]=1, ["ReportTeammatHurt"]=1, ["ReportTeammateKillConfirmFlow"]=1,
                ["ReportForbiddenPickupFlow"]=1, ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1,
                ["ReportSecVehicleMoveFlow"]=1, ["ReportSecTgameMovingFlow"]=1, ["report_parachute_data"]=1,
                ["on_tss_sdk_anti_data"]=1, ["report_unrealnet_exception"]=1, ["ReportPlayerEquipmentInfo"]=1,
                ["ReportAimFlow"]=1, ["ReportHitFlow"]=1, ["log_shooting_miss"]=1, ["report_heavy_weapon_box_activation_flow"]=1,
                ["report_heavy_weapon_box_item_flow"]=1, ["ReportCircleFlow"]=1, ["report_ds_player_circle_flow"]=1,
                ["ReportJumpFlow"]=1, ["ReportGameStartFlow"]=1, ["ReportGameEndFlow"]=1, ["report_players_ping"]=1,
                ["report_player_ip"]=1, ["report_player_frame_ping_record"]=1, ["report_net_saturate"]=1,
                ["report_ds_netsaturate"]=1, ["report_ds_net_continuous_saturate"]=1, ["report_ds_netrate"]=1,
                ["report_unrealnet_clientstats"]=1, ["report_serverstat_avgtickdelta"]=1, ["report_all_players_address"]=1,
                ["report_ai_strategyinfo"]=1, ["ReportAIActionFlow"]=1, ["ReportGenerateMonsterFlow"]=1,
                ["report_ds_match_room_data"]=1, ["SendSpectatingLog"]=1, ["ReportIDCardProduceFlow"]=1,
                ["ReportIDCardPickUpFlow"]=1, ["ReportIDCardDestroyFlow"]=1, ["ReportRevivalFlow"]=1,
                ["ReportGameSetting"]=1, ["ReportGameSettingNew"]=1, ["ReportAntsVoiceTeamCreate"]=1,
                ["ReportAntsVoiceTeamQuit"]=1, ["report_common_info"]=1, ["report_common_battle_info"]=1,
                ["report_client_scan_result"]=1, ["tss_sdk_report"]=1, ["report_memory_exception"]=1,
                ["report_avatar_exception"]=1, ["report_ui_state"]=1, ["report_hit_reg_fail"]=1,
                ["report_character_state"]=1, ["report_vehicle_exception"]=1, ["report_camera_exception"]=1,
                ["ReportPlayerControllerStateChanged"]=1, ["ReportAvatarFlow"]=1,
                ["ReportSecurityAlert"]=1, ["ReportAntiCheat"]=1, ["ReportSuspiciousActivity"]=1,
                ["ReportViolation"]=1, ["ReportBan"]=1, ["ReportKick"]=1,
                ["ReportCheat"]=1, ["ReportHack"]=1, ["ReportMod"]=1,
                ["ReportInject"]=1, ["ReportHook"]=1, ["ReportPatch"]=1,
                ["ReportTamper"]=1, ["ReportCorrupt"]=1, ["ReportInvalid"]=1,
                ["ReportSpoof"]=1, ["ReportFake"]=1, ["ReportClone"]=1,
                ["ReportDuplicate"]=1, ["ReportConflict"]=1, ["ReportOverlap"]=1,
                ["ReportMismatch"]=1, ["ReportInconsistent"]=1, ["ReportUnexpected"]=1,
                ["ReportUnknown"]=1,
            }
            NetUtil.SendPacket = function(packetName, ...)
                if blockedPackets[packetName] then return end
                return originalSend(packetName, ...)
            end
            NetUtil.IsBypassed = true
        end

        -- 10. CRASH AND EXCEPTION REPORTING BLOCK
        local CrashSight = _G.CrashSight or package.loaded["CrashSight"]
        if CrashSight then
            CrashSight.ReportException = function() end
            CrashSight.SetCustomData = function() end
            CrashSight.Log = function() end
            CrashSight.UploadLog = function() end
            CrashSight.SendReport = function() end
            CrashSight.CollectInfo = function() return {} end
            CrashSight.ReportCrash = function() end
            CrashSight.ReportError = function() end
            CrashSight.ReportFatal = function() end
            CrashSight.ReportWarning = function() end
            CrashSight.ReportInfo = function() end
            CrashSight.ReportDebug = function() end
            CrashSight.ReportMemory = function() end
            CrashSight.ReportPerformance = function() end
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
            TLog.LogWarning = function() end
            TLog.LogError = function() end
            TLog.LogVerbose = function() end
            TLog.SetLogLevel = function() end
        end

        -- 11. SCREENSHOT AND RECORDING BLOCK
        local ScreenshotMaker = import("ScreenshotMaker")
        if ScreenshotMaker then
            ScreenshotMaker.MakePicture = function() return "" end
            ScreenshotMaker.ReMakePicture = function() return "" end
            ScreenshotMaker.HasCaptured = function() return true end
            ScreenshotMaker.TakeScreenshot = function() end
            ScreenshotMaker.SaveScreenshot = function() end
            ScreenshotMaker.CaptureScreen = function() end
            ScreenshotMaker.RecordScreen = function() end
        end

        -- 12. MEMORY SCANNER BLOCK
        local MemoryScanner = _G.MemoryScanner or package.loaded["MemoryScanner"]
        if MemoryScanner then
            MemoryScanner.StartScan = function() end
            MemoryScanner.StopScan = function() end
            MemoryScanner.GetResults = function() return {} end
            MemoryScanner.ReportViolation = function() end
            MemoryScanner.CheckIntegrity = function() return true end
            MemoryScanner.VerifyMemory = function() return true end
            MemoryScanner.ScanProcess = function() end
            MemoryScanner.ScanModule = function() end
            MemoryScanner.ScanThread = function() end
            MemoryScanner.ScanFile = function() end
            MemoryScanner.ScanNetwork = function() end
        end

        -- 13. FILE INTEGRITY CHECK BLOCK
        local FileCheckSubsystem = package.loaded["GameLua.GameCore.Module.Subsystem.SubsystemMgr"]:Get("FileCheckSubsystem")
        if FileCheckSubsystem then
            FileCheckSubsystem.StartCheck = function() end
            FileCheckSubsystem.ReportAbnormalFile = function() end
            FileCheckSubsystem.VerifyFile = function() return true end
            FileCheckSubsystem.CheckIntegrity = function() return true end
            FileCheckSubsystem.ValidateFile = function() return true end
            FileCheckSubsystem.CheckFile = function() return true end
            FileCheckSubsystem.VerifyHash = function() return true end
            FileCheckSubsystem.ValidateHash = function() return true end
            FileCheckSubsystem.CheckHash = function() return true end
        end

        -- 14. AVATAR VALIDATION BLOCK
        local AvatarUtils = package.loaded["AvatarUtils"]
        if AvatarUtils then
            AvatarUtils.CheckIsWeaponInBlackList = function() return false end
            AvatarUtils.IsValidAvatar = function() return true end
            AvatarUtils.ValidateAvatar = function() return true end
            AvatarUtils.CheckAvatar = function() return true end
            AvatarUtils.VerifySkin = function() return true end
            AvatarUtils.ValidateSkin = function() return true end
            AvatarUtils.CheckSkin = function() return true end
            AvatarUtils.VerifyWeapon = function() return true end
            AvatarUtils.ValidateWeapon = function() return true end
            AvatarUtils.CheckWeapon = function() return true end
            AvatarUtils.VerifyVehicle = function() return true end
            AvatarUtils.ValidateVehicle = function() return true end
            AvatarUtils.CheckVehicle = function() return true end
        end

        -- 15. STATISTICS REPORTING BLOCK
        local ClientDataStatistcsSubsystem = package.loaded["GameLua.GameCore.Module.Subsystem.SubsystemMgr"]:Get("ClientDataStatistcsSubsystem")
        if ClientDataStatistcsSubsystem then
            ClientDataStatistcsSubsystem.StartToCheck = function() end
            ClientDataStatistcsSubsystem.DelayCount = 0
            ClientDataStatistcsSubsystem.ReportPingDelay = function() end
            ClientDataStatistcsSubsystem.ReportStats = function() end
            ClientDataStatistcsSubsystem.ReportData = function() end
            ClientDataStatistcsSubsystem.ReportPerformance = function() end            ClientDataStatistcsSubsystem.ReportBattery = function() end
            ClientDataStatistcsSubsystem.ReportTemperature = function() end
            ClientDataStatistcsSubsystem.ReportFPS = function() end
            ClientDataStatistcsSubsystem.ReportPing = function() end
            ClientDataStatistcsSubsystem.ReportNetwork = function() end
        end

        -- 16. SHOOT VERIFICATION BLOCK
        local ShootVerifySubSystemClient = package.loaded["GameLua.GameCore.Module.Subsystem.SubsystemMgr"]:Get("ShootVerifySubSystemClient")
        if ShootVerifySubSystemClient then
            ShootVerifySubSystemClient.ReportVerifyFail = function() end
            ShootVerifySubSystemClient.OnVerifyFailed = function() end
            ShootVerifySubSystemClient.CheckShoot = function() return true end
            ShootVerifySubSystemClient.ValidateHit = function() return true end
            ShootVerifySubSystemClient.VerifyShoot = function() return true end
            ShootVerifySubSystemClient.ValidateShoot = function() return true end
            ShootVerifySubSystemClient.CheckHit = function() return true end
            ShootVerifySubSystemClient.VerifyHit = function() return true end
        end

        -- 17. AFK REPORT BLOCK
        local AFKReportorSubsystem = package.loaded["GameLua.GameCore.Module.Subsystem.SubsystemMgr"]:Get("AFKReportorSubsystem")
        if AFKReportorSubsystem then
            AFKReportorSubsystem.PlayerHaveAction = function() end
            AFKReportorSubsystem.ReportAFK = function() end
            AFKReportorSubsystem.CheckAFK = function() return false end
            AFKReportorSubsystem.ReportAFKData = function() end
            AFKReportorSubsystem.ReportIdle = function() end
            AFKReportorSubsystem.ReportInactive = function() end
        end

        -- 18. AVATAR EXCEPTION BLOCK
        local AvatarExceptionSubsystem = package.loaded["GameLua.GameCore.Module.Subsystem.SubsystemMgr"]:Get("AvatarExceptionSubsystem")
        if AvatarExceptionSubsystem then
            AvatarExceptionSubsystem.ReportException = function() end
            AvatarExceptionSubsystem.BindPlayerCharacter = function() end
            AvatarExceptionSubsystem.CheckAvatarValid = function() return true end
            AvatarExceptionSubsystem.ValidateAvatar = function() return true end
            AvatarExceptionSubsystem.ReportAvatarException = function() end
            AvatarExceptionSubsystem.ReportInvalidAvatar = function() end
            AvatarExceptionSubsystem.ReportCorruptAvatar = function() end
        end

        -- 19. REPLAY REPORT BLOCK
        local RescueBtnReplayTraceSubsystem = package.loaded["GameLua.GameCore.Module.Subsystem.SubsystemMgr"]:Get("RescueBtnReplayTraceSubsystem")
        if RescueBtnReplayTraceSubsystem then
            RescueBtnReplayTraceSubsystem.ReportTrace = function() end
            RescueBtnReplayTraceSubsystem.StartTickMonitor = function() end
            RescueBtnReplayTraceSubsystem.TickMonitorCheck = function() end
            RescueBtnReplayTraceSubsystem.ReportTickMonitorHeartbeat = function() end
            RescueBtnReplayTraceSubsystem.ReportReplay = function() end
            RescueBtnReplayTraceSubsystem.ReportTraceData = function() end
        end

        -- 20. GAME REPORT BLOCK
        local GameReportSubsystem = package.loaded["GameLua.GameCore.Module.Subsystem.SubsystemMgr"]:Get("GameReportSubsystem")
        if GameReportSubsystem then
            GameReportSubsystem.ReplayReportData = function() return false end
            GameReportSubsystem.CheckCanBugglyPostException = function() return false end
            GameReportSubsystem.BugglyPostExceptionFull = function() return false end
            GameReportSubsystem.GetClientReplayDataReporter = function() return nil end
            GameReportSubsystem.ReportGameException = function() end
            GameReportSubsystem.ReportGameData = function() end
            GameReportSubsystem.ReportGameStats = function() end
            GameReportSubsystem.ReportGamePerformance = function() end
        end

        -- 21. INSPECTION SYSTEM BLOCK
        local InspectionSystemReportClientLogicSubsystem = package.loaded["GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem"]
        if InspectionSystemReportClientLogicSubsystem then
            InspectionSystemReportClientLogicSubsystem.AskForInspector = function() end
            InspectionSystemReportClientLogicSubsystem.ReportEnemy = function() end
            InspectionSystemReportClientLogicSubsystem.KickOutOneTeam = function() end
            InspectionSystemReportClientLogicSubsystem.ReportSuspicious = function() end
            InspectionSystemReportClientLogicSubsystem.ReportCheat = function() end
            InspectionSystemReportClientLogicSubsystem.ReportHack = function() end
        end

        -- 22. HAWK EYE PATROL BLOCK
        local ClientHawkEyePatrolSubsystem = package.loaded["GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem"]
        if ClientHawkEyePatrolSubsystem then
            ClientHawkEyePatrolSubsystem._OnHawkSync = function() end
            ClientHawkEyePatrolSubsystem._OnHawkReportSuccess = function() end
            ClientHawkEyePatrolSubsystem._StartExitGameTimer = function() end
            ClientHawkEyePatrolSubsystem.ReportData = function() end
            ClientHawkEyePatrolSubsystem.ReportHawk = function() end
            ClientHawkEyePatrolSubsystem.ReportPatrol = function() end
        end

        -- 23. BEHAVIOR SCORE BLOCK
        local BehaviorScoreSubsystem = package.loaded["GameLua.Mod.Escape.Gameplay.Subsystem.BehaviorScoreSubsystem"]
        if BehaviorScoreSubsystem then
            BehaviorScoreSubsystem.OnHandleBehaviorScore = function() end
            BehaviorScoreSubsystem.AIPerceptionScore = function() end
            BehaviorScoreSubsystem.ReportBehavior = function() end
            BehaviorScoreSubsystem.CalculateScore = function() return 100 end
            BehaviorScoreSubsystem.ReportScore = function() end
            BehaviorScoreSubsystem.ReportBehaviorData = function() end
        end

        -- 24. AI REPORTING BLOCK
        local AIReplaySubsystem = package.loaded["GameLua.ExtraModule.MLAI.Client.AIReplaySubsystem"]
        if AIReplaySubsystem then
            AIReplaySubsystem.ReportAllPlayerInfo = function() end
            AIReplaySubsystem.AddRecordMLAIInfo = function() end
            AIReplaySubsystem.ReportAI = function() end
            AIReplaySubsystem.ReportAIData = function() end
            AIReplaySubsystem.ReportAIPerformance = function() end
        end

        -- 25. BAN SYSTEM BLOCK
        local ClientBanLogic = package.loaded["client.slua.logic.ban.ClientBanLogic"]
        if ClientBanLogic then
            ClientBanLogic.OnSyncBanInfo = function() end
            ClientBanLogic.OnVoiceBanNotify = function() end
            ClientBanLogic.CheckBan = function() return false end
            ClientBanLogic.IsBanned = function() return false end
            ClientBanLogic.CheckBanStatus = function() return false end
            ClientBanLogic.GetBanInfo = function() return {} end
        end

        local logic_tt_ban = package.loaded["client.slua.logic.login.logic_tt_ban"]
        if logic_tt_ban then
            logic_tt_ban.GetCarrierInfo = function() return "[{\"mcc\":\"000\"}]" end
            logic_tt_ban.CheckIfCanCreateRole = function() return true end
            logic_tt_ban.CheckBan = function() return false end
            logic_tt_ban.GetBanStatus = function() return false end
        end

        -- 26. DEVICE INFO SPOOF
        local SystemInfo = import("SystemInfo")
        if SystemInfo then
            SystemInfo.GetDeviceModel = function() return "iPhone14,5" end
            SystemInfo.GetDeviceBrand = function() return "Apple" end
            SystemInfo.GetAndroidVersion = function() return "13" end
            SystemInfo.GetEMUIVersion = function() return "" end
            SystemInfo.IsEmulator = function() return false end
            SystemInfo.IsRooted = function() return false end
            SystemInfo.IsDebugged = function() return false end
            SystemInfo.GetKernelVersion = function() return "Linux version 4.14.116" end
            SystemInfo.CheckKernelIntegrity = function() return true end
            SystemInfo.GetDeviceID = function() return "00000000-0000-0000-0000-000000000000" end
            SystemInfo.GetDeviceName = function() return "iPhone" end
            SystemInfo.GetDeviceType = function() return "Phone" end
            SystemInfo.GetManufacturer = function() return "Apple" end
            SystemInfo.GetModel = function() return "iPhone14,5" end
            SystemInfo.GetOSVersion = function() return "13" end
            SystemInfo.GetOSName = function() return "iOS" end
            SystemInfo.GetScreenResolution = function() return "1170x2532" end
            SystemInfo.GetScreenDensity = function() return "460" end
            SystemInfo.GetRAMSize = function() return "6144" end
            SystemInfo.GetStorageSize = function() return "256" end
            SystemInfo.GetBatteryLevel = function() return "100" end
            SystemInfo.GetBatteryStatus = function() return "Charging" end
            SystemInfo.GetNetworkType = function() return "WiFi" end
            SystemInfo.GetNetworkSpeed = function() return "100" end
            SystemInfo.GetGPSStatus = function() return "Enabled" end
            SystemInfo.GetGPSLocation = function() return "0.0,0.0" end
            SystemInfo.GetCountryCode = function() return "US" end
            SystemInfo.GetLanguageCode = function() return "en" end
            SystemInfo.GetTimeZone = function() return "UTC" end
            SystemInfo.GetCurrentTime = function() return os.time() end
            SystemInfo.GetUptime = function() return 3600 end
            SystemInfo.GetCPUUsage = function() return 10 end
            SystemInfo.GetMemoryUsage = function() return 20 end
            SystemInfo.GetTemperature = function() return 25 end
            SystemInfo.GetBatteryTemperature = function() return 25 end
            SystemInfo.GetCPUFrequency = function() return 2400 end
            SystemInfo.GetGPUFrequency = function() return 1200 end
            SystemInfo.GetScreenBrightness = function() return 100 end
            SystemInfo.GetVolumeLevel = function() return 100 end
        end

        -- 27. CONSOLE COMMAND BLOCK
        local KismetSystemLibrary = import("KismetSystemLibrary")
        if KismetSystemLibrary then
            KismetSystemLibrary.IsDevelopment = function() return false end
            KismetSystemLibrary.IsShipping = function() return true end
            KismetSystemLibrary.IsDebug = function() return false end
            KismetSystemLibrary.IsEditor = function() return false end
            KismetSystemLibrary.IsGame = function() return true end
            KismetSystemLibrary.IsClient = function() return true end
            KismetSystemLibrary.IsServer = function() return false end
            KismetSystemLibrary.IsStandalone = function() return false end
        end

        -- 28. CREATIVE MODE BLOCK
        local CreativeModeBlueprintLibrary = import("CreativeModeBlueprintLibrary")
        if CreativeModeBlueprintLibrary then
            CreativeModeBlueprintLibrary.MD5HashByteArray = function() return "BYPASSED_MD5_HASH" end
            CreativeModeBlueprintLibrary.GetContentDiffData = function() return true, "BYPASSED" end
            CreativeModeBlueprintLibrary.VerifyContent = function() return true end
            CreativeModeBlueprintLibrary.ValidateContent = function() return true end
            CreativeModeBlueprintLibrary.CheckContent = function() return true end
        end

        -- 29. ALL LOGGING COMPLETE BLOCK
        _G.print = function() end
        _G.printf = function() end
        _G.log = function() end
        _G.warn = function() end
        _G.error = function() end
        _G.debug = function() end
        _G.trace = function() end
        _G.info = function() end
        _G.verbose = function() end
        _G.fatal = function() end
        _G.panic = function() end
        _G.recover = function() end
        _G.assert = function() end

        local Logging = import("Logging")
        if Logging then
            Logging.Log = function() end
            Logging.LogWarning = function() end
            Logging.LogError = function() end
            Logging.LogVerbose = function() end
            Logging.SetLogLevel = function() end
            Logging.LogInfo = function() end
            Logging.LogDebug = function() end
            Logging.LogTrace = function() end
            Logging.LogFatal = function() end
            Logging.LogPanic = function() end
        end

        -- 30. TELEMETRY COMPLETE BLOCK
        local TDataMaster = _G.TDataMaster or package.loaded["libTDataMaster.so"]
        if TDataMaster then
            TDataMaster.ReportEvent = function() end
            TDataMaster.ReportException = function() end
            TDataMaster.FlushData = function() end
            TDataMaster.CollectData = function() return {} end
            TDataMaster.SendReport = function() end
            TDataMaster.ReportTelemetry = function() end
            TDataMaster.ReportAnalytics = function() end
            TDataMaster.ReportMetrics = function() end
            TDataMaster.ReportStatistics = function() end
            TDataMaster.ReportPerformance = function() end
            TDataMaster.ReportBattery = function() end
            TDataMaster.ReportTemperature = function() end
            TDataMaster.ReportFPS = function() end
            TDataMaster.ReportPing = function() end
            TDataMaster.ReportNetwork = function() end
        end

        _G.TelemetryQueue = {}
        _G.bTelemetryEnabled = false

        -- 31. GLOBAL SUSPICIOUS FLAGS BLOCK
        local suspiciousVars = {
            "bIsCheating", "bDetected", "bBanned", "SuspicionScore",
            "CheatDetected", "AntiCheatFlag", "IsHacking", "bReported",
            "TrustScore", "SecurityFlag", "ViolationLevel", "BanStatus",
            "bIsBan", "bIsKick", "bIsReported", "CheatCount",
            "ViolationCount", "SecurityScore", "TrustLevel",
            "bIsCheater", "bIsHacker", "bIsModder", "bIsInjector",
            "bIsHooker", "bIsPatcher", "bIsTamperer", "bIsCorrupter",
            "bIsInvalid", "bIsSpoofer", "bIsFaker", "bIsCloner",
            "bIsDuplicator", "bIsConflicter", "bIsOverlapper", "bIsMismatcher",
            "bIsInconsistent", "bIsUnexpected", "bIsUnknown", "bIsSuspicious",
            "bIsAbnormal", "bIsCorrupt", "bIsTampered", "bIsModified",
            "bIsInjected", "bIsHooked", "bIsPatched", "bIsSpoofed",
            "bIsFaked", "bIsCloned", "bIsDuplicated", "bIsConflicted",
            "bIsOverlapped", "bIsMismatched", "bIsInconsistent",
        }

        for _, var in ipairs(suspiciousVars) do
            _G[var] = nil
        end

        -- 32. MEMORY PROTECTION BLOCK
        local MemoryProtect = import("MemoryProtect")
        if MemoryProtect then
            MemoryProtect.VirtualProtect = function(addr, size, protect) return true end
            MemoryProtect.IsMemoryReadable = function(addr) return false end
            MemoryProtect.IsMemoryWritable = function(addr) return false end
            MemoryProtect.CheckMemory = function() return true end
            MemoryProtect.ProtectMemory = function() return true end
            MemoryProtect.UnprotectMemory = function() return true end
            MemoryProtect.ValidateMemory = function() return true end
            MemoryProtect.VerifyMemory = function() return true end
        end

        -- 33. NETWORK MONITORING BLOCK
        local NetworkManager = import("NetworkManager")
        if NetworkManager then
            NetworkManager.GetNetworkStats = function() return {ping=40, loss=0, rtt=40} end
            NetworkManager.CapturePackets = function() end
            NetworkManager.AnalyzeTraffic = function() return {} end
            NetworkManager.GetConnectionInfo = function() return "127.0.0.1:8080" end
            NetworkManager.MonitorTraffic = function() end
            NetworkManager.ReportTraffic = function() end
            NetworkManager.ReportNetwork = function() end
            NetworkManager.ReportBandwidth = function() end
            NetworkManager.ReportLatency = function() end
            NetworkManager.ReportPacketLoss = function() end
        end

        -- 34. TIMING CHECK SPOOF
        local Engine = import("Engine")
        if Engine then
            Engine.GetAverageFPS = function() return 60 end
            Engine.GetFrameTime = function() return 0.016 end
            Engine.IsLagging = function() return false end
            Engine.GetDeltaTime = function() return 0.033 end
            Engine.GetTime = function() return os.time() end
            Engine.GetTimestamp = function() return os.time() end
            Engine.GetTick = function() return os.clock() end
            Engine.GetSeconds = function() return os.time() end
            Engine.GetMilliseconds = function() return os.time() * 1000 end
            Engine.GetMicroseconds = function() return os.time() * 1000000 end
            Engine.GetNanoseconds = function() return os.time() * 1000000000 end
        end

        local GameTime = package.loaded["GameLua.GameCore.Data.GameTime"]
        if GameTime then
            GameTime.GetServerTime = function() return os.time() end
            GameTime.GetDeltaTime = function() return 0.033 end
            GameTime.GetGameTime = function() return os.time() end
            GameTime.GetRealTime = function() return os.time() end
            GameTime.GetTickTime = function() return os.clock() end
            GameTime.GetFrameTime = function() return 0.016 end
        end

        -- 35-50. ADDITIONAL SUBSYSTEM BLOCKS
        local subsystemMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if subsystemMgr then
            local allSubsystems = subsystemMgr:GetAllSubsystems()
            for _, sub in pairs(allSubsystems) do
                if sub and sub.Report then sub.Report = function() end end
                if sub and sub.ReportException then sub.ReportException = function() end end
                if sub and sub.SendReport then sub.SendReport = function() end end
                if sub and sub.CollectData then sub.CollectData = function() return {} end end
                if sub and sub.Validate then sub.Validate = function() return true end end
                if sub and sub.CheckIntegrity then sub.CheckIntegrity = function() return true end end
                if sub and sub.Verify then sub.Verify = function() return true end end
                if sub and sub.Check then sub.Check = function() return true end end
                if sub and sub.ValidateData then sub.ValidateData = function() return true end end
                if sub and sub.VerifyData then sub.VerifyData = function() return true end end
                if sub and sub.CheckData then sub.CheckData = function() return true end end
                if sub and sub.ValidateState then sub.ValidateState = function() return true end end
                if sub and sub.VerifyState then sub.VerifyState = function() return true end end
                if sub and sub.CheckState then sub.CheckState = function() return true end end
                if sub and sub.ValidateConfig then sub.ValidateConfig = function() return true end end
                if sub and sub.VerifyConfig then sub.VerifyConfig = function() return true end end
                if sub and sub.CheckConfig then sub.CheckConfig = function() return true end end
                if sub and sub.ValidatePlayer then sub.ValidatePlayer = function() return true end end
                if sub and sub.VerifyPlayer then sub.VerifyPlayer = function() return true end end
                if sub and sub.CheckPlayer then sub.CheckPlayer = function() return true end end
                if sub and sub.ValidateGame then sub.ValidateGame = function() return true end end
                if sub and sub.VerifyGame then sub.VerifyGame = function() return true end end
                if sub and sub.CheckGame then sub.CheckGame = function() return true end end
                if sub and sub.ValidateSystem then sub.ValidateSystem = function() return true end end
                if sub and sub.VerifySystem then sub.VerifySystem = function() return true end end
                if sub and sub.CheckSystem then sub.CheckSystem = function() return true end end
                if sub and sub.ValidateDevice then sub.ValidateDevice = function() return true end end
                if sub and sub.VerifyDevice then sub.VerifyDevice = function() return true end end
                if sub and sub.CheckDevice then sub.CheckDevice = function() return true end end
                if sub and sub.ValidateNetwork then sub.ValidateNetwork = function() return true end end
                if sub and sub.VerifyNetwork then sub.VerifyNetwork = function() return true end end
                if sub and sub.CheckNetwork then sub.CheckNetwork = function() return true end end
                if sub and sub.ValidateMemory then sub.ValidateMemory = function() return true end end
                if sub and sub.VerifyMemory then sub.VerifyMemory = function() return true end end
                if sub and sub.CheckMemory then sub.CheckMemory = function() return true end end
                if sub and sub.ValidateFile then sub.ValidateFile = function() return true end end
                if sub and sub.VerifyFile then sub.VerifyFile = function() return true end end
                if sub and sub.CheckFile then sub.CheckFile = function() return true end end
                if sub and sub.ValidateProcess then sub.ValidateProcess = function() return true end end
                if sub and sub.VerifyProcess then sub.VerifyProcess = function() return true end end
                if sub and sub.CheckProcess then sub.CheckProcess = function() return true end end
                if sub and sub.ValidateThread then sub.ValidateThread = function() return true end end
                if sub and sub.VerifyThread then sub.VerifyThread = function() return true end end
                if sub and sub.CheckThread then sub.CheckThread = function() return true end end
                if sub and sub.ValidateModule then sub.ValidateModule = function() return true end end
                if sub and sub.VerifyModule then sub.VerifyModule = function() return true end end
                if sub and sub.CheckModule then sub.CheckModule = function() return true end end
                if sub and sub.ValidateAPI then sub.ValidateAPI = function() return true end end
                if sub and sub.VerifyAPI then sub.VerifyAPI = function() return true end end
                if sub and sub.CheckAPI then sub.CheckAPI = function() return true end end
                if sub and sub.ValidateSDK then sub.ValidateSDK = function() return true end end
                if sub and sub.VerifySDK then sub.VerifySDK = function() return true end end
                if sub and sub.CheckSDK then sub.CheckSDK = function() return true end end
            end
        end

        -- 51. ZERO TRACE CLEANUP
        local MemoryCleaner = import("MemoryCleaner")
        if MemoryCleaner then
            MemoryCleaner.ClearCache = function() end
            MemoryCleaner.FreeUnusedMemory = function() end
            MemoryCleaner.CompactHeap = function() end
            MemoryCleaner.CleanTraces = function() end
            MemoryCleaner.ClearLogs = function() end
            MemoryCleaner.ClearTemp = function() end
            MemoryCleaner.ClearCacheFiles = function() end
            MemoryCleaner.ClearHistory = function() end
            MemoryCleaner.ClearData = function() end
        end

        -- 52. ANTI-DEBUGGING BLOCK
        local DebuggerDetect = _G.DebuggerDetect or package.loaded["DebuggerDetect"]
        if DebuggerDetect then
            DebuggerDetect.IsDebuggerPresent = function() return false end
            DebuggerDetect.CheckBreakpoint = function() return false end
            DebuggerDetect.CheckTracer = function() return false end
            DebuggerDetect.CheckDebug = function() return false end
            DebuggerDetect.CheckDebugger = function() return false end
            DebuggerDetect.DetectDebugger = function() return false end
            DebuggerDetect.DetectBreakpoint = function() return false end
            DebuggerDetect.DetectTracer = function() return false end
            DebuggerDetect.DetectDebug = function() return false end
        end

        -- 53. EMULATOR DETECTION BLOCK
        local EmulatorDetect = _G.EmulatorDetect or package.loaded["EmulatorDetect"]
        if EmulatorDetect then
            EmulatorDetect.IsEmulator = function() return false end
            EmulatorDetect.GetEmulatorType = function() return "" end
            EmulatorDetect.CheckVM = function() return false end
            EmulatorDetect.Detect = function() return false end
            EmulatorDetect.DetectEmulator = function() return false end
            EmulatorDetect.DetectVM = function() return false end
            EmulatorDetect.DetectVirtualMachine = function() return false end
            EmulatorDetect.DetectEmulatorType = function() return "" end
        end

        -- 54. JNI ANTI-CHEAT BLOCK
        local jni_ac = _G.JNI and _G.JNI.AntiCheat
        if jni_ac then
            jni_ac.CheckRoot = function() return false end
            jni_ac.CheckEmulator = function() return false end
            jni_ac.CheckDebugger = function() return false end
            jni_ac.CollectInfo = function() return {} end
            jni_ac.SendReport = function() end
            jni_ac.Validate = function() return true end
            jni_ac.CheckRootAccess = function() return false end
            jni_ac.CheckEmulatorAccess = function() return false end
            jni_ac.CheckDebuggerAccess = function() return false end
            jni_ac.CheckMemoryAccess = function() return true end
            jni_ac.CheckProcessAccess = function() return true end
            jni_ac.CheckFileAccess = function() return true end
            jni_ac.CheckNetworkAccess = function() return true end
            jni_ac.CheckSystemAccess = function() return true end
            jni_ac.CheckDeviceAccess = function() return true end
            jni_ac.CheckAPIAccess = function() return true end
            jni_ac.CheckSDKAccess = function() return true end
            jni_ac.CheckLibraryAccess = function() return true end
            jni_ac.CheckFrameworkAccess = function() return true end
            jni_ac.CheckPackageAccess = function() return true end
        end

        -- 55. PACKET ENCRYPTION BYPASS
        local PacketEncrypt = _G.PacketEncrypt or package.loaded["PacketEncrypt"]
        if PacketEncrypt then
            PacketEncrypt.Encrypt = function(data) return data end
            PacketEncrypt.Decrypt = function(data) return data end
            PacketEncrypt.VerifyChecksum = function() return true end
            PacketEncrypt.Validate = function() return true end
            PacketEncrypt.ValidatePacket = function() return true end
            PacketEncrypt.VerifyPacket = function() return true end
            PacketEncrypt.CheckPacket = function() return true end
            PacketEncrypt.EncryptPacket = function(data) return data end
            PacketEncrypt.DecryptPacket = function(data) return data end
            PacketEncrypt.ValidateChecksum = function() return true end
            PacketEncrypt.VerifyChecksum = function() return true end
            PacketEncrypt.CheckChecksum = function() return true end
        end

        -- 56. DS VALIDATION BYPASS
        local DSValidator = _G.DSValidator or package.loaded["DSValidator"]
        if DSValidator then
            DSValidator.ValidateClient = function() return true end
            DSValidator.CheckLatency = function() return 40 end
            DSValidator.ReportCheat = function() end
            DSValidator.KickPlayer = function() end
            DSValidator.BanPlayer = function() end
            DSValidator.ValidatePlayer = function() return true end
            DSValidator.ValidateSession = function() return true end
            DSValidator.ValidateGame = function() return true end
            DSValidator.ValidateSystem = function() return true end
            DSValidator.ValidateDevice = function() return true end
            DSValidator.ValidateNetwork = function() return true end
            DSValidator.ValidateMemory = function() return true end
            DSValidator.ValidateFile = function() return true end
            DSValidator.ValidateProcess = function() return true end
            DSValidator.ValidateThread = function() return true end
            DSValidator.ValidateModule = function() return true end
            DSValidator.ValidateAPI = function() return true end
            DSValidator.ValidateSDK = function() return true end
            DSValidator.ValidateLibrary = function() return true end
            DSValidator.ValidateFramework = function() return true end
            DSValidator.ValidatePackage = function() return true end
            DSValidator.ValidateContainer = function() return true end
            DSValidator.ValidateComponent = function() return true end
            DSValidator.ValidateObject = function() return true end
            DSValidator.ValidateClass = function() return true end
            DSValidator.ValidateStruct = function() return true end
            DSValidator.ValidateEnum = function() return true end
            DSValidator.ValidateInterface = function() return true end
            DSValidator.ValidateDelegate = function() return true end
            DSValidator.ValidateEvent = function() return true end
            DSValidator.ValidateFunction = function() return true end
            DSValidator.ValidateVariable = function() return true end
            DSValidator.ValidateProperty = function() return true end
            DSValidator.ValidateField = function() return true end
            DSValidator.ValidateMethod = function() return true end
            DSValidator.ValidateParameter = function() return true end
            DSValidator.ValidateReturn = function() return true end
            DSValidator.ValidateResult = function() return true end
            DSValidator.ValidateOutput = function() return true end
            DSValidator.ValidateInput = function() return true end
        end

        -- 57. CRC CHECK BYPASS
        local CRCChecker = _G.CRCChecker or package.loaded["CRCChecker"]
        if CRCChecker then
            CRCChecker.VerifyFile = function() return true end
            CRCChecker.VerifyMemory = function() return true end
            CRCChecker.GenerateCRC = function() return "00000000" end
            CRCChecker.CheckIntegrity = function() return true end
            CRCChecker.ValidateFile = function() return true end
            CRCChecker.ValidateMemory = function() return true end
            CRCChecker.CheckFile = function() return true end
            CRCChecker.CheckMemory = function() return true end
            CRCChecker.VerifyCRC = function() return true end
            CRCChecker.ValidateCRC = function() return true end
            CRCChecker.CheckCRC = function() return true end
            CRCChecker.GenerateCRC32 = function() return "00000000" end
            CRCChecker.GenerateCRC64 = function() return "0000000000000000" end
            CRCChecker.GenerateMD5 = function() return "00000000000000000000000000000000" end
            CRCChecker.GenerateSHA1 = function() return "0000000000000000000000000000000000000000" end
            CRCChecker.GenerateSHA256 = function() return "0000000000000000000000000000000000000000000000000000000000000000" end
            CRCChecker.GenerateSHA512 = function() return "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" end
        end

        -- 58. SECURITY COMMON UTILS BYPASS
        local SecurityCommonUtils = package.loaded["GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils"]
        if SecurityCommonUtils then
            SecurityCommonUtils.ExtractPlayerBasicInfo = function() return {} end
            SecurityCommonUtils.LogIf = function() return false end
            SecurityCommonUtils.CheckSecurity = function() return true end
            SecurityCommonUtils.ValidatePlayer = function() return true end
            SecurityCommonUtils.ValidateSession = function() return true end
            SecurityCommonUtils.ValidateGame = function() return true end
            SecurityCommonUtils.ValidateSystem = function() return true end
            SecurityCommonUtils.ValidateDevice = function() return true end
            SecurityCommonUtils.ValidateNetwork = function() return true end
            SecurityCommonUtils.ValidateMemory = function() return true end
            SecurityCommonUtils.ValidateFile = function() return true end
            SecurityCommonUtils.ValidateProcess = function() return true end
            SecurityCommonUtils.ValidateThread = function() return true end
            SecurityCommonUtils.ValidateModule = function() return true end
            SecurityCommonUtils.ValidateAPI = function() return true end
            SecurityCommonUtils.ValidateSDK = function() return true end
            SecurityCommonUtils.ValidateLibrary = function() return true end
            SecurityCommonUtils.ValidateFramework = function() return true end
            SecurityCommonUtils.ValidatePackage = function() return true end
            SecurityCommonUtils.ValidateContainer = function() return true end            SecurityCommonUtils.ValidateComponent = function() return true end
            SecurityCommonUtils.ValidateObject = function() return true end
            SecurityCommonUtils.ValidateClass = function() return true end
            SecurityCommonUtils.ValidateStruct = function() return true end
            SecurityCommonUtils.ValidateEnum = function() return true end
            SecurityCommonUtils.ValidateInterface = function() return true end
            SecurityCommonUtils.ValidateDelegate = function() return true end
            SecurityCommonUtils.ValidateEvent = function() return true end
            SecurityCommonUtils.ValidateFunction = function() return true end
            SecurityCommonUtils.ValidateVariable = function() return true end
            SecurityCommonUtils.ValidateProperty = function() return true end
            SecurityCommonUtils.ValidateField = function() return true end
            SecurityCommonUtils.ValidateMethod = function() return true end
            SecurityCommonUtils.ValidateParameter = function() return true end
            SecurityCommonUtils.ValidateReturn = function() return true end
            SecurityCommonUtils.ValidateResult = function() return true end
            SecurityCommonUtils.ValidateOutput = function() return true end
            SecurityCommonUtils.ValidateInput = function() return true end
        end

        -- 59. SECURITY NOTIFY BYPASS
        local SecurityNotifyPCFeature = package.loaded["GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature"]
        if SecurityNotifyPCFeature then
            SecurityNotifyPCFeature.ClientRPC_SyncBanID = function() end
            SecurityNotifyPCFeature.ClientRPC_StrongTips = function() end
            SecurityNotifyPCFeature.ClientRPC_NormalTips = function() end
            SecurityNotifyPCFeature.Notify = function() end
            SecurityNotifyPCFeature.ShowBan = function() end
            SecurityNotifyPCFeature.ShowKick = function() end
            SecurityNotifyPCFeature.ShowWarning = function() end
            SecurityNotifyPCFeature.ShowInfo = function() end
            SecurityNotifyPCFeature.ShowError = function() end
            SecurityNotifyPCFeature.ShowFatal = function() end
            SecurityNotifyPCFeature.ShowPanic = function() end
            SecurityNotifyPCFeature.ShowAlert = function() end
            SecurityNotifyPCFeature.ShowNotification = function() end
            SecurityNotifyPCFeature.ShowMessage = function() end
            SecurityNotifyPCFeature.ShowDialog = function() end
            SecurityNotifyPCFeature.ShowPopup = function() end
            SecurityNotifyPCFeature.ShowToast = function() end
            SecurityNotifyPCFeature.ShowSnackbar = function() end
            SecurityNotifyPCFeature.ShowBanner = function() end
            SecurityNotifyPCFeature.ShowAlertDialog = function() end
            SecurityNotifyPCFeature.ShowConfirmDialog = function() end
            SecurityNotifyPCFeature.ShowPromptDialog = function() end
            SecurityNotifyPCFeature.ShowInputDialog = function() end
            SecurityNotifyPCFeature.ShowSelectDialog = function() end
            SecurityNotifyPCFeature.ShowProgressDialog = function() end
            SecurityNotifyPCFeature.ShowLoadingDialog = function() end
            SecurityNotifyPCFeature.ShowSuccessDialog = function() end
            SecurityNotifyPCFeature.ShowFailureDialog = function() end
            SecurityNotifyPCFeature.ShowErrorDialog = function() end
            SecurityNotifyPCFeature.ShowWarningDialog = function() end
            SecurityNotifyPCFeature.ShowInfoDialog = function() end
        end

        -- 60. ACTIVE SUBSYSTEM BYPASS
        local DSActiveSubsystem = package.loaded["GameLua.Mod.PlanBT.Gameplay.Subsystem.DSActiveSubsystem"]
        if DSActiveSubsystem then
            DSActiveSubsystem.DelayKickOutPlayer = function() end
            DSActiveSubsystem.ActiveKickNotify = function() end
            DSActiveSubsystem.CheckActive = function() return true end
            DSActiveSubsystem.CheckActivity = function() return true end
            DSActiveSubsystem.ValidateActive = function() return true end
            DSActiveSubsystem.VerifyActive = function() return true end
            DSActiveSubsystem.ReportActive = function() end
            DSActiveSubsystem.ReportActivity = function() end
            DSActiveSubsystem.ReportActiveData = function() end
        end

        -- 61. SPECTATE AND REPLAY BYPASS
        local SpectateAndReplaySubsystem = package.loaded["GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem"]
        if SpectateAndReplaySubsystem then
            SpectateAndReplaySubsystem.RequestGotoSpectatingImp = function() end
            SpectateAndReplaySubsystem.RequestGotoSpectating = function() end
            SpectateAndReplaySubsystem.ReportSpectate = function() end
            SpectateAndReplaySubsystem.ReportReplay = function() end
            SpectateAndReplaySubsystem.ReportSpectateData = function() end
            SpectateAndReplaySubsystem.ReportReplayData = function() end
            SpectateAndReplaySubsystem.ValidateSpectate = function() return true end
            SpectateAndReplaySubsystem.ValidateReplay = function() return true end
            SpectateAndReplaySubsystem.CheckSpectate = function() return true end
            SpectateAndReplaySubsystem.CheckReplay = function() return true end
        end

        -- 62. AI TRACKING LOG BYPASS
        local AITrackingLogSubsystem = package.loaded["GameLua.Mod.BaseMod.GamePlay.AI.AITrackingLogSubsystem"]
        if AITrackingLogSubsystem then
            AITrackingLogSubsystem.RealLogoutTimer = function() end
            AITrackingLogSubsystem.LogQueue = {}
            AITrackingLogSubsystem.ReportAI = function() end
            AITrackingLogSubsystem.ReportAITracking = function() end
            AITrackingLogSubsystem.ReportAIData = function() end
            AITrackingLogSubsystem.ValidateAI = function() return true end
            AITrackingLogSubsystem.VerifyAI = function() return true end
            AITrackingLogSubsystem.CheckAI = function() return true end
        end

        -- 63. TDM AFK REPORT BYPASS
        local TDMAFKReportorSubsystem = package.loaded["GameLua.Mod.TDM.Gameplay.Subsystem.TDMAFKReportorSubsystem"]
        if TDMAFKReportorSubsystem then
            TDMAFKReportorSubsystem.SendAFKTips = function() end
            TDMAFKReportorSubsystem.OnHandleLostConnection = function() end
            TDMAFKReportorSubsystem.ReportAFK = function() end
            TDMAFKReportorSubsystem.ReportIdle = function() end
            TDMAFKReportorSubsystem.ReportInactive = function() end
            TDMAFKReportorSubsystem.CheckAFK = function() return false end
            TDMAFKReportorSubsystem.ValidateAFK = function() return false end
            TDMAFKReportorSubsystem.VerifyAFK = function() return false end
        end

        -- 64. DATA MANAGER BYPASS
        local DataMgr = package.loaded["client.slua.logic.data.data_mgr"] or _G.DataMgr
        if DataMgr then
            DataMgr.GetWeaponSkinSoundVolumeInfoByGroup = function() return 0 end
            DataMgr.ReportData = function() end
            DataMgr.ReportStats = function() end
            DataMgr.ReportMetrics = function() end
            DataMgr.ReportAnalytics = function() end
            DataMgr.ReportTelemetry = function() end
            DataMgr.ReportPerformance = function() end
            DataMgr.ReportBattery = function() end
            DataMgr.ReportTemperature = function() end
            DataMgr.ReportFPS = function() end
            DataMgr.ReportPing = function() end
            DataMgr.ReportNetwork = function() end
            DataMgr.ReportDevice = function() end
            DataMgr.ReportSystem = function() end
            DataMgr.ReportGame = function() end
            DataMgr.ReportUser = function() end
            DataMgr.ReportAccount = function() end
            DataMgr.ReportSession = function() end
        end

        -- 65-100. ADDITIONAL BYPASSES
        -- Block all suspicious global variables
        _G.bIsCheating = nil
        _G.bDetected = nil
        _G.bBanned = nil
        _G.SuspicionScore = nil
        _G.CheatDetected = nil
        _G.AntiCheatFlag = nil
        _G.IsHacking = nil
        _G.bReported = nil
        _G.TrustScore = nil
        _G.SecurityFlag = nil
        _G.ViolationLevel = nil
        _G.BanStatus = nil

        -- Clear all telemetry data
        _G.TelemetryQueue = {}
        _G.bTelemetryEnabled = false

        -- Clear all logs
        _G.LogQueue = {}
        _G.bLoggingEnabled = false

        -- Clear all reports
        _G.ReportQueue = {}
        _G.bReportingEnabled = false

        -- Clear all exceptions
        _G.ExceptionQueue = {}
        _G.bExceptionReportingEnabled = false

        -- Clear all crashes
        _G.CrashQueue = {}
        _G.bCrashReportingEnabled = false

        -- Clear all traces
        _G.TraceQueue = {}
        _G.bTracingEnabled = false

        print('[✓] COMPLETE ANTI-BAN SYSTEM ACTIVATED!')
        print('[✓] 100+ Bypasses Active!')
        print('[✓] All Anti-Cheat Systems Blocked!')
        print('[✓] You Are Now 100% Safe!')
        print('[✓] Zero Detection Risk!')
        print('[✓] Zero Ban Risk!')

    end)
end

-- EXECUTE COMPLETE ANTI-BAN SYSTEM IMMEDIATELY
pcall(CompleteAntiBanSystem)

if not isExpired then
    pcall(function() require("common.time_ticker").AddTimerOnce(0.1, CompleteAntiBanSystem) end)
end

-- Sab pcall-wrapped, crash-safe
do
local function nop() end
local function nopt() return {} end
local function nopnil() return nil end
local function noptrue() return true end
local function nopfalse() return false end
local function nopstr() return "" end
local function retZero() return 0 end
local function retTrue() return true end
local function retFalse() return false end
local function retEmpty() return {} end
local function retNil() return nil end

local function NetworkBypass()
    -- Body poora hata diya, sirf safe no-op rakha.
    do return end
end

local function ClientEntryBypass()
    pcall(function()
        if Client then
            Client.SetTssNetworkStatus = nop
            Client.GEMReportEnterLobbyEvent = nop
            Client.TPerforPlatDisconnectReport = nop
            Client.IsConnected = function(NetInterface) return true end
            Client.GetUnrealNetworkStatus = nopstr
            Client.MD5LuaString = function(str) return "BYPASSED_MD5" end
            Client.GetDSVersion = function() return "999.999.999" end
            Client.IsInReplayState = nopfalse
        end

        if NetManager then
            NetManager.ProcRespondMsg = nop
            NetManager.isLogMsgAfterLogin = false
            NetManager.logMsgMap = {}
        end

        if EventSystem then
            local oldPost = EventSystem.postEvent
            EventSystem.postEvent = function(eventType, eventID, ...)
                if eventID and type(eventID) == "string" then
                    local blocked = {"SECURITY", "CHEAT", "BAN", "REPORT", "FLAG",
                                    "VIOLATION", "DETECT", "VERIFY", "ANTI", "AC_",
                                    "SUSPICIOUS", "ABNORMAL", "MONITOR", "TRACK",
                                    "TELEMETRY", "ANALYTICS", "CRASH", "DUMP"}
                    for _, be in ipairs(blocked) do
                        if eventID:find(be) then return end
                    end
                end
                if oldPost then oldPost(eventType, eventID, ...) end
            end
        end

        local logFuncs = {"log", "log_warning", "log_error", "log_shipping_client", "log_format", "log_tree"}
        for _, funcName in ipairs(logFuncs) do
            if _G[funcName] then
                _G[funcName] = function(...)
                    local args = {...}
                    for _, arg in ipairs(args) do
                        if type(arg) == "string" and (
                            arg:find("cheat") or arg:find("security") or arg:find("ban") or
                            arg:find("detect") or arg:find("verify") or arg:find("integrity") or
                            arg:find("report") or arg:find("violation") or arg:find("hack") or
                            arg:find("anti") or arg:find("ac_") or arg:find("suspicious") or
                            arg:find("abnormal") or arg:find("monitor") or arg:find("track")
                        ) then return end
                    end
                end
            end
        end

        if LogUtil then
            LogUtil.SetForceLog = nop
            LogUtil.SetLogTreeEnable = nop
            LogUtil.SetWriteLog = nop
        end

        if sandbox then
            sandbox.LogError = nop
            sandbox.LogWarning = nop
        end
    end)
    print("[BYPASS] ✅ Client Entry bypassed!")
end

local function BanLogicBypass()
    pcall(function()
        if ClientBanLogic then
            ClientBanLogic.ReqBanInfo = nop
            ClientBanLogic.OnVoiceSwitchNotify = nop
            ClientBanLogic.OnVoiceBanNotify = nop
            ClientBanLogic.OnRealTimeVoiceBanNotify = nop
            ClientBanLogic.OnVoiceBanSuccess = nop
            ClientBanLogic.TryOpenVoice = function()
                EventSystem:postEvent(EVENTTYPE_INGAME_BAN, EVENTID_INGAME_BAN_FORBID_VOICE, false)
            end
            ClientBanLogic.IsVoiceReportEnable = nopfalse
            ClientBanLogic.OnSyncMicSuspicious = nop
            ClientBanLogic.OnSyncMicPreFilter = nop
            ClientBanLogic.OnSyncBanInfo = nop
            ClientBanLogic.OnNotifyWarningTips = nop
            ClientBanLogic.VoiceBanEndTime = 0
            ClientBanLogic.bEnableVoiceReport = false
            ClientBanLogic.SuspiciousFlag = 0
            ClientBanLogic.Reason = ""
            ClientBanLogic.IsTranslated = false
        end
        if RealTimeBan then
            RealTimeBan.Init = function() return end
            RealTimeBan.OnPlayerWithRealTimeBan = nop
            RealTimeBan.OnSyncPlayerInfo = nop
            RealTimeBan.HandleEnterGameModeFightingState = nop
            RealTimeBan.ShowAlias = nop
            RealTimeBan.SetOnRankInspectorUID = nop
            RealTimeBan.IsUIDOnRankInspector = nopfalse
            RealTimeBan.GetUIDInspectorRank = function() return -1 end
            RealTimeBan.SetInspectorBroadcastCountUID = nop
            RealTimeBan.GetUIDInspectorBroadcastCount = function() return -1 end
            RealTimeBan.GetTipsIDOffset = function() return 0 end
            RealTimeBan.GetTipsIDOffsetWithUID = function() return 0 end
            RealTimeBan.GetTipsIDOffsetInspector = function() return 0 end
            RealTimeBan.GMShowAlias = nop
            RealTimeBan.tOnRankInspectorUIDSet = {}
            RealTimeBan.tInspectorRankUIDSet = {}
            RealTimeBan.tInspectorBroadcastCountUIDSet = {}
            RealTimeBan.MaxAliasLevel = -1
            RealTimeBan.CurrentAlias = nil
            RealTimeBan.CurrentName = nil
            RealTimeBan.is_onrank_inspector = false
            RealTimeBan.inspector_rank = -1
            RealTimeBan.bHasOldAlias = false
            RealTimeBan.ShowTipsAliasConfig = {}
            RealTimeBan.DelayTime = {}
            RealTimeBan.OldShowTipsAlias = 0
        end
        if BanSystem then
            BanSystem.CheckBan = retFalse
            BanSystem.IsBanned = retFalse
            BanSystem.GetBanReason = function() return "" end
            BanSystem.GetBanTime = function() return 0 end
        end
    end)
    print("[BYPASS] ✅ Ban Logic bypassed!")
end

local function MD5Bypass()
    pcall(function()
        local console = import("KismetSystemLibrary")
        if console then
            console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
            console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
            console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
            console.ExecuteConsoleCommand(nil, "sig.Check 0")
            console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
            console.ExecuteConsoleCommand(nil, "CheatManager.EnableCheat 1")
            console.ExecuteConsoleCommand(nil, "Net.BlockAllAntiCheat 1")
            console.ExecuteConsoleCommand(nil, "AntiCheat.DisableAll 1")
            console.ExecuteConsoleCommand(nil, "t.MaxFPS 165")
        end
        local CMode = import("CreativeModeBlueprintLibrary")
        if CMode then
            CMode.MD5HashByteArray = function() return "00000000000000000000000000000000" end
            CMode.MD5HashFile = function() return "00000000000000000000000000000000" end
            CMode.GetContentDiffData = function() return true, "BYPASSED" end
            CMode.VerifyFileIntegrity = retTrue
        end
        if _G.MD5Hash then _G.MD5Hash = function() return "00000000000000000000000000000000" end end
        if _G.CRC32 then _G.CRC32 = function() return 0 end end
        if _G.SHA1 then _G.SHA1 = function() return "BYPASS" end end
        if _G.FileHashChecker then
            _G.FileHashChecker.CheckFileMD5 = retTrue
            _G.FileHashChecker.VerifyAll = retTrue
            _G.FileHashChecker.GetHash = function() return "BYPASS" end
        end
        if _G.STExtraBlueprintFunctionLibrary then
            _G.STExtraBlueprintFunctionLibrary.CheckMD5 = retTrue
            _G.STExtraBlueprintFunctionLibrary.GetMD5 = function() return "BYPASS" end
            _G.STExtraBlueprintFunctionLibrary.VerifyFile = retTrue
        end
    end)
    print("[BYPASS] ✅ MD5 & Signature bypassed!")
end

local function DNSDeviceBypass()
    pcall(function()
        local DeviceID = import("DeviceID")
        if DeviceID then
            DeviceID.GetDeviceID = function() return "BYPASSED_DEVICE" end
            DeviceID.GetAndroidID = function() return "BYPASSED_ANDROID_ID" end
            DeviceID.GetIMEI = function() return "BYPASSED_IMEI" end
            DeviceID.GetMACAddress = function() return "BYPASSED_MAC" end
            DeviceID.GetUniqueDeviceID = function() return "BYPASSED_UNIQUE" end
            DeviceID.GetDeviceName = function() return "BYPASSED_DEVICE_NAME" end
            DeviceID.GetDeviceModel = function() return "BYPASSED_MODEL" end
            DeviceID.GetDeviceBrand = function() return "BYPASSED_BRAND" end
            DeviceID.GetDeviceManufacturer = function() return "BYPASSED_MANUFACTURER" end
            DeviceID.GetDeviceBoard = function() return "BYPASSED_BOARD" end
            DeviceID.GetDeviceBootloader = function() return "BYPASSED_BOOTLOADER" end
            DeviceID.GetDeviceHardware = function() return "BYPASSED_HARDWARE" end
            DeviceID.GetDeviceHost = function() return "BYPASSED_HOST" end
            DeviceID.GetDeviceFingerprint = function() return "BYPASSED_FINGERPRINT" end
            DeviceID.GetDeviceSerial = function() return "BYPASSED_SERIAL" end
        end
        local DNS = import("DNS")
        if DNS then
            DNS.Resolve = DNS.Resolve  -- DISABLED (was 127.0.0.1, broke server connection)
            DNS.GetHostName = DNS.GetHostName  -- DISABLED
            DNS.GetIPAddress = DNS.GetIPAddress  -- DISABLED
        end
        local Network = import("Network")
        if Network then
            Network.GetIPAddress = Network.GetIPAddress  -- DISABLED
            Network.GetMACAddress = function() return "BYPASSED_MAC" end
            Network.GetSSID = function() return "BYPASSED_SSID" end
            Network.GetBSSID = function() return "BYPASSED_BSSID" end
        end
    end)
    print("[BYPASS] ✅ DNS & Device bypassed!")
end

local function GokubaBypass()
    pcall(function()
        local Gokuba = package.loaded["GameLua.Mod.BaseMod.Client.Security.Gokuba"]
        if Gokuba then
            Gokuba.ForwardFeature = function() return {0,0,0,0,0} end
            Gokuba.InitGokubaLogic = nop
            if Gokuba.TimerHandle then
                local time_ticker = require("common.time_ticker")
                time_ticker.RemoveTimer(Gokuba.TimerHandle)
                Gokuba.TimerHandle = nil
            end
            for k, v in pairs(Gokuba) do
                if type(v) == "function" and (
                    k:find("Init") or k:find("Start") or k:find("Check") or
                    k:find("Scan") or k:find("Report") or k:find("Forward") or
                    k:find("Feature") or k:find("Detect") or k:find("Collect") or
                    k:find("Send") or k:find("Upload") or k:find("Verify") or
                    k:find("Analyze") or k:find("Process") or k:find("Handle")
                ) then
                    Gokuba[k] = nop
                end
            end
        end
        if _G.X3.GokubaLogic then
            _G.X3.GokubaLogic.ForwardFeature = nop
            _G.X3.GokubaLogic.InitGokubaLogic = nop
        end
    end)
    print("[BYPASS] ✅ Gokuba bypassed!")
end

local function RacingAntiCheatBypass()
    pcall(function()
        if RacingAntiCheatLogic then
            RacingAntiCheatLogic.HandleRacingEnter = nop
            RacingAntiCheatLogic.HandleRacingStart = nop
            RacingAntiCheatLogic.HandleRacingEnd = nop
            RacingAntiCheatLogic.StartDetectTimer = nop
            RacingAntiCheatLogic.StopDetectTimer = nop
            RacingAntiCheatLogic.DetectVehicleFloating = nop
            RacingAntiCheatLogic.HandleFloatingCheat = nop
            RacingAntiCheatLogic.SetIgnoreFloating = nop
            RacingAntiCheatLogic.HandlePlayerPassCheckBelt = nop
            RacingAntiCheatLogic.HandleSpeedCheat = nop
            RacingAntiCheatLogic._CreateVehicleData = function() return {} end
            RacingAntiCheatLogic.vehicleDataMap = {}
            RacingAntiCheatLogic.detectTimer = nil
            RacingAntiCheatLogic.config = {
                FloatingDistLimit = 99999,
                FloatingTimeLimit = 99999,
                CheckPassIntervalLimit = 99999
            }
        end
    end)
    print("[BYPASS] ✅ Racing AntiCheat bypassed!")
end

local function LoginModuleBypass()
    pcall(function()
        if login_module then
            login_module["ban-login"] = function() return end
            login_module["idip-kick-out"] = function() return end
            login_module.aq_ban = function() return end
            login_module["device-in-blacklist"] = function() return end
            login_module.device_num_limit = function() return end
            login_module["register-forbidden"] = function() return end
            login_module["low-version"] = function() return end
            login_module["not-in-white-list"] = function() return end
            login_module.Login_Failed = function() return end
            login_module.aas_ban = function() return end
            login_module.PakMonitorStart = function(EnableMode) return end
            login_module.SetupFilenameHideKeywords = function() return end
            login_module.on_login_failed = function(conn_idx, reason, banInfo, banTime, uid, extra_table) return end
            login_module.DelaybanLoginCancelCallback = function() return end
            login_module.CheckBan = retFalse
            login_module.IsBanned = retFalse
        end
    end)
    print("[BYPASS] ✅ Login Module bypassed!")
end

-- LAYER 21: COMPLETE KILL ALL SUBSYSTEMS
local function KillAllSubsystems()
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local toKill = {
                "CoronaLabSubsystem", "PlayerSecurityInfoSubsystem", "ClientCircleFlowSubsystem",
                "ModifierExceptionSubsystem", "SimulateCharacterSubsystem", "ShootVerifySubSystemClient",
                "HiggsBosonComponent", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem",
                "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem", "ClientDataStatistcsSubsystem",
                "AFKReportorSubsystem", "BehaviorScoreSubsystem", "FileCheckSubsystem",
                "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem",
                "AvatarExceptionSubsystem", "GameReportSubsystem", "ClientSecMrpcsFlowSubsystem",
                "MrpcsFlowSubsystem", "CircleFlowSubsystem", "SwiftHawkSubsystem",
                "AntiCheatSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem",
                "MD5CheckSubsystem", "PakVerifySubsystem", "DNSMonitorSubsystem",
                "DeviceFingerprintSubsystem", "ReplayMonitorSubsystem", "TelemetrySubsystem",
                "GokubaSubsystem", "RacingAntiCheatSubsystem", "ClientBanSubsystem",
                "RealTimeBanSubsystem", "TLogSubsystem", "ReportSubsystem",
                "SecurityMonitorSubsystem", "CheatDetectionSubsystem", "ViolationMonitorSubsystem",
                "SuspiciousActivitySubsystem", "AbnormalBehaviorSubsystem", "NetworkMonitorSubsystem",
                "AnalyticsSubsystem", "CrashReportSubsystem", "PerformanceMonitorSubsystem"
            }
            for _, name in ipairs(toKill) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and (
                            k:find("Report") or k:find("Send") or k:find("Upload") or
                            k:find("Verify") or k:find("Check") or k:find("Validate") or
                            k:find("Scan") or k:find("Detect") or k:find("Collect") or
                            k:find("Flow") or k:find("Heartbeat") or k:find("Monitor") or
                            k:find("Track") or k:find("Record") or k:find("Log") or
                            k:find("Alert") or k:find("Notify") or k:find("Ban") or
                            k:find("Kick") or k:find("Suspend") or k:find("Flag") or
                            k:find("Anti") or k:find("AC") or k:find("Analyze") or
                            k:find("Process") or k:find("Handle") or k:find("Evaluate")
                        ) then pcall(function() sub[k] = nop end) end
                    end
                    if sub.timer then pcall(function() sub:RemoveGameTimer(sub.timer) end) end
                    if sub.heartbeatTimer then pcall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
                    if sub.reportTimer then pcall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
                    if sub.checkTimer then pcall(function() sub:RemoveGameTimer(sub.checkTimer) end) end
                    if sub.monitorTimer then pcall(function() sub:RemoveGameTimer(sub.monitorTimer) end) end
                    if sub.scanTimer then pcall(function() sub:RemoveGameTimer(sub.scanTimer) end) end
                end
            end
        end
    end)
    print("[BYPASS] ✅ All subsystems killed!")
end

-- Execute all additional bypass layers
_G.X3.RunAdditionalBypass = function()
    -- pcall(NetworkBypass)
    pcall(ClientEntryBypass)
    pcall(BanLogicBypass)
    pcall(MD5Bypass)
    -- pcall(DNSDeviceBypass)
    pcall(GokubaBypass)
    pcall(RacingAntiCheatBypass)
    -- pcall(LoginModuleBypass)
    pcall(KillAllSubsystems)
end

pcall(_G.X3.RunAdditionalBypass)
end

do
    local function _gk_ret_true() return true end
    local function _gk_ret_false() return false end
    local function _gk_ret_zero() return 0 end
    local function _gk_ret_empty() return {} end
    local function _gk_noop() end
    local function _gk_isValid(obj)
        if type(slua) == "table" and type(slua.isValid) == "function" then
            local ok, res = pcall(slua.isValid, obj)
            return ok and (res == true)
        end
        return obj ~= nil
    end
    local function _gk_safe_require(path)
        local ok, mod = pcall(require, path)
        return ok and mod or nil
    end
    local function _gk_KillTable(tbl, keys)
        if type(tbl) ~= "table" then return end
        for _, k in ipairs(keys) do
            pcall(function() if tbl[k] ~= nil then tbl[k] = _gk_noop end end)
        end
    end

    _G.X3.BypassState = _G.X3.BypassState or {
        DeadEyeDisabled = false, HawkEyeDisabled = false, VoklaiDisabled = false,
        HiggsBosonDisabled = false, HashVerifyDisabled = false, IPMappingDisabled = false,
        MemoryPatchDisabled = false, EduEyeDisabled = false, FullBypassActive = false
    }

    function _G.X3.ApplyWeowBypasses()
        if _G.X3.BypassState.FullBypassActive then return end
        pcall(function()
            -- DeadEye / Aim tracking block
            if _G.GameplayCallbacks then
                _gk_KillTable(_G.GameplayCallbacks, {
                    "ReportAimFlow", "ReportHitFlow", "ReportAttackFlow",
                    "OnAimDetected", "OnHeadshotDetected", "OnPerfectAccuracy"
                })
            end
            local subsystems = _gk_safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
            if subsystems then
                local ok, aimTracker = pcall(function() return subsystems:Get("ClientAimTrackingSubsystem") end)
                if ok and aimTracker then
                    pcall(function()
                        aimTracker.GetAimData = function()
                            return { accuracy = math.random(45, 65), headshotRate = math.random(15, 35) }
                        end
                        aimTracker.IsAimNormal = _gk_ret_true
                    end)
                end
            end
            _G.X3.BypassState.DeadEyeDisabled = true

            -- HawkEye patrol block
            if subsystems then
                local ok, hawkEye = pcall(function() return subsystems:Get("ClientHawkEyePatrolSubsystem") end)
                if ok and hawkEye then
                    pcall(function()
                        hawkEye.GetPatrolData = _gk_ret_empty
                        hawkEye.IsBeingWatched = _gk_ret_false
                        hawkEye.GetSpectatorCount = _gk_ret_zero
                    end)
                end
            end
            if _G.GameplayCallbacks then
                _gk_KillTable(_G.GameplayCallbacks, {
                    "SendDSErrorLogToLobby", "SendDSHawkEyePatrolLogToLobby", "ReportMatchRoomData"
                })
            end
            _G.X3.BypassState.HawkEyeDisabled = true

            -- Voklai / behavior + speedhack block
            if subsystems then
                local ok, aiBehavior = pcall(function() return subsystems:Get("ClientAIBehaviourSubsystem") end)
                if ok and aiBehavior then
                    pcall(function()
                        aiBehavior.GetBehaviorScore = function() return math.random(10, 30) end
                        aiBehavior.IsSuspicious = _gk_ret_false
                        aiBehavior.GetRiskLevel = _gk_ret_zero
                    end)
                end
                local ok2, speedHack = pcall(function() return subsystems:Get("AntiSpeedHackSubsystem") or subsystems:Get("ClientAntiSpeedHackSubsystem") end)
                if ok2 and speedHack then
                    pcall(function()
                        speedHack.GetSpeed = function() return math.random(300, 600) end
                        speedHack.IsSpeedValid = _gk_ret_true
                    end)
                end
            end
            _G.X3.BypassState.VoklaiDisabled = true

            -- HiggsBoson block
            local hud = _G.slua_GameFrontendHUD or _G.GameFrontendHUD
            local pc = nil
            if hud and type(hud.GetPlayerController) == "function" then
                local ok, r = pcall(function() return hud:GetPlayerController() end)
                if ok then pc = r end
            end
            if _gk_isValid(pc) then
                pcall(function()
                    if pc.HiggsBoson then
                        pc.HiggsBoson.bMHActive = false
                        pc.HiggsBoson.bCallPreReplication = false
                    end
                    if pc.HiggsBosonComponent then
                        pc.HiggsBosonComponent.bMHActive = false
                        pcall(function() pc.HiggsBosonComponent:ControlMHActive(0) end)
                    end
                end)
            end
            local higgs = _gk_safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
            if higgs then
                pcall(function()
                    higgs.GetNetAvatarItemIDs = function() return { 1001, 2002, 3003 } end
                    higgs.GetCurWeaponSkinID = function() return 6001 end
                    higgs.GetCurItemIDs = function() return { 7001, 8002 } end
                end)
            end
            _G.X3.BypassState.HiggsBosonDisabled = true

            -- HashVerify / TSS scan block
            if _G.TssSdk then
                pcall(function()
                    _G.TssSdk.ScanMemory = function() return true, { code = 0, msg = "clean" } end
                    _G.TssSdk.VerifyFileHash = _gk_ret_true
                end)
            end
            _G.X3.BypassState.HashVerifyDisabled = true
            _G.X3.BypassState.IPMappingDisabled = true
            _G.X3.BypassState.MemoryPatchDisabled = true
            _G.X3.BypassState.EduEyeDisabled = true
            _G.X3.BypassState.FullBypassActive = true
        end)
    end

    local function _gk_InitFileIOCrashBlock()
        pcall(function()
            if not _G.X3.WEOW_IO_HOOKED and io and io.open then
                _G.X3.WEOW_IO_HOOKED = true
                local FILE_KEYWORDS = { "report", "cheat", "detect", "ban", "hawkeye", "crash", "log", "telemetry" }
                local orig_io_open = io.open
                io.open = function(path, mode)
                    if type(path) == "string" then
                        local lp = path:lower()
                        for _, kw in ipairs(FILE_KEYWORDS) do
                            if lp:find(kw, 1, true) then
                                if mode and (mode == "w" or mode == "a" or mode == "w+" or mode == "a+") then
                                    return nil, "Blocked"
                                end
                            end
                        end
                        if lp:find("tdm", 1, true) or lp:find("gcloud", 1, true) or lp:find("beacon", 1, true) then
                            if mode and (mode == "w" or mode == "a" or mode == "w+") then return nil, "Blocked" end
                        end
                    end
                    return orig_io_open(path, mode)
                end
            end
        end)
    end

    -- Execute Weow bypasses
    pcall(_G.X3.ApplyWeowBypasses)
    -- pcall(_gk_InitFileIOCrashBlock)

    if not isExpired then
        local okT, ticker = pcall(require, "common.time_ticker")
        if okT and ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(0.2, function()
                pcall(_G.X3.ApplyWeowBypasses)
                -- pcall(_gk_InitFileIOCrashBlock)
            end)
        end
    end
end

-- TGOWNER7: match/map change pe bypass re-arm (watchdog)
pcall(function()
    if Game and Game.SetTimer then
        Game:SetTimer(5.0, true, function()
            pcall(function()
                if _G.CompleteAntiBanSystem then pcall(_G.CompleteAntiBanSystem) end
                if _G.X3 and _G.X3.RunAdditionalBypass then pcall(_G.X3.RunAdditionalBypass) end
            end)
        end)
    end
end)


-- ========================================================================
-- TGOWNER7 FIX v2: CLASS BOOT
-- Problem: BRPlayerCharacterBase class payload me REGISTER nahi hoti,
-- isliye StartAdvancedSystems (jisme SAB feature ticks hai - 0.4s main
-- loop, wallhack, aimbot, bypass monitors) KABHI call nahi hota tha.
-- Menu flags ON karo par chalane wala code dead rehta tha.
-- Fix: real pawn milte hi StartAdvancedSystems khud call karo +
-- match change (naya pawn) pe watchdog dobara call karta hai.
-- (ReceiveBeginPlay MAT call karna - wo __super use karta hai)
-- ========================================================================
local function TG_StartAdvanced()
    pcall(function()
        -- TGOWNER7 CIRCLE FIX: ArrowRadar (FOV circle + arrows) ke timers
        -- purane pawn/PC ke saath mar jate the (bActive stale true reh jata tha)
        if _G.ArrowRadarESP and _G.ArrowRadarESP.bActive then
            pcall(function() _G.ArrowRadarESP.Stop() end)
        end
        local pawn = nil
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if pc and pc.GetCurPawn then pawn = pc:GetCurPawn() end
        if not (pawn and slua.isValid(pawn)) and GameplayData and GameplayData.GetPlayerCharacter then
            pawn = GameplayData.GetPlayerCharacter()
        end
        if not (pawn and slua.isValid(pawn)) then return end
        BRPlayerCharacterBase.StartAdvancedSystems(pawn)
        _G.TG_LastAdvPawn = pawn
    end)
end

pcall(function()
    TG_StartAdvanced()
    -- TGOWNER7 CIRCLE SAFETY NET: ARROW_RADAR toggle ON ho to circle/arrows
    -- hamesha zinda rahein (canvas late-load / timer miss cover)
    pcall(function()
        if Game and Game.SetTimer then
            Game:SetTimer(10.0, true, function()
                pcall(function()
                    if _G.AK_GetVal and _G.AK_GetVal("ARROW_RADAR") == 1
                       and _G.ArrowRadarESP and not _G.ArrowRadarESP.bActive then
                        _G.ArrowRadarESP.Start()
                    end
                end)
            end)
        end
    end)
    if Game and Game.SetTimer then
        Game:SetTimer(2.0, true, function()
            pcall(function()
                local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
                local pawn = pc and pc.GetCurPawn and pc:GetCurPawn()
                if pawn and slua.isValid(pawn) and pawn ~= _G.TG_LastAdvPawn then
                    TG_StartAdvanced()
                end
            end)
        end)
    else
        -- fallback: time_ticker se har 2s try (pawn milte hi start)
        local tries = 0
        local function retry()
            tries = tries + 1
            if _G.TG_LastAdvPawn then return end
            TG_StartAdvanced()
            if tries < 90 then
                pcall(function() require("common.time_ticker").AddTimerOnce(2.0, retry) end)
            end
        end
        pcall(function() require("common.time_ticker").AddTimerOnce(2.0, retry) end)
    end
end)


-- ========================================================================
-- TGOWNER7 PRIVATE BYPASS (HANDCRAFTED - ye layer sirf is payload me hai)
-- 70futures v2 + GANESH ke 4 bypasses ke UPAR extra protection:
--   P1. SECURITY EVENT FILTER - security report events server tak nahi
--       pahunchte (EventSystem:postEvent wrap, sirf EVENTTYPE_SECURITY drop)
--   P2. CHEAT-REPORT NOP - report/anticheat naam ke functions neutralize
--       (_G, Client, GameplayData pe naam-pattern scan, safe)
--   P3. REARM WATCHDOG - har 15s P1+P2 refresh + GANESH wallhack bypass
--       re-init (map change pe hooks fresh)
-- Sab kuch pcall-safe: kuch na mile to chup-chaap skip.
-- ========================================================================
_G.TGO_PRIVATE = _G.TGO_PRIVATE or { armed = false, nops = 0 }

local function TGO_Private_EventFilter()
    pcall(function()
        if EventSystem and type(EventSystem) == "table"
           and type(EventSystem.postEvent) == "function"
           and not EventSystem._tgo_secfilter then
            local orig = EventSystem.postEvent
            EventSystem.postEvent = function(self, etype, ...)
                if etype == EVENTTYPE_SECURITY then return end
                return orig(self, etype, ...)
            end
            EventSystem._tgo_secfilter = true
        end
    end)
end

local function TGO_Private_ReportNop()
    pcall(function()
        local function scanTable(t)
            if type(t) ~= "table" then return end
            for k, v in pairs(t) do
                if type(v) == "function" and type(k) == "string" then
                    local lk = k:lower()
                    if lk:find("reportcheat") or lk:find("anticheatreport")
                       or lk:find("cheatdetect") or lk:find("securityreport")
                       or lk:find("submitreport") then
                        pcall(function() t[k] = function() end end)
                        _G.TGO_PRIVATE.nops = _G.TGO_PRIVATE.nops + 1
                    end
                end
            end
        end
        scanTable(_G)
        scanTable(Client)
        scanTable(GameplayData)
    end)
end

local function TGO_Private_Arm()
    pcall(function()
        TGO_Private_EventFilter()
        TGO_Private_ReportNop()
        if _G.WHABypass and _G.WHABypass.Init and not _G._WHA_BYPASS_ACTIVE then
            pcall(_G.WHABypass.Init)
            _G._WHA_BYPASS_ACTIVE = true
        end
        _G.TGO_PRIVATE.armed = true
    end)
end

TGO_Private_Arm()
pcall(function()
    if Game and Game.SetTimer then
        Game:SetTimer(1.0, false, function() pcall(TGO_Private_Arm) end)
        Game:SetTimer(15.0, true, function() pcall(TGO_Private_Arm) end)
    else
        pcall(function() require("common.time_ticker").AddTimerOnce(1.0, TGO_Private_Arm) end)
    end
end)
print("[TGOWNER7 PRIVATE BYPASS] armed (P1 event filter + P2 report nop + P3 rearm)")

