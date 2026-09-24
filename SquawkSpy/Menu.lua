--[[ Right-click menu for a list row.

	Midnight replaced UIDropDownMenu with the Menu API and the old one may be
	gone entirely, so this uses whichever exists and falls back to a small
	self-contained menu frame if neither does.
]]

local SquawkSpy = SquawkSpy
local Menu = {}
SquawkSpy.Menu = Menu

local REASONS = {
	"Ganked me",
	"Ganked a guild member",
	"Ganked a friend",
	"Ninja looter",
	"Camping a quest area",
	"Just because",
}

-- The actions, built once per open so the menu reflects current state.
local function buildActions(name)
	local actions = {}
	local isKoS = SquawkSpy:IsKoS(name)

	if isKoS then
		actions[#actions + 1] = { text = "Remove from Kill on Sight",
			func = function() SquawkSpy:RemoveKoS(name) end }
	else
		actions[#actions + 1] = { text = "Add to Kill on Sight",
			func = function() SquawkSpy:AddKoS(name) end }
	end

	-- Type your own note.  Adds them to the list first if they are not on it.
	local note = SquawkSpy:GetKoSNote(name)
	actions[#actions + 1] = {
		text = note and "Edit note..." or "Add with a note...",
		func = function() SquawkSpy:PromptKoSNote(name) end,
	}

	local reasons = {}
	for _, reason in ipairs(REASONS) do
		reasons[#reasons + 1] = { text = reason, func = function() SquawkSpy:AddKoS(name, reason) end }
	end
	if note then
		reasons[#reasons + 1] = { text = "Clear the note", func = function() SquawkSpy:SetKoSNote(name, "") end }
	end
	actions[#actions + 1] = { text = "Quick note", submenu = reasons }

	-- Guild-wide: everyone in the guild running this sees it, note and all.
	local guildEntry = SquawkSpy.Guild and SquawkSpy.Guild:IsKoS(name)
	if guildEntry then
		actions[#actions + 1] = { text = "Remove from |cffff8000Guild|r Kill on Sight",
			func = function() SquawkSpy.Guild:Remove(name) end }
	else
		actions[#actions + 1] = { text = "Add to |cffff8000Guild|r Kill on Sight",
			func = function() SquawkSpy.Guild:Add(name) end }
	end
	actions[#actions + 1] = {
		text = guildEntry and "Edit guild note..." or "Add to guild with a note...",
		func = function() SquawkSpy:PromptGuildNote(name) end,
	}

	-- Per-player alert sound, so one particular name can have its own alarm.
	local sounds = { {
		text = "Use the default",
		func = function() SquawkSpy:SetKoSSound(name, nil) end,
	} }
	for _, entry in ipairs(SquawkSpy.AlertSoundChoices) do
		sounds[#sounds + 1] = {
			text = entry.label,
			func = function()
				if not SquawkSpy:IsKoS(name) then SquawkSpy:AddKoS(name) end
				SquawkSpy:SetKoSSound(name, entry.file)
			end,
		}
	end
	actions[#actions + 1] = { text = "Alert sound", submenu = sounds }

	actions[#actions + 1] = { separator = true }

	if SquawkSpy:IsIgnored(name) then
		actions[#actions + 1] = { text = "Stop ignoring", func = function() SquawkSpy:RemoveIgnore(name) end }
	else
		actions[#actions + 1] = { text = "Ignore this player", func = function() SquawkSpy:AddIgnore(name) end }
	end
	actions[#actions + 1] = { text = "Remove from list", func = function() SquawkSpy:RemovePlayerData(name) end }

	actions[#actions + 1] = { separator = true }

	local announce = {}
	for _, channel in ipairs({ "SAY", "PARTY", "GUILD", "YELL" }) do
		announce[#announce + 1] = { text = channel:sub(1, 1) .. channel:sub(2):lower(),
			func = function() Menu:Announce(name, channel) end }
	end
	actions[#actions + 1] = { text = "Announce", submenu = announce }
	actions[#actions + 1] = { text = "Who query", func = function()
		if C_FriendList and C_FriendList.SendWho then
			C_FriendList.SendWho(name)
		elseif SendWho then
			SendWho(name)
		end
	end }

	return actions
end

function Menu:Announce(name, channel)
	local player = SquawkSpy:GetPlayer(name)
	local level = player and player.level or "??"
	local class = player and SquawkSpy.ClassNames[player.class or ""] or ""
	local msg = ("Spy: %s (level %s %s) spotted at %s"):format(
		name, tostring(level), class, SquawkSpy:GetLocationText())
	if channel == "PARTY" and not (IsInGroup and IsInGroup()) then return end
	if channel == "GUILD" and not IsInGuild() then return end
	pcall(SendChatMessage, msg, channel)
end

-- ---------------------------------------------------------------------------
-- fallback menu frame
-- ---------------------------------------------------------------------------

local function ensureFallback()
	if Menu.Frame then return Menu.Frame end
	local f = CreateFrame("Frame", "SquawkSpy_Menu", UIParent, "BackdropTemplate")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 8,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	f:SetBackdropColor(0, 0, 0, 0.95)
	f:EnableMouse(true)
	f.Buttons = {}
	f:Hide()

	f:SetScript("OnShow", function(self)
		self.closer = self.closer or CreateFrame("Frame", nil, UIParent)
		self.closer:SetAllPoints(UIParent)
		self.closer:SetFrameStrata("FULLSCREEN")
		self.closer:EnableMouse(true)
		self.closer:SetScript("OnMouseDown", function() f:Hide() end)
		self.closer:Show()
	end)
	f:SetScript("OnHide", function(self)
		if self.closer then self.closer:Hide() end
		if Menu.SubFrame then Menu.SubFrame:Hide() end
	end)

	Menu.Frame = f
	return f
end

local function layoutFallback(frame, title, actions, anchorFrame, anchorX, anchorY)
	local width = 150
	local y = -8

	frame.TitleText = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.TitleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
	frame.TitleText:SetText(title)
	y = y - 18

	for _, button in ipairs(frame.Buttons) do button:Hide() end

	local index = 0
	for _, action in ipairs(actions) do
		if action.separator then
			y = y - 6
		else
			index = index + 1
			local b = frame.Buttons[index]
			if not b then
				b = CreateFrame("Button", nil, frame)
				b:SetHeight(16)
				b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				b.Text:SetPoint("LEFT", b, "LEFT", 4, 0)
				b.Text:SetJustifyH("LEFT")
				b.Highlight = b:CreateTexture(nil, "HIGHLIGHT")
				b.Highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
				b.Highlight:SetBlendMode("ADD")
				b.Highlight:SetAllPoints(b)
				frame.Buttons[index] = b
			end
			b:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, y)
			b:SetWidth(width - 12)
			b.Text:SetText(action.submenu and (action.text .. "  |cffffd100>|r") or action.text)
			b:SetScript("OnClick", function(self)
				if action.submenu then
					Menu:OpenFallback("", action.submenu, self, self:GetWidth(), 0, true)
				else
					frame:Hide()
					action.func()
				end
			end)
			b:Show()
			y = y - 16
		end
	end

	frame:SetWidth(width)
	frame:SetHeight(-y + 8)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", anchorX or 0, anchorY or 0)
	frame:Show()
end

function Menu:OpenFallback(title, actions, anchorFrame, x, y, isSub)
	if isSub then
		if not Menu.SubFrame then
			Menu.SubFrame = CreateFrame("Frame", "SquawkSpy_SubMenu", Menu.Frame, "BackdropTemplate")
			Menu.SubFrame:SetFrameStrata("FULLSCREEN_DIALOG")
			Menu.SubFrame:SetBackdrop(Menu.Frame:GetBackdrop())
			Menu.SubFrame:SetBackdropColor(0, 0, 0, 0.95)
			Menu.SubFrame:EnableMouse(true)
			Menu.SubFrame.Buttons = {}
		end
		layoutFallback(Menu.SubFrame, title, actions, anchorFrame, x, y)
	else
		layoutFallback(ensureFallback(), title, actions, anchorFrame, x, y)
	end
end

-- ---------------------------------------------------------------------------
-- entry point
-- ---------------------------------------------------------------------------

function Menu:Open(owner, name)
	local actions = buildActions(name)

	if SquawkSpy.Caps.menuUtil then
		local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
			root:CreateTitle(name)
			for _, action in ipairs(actions) do
				if action.separator then
					root:CreateDivider()
				elseif action.submenu then
					local sub = root:CreateButton(action.text)
					for _, entry in ipairs(action.submenu) do
						sub:CreateButton(entry.text, entry.func)
					end
				else
					root:CreateButton(action.text, action.func)
				end
			end
		end)
		if ok then return end
		SquawkSpy.Caps.menuUtil = false -- do not try again this session
	end

	Menu:OpenFallback(name, actions, owner, 0, 0)
end
