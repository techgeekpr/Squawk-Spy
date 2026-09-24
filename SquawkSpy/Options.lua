--[[ Options panel.  Registered with the Settings API when the client has one,
     otherwise shown as a standalone movable window. ]]

local SquawkSpy = SquawkSpy
local Options = {}
SquawkSpy.Options = Options

local CHECKBOXES = {
	{ column = 1, header = "General" },
	{ column = 1, key = "Enabled",                 text = "Enable Spy" },
	{ column = 1, key = "MainWindowVis",           text = "Show the Spy window" },
	{ column = 1, key = "Locked",                  text = "Lock windows in place" },
	{ column = 1, key = "ResizeSpy",               text = "Resize the window to fit the list" },
	{ column = 1, key = "PrioritiseKoS",           text = "Sort Kill on Sight players first" },
	{ column = 1, key = "ShowKoSButton",           text = "Kill on Sight button on the target frame" },
	{ column = 1, key = "DisplayOnMap",            text = "Show sightings on the world map" },

	{ column = 1, header = "Where Spy watches" },
	{ column = 1, key = "EnabledInBattlegrounds",  text = "Battlegrounds" },
	{ column = 1, key = "EnabledInArenas",         text = "Arenas" },
	{ column = 1, key = "EnabledInSanctuaries",    text = "Sanctuaries" },
	{ column = 1, key = "DisableWhenPVPUnflagged", text = "Sleep while you are not PvP flagged" },

	{ column = 2, header = "Detection" },
	{ column = 2, key = "DetectNameplates",        text = "Nameplates",
		tooltip = "The main source on this client. Enemy nameplates must be turned on (V toggles them)." },
	{ column = 2, key = "DetectTarget",            text = "Your target and focus" },
	{ column = 2, key = "DetectMouseover",         text = "Anything you mouse over" },
	{ column = 2, key = "DetectGroupTargets",      text = "What your party or raid is fighting" },
	{ column = 2, key = "DetectChat",              text = "Enemy say, yell and emotes",
		tooltip = "Faction is confirmed from the sender's GUID, so friendly players are never listed." },
	{ column = 2, key = "DetectComms",             text = "Sightings shared by other Spy users" },
	{ column = 2, key = "DetectCombatLog",         text = "Combat log",
		tooltip = "This client closes the combat log to addons; the option is here in case a future build re-opens it." },

	{ column = 2, header = "Alerts" },
	{ column = 2, key = "AlertOnKoS",              text = "Alert on Kill on Sight players" },
	{ column = 2, key = "AlertOnStealth",          text = "Alert on stealthed players" },
	{ column = 2, key = "AlertOnNearby",           text = "Alert on any enemy detected" },
	{ column = 2, key = "AlertSounds",             text = "Play alert sounds" },
	{ column = 2, key = "SoundOnDetection",        text = "Short blip on every player found",
		tooltip = "A single short sound whenever someone new appears, at most once every 1.2 seconds no matter how many arrive at once." },
	{ column = 2, key = "DisplayWarnings",         text = "Print warnings in the chat frame" },

	{ column = 2, header = "Guild Kill on Sight" },
	{ column = 2, key = "guildKoS",                text = "Alert on the guild list too",
		tooltip = "Anyone your guild has marked raises the same alert as your own list, with the note and who set it." },
	{ column = 2, key = "announceGuildKoS",        text = "Tell me when a guildmate marks someone",
		tooltip = "Prints a line when another guild member adds or clears a name. The list itself syncs either way." },
}

local LIST_DATA = {
	{ "1NameLevelClass", "Name, level and class" },
	{ "2NameLevelGuild", "Name, level and guild" },
	{ "3NameLevelOnly",  "Name and level" },
	{ "5NameGuild",      "Name and guild" },
}

local REMOVE_AFTER = { "Never", "30secs", "1min", "5mins", "10mins", "15mins" }

