--[[ The statistics window: every player this character has ever seen. ]]

local SquawkSpy = SquawkSpy
local Stats = {}
SquawkSpy.Stats = Stats

local ROWS = 18
local ROW_HEIGHT = 16
local COLUMN_GAP = 4
local MARGIN = 12
local HEADER_HEIGHT = 52   -- title, filter box and column headers
local FOOTER_HEIGHT = 28   -- the summary line, which needs its own space

local COLUMNS = {
	{ key = "name",   title = "Name",      width = 130, justify = "LEFT" },
	{ key = "level",  title = "Lvl",       width = 34,  justify = "RIGHT" },
	{ key = "class",  title = "Class",     width = 66,  justify = "LEFT" },
	{ key = "guild",  title = "Guild",     width = 120, justify = "LEFT" },
	{ key = "wins",   title = "W",         width = 26,  justify = "RIGHT" },
	{ key = "loses",  title = "L",         width = 26,  justify = "RIGHT" },
	{ key = "kos",    title = "Reason",    width = 110, justify = "LEFT" },
	{ key = "time",   title = "Last seen", width = 92,  justify = "RIGHT" },
}

-- Width the columns actually occupy, gaps included, so the window is sized
-- from the table rather than the table being guessed to fit the window.
local CONTENT_WIDTH = 0
for index, column in ipairs(COLUMNS) do
	CONTENT_WIDTH = CONTENT_WIDTH + column.width
	if index < #COLUMNS then CONTENT_WIDTH = CONTENT_WIDTH + COLUMN_GAP end
end
local WINDOW_WIDTH = CONTENT_WIDTH + MARGIN * 2

-- SecondsToTime spells out "13 Min 49 Sec", which is too wide for a column.
local function compactTime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds < 60 then return seconds .. "s" end
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then return ("%dm %ds"):format(minutes, seconds % 60) end
	local hours = math.floor(minutes / 60)
	if hours < 24 then return ("%dh %dm"):format(hours, minutes % 60) end
	return ("%dd %dh"):format(math.floor(hours / 24), hours % 24)
end

Stats.sortKey = "time"
Stats.sortAscending = false
Stats.offset = 0
Stats.filter = ""

local function rowValue(entry, key)
	if key == "name" then return entry.name end
	if key == "level" then return entry.level or 0 end
	if key == "class" then return SquawkSpy.ClassNames[entry.class or ""] or "" end
	if key == "guild" then return entry.guild or "" end
	if key == "wins" then return entry.wins or 0 end
	if key == "loses" then return entry.loses or 0 end
	if key == "kos" then
		local kos = SquawkSpy.data.KOSData[entry.name]
		return kos and (kos.reason ~= "" and kos.reason or "Kill on Sight") or ""
	end
	if key == "time" then return entry.time or 0 end
	return ""
end

