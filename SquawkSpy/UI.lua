--[[ The Spy windows: main list, alert popup, target KoS button, map notes.

	Geometry, textures and colours follow the original Spy exactly so the addon
	looks the same on screen.
]]

local SquawkSpy = SquawkSpy
local UI = {}
SquawkSpy.UI = UI

local MEDIA = "Interface\\AddOns\\SquawkSpy\\Textures\\"

-- The art in Textures\ belongs to the original Spy addon and is not shipped
-- with this one, so every file it would have used names a stock Blizzard
-- texture to fall back on.  Drop Spy's Textures folder in and you get Spy's
-- look; leave it out and the window still draws, just with the game's own art.
local FALLBACK = {
	["bar-flat.tga"]          = "Interface\\TargetingFrame\\UI-StatusBar",
	["button-highlight.tga"]  = "Interface\\Buttons\\ButtonHilight-Square",
	["button-left.tga"]       = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
	["button-right.tga"]      = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
	["button-clear.tga"]      = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
	["button-file.tga"]       = "Interface\\Icons\\INV_Misc_Note_01",
	["button-on.tga"]         = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
	["button-off.tga"]        = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
	["resize-bottomright.tga"] = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
}

local function media(file)
	local path = MEDIA .. file
	if SquawkSpy:TextureExists(path) then return path end
	return FALLBACK[file] or path
end

local BAR_TEXTURE = media("bar-flat.tga")

local function classColor(class)
	return SquawkSpy.ClassColors[class] or SquawkSpy.ClassColors.UNKNOWN
end

-- ---------------------------------------------------------------------------
-- window chrome (Widgets.lua in the original)
-- ---------------------------------------------------------------------------

local function createWindow(name, title, height, width)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent)
	f:SetHeight(height)
	f:SetWidth(width)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)

	f:SetScript("OnMouseDown", function(self, button)
		if not SquawkSpy.db.Locked and button == "LeftButton" then
			self:StartMoving()
			self.isMoving = true
		end
	end)
	f:SetScript("OnMouseUp", function(self)
		if self.isMoving then
			self:StopMovingOrSizing()
			self.isMoving = false
			UI:SavePositions()
		end
	end)

	f.Background = f:CreateTexture(nil, "BACKGROUND")
	f.Background:SetTexture("Interface\\CHARACTERFRAME\\UI-Party-Background")
	f.Background:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -32)
	f.Background:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 2)
	local bg = SquawkSpy.db.Colors.Window.Background
	f.Background:SetVertexColor(bg.r, bg.g, bg.b, bg.a)

	f.TitleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.TitleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -11)
	f.TitleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -11)
	f.TitleBar:SetHeight(22)
	f.TitleBar:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 8,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	f.TitleBar:SetBackdropColor(0, 0, 0, 1)
	local border = SquawkSpy.db.Colors.Window.Title
	f.TitleBar:SetBackdropBorderColor(border.r, border.g, border.b, border.a)

	-- On the title bar, not the window: the bar is a child frame with an
	-- opaque backdrop, and a child draws over its parent's regions.
	f.Title = f.TitleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -16)
	f.Title:SetJustifyH("LEFT")
	f.Title:SetHeight(SquawkSpy.db.MainWindow.TextHeight)
	f.Title:SetText(title)
	local tc = SquawkSpy.db.Colors.Window.TitleText
	f.Title:SetTextColor(tc.r, tc.g, tc.b, tc.a)

	f.CloseButton = CreateFrame("Button", nil, f)
	f.CloseButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	f.CloseButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
	f.CloseButton:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	f.CloseButton:SetWidth(20)
	f.CloseButton:SetHeight(20)
	f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -12)
	f.CloseButton:SetScript("OnClick", function(self) self:GetParent():Hide() end)

	return f
end

