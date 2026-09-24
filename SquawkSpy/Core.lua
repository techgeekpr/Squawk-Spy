--[[ Spy for WoW: Forever -- core database, lists and zone logic.

	Inspired by the Spy addon by Immolation and Slipjack.  None of its code is
	used: Spy's detection was built on COMBAT_LOG_EVENT_UNFILTERED, which this
	client removed, so the engine here is new.  The lists, windows, alerts and
	Kill on Sight workflow follow the original because that is what made it
	worth rebuilding.

	Made by Avoid Me of <Squawk>.

	The Forever beta runs the Midnight (12.x) addon API on a Classic world.
	Two consequences drive the whole design:

	  * COMBAT_LOG_EVENT_UNFILTERED errors on RegisterEvent and
	    CombatLogGetCurrentEventInfo is gone, so the original Spy's main
	    detection source does not exist.  Detect.lua replaces it.
	  * SavedVariables are written but never restored, so we restore them
	    ourselves from the SV junctions listed in the TOC.
]]

local ADDON = ...

SquawkSpy = {}
local SquawkSpy = SquawkSpy

SquawkSpy.Version = "2.0.0"
SquawkSpy.Signature = "SquawkSpy"
SquawkSpy.ButtonLimit = 15

SquawkSpy.NearbyList = {}      -- player -> time the current sighting started
SquawkSpy.ActiveList = {}      -- player -> time last seen
SquawkSpy.InactiveList = {}    -- player -> time last seen
SquawkSpy.LastHourList = {}    -- player -> time last seen
SquawkSpy.CurrentList = {}     -- ordered array shown in the window
SquawkSpy.ButtonName = {}
SquawkSpy.ListAmountDisplayed = 0
SquawkSpy.EnabledInZone = false
SquawkSpy.InInstance = false
SquawkSpy.IsEnabled = false
SquawkSpy.AlertType = nil

SquawkSpy.ActiveTimeout = 150
SquawkSpy.InactiveTimeout = 300

-- ---------------------------------------------------------------------------
-- Capability probe.  Everything below degrades instead of erroring.
-- ---------------------------------------------------------------------------

local function has(v) return type(v) == "function" end

SquawkSpy.Caps = {}

function SquawkSpy:ProbeCapabilities()
	local caps = SquawkSpy.Caps
	caps.namePlates = has(C_NamePlate and C_NamePlate.GetNamePlates)
		or has(C_NamePlateManager and C_NamePlateManager.GetNamePlates)
	caps.menuUtil = type(MenuUtil) == "table" and has(MenuUtil.CreateContextMenu)
	caps.dropDown = has(_G.ToggleDropDownMenu) and has(_G.UIDropDownMenu_Initialize)
	caps.settings = type(Settings) == "table" and has(Settings.RegisterCanvasLayoutCategory)
	caps.addonMessage = has(C_ChatInfo and C_ChatInfo.SendAddonMessage)
	caps.guildInfo = has(_G.GetGuildInfo)
	caps.zonePvP = has(_G.GetZonePVPInfo) or has(C_PvP and C_PvP.GetZonePVPInfo)

	-- The combat log: register inside a pcall, because on Midnight-era clients
	-- RegisterEvent itself throws for this event.
	caps.combatLog = false
	if has(_G.CombatLogGetCurrentEventInfo) then
		local probe = CreateFrame("Frame")
		local ok = pcall(probe.RegisterEvent, probe, "COMBAT_LOG_EVENT_UNFILTERED")
		if ok then
			caps.combatLog = true
			SquawkSpy.CombatLogFrame = probe
		end
	end
	return caps
end

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------

local function copy(t)
	local n = {}
	for k, v in pairs(t) do
		if type(v) == "table" then n[k] = copy(v) else n[k] = v end
	end
	return n
end
SquawkSpy.CopyTable = copy