local function cycle(list, current)
	for i, entry in ipairs(list) do
		local value = type(entry) == "table" and entry[1] or entry
		if value == current then
			local nextEntry = list[i + 1] or list[1]
			return type(nextEntry) == "table" and nextEntry[1] or nextEntry
		end
	end
	local first = list[1]
	return type(first) == "table" and first[1] or first
end

local function label(list, value)
	for _, entry in ipairs(list) do
		if type(entry) == "table" then
			if entry[1] == value then return entry[2] end
		elseif entry == value then
			return entry
		end
	end
	return tostring(value)
end

function Options:Initialize()
	local panel = CreateFrame("Frame", "SquawkSpy_OptionsPanel", UIParent, "BackdropTemplate")
	Options.Panel = panel
	panel.name = "Spy"
	panel:SetWidth(620)
	panel:SetHeight(520)
	panel:Hide()

	panel.Title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	panel.Title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
	panel.Title:SetText("Squawk Spy " .. SquawkSpy.Version)

	panel.SubTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	panel.SubTitle:SetPoint("TOPLEFT", panel.Title, "BOTTOMLEFT", 0, -6)
	panel.SubTitle:SetJustifyH("LEFT")
	panel.SubTitle:SetWidth(580)
	panel.SubTitle:SetText("Detects and alerts you to the presence of nearby enemy players.")

	panel.Credit = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	panel.Credit:SetPoint("TOPLEFT", panel.SubTitle, "BOTTOMLEFT", 0, -4)
	panel.Credit:SetJustifyH("LEFT")
	panel.Credit:SetWidth(580)
	panel.Credit:SetText("|cffffd100Made by: Avoid Me|r |cff82c5ff<Squawk>|r|n"
		.. "|cff888888A re-work of the |rSpy|cff888888 addon by |rImmolation|cff888888 and |rSlipjack|cff888888, "
		.. "rebuilt for this client because Midnight closed the combat log Spy relied on.|n"
		.. "Artwork and sounds are theirs, read from your installed copy of Spy "
		.. "-- type |r/spy art|cff888888 to see what was found.|r")

	-- The credit runs to three lines, so the controls start below it.
	local y = { [1] = -104, [2] = -104 }
	local x = { [1] = 20, [2] = 330 }
	panel.Controls = {}

	for _, item in ipairs(CHECKBOXES) do
		local column = item.column
		if item.header then
			local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			header:SetPoint("TOPLEFT", panel, "TOPLEFT", x[column], y[column] - 6)
			header:SetText(item.header)
			y[column] = y[column] - 28
		else
			local check = CreateFrame("CheckButton", "SquawkSpy_Option_" .. item.key, panel, "UICheckButtonTemplate")
			check:SetPoint("TOPLEFT", panel, "TOPLEFT", x[column], y[column])
			check:SetWidth(22)
			check:SetHeight(22)
			local text = check.Text or _G[check:GetName() .. "Text"]
			if text then
				text:SetText(item.text)
				text:SetFontObject("GameFontHighlightSmall")
			end
			check.key = item.key
			check:SetScript("OnClick", function(self)
				SquawkSpy.db[self.key] = self:GetChecked() and true or false
				Options:Apply(self.key)
			end)
			if item.tooltip then
				check:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:AddLine(item.text, 1, 0.82, 0, 1)
					GameTooltip:AddLine(item.tooltip, 1, 1, 1, 1, true)
					GameTooltip:Show()
				end)
				check:SetScript("OnLeave", function() GameTooltip:Hide() end)
			end
			panel.Controls[#panel.Controls + 1] = check
			y[column] = y[column] - 24
		end
	end

	-- cycling buttons for the two list settings
	local function cycleButton(column, text, getter, onClick)
		local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		button:SetPoint("TOPLEFT", panel, "TOPLEFT", x[column], y[column] - 8)
		button:SetWidth(270)
		button:SetHeight(22)
		button.Label = text
		button.getter = getter
		button:SetScript("OnClick", function(self)
			onClick()
			self:SetText(self.Label .. ": " .. self.getter())
			SquawkSpy:RefreshCurrentList()
		end)
		button:SetText(text .. ": " .. getter())
		panel.Controls[#panel.Controls + 1] = button
		y[column] = y[column] - 30
		return button
	end

	cycleButton(1, "Bar text",
		function() return label(LIST_DATA, SquawkSpy.db.DisplayListData) end,
		function() SquawkSpy.db.DisplayListData = cycle(LIST_DATA, SquawkSpy.db.DisplayListData) end)

	cycleButton(2, "Kill on Sight sound",
		function() return SquawkSpy:AlertSoundLabel(SquawkSpy.db.AlertSoundKoS) end,
		function() SquawkSpy:CycleKoSSound() end)

	cycleButton(2, "Detection sound",
		function() return SquawkSpy:GetDetectionSound(SquawkSpy.db.DetectionSound).label end,
		function() SquawkSpy:CycleDetectionSound() end)

	cycleButton(1, "Forget players after",
		function() return label(REMOVE_AFTER, SquawkSpy.db.RemoveUndetected) end,
		function()
			SquawkSpy.db.RemoveUndetected = cycle(REMOVE_AFTER, SquawkSpy.db.RemoveUndetected)
			SquawkSpy:ApplyTimeouts()
		end)

	panel.Footer = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	panel.Footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 16)
	panel.Footer:SetJustifyH("LEFT")
	panel.Footer:SetWidth(580)
	panel.Footer:SetText("/spy toggles the window  -  /spy diag reports what this client allows  -  /spy stats opens statistics")

	panel:SetScript("OnShow", function() Options:Refresh() end)

	-- Register with whichever settings system this client has.
	if SquawkSpy.Caps.settings then
		local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Spy")
		if ok and category then
			category.ID = "Spy"
			Options.Category = category
			pcall(Settings.RegisterAddOnCategory, category)
			return
		end
	end
	if type(InterfaceOptions_AddCategory) == "function" then
		pcall(InterfaceOptions_AddCategory, panel)
		return
	end

	-- No settings system: make the panel a standalone window.
	Options.Standalone = true
	panel:SetParent(UIParent)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0, 0, 0, 0.92)
	panel:SetScript("OnMouseDown", function(self) self:StartMoving() end)
	panel:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

	local close = CreateFrame("Button", nil, panel)
	close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
	close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	close:SetWidth(20)
	close:SetHeight(20)
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() panel:Hide() end)
end