local function toolButton(parent, texture, size, tooltip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetNormalTexture(media(texture))
	b:SetPushedTexture(media(texture))
	b:SetHighlightTexture(media("button-highlight.tga"))
	b:SetWidth(size)
	b:SetHeight(size)
	b:SetFrameLevel(parent:GetFrameLevel() + 2)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tooltip, 1, 0.82, 0, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", onClick)
	return b
end

-- ---------------------------------------------------------------------------
-- rows
-- ---------------------------------------------------------------------------

function UI:CreateRow(num)
	local window = UI.MainWindow
	if window.Rows[num] then return end

	-- A secure action button is the only way an addon may target a unit by
	-- name.  If the template is unavailable we still build the row; it just
	-- will not target on click.
	local ok, row = pcall(CreateFrame, "Button", "SquawkSpy_Bar" .. num, window, "SecureActionButtonTemplate")
	if not ok or not row then
		row = CreateFrame("Button", "SquawkSpy_Bar" .. num, window)
		row.insecure = true
	else
		row:SetAttribute("type1", "macro")
		row:SetAttribute("macrotext", "")
	end
	row:RegisterForClicks("AnyUp")

	row:SetPoint("TOPLEFT", window, "TOPLEFT", 2,
		-34 - (SquawkSpy.db.MainWindow.RowHeight + SquawkSpy.db.MainWindow.RowSpacing) * (num - 1))
	row:SetHeight(SquawkSpy.db.MainWindow.RowHeight)
	row:SetWidth(window:GetWidth() - 4)
	row.id = num

	row.StatusBar = CreateFrame("StatusBar", nil, row)
	row.StatusBar:SetAllPoints(row)
	row.StatusBar:SetStatusBarTexture(BAR_TEXTURE)
	row.StatusBar:SetStatusBarColor(0.5, 0.5, 0.5, 0.8)
	row.StatusBar:SetMinMaxValues(0, 100)
	row.StatusBar:SetValue(100)

	row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.Highlight:SetTexture("Interface\\CharacterFrame\\BarFill")
	row.Highlight:SetBlendMode("ADD")
	row.Highlight:SetAllPoints(row)

	row.LeftText = row.StatusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.LeftText:SetPoint("LEFT", row.StatusBar, "LEFT", 2, 0)
	row.LeftText:SetJustifyH("LEFT")
	row.LeftText:SetHeight(SquawkSpy.db.MainWindow.TextHeight)

	row.RightText = row.StatusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.RightText:SetPoint("RIGHT", row.StatusBar, "RIGHT", -2, 0)
	row.RightText:SetJustifyH("RIGHT")

	UI:SetRowFonts(row)

	row:SetScript("OnEnter", function(self) UI:ShowRowTooltip(self, true) end)
	row:SetScript("OnLeave", function(self) UI:ShowRowTooltip(self, false) end)
	if row.insecure then
		-- No secure template: the row can still open its menu, it just cannot
		-- target, because only secure code may call TargetUnit.
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" and self.Name then SquawkSpy.Menu:Open(self, self.Name) end
		end)
	else
		-- OnClick belongs to the secure handler; hook around it instead.
		row:SetScript("PreClick", function(self, button)
			if button == "LeftButton" and not InCombatLockdown() and self.Name then
				self:SetAttribute("macrotext", "/targetexact " .. self.Name)
			end
		end)
		row:SetScript("PostClick", function(self, button)
			if button == "RightButton" and self.Name then SquawkSpy.Menu:Open(self, self.Name) end
		end)
	end

	row:Hide()
	window.Rows[num] = row
end

function UI:SetRowFonts(row)
	local rh = SquawkSpy.db.MainWindow.RowHeight
	local file, _, flags = row.LeftText:GetFont()
	row.LeftText:SetFont(file, math.max(rh * 0.75, rh - 3), flags)
	row.RightText:SetFont(file, math.max(rh * 0.65, rh - 12), flags)
end

function UI:SetBar(num, name, desc, class, opacity)
	local row = UI.MainWindow.Rows[num]
	if not row then return end

	row.Name = name
	row.LeftText:SetText(name)
	row.RightText:SetText(desc)
	row.LeftText:SetWidth(row:GetWidth() - row.RightText:GetStringWidth() - 4)

	local c = classColor(class)
	row.StatusBar:SetStatusBarColor(c.r, c.g, c.b, (c.a or 0.6) * opacity)

	local t = SquawkSpy.db.Colors.BarText
	row.LeftText:SetTextColor(t.r, t.g, t.b, opacity)
	row.RightText:SetTextColor(t.r, t.g, t.b, opacity)
end

-- ---------------------------------------------------------------------------
-- main window
-- ---------------------------------------------------------------------------