function Stats:BuildList()
	local list = {}
	local filter = Stats.filter:lower()
	for name, data in pairs(SquawkSpy.data.PlayerData) do
		local entry = data
		entry.name = name
		if filter == "" then
			list[#list + 1] = entry
		else
			local guild = (entry.guild or ""):lower()
			local class = (SquawkSpy.ClassNames[entry.class or ""] or ""):lower()
			if name:lower():find(filter, 1, true) or guild:find(filter, 1, true)
				or class:find(filter, 1, true) then
				list[#list + 1] = entry
			end
		end
	end

	local key, ascending = Stats.sortKey, Stats.sortAscending
	table.sort(list, function(a, b)
		local av, bv = rowValue(a, key), rowValue(b, key)
		if type(av) ~= type(bv) then av, bv = tostring(av), tostring(bv) end
		if av == bv then return a.name < b.name end
		if ascending then return av < bv end
		return av > bv
	end)
	Stats.list = list
	return list
end

function Stats:Initialize()
	local f = CreateFrame("Frame", "SquawkSpy_StatsWindow", UIParent, "BackdropTemplate")
	Stats.Window = f
	f:SetWidth(WINDOW_WIDTH)
	f:SetHeight(HEADER_HEIGHT + ROWS * ROW_HEIGHT + FOOTER_HEIGHT)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0, 0, 0, 0.9)
	local border = SquawkSpy.db.Colors.Window.Title
	f:SetBackdropBorderColor(border.r, border.g, border.b, 1)

	f:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and not SquawkSpy.db.Locked then
			self:StartMoving()
			self.isMoving = true
		end
	end)
	f:SetScript("OnMouseUp", function(self)
		if self.isMoving then self:StopMovingOrSizing() self.isMoving = false end
	end)

	f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	f.Title:SetText("Spy Statistics")

	f.Close = CreateFrame("Button", nil, f)
	f.Close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	f.Close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
	f.Close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	f.Close:SetWidth(20)
	f.Close:SetHeight(20)
	f.Close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
	f.Close:SetScript("OnClick", function() f:Hide() end)

	f.FilterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.FilterLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -190, -13)
	f.FilterLabel:SetText("Filter:")

	f.Filter = CreateFrame("EditBox", "SquawkSpy_StatsFilter", f, "InputBoxTemplate")
	f.Filter:SetPoint("LEFT", f.FilterLabel, "RIGHT", 8, 0)
	f.Filter:SetWidth(140)
	f.Filter:SetHeight(18)
	f.Filter:SetAutoFocus(false)
	f.Filter:SetScript("OnTextChanged", function(self)
		Stats.filter = self:GetText() or ""
		Stats.offset = 0
		Stats:Update()
	end)
	f.Filter:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.Filter:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

	-- header
	f.Headers = {}
	local x = MARGIN
	for index, column in ipairs(COLUMNS) do
		local header = CreateFrame("Button", nil, f)
		header:SetPoint("TOPLEFT", f, "TOPLEFT", x, -34)
		header:SetWidth(column.width)
		header:SetHeight(16)
		header.Text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header.Text:SetAllPoints(header)
		header.Text:SetJustifyH(column.justify)
		header.Text:SetText(column.title)
		header:SetScript("OnClick", function()
			if Stats.sortKey == column.key then
				Stats.sortAscending = not Stats.sortAscending
			else
				Stats.sortKey = column.key
				Stats.sortAscending = (column.key == "name" or column.key == "class" or column.key == "guild")
			end
			Stats:Update()
		end)
		f.Headers[index] = header
		x = x + column.width + COLUMN_GAP
	end

	-- rows
	f.Rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, f)
		row:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, -HEADER_HEIGHT - (i - 1) * ROW_HEIGHT)
		row:SetWidth(CONTENT_WIDTH)
		row:SetHeight(ROW_HEIGHT)
		row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
		row.Highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		row.Highlight:SetBlendMode("ADD")
		row.Highlight:SetAllPoints(row)
		row.Cells = {}
		local cx = 0
		for index, column in ipairs(COLUMNS) do
			local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
			cell:SetWidth(column.width)
			cell:SetHeight(ROW_HEIGHT)
			cell:SetJustifyH(column.justify)
			row.Cells[index] = cell
			cx = cx + column.width + COLUMN_GAP
		end
		row:RegisterForClicks("AnyUp")
		row:SetScript("OnClick", function(self, button)
			if not self.Name then return end
			if button == "RightButton" then
				SquawkSpy.Menu:Open(self, self.Name)
			else
				Stats:ShowHistory(self.Name)
			end
		end)
		f.Rows[i] = row
	end

	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		local total = Stats.list and #Stats.list or 0
		Stats.offset = math.max(0, math.min(Stats.offset - delta * 3, math.max(0, total - ROWS)))
		Stats:Update()
	end)

	f.Footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MARGIN, 9)
	f.Footer:SetJustifyH("LEFT")
	f.Footer:SetWidth(CONTENT_WIDTH)

	f:Hide()
end