local function fill(target, source)
	for k, v in pairs(source) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			fill(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
	return target
end

SquawkSpy.ClassColors = {
	HUNTER      = { r = 0.67, g = 0.83, b = 0.45, a = 0.6 },
	WARLOCK     = { r = 0.53, g = 0.53, b = 0.93, a = 0.6 },
	PRIEST      = { r = 1.00, g = 1.00, b = 1.00, a = 0.6 },
	PALADIN     = { r = 0.96, g = 0.55, b = 0.73, a = 0.6 },
	MAGE        = { r = 0.25, g = 0.78, b = 0.92, a = 0.6 },
	ROGUE       = { r = 1.00, g = 0.96, b = 0.41, a = 0.6 },
	DRUID       = { r = 1.00, g = 0.49, b = 0.04, a = 0.6 },
	SHAMAN      = { r = 0.00, g = 0.44, b = 0.87, a = 0.6 },
	WARRIOR     = { r = 0.78, g = 0.61, b = 0.43, a = 0.6 },
	PET         = { r = 0.09, g = 0.61, b = 0.55, a = 0.6 },
	MOB         = { r = 0.58, g = 0.24, b = 0.63, a = 0.6 },
	UNKNOWN     = { r = 0.10, g = 0.10, b = 0.10, a = 0.6 },
	HOSTILE     = { r = 0.70, g = 0.10, b = 0.10, a = 0.6 },
}

SquawkSpy.ClassNames = {
	HUNTER = "Hunter", WARLOCK = "Warlock", PRIEST = "Priest", PALADIN = "Paladin",
	MAGE = "Mage", ROGUE = "Rogue", DRUID = "Druid", SHAMAN = "Shaman",
	WARRIOR = "Warrior", UNKNOWN = "Unknown",
}

SquawkSpy.Defaults = {
	Enabled = true,
	MainWindowVis = true,
	CurrentList = 1,
	Locked = false,
	ClampToScreen = true,
	InvertSpy = false,
	ResizeSpy = true,
	ResizeSpyLimit = 15,
	RemoveUndetected = "5mins",
	PrioritiseKoS = true,
	DisplayListData = "1NameLevelClass",

	EnabledInBattlegrounds = true,
	EnabledInSanctuaries = false,
	EnabledInArenas = true,
	-- Forever has no combat log, so nameplates are most of our vision.  The
	-- original defaults this to true; staying awake while unflagged is more
	-- useful when detection range is already shorter.
	DisableWhenPVPUnflagged = false,
	FilteredZones = {},

	-- detection sources (see Detect.lua)
	DetectNameplates = true,
	DetectTarget = true,
	DetectMouseover = true,
	DetectGroupTargets = true,
	DetectChat = true,
	DetectComms = true,
	DetectCombatLog = true,      -- used only if the client still has one

	-- alerts
	AlertOnKoS = true,
	AlertOnStealth = true,
	AlertOnNearby = false,
	AlertSounds = true,
	AlertSoundKoS = "detected-kos.mp3",
	AlertSoundStealth = "detected-stealth.mp3",
	AlertSoundNearby = "detected-nearby.mp3",
	-- guild Kill on Sight
	guildKoS = true,                -- alert on the guild list as well
	announceGuildKoS = true,        -- print when a guildmate marks someone
	guildKoSSound = "detected-kosguild.mp3",

	-- Spy's own artwork, used when your installed copy of Spy provides it.
	WindowSkin = "industrial",      -- "industrial" (Spy's art) or "classic"
	BarTexture = "bar-flat.tga",    -- bar-flat.tga or bar-blend.tga

	SoundOnDetection = true,
	DetectionSound = "click",
	DisplayWarnings = true,

	DisplayOnMap = true,
	ShowKoSButton = true,

	MainWindow = {
		RowHeight = 14,
		RowSpacing = 2,
		TextHeight = 12,
		Alpha = 1,
		Buttons = { ClearButton = true, LeftButton = true, RightButton = true },
		Position = { x = 4, y = 740, w = 160, h = 34 },
	},
	AlertWindow = {
		NameSize = 14,
		LocationSize = 10,
		Position = { x = 750, y = 750 },
	},
	Colors = {
		Window = {
			Title       = { r = 1, g = 0, b = 0, a = 1 },
			Background  = { r = 24/255, g = 24/255, b = 24/255, a = 1 },
			TitleText   = { r = 1, g = 1, b = 1, a = 1 },
		},
		BarText = { r = 1, g = 1, b = 1, a = 1 },
		Alert = {
			Background     = { r = 0, g = 0, b = 0, a = 0.4 },
			KOSBorder      = { r = 1, g = 0, b = 0, a = 0.4 },
			KOSText        = { r = 1, g = 0, b = 0, a = 1 },
			StealthBorder  = { r = 0.6, g = 0.2, b = 1, a = 0.4 },
			StealthText    = { r = 0.6, g = 0.2, b = 1, a = 1 },
			NearbyBorder   = { r = 1, g = 0.82, b = 0, a = 0.4 },
			NearbyText     = { r = 1, g = 0.82, b = 0, a = 1 },
			NameText       = { r = 1, g = 1, b = 1, a = 1 },
			LocationText   = { r = 1, g = 0.82, b = 0, a = 1 },
		},
		Class = SquawkSpy.ClassColors,
	},
}

SquawkSpy.ListTypes = {
	{ "Nearby",        "ManageNearbyList",      "ManageNearbyListExpirations" },
	{ "Last Hour",     "ManageLastHourList",    "ManageLastHourListExpirations" },
	{ "Ignore",        "ManageIgnoreList" },
	{ "Kill on Sight", "ManageKillOnSightList" },
	{ "Guild KoS",     "ManageGuildKoSList" },
}

SquawkSpy.RemoveTimeouts = {
	["Never"]   = { 30,  -1  },
	["30secs"]  = { 30,  60  },
	["1min"]    = { 60,  120 },
	["5mins"]   = { 150, 300 },
	["10mins"]  = { 300, 600 },
	["15mins"]  = { 450, 900 },
}

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

local function newCharDB()
	return { PlayerData = {}, KOSData = {}, IgnoreData = {}, Stats = {}, lastSeen = 0 }
end

-- Merge the snapshots parked by Restore1..3.lua.  Data is keyed per character,
-- so a newest-wins merge per key is correct even across game accounts.
function SquawkSpy:RestoreSavedVariables()
	local snapshots = SquawkSpy_Restore
	SquawkSpy_Restore = nil

	local live = (type(SquawkSpyDB) == "table") and SquawkSpyDB or nil
	SquawkSpyDB = live or {}
	SquawkSpyDB.chars = SquawkSpyDB.chars or {}
	SquawkSpyDB.profiles = SquawkSpyDB.profiles or {}

	local restored = 0
	if type(snapshots) == "table" then
		for _, snap in ipairs(snapshots) do
			if type(snap) == "table" then
				restored = restored + 1
				for key, data in pairs(snap.chars or {}) do
					local cur = SquawkSpyDB.chars[key]
					if type(data) == "table"
						and (not cur or (data.lastSeen or 0) > (cur.lastSeen or 0)) then
						SquawkSpyDB.chars[key] = data
					end
				end
				for key, data in pairs(snap.profiles or {}) do
					if type(data) == "table" and not SquawkSpyDB.profiles[key] then
						SquawkSpyDB.profiles[key] = data
					end
				end
				if snap.sessions then
					SquawkSpyDB.sessions = math.max(SquawkSpyDB.sessions or 0, snap.sessions)
				end
				if snap.importedLegacy then SquawkSpyDB.importedLegacy = true end
			end
		end
	end

	-- live ~= nil means the client's own restore stage ran, i.e. the Forever
	-- SavedVariables bug is fixed; the shim is then simply redundant.
	-- Carried over from the old SpyF name: adopt any character or profile that
	-- has no counterpart yet, so the rename costs nothing.
	local legacy = SquawkSpy_Legacy
	SquawkSpy_Legacy = nil
	if type(legacy) == "table" then
		for _, snap in ipairs(legacy) do
			if type(snap) == "table" then
				for key, data in pairs(snap.chars or {}) do
					if not SquawkSpyDB.chars[key] then
						SquawkSpyDB.chars[key] = data
						SquawkSpy.AdoptedChars = (SquawkSpy.AdoptedChars or 0) + 1
					end
				end
				for key, profile in pairs(snap.profiles or {}) do
					if not SquawkSpyDB.profiles[key] then SquawkSpyDB.profiles[key] = profile end
				end
			end
		end
	end

	SquawkSpy.ClientRestoredSV = live ~= nil
	SquawkSpy.RestoredSnapshots = restored
	SquawkSpyDB.sessions = (SquawkSpyDB.sessions or 0) + 1
	SquawkSpyDB.version = 2
end

function SquawkSpy:InitDatabase()
	SquawkSpy:RestoreSavedVariables()

	local name = UnitName("player") or "Unknown"
	local realm = GetRealmName() or "Unknown"
	SquawkSpy.CharacterName = name
	SquawkSpy.RealmName = realm
	SquawkSpy.CharacterKey = name .. " - " .. realm
	SquawkSpy.FactionName = UnitFactionGroup("player") or "Alliance"
	SquawkSpy.EnemyFactionName = (SquawkSpy.FactionName == "Alliance") and "Horde" or "Alliance"

	SquawkSpyDB.profiles[SquawkSpy.CharacterKey] = SquawkSpyDB.profiles[SquawkSpy.CharacterKey] or {}
	SquawkSpy.db = fill(SquawkSpyDB.profiles[SquawkSpy.CharacterKey], copy(SquawkSpy.Defaults))

	SquawkSpyDB.chars[SquawkSpy.CharacterKey] = SquawkSpyDB.chars[SquawkSpy.CharacterKey] or newCharDB()
	SquawkSpy.data = SquawkSpyDB.chars[SquawkSpy.CharacterKey]
	SquawkSpy.data.PlayerData = SquawkSpy.data.PlayerData or {}
	SquawkSpy.data.KOSData = SquawkSpy.data.KOSData or {}
	SquawkSpy.data.IgnoreData = SquawkSpy.data.IgnoreData or {}
	SquawkSpy.data.Stats = SquawkSpy.data.Stats or {}
	SquawkSpy.data.lastSeen = time()

	SquawkSpy:ApplyTimeouts()
end

function SquawkSpy:ApplyTimeouts()
	local t = SquawkSpy.RemoveTimeouts[SquawkSpy.db.RemoveUndetected] or SquawkSpy.RemoveTimeouts["5mins"]
	SquawkSpy.ActiveTimeout, SquawkSpy.InactiveTimeout = t[1], t[2]
end

-- One-time import of the original Spy's lists, if that addon is also loaded.
function SquawkSpy:ImportLegacySpy()
	if SquawkSpyDB.importedLegacy then return 0 end
	SquawkSpyDB.importedLegacy = true
	local legacy = _G.SpyPerCharDB
	if type(legacy) ~= "table" then return 0 end
	local count = 0
	for name, entry in pairs(legacy.KOSData or {}) do
		if not SquawkSpy.data.KOSData[name] then
			SquawkSpy.data.KOSData[name] = (type(entry) == "table") and entry or { reason = "" }
			count = count + 1
		end
	end
	for name in pairs(legacy.IgnoreData or {}) do
		SquawkSpy.data.IgnoreData[name] = true
	end
	for name, entry in pairs(legacy.PlayerData or {}) do
		if type(entry) == "table" and not SquawkSpy.data.PlayerData[name] then
			SquawkSpy.data.PlayerData[name] = entry
		end
	end
	if count > 0 then
		SquawkSpy:Print(("imported %d Kill on Sight entries from the original Spy."):format(count))
	end
	return count
end

-- ---------------------------------------------------------------------------
-- Player records
-- ---------------------------------------------------------------------------

function SquawkSpy:GetPlayer(name)
	return SquawkSpy.data and SquawkSpy.data.PlayerData[name]
end

function SquawkSpy:IsKoS(name)
	return SquawkSpy.data and SquawkSpy.data.KOSData[name] ~= nil
end

function SquawkSpy:IsIgnored(name)
	return SquawkSpy.data and SquawkSpy.data.IgnoreData[name] ~= nil
end

function SquawkSpy:UpdatePlayerData(name, info)
	if not name or name == "" then return end
	local db = SquawkSpy.data.PlayerData
	local player = db[name]
	if not player then
		player = { name = name, isGuess = true, wins = 0, loses = 0 }
		db[name] = player
	end
	if info then
		if info.class and info.class ~= "UNKNOWN" then player.class = info.class end
		if info.race then player.race = info.race end
		if info.guild then player.guild = info.guild end
		if info.faction then player.faction = info.faction end
		local level = tonumber(info.level)
		if level and level > 0 then
			player.level = level
			if info.isGuess == false then player.isGuess = false end
		end
		if info.zone then player.zone = info.zone end
		if info.subZone then player.subZone = info.subZone end
		if info.mapID then player.mapID = info.mapID end
		if info.x then player.x = info.x end
		if info.y then player.y = info.y end
		if info.source then player.source = info.source end
	end
	player.time = time()
	return player
end

-- ---------------------------------------------------------------------------
-- Fight record
-- ---------------------------------------------------------------------------

SquawkSpy.EncounterLimit = 25   -- kept per player, oldest dropped first

function SquawkSpy:CurrentPosition()
	local info = { zone = GetZoneText(), subZone = GetSubZoneText() }
	if C_Map and C_Map.GetBestMapForUnit then
		local mapID = C_Map.GetBestMapForUnit("player")
		if mapID then
			info.mapID = mapID
			local pos = C_Map.GetPlayerMapPosition(mapID, "player")
			if pos then info.x, info.y = pos:GetXY() end
		end
	end
	return info
end

-- result is "win" (you killed them) or "loss" (they killed you).
function SquawkSpy:RecordEncounter(name, result, info)
	if not name or name == "" or not SquawkSpy.data then return end
	local player = SquawkSpy:GetPlayer(name) or SquawkSpy:UpdatePlayerData(name, info)
	if not player then return end

	player.encounters = player.encounters or {}
	local last = player.encounters[#player.encounters]
	-- One death produces several signals; collapse anything identical that
	-- lands within a few seconds.
	if last and last.result == result and (time() - (last.time or 0)) < 5 then return end

	local where = SquawkSpy:CurrentPosition()
	local entry = {
		time = time(),
		result = result,
		zone = where.zone,
		subZone = where.subZone,
		mapID = where.mapID,
		x = where.x,
		y = where.y,
		level = player.level,
		myLevel = UnitLevel("player"),
	}
	player.encounters[#player.encounters + 1] = entry
	while #player.encounters > SquawkSpy.EncounterLimit do
		table.remove(player.encounters, 1)
	end

	if result == "win" then
		player.wins = (player.wins or 0) + 1
	else
		player.loses = (player.loses or 0) + 1
	end

	if SquawkSpy.db.DisplayWarnings then
		SquawkSpy:Print(("%s %s at %s  (%d-%d against you)"):format(
			result == "win" and "Killed" or "|cffff0000Killed by|r",
			name, SquawkSpy:EncounterLocation(entry),
			player.wins or 0, player.loses or 0))
	end
	if SquawkSpy.Stats then SquawkSpy.Stats:Update() end
	return entry
end

function SquawkSpy:EncounterLocation(entry)
	if not entry then return "" end
	local zone = entry.zone or "somewhere"
	if entry.subZone and entry.subZone ~= "" and entry.subZone ~= zone then
		return entry.subZone .. ", " .. zone
	end
	return zone
end

-- "Hillsbrad Foothills (34.2, 61.8)" when we know the coordinates.
function SquawkSpy:EncounterLocationLong(entry)
	local text = SquawkSpy:EncounterLocation(entry)
	if entry and entry.x and entry.y then
		text = ("%s (%.1f, %.1f)"):format(text, entry.x * 100, entry.y * 100)
	end
	return text
end

function SquawkSpy:GetRecord(name)
	local player = SquawkSpy:GetPlayer(name)
	if not player then return 0, 0 end
	return player.wins or 0, player.loses or 0
end

function SquawkSpy:PrintHistory(name)
	local player = SquawkSpy:GetPlayer(name)
	if not player then
		SquawkSpy:Print("no record of " .. name .. ".")
		return
	end
	local wins, loses = SquawkSpy:GetRecord(name)
	SquawkSpy:Print(("%s: %d killed, %d deaths to them."):format(name, wins, loses))
	local encounters = player.encounters
	if not encounters or #encounters == 0 then
		SquawkSpy:Print("no individual fights recorded yet.")
		return
	end
	for i = #encounters, 1, -1 do
		local entry = encounters[i]
		SquawkSpy:Print(("  %s  %s  -  %s ago"):format(
			entry.result == "win" and "|cff00ff00won |r" or "|cffff0000lost|r",
			SquawkSpy:EncounterLocationLong(entry),
			SecondsToTime(time() - (entry.time or time()))))
	end
end

-- ---------------------------------------------------------------------------
-- Kill on Sight: note and alert sound
-- ---------------------------------------------------------------------------

-- Anything here can be the alert sound for the whole list or for one player.
SquawkSpy.AlertSoundChoices = {
	{ file = "detected-kos.mp3",      label = "Kill on Sight (default)" },
	{ file = "detected-kosguild.mp3", label = "Guild warning" },
	{ file = "detected-race.mp3",     label = "Race to the kill" },
	{ file = "detected-kosaway.mp3",  label = "Spotted elsewhere" },
	{ file = "detected-stealth.mp3",  label = "Stealth warning" },
	{ file = "whip.mp3",              label = "Whip" },
	{ file = "neck-snap.mp3",         label = "Snap" },
	{ file = "list-add.mp3",          label = "Chime" },
	{ file = "detected-nearby.mp3",   label = "Chirp" },
	{ file = false,                   label = "Silent" },
}

function SquawkSpy:AlertSoundLabel(file)
	if file == nil then return "Default" end
	for _, entry in ipairs(SquawkSpy.AlertSoundChoices) do
		if entry.file == file then return entry.label end
	end
	return tostring(file)
end

function SquawkSpy:CycleKoSSound()
	local choices = SquawkSpy.AlertSoundChoices
	local index = 1
	for i, entry in ipairs(choices) do
		if entry.file == SquawkSpy.db.AlertSoundKoS then index = i break end
	end
	local nextEntry = choices[index + 1] or choices[1]
	SquawkSpy.db.AlertSoundKoS = nextEntry.file
	if nextEntry.file then SquawkSpy:PlayMedia(nextEntry.file) end
	SquawkSpy:Print("Kill on Sight sound: " .. nextEntry.label)
end

function SquawkSpy:AddKoS(name, note)
	if not name or name == "" then return end
	local entry = SquawkSpy.data.KOSData[name] or {}
	SquawkSpy.data.KOSData[name] = entry
	if note then entry.reason = note end
	entry.time = time()
	SquawkSpy.data.IgnoreData[name] = nil
	SquawkSpy:PlayMedia("list-add.mp3")
	SquawkSpy:Print(name .. " added to the Kill on Sight list."
		.. ((entry.reason and entry.reason ~= "") and (" Note: " .. entry.reason) or ""))
	SquawkSpy:RefreshCurrentList()
	if SquawkSpy.Stats then SquawkSpy.Stats:Update() end
end

function SquawkSpy:SetKoSNote(name, note)
	if not name or name == "" then return end
	if not SquawkSpy.data.KOSData[name] then
		SquawkSpy:AddKoS(name, note)
		return
	end
	SquawkSpy.data.KOSData[name].reason = note
	SquawkSpy:Print(("note for %s: %s"):format(name, (note and note ~= "") and note or "(cleared)"))
	SquawkSpy:RefreshCurrentList()
	if SquawkSpy.Stats then SquawkSpy.Stats:Update() end
end

function SquawkSpy:GetKoSNote(name)
	local entry = SquawkSpy.data and SquawkSpy.data.KOSData[name]
	if entry and entry.reason and entry.reason ~= "" then return entry.reason end
	return nil
end

-- file = a bundled sound, false for silence, nil to follow the list default.
function SquawkSpy:SetKoSSound(name, file)
	local entry = SquawkSpy.data.KOSData[name]
	if not entry then return end
	entry.sound = file
	if file then SquawkSpy:PlayMedia(file) end
	SquawkSpy:Print(("alert sound for %s: %s"):format(name, SquawkSpy:AlertSoundLabel(file)))
end

function SquawkSpy:GetKoSSound(name)
	local entry = SquawkSpy.data and SquawkSpy.data.KOSData[name]
	if not entry then return SquawkSpy.db.AlertSoundKoS end
	if entry.sound ~= nil then return entry.sound end
	return SquawkSpy.db.AlertSoundKoS
end

-- Typed note, via the standard popup.
StaticPopupDialogs["SQUAWKSPY_KOS_NOTE"] = {
	text = "Kill on Sight note for %s",
	button1 = ACCEPT or "Accept",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	maxLetters = 120,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnAccept = function(self, data)
		local edit = self.editBox or (self.GetName and _G[self:GetName() .. "EditBox"])
		local text = edit and edit:GetText() or ""
		SquawkSpy:SetKoSNote(data, text)
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local text = self:GetText() or ""
		SquawkSpy:SetKoSNote(parent.data, text)
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["SQUAWKSPY_GUILD_NOTE"] = {
	text = "Guild Kill on Sight note for %s|nEveryone in the guild sees this.",
	button1 = ACCEPT or "Accept",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	maxLetters = 100,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnAccept = function(self, data)
		local edit = self.editBox or (self.GetName and _G[self:GetName() .. "EditBox"])
		SquawkSpy.Guild:Add(data, edit and edit:GetText() or "")
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		SquawkSpy.Guild:Add(parent.data, self:GetText() or "")
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

function SquawkSpy:PromptGuildNote(name)
	if not name or name == "" then
		SquawkSpy:Print("usage: /spy gkos <name>, or target a player first.")
		return
	end
	if not IsInGuild() then
		SquawkSpy:Print("you are not in a guild.")
		return
	end

	local dialog = StaticPopup_Show("SQUAWKSPY_GUILD_NOTE", name, nil, name)
	if not dialog then return end
	dialog.data = name
	local edit = dialog.editBox or (dialog.GetName and _G[dialog:GetName() .. "EditBox"])
	if edit then
		local entry = SquawkSpy.Guild:IsKoS(name)
		edit:SetText((entry and entry.reason) or "")
		edit:HighlightText()
		edit:SetFocus()
	end
end

function SquawkSpy:PromptKoSNote(name)
	if not name or name == "" then
		SquawkSpy:Print("usage: /spy note <name>, or target a player first.")
		return
	end
	if not SquawkSpy.data.KOSData[name] then SquawkSpy:AddKoS(name) end
	local dialog = StaticPopup_Show("SQUAWKSPY_KOS_NOTE", name, nil, name)
	if not dialog then return end
	dialog.data = name
	local edit = dialog.editBox or (dialog.GetName and _G[dialog:GetName() .. "EditBox"])
	if edit then
		edit:SetText(SquawkSpy:GetKoSNote(name) or "")
		edit:HighlightText()
		edit:SetFocus()
	end
end

function SquawkSpy:RemoveKoS(name)
	if not name then return end
	SquawkSpy.data.KOSData[name] = nil
	SquawkSpy:PlayMedia("list-remove.mp3")
	SquawkSpy:Print(name .. " removed from the Kill on Sight list.")
	SquawkSpy:RefreshCurrentList()
end

function SquawkSpy:AddIgnore(name)
	if not name then return end
	SquawkSpy.data.IgnoreData[name] = true
	SquawkSpy.data.KOSData[name] = nil
	SquawkSpy:RemovePlayerFromList(name)
	SquawkSpy:RefreshCurrentList()
end

function SquawkSpy:RemoveIgnore(name)
	if not name then return end
	SquawkSpy.data.IgnoreData[name] = nil
	SquawkSpy:RefreshCurrentList()
end

function SquawkSpy:RemovePlayerFromList(name)
	SquawkSpy.NearbyList[name] = nil
	SquawkSpy.ActiveList[name] = nil
	SquawkSpy.InactiveList[name] = nil
	SquawkSpy.LastHourList[name] = nil
end

function SquawkSpy:RemovePlayerData(name)
	SquawkSpy:RemovePlayerFromList(name)
	SquawkSpy.data.PlayerData[name] = nil
	SquawkSpy:RefreshCurrentList()
end

function SquawkSpy:ClearList()
	wipe(SquawkSpy.NearbyList)
	wipe(SquawkSpy.ActiveList)
	wipe(SquawkSpy.InactiveList)
	if SquawkSpy.db.CurrentList == 2 then wipe(SquawkSpy.LastHourList) end
	SquawkSpy:RefreshCurrentList()
end

-- ---------------------------------------------------------------------------
-- List building (mirrors the original Spy ordering rules)
-- ---------------------------------------------------------------------------

function SquawkSpy:ManageNearbyList()
	local prioritiseKoS = SquawkSpy.db.PrioritiseKoS
	local activeKoS, active, inactiveKoS, inactive = {}, {}, {}, {}

	for player in pairs(SquawkSpy.ActiveList) do
		local position = SquawkSpy.NearbyList[player]
		if position then
			if prioritiseKoS and SquawkSpy:IsKoS(player) then
				activeKoS[#activeKoS + 1] = { player = player, time = position }
			else
				active[#active + 1] = { player = player, time = position }
			end
		end
	end
	for player in pairs(SquawkSpy.InactiveList) do
		local position = SquawkSpy.NearbyList[player]
		if position then
			if prioritiseKoS and SquawkSpy:IsKoS(player) then
				inactiveKoS[#inactiveKoS + 1] = { player = player, time = position }
			else
				inactive[#inactive + 1] = { player = player, time = position }
			end
		end
	end

	local byTime = function(a, b) return a.time < b.time end
	table.sort(activeKoS, byTime)
	table.sort(inactiveKoS, byTime)
	table.sort(active, byTime)
	table.sort(inactive, byTime)

	local list = {}
	for _, v in ipairs(activeKoS) do list[#list + 1] = v end
	for _, v in ipairs(inactiveKoS) do list[#list + 1] = v end
	for _, v in ipairs(active) do list[#list + 1] = v end
	for _, v in ipairs(inactive) do list[#list + 1] = v end
	SquawkSpy.CurrentList = list
end

function SquawkSpy:ManageLastHourList()
	local list = {}
	for player, seen in pairs(SquawkSpy.LastHourList) do
		list[#list + 1] = { player = player, time = seen }
	end
	table.sort(list, function(a, b) return a.time > b.time end)
	SquawkSpy.CurrentList = list
end

local function listFromKeys(source)
	local list = {}
	for player in pairs(source) do
		local data = SquawkSpy:GetPlayer(player)
		list[#list + 1] = { player = player, time = (data and data.time) or 0 }
	end
	table.sort(list, function(a, b) return a.time > b.time end)
	SquawkSpy.CurrentList = list
end

function SquawkSpy:ManageIgnoreList() listFromKeys(SquawkSpy.data.IgnoreData) end

function SquawkSpy:ManageGuildKoSList()
	local list = SquawkSpy.Guild and SquawkSpy.Guild:List()
	listFromKeys(list or {})
end
function SquawkSpy:ManageKillOnSightList() listFromKeys(SquawkSpy.data.KOSData) end

function SquawkSpy:ManageNearbyListExpirations()
	local now = time()
	for player, seen in pairs(SquawkSpy.ActiveList) do
		if (now - seen) > SquawkSpy.ActiveTimeout then
			SquawkSpy.InactiveList[player] = seen
			SquawkSpy.ActiveList[player] = nil
		end
	end
	if SquawkSpy.InactiveTimeout >= 0 then
		for player, seen in pairs(SquawkSpy.InactiveList) do
			if (now - seen) > SquawkSpy.InactiveTimeout then
				SquawkSpy.InactiveList[player] = nil
				SquawkSpy.NearbyList[player] = nil
			end
		end
	end
end

function SquawkSpy:ManageLastHourListExpirations()
	local now = time()
	for player, seen in pairs(SquawkSpy.LastHourList) do
		if (now - seen) > 3600 then SquawkSpy.LastHourList[player] = nil end
	end
end

function SquawkSpy:ManageExpirations()
	SquawkSpy:ManageNearbyListExpirations()
	SquawkSpy:ManageLastHourListExpirations()
	SquawkSpy:RefreshCurrentList()
end

function SquawkSpy:GetActiveCount()
	local n = 0
	for _ in pairs(SquawkSpy.ActiveList) do n = n + 1 end
	return n
end

-- ---------------------------------------------------------------------------
-- Detection entry point.  Every source in Detect.lua funnels through here.
-- ---------------------------------------------------------------------------

function SquawkSpy:PlayerDetected(name, info, source)
	if not SquawkSpy.IsEnabled or not name or name == "" then return end
	if name == SquawkSpy.CharacterName then return end
	if not SquawkSpy.EnabledInZone then return end
	if SquawkSpy:IsIgnored(name) then return end

	local now = time()
	local isNew = SquawkSpy.NearbyList[name] == nil

	SquawkSpy:UpdatePlayerData(name, info)
	if isNew then SquawkSpy.NearbyList[name] = now end
	SquawkSpy.ActiveList[name] = now
	SquawkSpy.InactiveList[name] = nil
	SquawkSpy.LastHourList[name] = now

	if isNew then
		-- A full alert already makes noise; the blip is for everyone else.
		if not SquawkSpy:AlertPlayer(name, info and info.alert, source) then
			SquawkSpy:PlayDetectionSound()
		end
		if SquawkSpy.db.DetectComms and not source then SquawkSpy.Detect:Broadcast(name) end
		if SquawkSpy.db.DisplayOnMap then SquawkSpy.UI:AddMapNote(name) end
		-- Only a new sighting changes what the window shows.  Re-seeing someone
		-- just moves a timestamp, and the nameplate sweep runs every second, so
		-- the periodic refresh picks those up instead.
		SquawkSpy:RefreshCurrentList(name)
	end
	return isNew
end

local function Guild_Note(entry)
	if entry and entry.reason and entry.reason ~= "" then return entry.reason end
	return nil
end

function SquawkSpy:AlertPlayer(name, alertKind, source)
	local location = SquawkSpy:GetLocationText()

	local guildEntry = SquawkSpy.db.guildKoS and SquawkSpy.Guild and SquawkSpy.Guild:IsKoS(name)

	if SquawkSpy:IsKoS(name) and SquawkSpy.db.AlertOnKoS then
		local note = SquawkSpy:GetKoSNote(name)
		SquawkSpy:PlayMedia(SquawkSpy:GetKoSSound(name))
		SquawkSpy.UI:ShowAlert("kos", name, source, location, note)
		if SquawkSpy.db.DisplayWarnings then
			SquawkSpy:Print("|cffff0000Kill on Sight:|r " .. name .. " (" .. location .. ")"
				.. (note and ("  -  " .. note) or ""))
		end
		return true
	elseif guildEntry then
		SquawkSpy:PlayMedia(SquawkSpy.db.guildKoSSound)
		SquawkSpy.UI:ShowAlert("kos", name, guildEntry.addedBy, location,
			Guild_Note(guildEntry))
		if SquawkSpy.db.DisplayWarnings then
			SquawkSpy:Print(("|cffff8000Guild Kill on Sight:|r %s (%s)%s")
				:format(name, location,
					(guildEntry.reason and guildEntry.reason ~= "")
						and ("  -  " .. guildEntry.reason) or ""))
		end
		return true
	elseif alertKind == "stealth" and SquawkSpy.db.AlertOnStealth then
		SquawkSpy:PlayMedia(SquawkSpy.db.AlertSoundStealth)
		SquawkSpy.UI:ShowAlert("stealth", name, source, location)
		return true
	elseif SquawkSpy.db.AlertOnNearby then
		SquawkSpy:PlayMedia(SquawkSpy.db.AlertSoundNearby)
		SquawkSpy.UI:ShowAlert("nearby", name, source, location)
		return true
	end
	return false
end

function SquawkSpy:GetLocationText()
	local zone = GetZoneText() or ""
	local sub = GetSubZoneText() or ""
	if sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
	return zone
end

-- ---------------------------------------------------------------------------
-- Detection blip: one short sound whenever a new player turns up.
-- ---------------------------------------------------------------------------

-- Numeric fallbacks are the stable sound kit ids, in case this client does not
-- expose the SOUNDKIT table.
SquawkSpy.DetectionSounds = {
	{ key = "click", label = "Soft click",     kit = "IG_MAINMENU_OPTION_CHECKBOX_ON", id = 856 },
	{ key = "tick",  label = "Quiet tick",     kit = "U_CHAT_SCROLL_BUTTON",           id = 1115 },
	{ key = "tab",   label = "Page flip",      kit = "IG_CHARACTER_INFO_TAB",          id = 841 },
	{ key = "snap",  label = "Snap (0.3s)",    file = "neck-snap.mp3" },
	{ key = "spy",   label = "Original Spy chirp (0.9s)", file = "detected-nearby.mp3" },
}

function SquawkSpy:GetDetectionSound(key)
	for _, entry in ipairs(SquawkSpy.DetectionSounds) do
		if entry.key == key then return entry end
	end
	return SquawkSpy.DetectionSounds[1]
end

local lastBlip = 0

-- Several players can appear in the same second (a passing raid), and five
-- blips at once is exactly the annoyance this is meant to avoid.
function SquawkSpy:PlayDetectionSound(force)
	if not force then
		if not SquawkSpy.db.SoundOnDetection or not SquawkSpy.db.AlertSounds then return end
		local now = GetTime()
		if (now - lastBlip) < 1.2 then return end
		lastBlip = now
	end

	local entry = SquawkSpy:GetDetectionSound(SquawkSpy.db.DetectionSound)
	if entry.file then
		pcall(PlaySoundFile, "Interface\\AddOns\\SquawkSpy\\Sounds\\" .. entry.file, "Master")
	else
		local id = (SOUNDKIT and entry.kit and SOUNDKIT[entry.kit]) or entry.id
		pcall(PlaySound, id, "Master")
	end
end

function SquawkSpy:CycleDetectionSound()
	local sounds = SquawkSpy.DetectionSounds
	local index = 1
	for i, entry in ipairs(sounds) do
		if entry.key == SquawkSpy.db.DetectionSound then index = i break end
	end
	local nextEntry = sounds[index + 1] or sounds[1]
	SquawkSpy.db.DetectionSound = nextEntry.key
	SquawkSpy.db.SoundOnDetection = true
	SquawkSpy:PlayDetectionSound(true)
	SquawkSpy:Print("detection sound: " .. nextEntry.label)
end

-- ---------------------------------------------------------------------------
-- media: Spy's own artwork and sounds
-- ---------------------------------------------------------------------------

-- This addon is a re-work of Spy, and it is meant to look and sound like Spy.
-- Spy's artwork and sounds are Immolation and Slipjack's work, published under
-- no licence that permits redistribution, so they are not shipped here.  They
-- are read from your installed copy of Spy instead.
--
-- Spy does not need to be enabled, and does not need to work on this client --
-- the folder only has to be on disk, because a texture or sound path resolves
-- through the file system and never consults the addon list.  Anything that
-- cannot be found falls back to stock Blizzard art, or to silence.
local ROOTS = {
	"Interface\\AddOns\\Spy\\",        -- your installed copy of Spy
	"Interface\\AddOns\\SquawkSpy\\",  -- or copied in here
}

SquawkSpy.TextureFallback = {
	["bar-flat.tga"]          = "Interface\\TargetingFrame\\UI-StatusBar",
	["bar-blend.tga"]         = "Interface\\TargetingFrame\\UI-StatusBar",
	["button-highlight.tga"]  = "Interface\\Buttons\\ButtonHilight-Square",
	["button-left.tga"]       = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
	["button-right.tga"]      = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
	["button-clear.tga"]      = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
	["button-file.tga"]       = "Interface\\Icons\\INV_Misc_Note_01",
	["button-crosshairs.tga"] = "Interface\\Minimap\\Tracking\\Target",
	["button-exclaim.tga"]    = "Interface\\Icons\\INV_Misc_QuestionMark",
	["button-exclaim1.tga"]   = "Interface\\Icons\\INV_Misc_QuestionMark",
	["button-on.tga"]         = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
	["button-off.tga"]        = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
	["IconBorder.tga"]        = "Interface\\Buttons\\UI-ActionButton-Border",
	["alert-background.tga"]  = "Interface\\Tooltips\\UI-Tooltip-Background",
	["alert-industrial.tga"]  = "Interface\\Tooltips\\UI-Tooltip-Background",
	["title-industrial.tga"]  = "Interface\\Tooltips\\UI-Tooltip-Background",
	["title-industrial2.tga"] = "Interface\\Tooltips\\UI-Tooltip-Background",
	["title-industrial3.tga"] = "Interface\\Tooltips\\UI-Tooltip-Background",
	["resize-bottomright.tga"]= "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
	["resize-bottomleft.tga"] = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
	["resize-topright.tga"]   = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
	["resize-topleft.tga"]    = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
	["resize-left.tga"]       = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
	["resize-right.tga"]      = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
}

-- Probed once, because the answer cannot change while you are logged in.
local mediaRoots
local function roots()
	if mediaRoots then return mediaRoots end
	mediaRoots = {}
	for _, root in ipairs(ROOTS) do
		if SquawkSpy:TextureExists(root .. "Textures\\bar-flat.tga") then
			mediaRoots[#mediaRoots + 1] = root
		end
	end
	return mediaRoots
end

-- Resolved per file rather than per folder, so a partial copy still works.
function SquawkSpy:Texture(file)
	for _, root in ipairs(roots()) do
		local path = root .. "Textures\\" .. file
		if SquawkSpy:TextureExists(path) then return path end
	end
	return SquawkSpy.TextureFallback[file]
end

function SquawkSpy:HasSpyMedia()
	return #roots() > 0
end

-- Says which artwork resolved and where from, because "the window looks plain"
-- and "Spy is not installed where I thought" look identical on screen.
function SquawkSpy:MediaDiagnostics()
	local found = roots()
	SquawkSpy:Print("---- artwork and sounds ----")
	if #found == 0 then
		SquawkSpy:Print("|cffff8000no Spy artwork found.|r Stock Blizzard art is being used and "
			.. "alerts are silent. Install Spy alongside this addon, or copy its "
			.. "Textures and Sounds folders into Interface\\AddOns\\SquawkSpy\\.")
	else
		for _, root in ipairs(found) do
			SquawkSpy:Print(("|cff00ff00found:|r %s"):format(root))
		end
	end

	local missing, total = {}, 0
	for file in pairs(SquawkSpy.TextureFallback) do
		total = total + 1
		local resolved = false
		for _, root in ipairs(found) do
			if SquawkSpy:TextureExists(root .. "Textures\\" .. file) then resolved = true break end
		end
		if not resolved then missing[#missing + 1] = file end
	end
	SquawkSpy:Print(("textures: %d of %d from Spy, %d on stock art")
		:format(total - #missing, total, #missing))
	if #missing > 0 and #missing <= 8 then
		SquawkSpy:Print("  falling back: " .. table.concat(missing, ", "))
	end
end

function SquawkSpy:PlayMedia(file)
	if not file or not SquawkSpy.db or not SquawkSpy.db.AlertSounds then return end
	for _, root in ipairs(roots()) do
		-- PlaySoundFile reports whether the file was actually there, which is the
		-- only way to tell one root from another without playing both.
		local ok, willPlay = pcall(PlaySoundFile, root .. "Sounds\\" .. file, "Master")
		if ok and willPlay ~= false then return true end
	end
	return false
end

-- SetTexture never fails, so a missing file looks the same as a working one
-- until you see the blank on screen.  GetTextureFileID resolves the path and
-- returns nil when there is nothing behind it.
local probe
function SquawkSpy:TextureExists(path)
	if not path then return false end
	if not probe then probe = UIParent:CreateTexture(nil, "BACKGROUND") probe:Hide() end
	if not pcall(probe.SetTexture, probe, path) then return false end

	if probe.GetTextureFileID then
		local id = probe:GetTextureFileID()
		probe:SetTexture(nil)
		return id ~= nil
	end
	local set = probe:GetTexture()
	probe:SetTexture(nil)
	return set ~= nil
end

function SquawkSpy:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff42b6f4Squawk Spy:|r " .. tostring(msg))
end

function SquawkSpy:RefreshCurrentList(player)
	if SquawkSpy.UI then SquawkSpy.UI:RefreshCurrentList(player) end
end

function SquawkSpy:CountTable(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

-- ---------------------------------------------------------------------------
-- Zone handling
-- ---------------------------------------------------------------------------

local function getZonePvPInfo()
	if type(_G.GetZonePVPInfo) == "function" then return _G.GetZonePVPInfo() end
	if C_PvP and type(C_PvP.GetZonePVPInfo) == "function" then return C_PvP.GetZonePVPInfo() end
	return nil
end

-- Why Spy is asleep, in the player's words rather than a boolean.
function SquawkSpy:ZoneStatusText()
	if SquawkSpy.EnabledInZone then
		return "watching " .. SquawkSpy:GetLocationText() .. "."
	end
	if not SquawkSpy.db.Enabled then
		return "|cffff0000Spy is switched off|r (/spy config to turn it back on)."
	end
	local pvpType = getZonePvPInfo()
	if pvpType == "sanctuary" and not SquawkSpy.db.EnabledInSanctuaries then
		return ("asleep in %s because it is a sanctuary. Enable \"Sanctuaries\" in /spy config to watch here.")
			:format(SquawkSpy:GetLocationText())
	end
	local inInstance, instanceType = IsInInstance()
	if inInstance then
		return ("asleep because this is a %s instance."):format(tostring(instanceType))
	end
	if SquawkSpy.db.DisableWhenPVPUnflagged and not UnitIsPVP("player") then
		return "asleep because you are not PvP flagged (\"Sleep while you are not PvP flagged\" in /spy config)."
	end
	local zone, subZone = GetZoneText() or "", GetSubZoneText() or ""
	if SquawkSpy.db.FilteredZones[zone] or SquawkSpy.db.FilteredZones[subZone] then
		return ("asleep because %s is on your filtered zone list."):format(zone)
	end
	return "asleep in this zone."
end

function SquawkSpy:ZoneChanged()
	SquawkSpy.InInstance = false
	local pvpType = getZonePvPInfo()
	local zone = GetZoneText() or ""
	local subZone = GetSubZoneText() or ""
	local filtered = SquawkSpy.db.FilteredZones[zone] or SquawkSpy.db.FilteredZones[subZone]

	if pvpType == "sanctuary" and not SquawkSpy.db.EnabledInSanctuaries then
		SquawkSpy.EnabledInZone = false
	elseif zone == "" or filtered then
		SquawkSpy.EnabledInZone = false
	else
		SquawkSpy.EnabledInZone = true
		local inInstance, instanceType = IsInInstance()
		if inInstance then
			SquawkSpy.InInstance = true
			if instanceType == "party" or instanceType == "raid"
				or (not SquawkSpy.db.EnabledInBattlegrounds and instanceType == "pvp")
				or (not SquawkSpy.db.EnabledInArenas and instanceType == "arena") then
				SquawkSpy.EnabledInZone = false
			end
		elseif SquawkSpy.db.DisableWhenPVPUnflagged and not UnitIsPVP("player") then
			SquawkSpy.EnabledInZone = false
		end
	end

	if not SquawkSpy.db.Enabled then SquawkSpy.EnabledInZone = false end

	if SquawkSpy.UI and SquawkSpy.UI.MainWindow then
		if SquawkSpy.EnabledInZone and SquawkSpy.db.MainWindowVis then
			SquawkSpy.UI:ShowMainWindow()
		else
			SquawkSpy.UI:HideMainWindow()
		end
	end
	SquawkSpy:RefreshCurrentList()
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

-- Nameplates are the backbone of detection on this client, so it is worth
-- knowing whether the game is drawing them at all.
local function getCVar(name)
	if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
	if type(GetCVar) == "function" then return GetCVar(name) end
	return nil
end

local function setCVar(name, value)
	if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, value) end
	if type(SetCVar) == "function" then return pcall(SetCVar, name, value) end
	return false
end

function SquawkSpy:EnemyNamePlatesShown()
	local value = getCVar("nameplateShowEnemies")
	return value == "1" or value == 1
end

-- Nameplate range is the only lever left on detection reach, so take the
-- highest value this client will actually keep rather than assuming one.
function SquawkSpy:EnableEnemyNamePlates()
	setCVar("nameplateShowEnemies", "1")

	local best = getCVar("nameplateMaxDistance")
	for _, candidate in ipairs({ "100", "80", "60", "41" }) do
		setCVar("nameplateMaxDistance", candidate)
		local actual = getCVar("nameplateMaxDistance")
		if actual == candidate then best = actual break end
	end

	SquawkSpy:Print(("enemy nameplates on, draw distance %s yards."):format(tostring(best)))
	SquawkSpy:Print("that distance is the whole of Spy's reach on this client - the combat log, which used to see much further, is closed to addons.")
end

function SquawkSpy:Diagnostics()
	local caps = SquawkSpy.Caps
	local _, build, _, tocversion = GetBuildInfo()
	SquawkSpy:Print("---- diagnostics ----")
	SquawkSpy:Print(("client build %s, interface %s"):format(tostring(build), tostring(tocversion)))
	SquawkSpy:Print(("combat log: %s"):format(caps.combatLog and "|cff00ff00available|r"
		or "|cffff0000closed to addons (Midnight restriction)|r"))
	SquawkSpy:Print(("nameplate API: %s"):format(caps.namePlates and "|cff00ff00yes|r" or "|cffff0000no|r"))
	SquawkSpy:Print(("addon messages: %s, menus: %s"):format(
		caps.addonMessage and "yes" or "no",
		caps.menuUtil and "Menu API" or (caps.dropDown and "UIDropDownMenu" or "|cffff0000none|r")))
	SquawkSpy:Print(("SavedVariables: %s, %d snapshot(s) restored, session #%d"):format(
		SquawkSpy.ClientRestoredSV and "client restore working" or "restored by shim",
		SquawkSpy.RestoredSnapshots or 0, SquawkSpyDB.sessions or 0))
	SquawkSpy:Print("zone: " .. SquawkSpy:ZoneStatusText())
	local window = SquawkSpy.UI.MainWindow
	if window then
		SquawkSpy:Print(("window: %s at %d,%d size %dx%d (screen %dx%d)"):format(
			window:IsShown() and "|cff00ff00shown|r" or "|cffff0000hidden|r",
			window:GetLeft() or -1, window:GetTop() or -1,
			window:GetWidth(), window:GetHeight(),
			UIParent:GetWidth(), UIParent:GetHeight()))
	else
		SquawkSpy:Print("window: |cffff0000the interface failed to start|r")
	end
	SquawkSpy:Print(("enemy nameplates: %s, draw distance %s yards"):format(
		SquawkSpy:EnemyNamePlatesShown() and "|cff00ff00on|r" or "|cffff0000off - /spy nameplates|r",
		tostring(getCVar("nameplateMaxDistance"))))
	SquawkSpy:Print(("nameplates visible: %d, detections this session: %d"):format(
		SquawkSpy.Detect:CountNamePlates(), SquawkSpy.Detect.DetectionCount or 0))
	SquawkSpy:Print(("known players: %d, kill on sight: %d"):format(
		SquawkSpy:CountTable(SquawkSpy.data.PlayerData), SquawkSpy:CountTable(SquawkSpy.data.KOSData)))
end

local function handleSlash(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()

	if cmd == "" or cmd == "toggle" then
		if SquawkSpy.UI:IsMainWindowShown() then
			SquawkSpy.UI:HideMainWindow(true)
		else
			SquawkSpy.UI:ShowMainWindow(true)
			if not SquawkSpy.EnabledInZone then SquawkSpy:Print(SquawkSpy:ZoneStatusText()) end
		end
	elseif cmd == "diag" or cmd == "debug" then
		SquawkSpy:Diagnostics()
	elseif cmd == "art" or cmd == "media" then
		SquawkSpy:MediaDiagnostics()
	elseif cmd == "clear" then
		SquawkSpy:ClearList()
	elseif cmd == "lock" then
		SquawkSpy.db.Locked = not SquawkSpy.db.Locked
		SquawkSpy:Print("windows " .. (SquawkSpy.db.Locked and "locked" or "unlocked"))
	elseif cmd == "reset" then
		SquawkSpy.db.MainWindow.Position = copy(SquawkSpy.Defaults.MainWindow.Position)
		SquawkSpy.db.AlertWindow.Position = copy(SquawkSpy.Defaults.AlertWindow.Position)
		SquawkSpy.UI:RestorePositions()
		SquawkSpy:Print("window positions reset")
	elseif cmd == "stats" then
		SquawkSpy.Stats:Toggle()
	elseif cmd == "config" or cmd == "options" then
		SquawkSpy.Options:Open()
	elseif cmd == "gkos" and rest ~= "" then
		SquawkSpy.Guild:Add(rest)
	elseif cmd == "ungkos" and rest ~= "" then
		SquawkSpy.Guild:Remove(rest)
	elseif cmd == "gsync" then
		SquawkSpy.Guild.lastRequest = 0
		SquawkSpy.Guild:RequestSync()
		SquawkSpy:Print(("asked the guild for its list (%d entries here now)")
			:format(SquawkSpy.Guild:Count()))
	elseif cmd == "kos" and rest ~= "" then
		SquawkSpy:AddKoS(rest)
	elseif cmd == "unkos" and rest ~= "" then
		SquawkSpy:RemoveKoS(rest)
	elseif cmd == "nameplates" then
		SquawkSpy:EnableEnemyNamePlates()
	elseif cmd == "note" then
		local who = rest
		if who == "" then who = SquawkSpy.UI:TargetName() end
		SquawkSpy:PromptKoSNote(who)
	elseif cmd == "kossound" then
		SquawkSpy:CycleKoSSound()
	elseif cmd == "sound" then
		if rest:lower() == "off" then
			SquawkSpy.db.SoundOnDetection = false
			SquawkSpy:Print("detection sound off.")
		else
			SquawkSpy:CycleDetectionSound()
		end
	elseif cmd == "history" or cmd == "record" then
		local who = rest
		if who == "" then who = SquawkSpy.UI:TargetName() end
		if who then SquawkSpy:PrintHistory(who) else SquawkSpy:Print("usage: /spy history <name>, or target a player first.") end
	else
		SquawkSpy:Print("/spy | clear | lock | reset | stats | history <name> | sound [off] | kossound | note <name> | config | diag")
		SquawkSpy:Print("kill on sight: |cffffd100kos <name>|r, |cffffd100unkos <name>|r, guild-wide: |cffffd100gkos <name>|r, |cffffd100ungkos <name>|r, |cffffd100gsync|r")
	end
end

SLASH_SQUAWKSPY1 = "/spy"
SLASH_SQUAWKSPY2 = "/spyf"
SlashCmdList["SQUAWKSPY"] = handleSlash

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_LOGOUT")
boot:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		SquawkSpy:ProbeCapabilities()
	elseif event == "PLAYER_LOGIN" then
		SquawkSpy:InitDatabase()
		SquawkSpy:ImportLegacySpy()
		-- Guarded individually: an unexpected API difference in one module
		-- should not stop the others, and detection matters most.
		for _, module in ipairs({ "UI", "Stats", "Options", "Detect", "Guild" }) do
			local ok, err = pcall(function() SquawkSpy[module]:Initialize() end)
			if not ok then
				SquawkSpy:Print(("|cffff0000%s failed to start:|r %s"):format(module, tostring(err)))
			end
		end
		SquawkSpy.IsEnabled = true
		SquawkSpy:ZoneChanged()
		C_Timer.NewTicker(5, function() SquawkSpy:ManageExpirations() end)
		if not SquawkSpy.Caps.combatLog then
			SquawkSpy:Print("this client closes the combat log to addons, so detection uses nameplates, targets, group targets and chat. Type |cff42b6f4/spy diag|r for details.")
		end
		if not SquawkSpy.EnabledInZone then
			SquawkSpy:Print(SquawkSpy:ZoneStatusText() .. " The window stays hidden until Spy is watching.")
		end
		if not SquawkSpy:EnemyNamePlatesShown() then
			SquawkSpy:Print("|cffff0000enemy nameplates are turned off|r - they are the main way Spy sees players on this client. Type |cff42b6f4/spy nameplates|r to turn them on.")
		end
	elseif event == "PLAYER_LOGOUT" then
		if SquawkSpy.data then SquawkSpy.data.lastSeen = time() end
	end
end)