function UI:Initialize()
	local pos = SquawkSpy.db.MainWindow.Position
	local window = createWindow("SquawkSpy_MainWindow", SquawkSpy.ListTypes[1][1], 34, pos.w or 160)
	UI.MainWindow = window

	window:SetResizable(true)
	if window.SetResizeBounds then
		pcall(window.SetResizeBounds, window, 90, 34, 300, 264)
	end
	-- Only a show/hide the player asked for changes the saved preference.  A
	-- zone-driven hide (a sanctuary, a filtered zone) must not, or the window
	-- never comes back after you walk into a city.
	window:SetScript("OnShow", function()
		if not UI.zoneDriven then SquawkSpy.db.MainWindowVis = true end
	end)
	window:SetScript("OnHide", function()
		if not UI.zoneDriven then SquawkSpy.db.MainWindowVis = false end
	end)

	window.TitleClick = CreateFrame("Frame", nil, window)
	window.TitleClick:SetAllPoints(window.Title)
	window.TitleClick:EnableMouse(true)
	window.TitleClick:EnableMouseWheel(true)
	window.TitleClick:SetScript("OnMouseDown", function(self, button)
		if not SquawkSpy.db.Locked and button == "LeftButton" then
			window:StartMoving()
			window.isMoving = true
		end
	end)
	window.TitleClick:SetScript("OnMouseUp", function()
		if window.isMoving then
			window:StopMovingOrSizing()
			window.isMoving = false
			UI:SavePositions()
		end
	end)
	window.TitleClick:SetScript("OnMouseWheel", function(_, delta)
		if not IsAltKeyDown() then return end
		if delta > 0 then UI:PrevMode() else UI:NextMode() end
	end)

	window.RightButton = toolButton(window, "button-right.tga", 16, "Next list", function() UI:NextMode() end)
	window.RightButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -23, -14.5)

	window.LeftButton = toolButton(window, "button-left.tga", 16, "Previous list", function() UI:PrevMode() end)
	window.LeftButton:SetPoint("RIGHT", window.RightButton, "LEFT", 0, 0)

	window.ClearButton = toolButton(window, "button-clear.tga", 16, "Clear the list", function() SquawkSpy:ClearList() end)
	window.ClearButton:SetPoint("RIGHT", window.LeftButton, "LEFT", 0, 0)

	window.StatsButton = toolButton(window, "button-file.tga", 12, "Statistics", function() SquawkSpy.Stats:Toggle() end)
	window.StatsButton:SetPoint("RIGHT", window.ClearButton, "LEFT", -4, 0)

	window.CountText = window.TitleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.CountText:SetPoint("RIGHT", window.StatsButton, "LEFT", -4, 0)
	window.CountText:SetFont("Fonts\\FRIZQT__.TTF", SquawkSpy.db.MainWindow.RowHeight * 0.85, "OUTLINE")
	window.CountText:SetJustifyH("RIGHT")
	window.CountText:SetText("|cFF0070DE0|r")

	-- resize grip
	window.Grip = CreateFrame("Button", nil, window)
	window.Grip:SetNormalTexture(media("resize-bottomright.tga"))
	window.Grip:SetHighlightTexture(media("resize-bottomright.tga"))
	window.Grip:SetWidth(16)
	window.Grip:SetHeight(16)
	window.Grip:SetAlpha(0)
	window.Grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)
	window.Grip:SetFrameLevel(window:GetFrameLevel() + 10)
	window.Grip:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
	window.Grip:SetScript("OnLeave", function(self) self:SetAlpha(0) end)
	window.Grip:SetScript("OnMouseDown", function(self, button)
		if not SquawkSpy.db.Locked and button == "LeftButton" then
			window.isResizing = true
			window:StartSizing("BOTTOMRIGHT")
		end
	end)
	window.Grip:SetScript("OnMouseUp", function()
		if window.isResizing then
			window:StopMovingOrSizing()
			window.isResizing = false
			UI:SavePositions()
			UI:ResizeMainWindow()
		end
	end)
	window:SetScript("OnSizeChanged", function() if window.isResizing then UI:ResizeMainWindow() end end)

	window.Rows = {}
	window.CurRows = 0
	for i = 1, SquawkSpy.db.ResizeSpyLimit do UI:CreateRow(i) end

	UI:CreateAlertWindow()
	UI:CreateKoSButton()
	UI:RestorePositions()
	UI:EnsureOnScreen()
	UI:SetCurrentList(SquawkSpy.db.CurrentList)

	if WorldMapFrame and WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnShow", function() UI:UpdateMapNotes() end)
	end

	if not SquawkSpy.db.MainWindowVis then window:Hide() end
end