function Stats:Update()
	local f = Stats.Window
	if Stats.History and Stats.History:IsShown() and Stats.History.player then
		Stats:ShowHistory(Stats.History.player)
	end
	if not f or not f:IsShown() then return end
	local list = Stats:BuildList()

	for i = 1, ROWS do
		local row = f.Rows[i]
		local entry = list[i + Stats.offset]
		if entry then
			row.Name = entry.name
			local color = SquawkSpy.ClassColors[entry.class or ""] or SquawkSpy.ClassColors.UNKNOWN
			for index, column in ipairs(COLUMNS) do
				local value = rowValue(entry, column.key)
				if column.key == "time" and type(value) == "number" and value > 0 then
					value = compactTime(time() - value)
				elseif column.key == "level" and value == 0 then
					value = "??"
				end
				row.Cells[index]:SetText(tostring(value))
				if column.key == "name" then
					row.Cells[index]:SetTextColor(color.r, color.g, color.b, 1)
				elseif column.key == "wins" then
					row.Cells[index]:SetTextColor(0.3, 1, 0.3, 1)
				elseif column.key == "loses" then
					row.Cells[index]:SetTextColor(1, 0.3, 0.3, 1)
				else
					row.Cells[index]:SetTextColor(1, 1, 1, 1)
				end
			end
			row:Show()
		else
			row.Name = nil
			row:Hide()
		end
	end

	local kos = SquawkSpy:CountTable(SquawkSpy.data.KOSData)
	f.Footer:SetText(("%d players seen  |  %d on the Kill on Sight list  |  left-click a row for its fight history, right-click for options")
		:format(#list, kos))
end

-- ---------------------------------------------------------------------------
-- fight history for one player
-- ---------------------------------------------------------------------------

local HISTORY_ROWS = 24

function Stats:CreateHistory()
	local f = CreateFrame("Frame", "SquawkSpy_HistoryWindow", UIParent, "BackdropTemplate")
	Stats.History = f
	f:SetWidth(330)
	f:SetHeight(64 + HISTORY_ROWS * ROW_HEIGHT)
	f:SetPoint("TOPLEFT", Stats.Window, "TOPRIGHT", 6, 0)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:SetBackdrop(Stats.Window:GetBackdrop())
	f:SetBackdropColor(0, 0, 0, 0.9)
	local border = SquawkSpy.db.Colors.Window.Title
	f:SetBackdropBorderColor(border.r, border.g, border.b, 1)
	f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
	f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

	f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)

	f.Record = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Record:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)

	f.Close = CreateFrame("Button", nil, f)
	f.Close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	f.Close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
	f.Close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	f.Close:SetWidth(20)
	f.Close:SetHeight(20)
	f.Close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
	f.Close:SetScript("OnClick", function() f:Hide() end)

	f.Rows = {}
	for i = 1, HISTORY_ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -50 - (i - 1) * ROW_HEIGHT)
		row:SetWidth(306)
		row:SetHeight(ROW_HEIGHT)

		row.Result = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Result:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.Result:SetWidth(34)
		row.Result:SetJustifyH("LEFT")

		row.Where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Where:SetPoint("LEFT", row, "LEFT", 36, 0)
		row.Where:SetWidth(190)
		row.Where:SetJustifyH("LEFT")

		row.When = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.When:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.When:SetWidth(76)
		row.When:SetJustifyH("RIGHT")

		f.Rows[i] = row
	end

	f.Empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Empty:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -52)
	f.Empty:SetWidth(300)
	f.Empty:SetJustifyH("LEFT")

	f:Hide()
end

function Stats:ShowHistory(name)
	if not Stats.History then Stats:CreateHistory() end
	local f = Stats.History
	f.player = name

	local wins, loses = SquawkSpy:GetRecord(name)
	local player = SquawkSpy:GetPlayer(name)
	local color = SquawkSpy.ClassColors[(player and player.class) or ""] or SquawkSpy.ClassColors.UNKNOWN
	f.Title:SetText(name)
	f.Title:SetTextColor(color.r, color.g, color.b, 1)
	f.Record:SetText(("|cff00ff00%d|r killed   |cffff0000%d|r deaths to them"):format(wins, loses))

	local encounters = (player and player.encounters) or {}
	for i = 1, HISTORY_ROWS do
		local row = f.Rows[i]
		-- newest first
		local entry = encounters[#encounters - i + 1]
		if entry then
			local won = entry.result == "win"
			row.Result:SetText(won and "|cff00ff00Won|r" or "|cffff0000Lost|r")
			row.Where:SetText(SquawkSpy:EncounterLocationLong(entry))
			row.When:SetText(compactTime(time() - (entry.time or time())) .. " ago")
			row:Show()
		else
			row:Hide()
		end
	end

	if #encounters == 0 then
		f.Empty:SetText("No fights recorded against this player yet. Kills and deaths are logged as they happen, with the spot they happened in.")
		f.Empty:Show()
	else
		f.Empty:Hide()
	end

	f:Show()
end

function Stats:Toggle()
	local f = Stats.Window
	if not f then return end
	if f:IsShown() then
		f:Hide()
		if Stats.History then Stats.History:Hide() end
	else
		f:Show()
		Stats.offset = 0
		Stats:Update()
	end
end