function Options:Refresh()
	for _, control in ipairs(Options.Panel.Controls) do
		if control.key then
			control:SetChecked(SquawkSpy.db[control.key] and true or false)
		elseif control.getter and control.Label then
			control:SetText(control.Label .. ": " .. control.getter())
		end
	end
end

function Options:Apply(key)
	if key == "MainWindowVis" then
		if SquawkSpy.db.MainWindowVis then SquawkSpy.UI:ShowMainWindow(true) else SquawkSpy.UI:HideMainWindow(true) end
	elseif key == "Enabled" or key == "EnabledInBattlegrounds" or key == "EnabledInArenas"
		or key == "EnabledInSanctuaries" or key == "DisableWhenPVPUnflagged" then
		SquawkSpy:ZoneChanged()
	elseif key == "ShowKoSButton" then
		SquawkSpy.UI:UpdateKoSButton()
	elseif key == "ResizeSpy" or key == "PrioritiseKoS" then
		SquawkSpy:RefreshCurrentList()
	end
end

function Options:Open()
	if not Options.Panel then
		SquawkSpy:Print("the options panel did not start on this client; use the slash commands instead.")
		return
	end
	if Options.Category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(Options.Category:GetID())
	elseif Options.Standalone then
		Options.Panel:Show()
		Options:Refresh()
	elseif type(InterfaceOptionsFrame_OpenToCategory) == "function" then
		InterfaceOptionsFrame_OpenToCategory(Options.Panel)
		InterfaceOptionsFrame_OpenToCategory(Options.Panel)
	else
		Options.Panel:Show()
	end
end