function UI:RestorePositions()
	local pos = SquawkSpy.db.MainWindow.Position
	local window = UI.MainWindow
	window:ClearAllPoints()
	window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x or 4, pos.y or 740)
	window:SetWidth(pos.w or 160)
	window:SetHeight(math.max(pos.h or 34, 34))
	UI:ResizeMainWindow()

	local apos = SquawkSpy.db.AlertWindow.Position
	UI.AlertWindow:ClearAllPoints()
	UI.AlertWindow:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", apos.x or 750, apos.y or 750)
end

function UI:SavePositions()
	local window = UI.MainWindow
	local pos = SquawkSpy.db.MainWindow.Position
	pos.x, pos.y = window:GetLeft(), window:GetTop()
	pos.w, pos.h = window:GetWidth(), window:GetHeight()

	local apos = SquawkSpy.db.AlertWindow.Position
	apos.x, apos.y = UI.AlertWindow:GetLeft(), UI.AlertWindow:GetTop()
end

function UI:ResizeMainWindow()
	local window = UI.MainWindow
	local width = window:GetWidth() - 4
	window.Title:SetWidth(math.max(width - 75, 10))
	for _, row in pairs(window.Rows) do
		row:SetWidth(width)
	end
	UI:ManageBarsDisplayed()
end

function UI:ManageBarsDisplayed()
	local window = UI.MainWindow
	local detected = SquawkSpy.ListAmountDisplayed
	local rowPitch = SquawkSpy.db.MainWindow.RowHeight + SquawkSpy.db.MainWindow.RowSpacing
	local bars = math.floor((window:GetHeight() - 34) / rowPitch)
	if bars > detected then bars = detected end
	if bars > SquawkSpy.db.ResizeSpyLimit then bars = SquawkSpy.db.ResizeSpyLimit end
	window.CurRows = bars

	if InCombatLockdown() then return end
	for i, row in pairs(window.Rows) do
		if i <= bars then row:Show() else row:Hide() end
	end
end

function UI:AutomaticallyResize()
	if InCombatLockdown() then return end
	local detected = math.min(SquawkSpy.ListAmountDisplayed, SquawkSpy.db.ResizeSpyLimit)
	local rowPitch = SquawkSpy.db.MainWindow.RowHeight + SquawkSpy.db.MainWindow.RowSpacing
	UI.MainWindow:SetHeight(35 + detected * rowPitch)
end

function UI:RefreshCurrentList(detectedPlayer)
	local window = UI.MainWindow
	if not window then return end

	local mode = SquawkSpy.db.CurrentList or 1
	local manage = SquawkSpy.ListTypes[mode] and SquawkSpy.ListTypes[mode][2]
	if manage and SquawkSpy[manage] then SquawkSpy[manage](SquawkSpy) end

	window.CountText:SetText("|cFF0070DE" .. SquawkSpy:GetActiveCount() .. "|r")

	if not window:IsShown() then return end

	local button = 1
	for _, entry in ipairs(SquawkSpy.CurrentList) do
		if button > SquawkSpy.ButtonLimit then break end
		local name = entry.player
		local player = SquawkSpy:GetPlayer(name)
		local level, class, guild, opacity = "??", "UNKNOWN", "??", 1

		if player then
			if player.level then
				level = player.level
				if player.isGuess and tonumber(player.level) and tonumber(player.level) < 60 then
					level = level .. "+"
				end
			end
			class = player.class or "UNKNOWN"
			guild = player.guild or "??"
		end

		local description = ""
		local setting = SquawkSpy.db.DisplayListData
		if setting == "1NameLevelClass" then
			description = level .. " " .. (SquawkSpy.ClassNames[class] or "")
		elseif setting == "2NameLevelGuild" then
			description = level .. " " .. guild
		elseif setting == "3NameLevelOnly" then
			description = tostring(level)
		elseif setting == "5NameGuild" then
			description = guild
		end

		if mode == 1 and SquawkSpy.InactiveList[name] then opacity = 0.5 end

		UI:SetBar(button, name, description, class, opacity)
		SquawkSpy.ButtonName[button] = name
		button = button + 1
	end
	SquawkSpy.ListAmountDisplayed = button - 1

	if SquawkSpy.db.ResizeSpy then
		UI:AutomaticallyResize()
	end
	UI:ManageBarsDisplayed()
end

function UI:SetCurrentList(mode)
	if not mode or mode > #SquawkSpy.ListTypes or mode < 1 then mode = 1 end
	SquawkSpy.db.CurrentList = mode
	UI.MainWindow.Title:SetText(SquawkSpy.ListTypes[mode][1])
	UI:RefreshCurrentList()
end

function UI:NextMode()
	local mode = (SquawkSpy.db.CurrentList or 1) + 1
	if mode > #SquawkSpy.ListTypes then mode = 1 end
	UI:SetCurrentList(mode)
end

function UI:PrevMode()
	local mode = (SquawkSpy.db.CurrentList or 1) - 1
	if mode < 1 then mode = #SquawkSpy.ListTypes end
	UI:SetCurrentList(mode)
end

function UI:IsMainWindowShown()
	return UI.MainWindow and UI.MainWindow:IsShown()
end

function UI:ShowMainWindow(manual)
	if not UI.MainWindow then return end
	if manual then
		SquawkSpy.db.MainWindowVis = true
		UI:EnsureOnScreen()
	end
	UI.zoneDriven = not manual
	UI.MainWindow:Show()
	UI.zoneDriven = false
	UI:RefreshCurrentList()
end

function UI:HideMainWindow(manual)
	if not UI.MainWindow then return end
	if manual then SquawkSpy.db.MainWindowVis = false end
	UI.zoneDriven = not manual
	UI.MainWindow:Hide()
	UI.zoneDriven = false
end

-- A saved position from another resolution or UI scale can put the window past
-- the edge of the screen, which looks exactly like the addon not loading.
function UI:EnsureOnScreen()
	local pos = SquawkSpy.db.MainWindow.Position
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local x, y = pos.x or 4, pos.y or 740
	if x < 0 or x > width - 40 or y < 40 or y > height then
		pos.x, pos.y = 4, math.min(740, height - 20)
		UI:RestorePositions()
		SquawkSpy:Print("the window was off screen, so it has been moved back to the top left.")
	end
end

-- ---------------------------------------------------------------------------
-- tooltip
-- ---------------------------------------------------------------------------

function UI:ShowRowTooltip(row, show)
	if not show then GameTooltip:Hide() return end
	local name = row.Name
	if not name then return end
	local player = SquawkSpy:GetPlayer(name)

	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(name, 0.8, 0.3, 0.22, 1)
	if player then
		local class = SquawkSpy.ClassNames[player.class or ""] or "Unknown"
		local level = player.level or "??"
		if player.isGuess and player.level then level = level .. "+" end
		GameTooltip:AddLine(("Level %s %s"):format(tostring(level), class), 1, 1, 1, 1)
		if player.race then GameTooltip:AddLine(player.race, 1, 1, 1, 1) end
		if player.guild then GameTooltip:AddLine("<" .. player.guild .. ">", 1, 1, 1, 1) end
		if player.zone then
			GameTooltip:AddLine(player.zone .. (player.subZone and player.subZone ~= ""
				and (", " .. player.subZone) or ""), 1, 0.82, 0, 1)
		end
		if player.time then
			GameTooltip:AddLine(("Last seen %s ago"):format(SecondsToTime(time() - player.time)), 1, 0.82, 0, 1)
		end
		if player.source then GameTooltip:AddLine("Seen via " .. player.source, 0.6, 0.6, 0.6, 1) end

		local wins, loses = player.wins or 0, player.loses or 0
		if wins > 0 or loses > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddDoubleLine("Record",
				("|cff00ff00%d|r killed  -  |cffff0000%d|r deaths"):format(wins, loses),
				1, 0.82, 0, 1, 1, 1)
		end

		local encounters = player.encounters
		if encounters and #encounters > 0 then
			local shown = 0
			for i = #encounters, 1, -1 do
				if shown >= 3 then break end
				local entry = encounters[i]
				local won = entry.result == "win"
				GameTooltip:AddDoubleLine(
					(won and "|cff00ff00Won|r  " or "|cffff0000Lost|r ") .. SquawkSpy:EncounterLocation(entry),
					SecondsToTime(time() - (entry.time or time())) .. " ago",
					1, 1, 1, 0.7, 0.7, 0.7)
				shown = shown + 1
			end
			if #encounters > 3 then
				GameTooltip:AddLine(("...%d more, /spy stats for the full record"):format(#encounters - 3),
					0.5, 0.5, 0.5, 1)
			end
		end
	end
	local guildEntry = SquawkSpy.Guild and SquawkSpy.Guild:IsKoS(name)
	if guildEntry then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Guild Kill on Sight", 1, 0.5, 0, 1)
		if guildEntry.reason and guildEntry.reason ~= "" then
			GameTooltip:AddLine('"' .. guildEntry.reason .. '"', 1, 0.82, 0, 1, true)
		end
		GameTooltip:AddLine("added by " .. (guildEntry.addedBy or "?"), 0.6, 0.6, 0.6, 1)
	end

	local kos = SquawkSpy.data.KOSData[name]
	if kos then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Kill on Sight", 1, 0, 0, 1)
		local note = SquawkSpy:GetKoSNote(name)
		if note then GameTooltip:AddLine('"' .. note .. '"', 1, 0.82, 0, 1, true) end
		if kos.sound ~= nil then
			GameTooltip:AddLine("Alert sound: " .. SquawkSpy:AlertSoundLabel(kos.sound), 0.6, 0.6, 0.6, 1)
		end
	end
	GameTooltip:AddLine("Left-click to target, right-click for options.", 0.5, 0.5, 0.5, 1)
	GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- alert window
-- ---------------------------------------------------------------------------

local ALERTS = {
	kos = { icon = "Interface\\Icons\\Ability_Creature_Cursed_02", title = "Kill on Sight!",
		border = "KOSBorder", text = "KOSText", duration = 4 },
	stealth = { icon = "Interface\\Icons\\Ability_Stealth", title = "Stealthed enemy!",
		border = "StealthBorder", text = "StealthText", duration = 5 },
	nearby = { icon = "Interface\\Icons\\Ability_Hunter_SniperShot", title = "Enemy nearby",
		border = "NearbyBorder", text = "NearbyText", duration = 3 },
}

function UI:CreateAlertWindow()
	local f = CreateFrame("Frame", "SquawkSpy_AlertWindow", UIParent, "BackdropTemplate")
	UI.AlertWindow = f
	f:SetHeight(42)
	f:SetWidth(200)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 8,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	local bg = SquawkSpy.db.Colors.Alert.Background
	f:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)

	f:SetScript("OnMouseDown", function(self, button)
		if not SquawkSpy.db.Locked and button == "LeftButton" then
			self:StartMoving()
			self.isMoving = true
		end
	end)
	f:SetScript("OnMouseUp", function(self)
		if self.isMoving then
			self:StopMovingOrSizing()
			self.isMoving = false
			UI:SavePositions()
		end
	end)

	f.Icon = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.Icon:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -5)
	f.Icon:SetWidth(32)
	f.Icon:SetHeight(32)

	f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Title:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -3)
	f.Title:SetJustifyH("LEFT")

	f.Name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -15)
	f.Name:SetJustifyH("LEFT")
	local file, _, flags = f.Name:GetFont()
	f.Name:SetFont(file, SquawkSpy.db.AlertWindow.NameSize, flags)

	f.Location = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Location:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -26)
	f.Location:SetJustifyH("LEFT")
	f.Location:SetFont(file, SquawkSpy.db.AlertWindow.LocationSize, flags)

	-- fade in, hold, fade out -- the original's SquawkSpyrameFlash
	f.elapsed = 0
	f:SetScript("OnUpdate", function(self, delta)
		if not self.flashDuration then return end
		self.elapsed = self.elapsed + delta
		local remaining = self.flashDuration - self.elapsed
		if remaining <= 0 then
			self.flashDuration = nil
			self:Hide()
		elseif remaining < 1 then
			self:SetAlpha(remaining)
		else
			self:SetAlpha(1)
		end
	end)
	f:Hide()
end

function UI:ShowAlert(kind, name, source, location, note)
	local style = ALERTS[kind]
	local f = UI.AlertWindow
	if not style or not f then return end

	-- a Kill on Sight alert outranks anything already on screen
	if f.flashDuration and f.alertKind == "kos" and kind ~= "kos" then return end

	local colors = SquawkSpy.db.Colors.Alert
	f:SetBackdropBorderColor(colors[style.border].r, colors[style.border].g,
		colors[style.border].b, 1)
	f.Icon:SetBackdrop({ bgFile = style.icon })

	local tc = colors[style.text]
	f.Title:SetTextColor(tc.r, tc.g, tc.b, 1)
	f.Title:SetText(source and (style.title .. " (" .. source .. ")") or style.title)

	local nc = colors.NameText
	f.Name:SetTextColor(nc.r, nc.g, nc.b, 1)
	f.Name:SetText(name)

	local lc = colors.LocationText
	f.Location:SetTextColor(lc.r, lc.g, lc.b, 1)
	-- A note is the reason you flagged them, so it earns the line over the
	-- location, which is appended when there is room for both.
	if note and note ~= "" then
		f.Location:SetText(location and location ~= ""
			and (note .. "  -  " .. location) or note)
	else
		f.Location:SetText(location or "")
	end

	local width = math.max(f.Title:GetStringWidth(), f.Name:GetStringWidth(),
		f.Location:GetStringWidth()) + 52
	f:SetWidth(width)
	f.Name:SetWidth(width - 52)
	f.Location:SetWidth(width - 52)

	f.alertKind = kind
	f.elapsed = 0
	f.flashDuration = style.duration
	f:SetAlpha(1)
	f:Show()
end

-- ---------------------------------------------------------------------------
-- Kill on Sight button on the target frame
-- ---------------------------------------------------------------------------

function UI:CreateKoSButton()
	local b = CreateFrame("Button", "SquawkSpy_KoSButton", UIParent)
	UI.KoSButton = b
	b:SetWidth(22)
	b:SetHeight(22)
	b:SetFrameStrata("HIGH")
	if TargetFrame then
		b:SetPoint("TOPLEFT", TargetFrame, "TOPRIGHT", -20, -14)
	else
		b:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
	end
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetAllPoints(b)
	b.Icon:SetTexture(media("button-off.tga"))
	b:RegisterForClicks("AnyUp")
	b:SetScript("OnEnter", function(self)
		local name = UI:TargetName()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Kill on Sight", 1, 0.82, 0, 1)
		GameTooltip:AddLine("Left-click to add or remove your target.", 1, 1, 1, 1)
		GameTooltip:AddLine("Right-click to write a note.", 1, 1, 1, 1)
		local note = name and SquawkSpy:GetKoSNote(name)
		if note then GameTooltip:AddLine('"' .. note .. '"', 1, 0.82, 0, 1, true) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(_, button)
		local name = UI:TargetName()
		if not name then return end
		if button == "RightButton" then
			SquawkSpy:PromptKoSNote(name)
		elseif SquawkSpy:IsKoS(name) then
			SquawkSpy:RemoveKoS(name)
		else
			SquawkSpy:AddKoS(name)
		end
		UI:UpdateKoSButton()
	end)
	b:Hide()
end

function UI:TargetName()
	if not UnitExists("target") or not UnitIsPlayer("target") then return nil end
	local name, realm = UnitName("target")
	if not name then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

function UI:UpdateKoSButton()
	local b = UI.KoSButton
	if not b then return end
	if not SquawkSpy.db.ShowKoSButton then b:Hide() return end
	local name = UI:TargetName()
	if name and UnitIsEnemy("player", "target") then
		b.Icon:SetTexture(media(SquawkSpy:IsKoS(name) and "button-on.tga" or "button-off.tga"))
		b:Show()
	else
		b:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- world map notes
-- ---------------------------------------------------------------------------

UI.MapNotes = {}

function UI:AddMapNote(name)
	if not SquawkSpy.db.DisplayOnMap then return end
	local player = SquawkSpy:GetPlayer(name)
	if not player or not player.mapID or not player.x then return end
	UI.MapNotes[name] = { mapID = player.mapID, x = player.x, y = player.y, time = time() }
	UI:UpdateMapNotes()
end

function UI:UpdateMapNotes()
	if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
	local container = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
	if not container then return end

	UI.MapPins = UI.MapPins or {}
	local shownMap = WorldMapFrame:GetMapID()
	local index = 0
	local now = time()

	for name, note in pairs(UI.MapNotes) do
		if now - note.time > 600 then
			UI.MapNotes[name] = nil
		elseif note.mapID == shownMap then
			index = index + 1
			local pin = UI.MapPins[index]
			if not pin then
				pin = container:CreateTexture(nil, "OVERLAY")
				pin:SetTexture("Interface\\Minimap\\ObjectIcons")
				pin:SetTexCoord(0.125, 0.25, 0, 0.125)
				pin:SetWidth(14)
				pin:SetHeight(14)
				UI.MapPins[index] = pin
			end
			pin:SetParent(container)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", container, "TOPLEFT",
				note.x * container:GetWidth(), -note.y * container:GetHeight())
			pin:Show()
		end
	end

	for i = index + 1, #(UI.MapPins or {}) do
		UI.MapPins[i]:Hide()
	end
end

