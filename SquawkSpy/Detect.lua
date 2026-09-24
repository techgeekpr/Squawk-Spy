--[[ Detection sources.

	The original Spy saw almost everything through COMBAT_LOG_EVENT_UNFILTERED:
	any enemy who cast, swung or was hit anywhere in combat-log range landed in
	the list.  Midnight removed that event and CombatLogGetCurrentEventInfo, and
	the Forever beta inherits the removal, so this file rebuilds the same list
	from every source that is still open to addons:

	  nameplates      every hostile player the client draws a plate for
	  target/focus    anything you or your group look at
	  mouseover       anything the cursor passes over
	  group targets   what your party or raid is fighting
	  chat            /say, /yell and emotes from the other faction, whose
	                  faction is confirmed through the sender's GUID
	  addon comms     other SquawkSpy users in your guild or group
	  combat log      still used, if a future build re-opens it

	Every source ends at SquawkSpy:PlayerDetected.
]]

local SquawkSpy = SquawkSpy
local Detect = {}
SquawkSpy.Detect = Detect

Detect.DetectionCount = 0

local ENEMY_RACE = {
	Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
	Draenei = "Alliance", Worgen = "Alliance",
	Orc = "Horde", Scourge = "Horde", Undead = "Horde", Tauren = "Horde",
	Troll = "Horde", BloodElf = "Horde", Goblin = "Horde",
}

local STEALTH_AURAS = { ["Stealth"] = true, ["Prowl"] = true, ["Shadowmeld"] = true }

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

-- Names arrive with a realm suffix for foreign-realm players; keep the same
-- "Name-Realm" shape the original Spy stored so imported lists still match.
local function normalizeName(name)
	if not name then return nil end
	name = name:gsub(" %- ", "-")
	if name == "" then return nil end
	return name
end

local function unitName(unit)
	local name, realm = UnitName(unit)
	if not name or name == UNKNOWNOBJECT or name == "" then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

local function isHostilePlayer(unit)
	if not UnitExists(unit) then return false end
	if not UnitIsPlayer(unit) then return false end
	if UnitIsUnit(unit, "player") then return false end
	if UnitIsFriend("player", unit) then return false end
	-- UnitCanAttack covers duels and FFA; UnitIsEnemy covers the normal case.
	return UnitIsEnemy("player", unit) or UnitCanAttack("player", unit)
end

-- Aura fields can be secret values on this client, and comparing a secret
-- throws, so the whole read is wrapped.
local function readStealthAura(unit)
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if get then
		for i = 1, 8 do
			local data = get(unit, i, "HELPFUL")
			if not data then break end
			if data.name and STEALTH_AURAS[data.name] then return true end
		end
	elseif type(UnitBuff) == "function" then
		for i = 1, 8 do
			local name = UnitBuff(unit, i)
			if not name then break end
			if STEALTH_AURAS[name] then return true end
		end
	end
	return false
end

local function hasStealthAura(unit)
	local ok, result = pcall(readStealthAura, unit)
	return ok and result
end

local function guildOf(unit)
	if type(GetGuildInfo) ~= "function" then return nil end
	local ok, guild = pcall(GetGuildInfo, unit)
	if ok and type(guild) == "string" and guild ~= "" then return guild end
	return nil
end

-- The nameplate sweep asks for our position many times a second; one lookup
-- per second is plenty for a map note.
local cachedPosition, cachedAt = nil, 0

local function position()
	local now = GetTime()
	if cachedPosition and (now - cachedAt) < 1 then
		local reuse = {}
		for k, v in pairs(cachedPosition) do reuse[k] = v end
		return reuse
	end

	local info = {}
	if C_Map and C_Map.GetBestMapForUnit then
		local mapID = C_Map.GetBestMapForUnit("player")
		if mapID then
			info.mapID = mapID
			local pos = C_Map.GetPlayerMapPosition(mapID, "player")
			if pos then
				local x, y = pos:GetXY()
				info.x, info.y = x, y
			end
		end
	end
	info.zone = GetZoneText()
	info.subZone = GetSubZoneText()

	cachedPosition, cachedAt = info, now
	local copy = {}
	for k, v in pairs(info) do copy[k] = v end
	return copy
end

-- ---------------------------------------------------------------------------
-- unit-token based detection (nameplates, target, mouseover, group targets)
-- ---------------------------------------------------------------------------

function Detect:ScanUnit(unit, source)
	if not SquawkSpy.EnabledInZone then return end
	if not isHostilePlayer(unit) then return end

	local name = normalizeName(unitName(unit))
	if not name then return end

	local info = position()
	local _, class = UnitClass(unit)
	info.class = class
	local _, race = UnitRace(unit)
	info.race = race
	info.guild = guildOf(unit)
	info.faction = UnitFactionGroup(unit)
	info.source = source

	local level = UnitLevel(unit)
	if level and level > 0 then
		info.level = level
		info.isGuess = false
	end

	if hasStealthAura(unit) then info.alert = "stealth" end

	Detect.DetectionCount = Detect.DetectionCount + 1
	SquawkSpy:PlayerDetected(name, info)

	-- Fight bookkeeping: are they swinging at us, and are they still standing?
	local theirTarget = unit .. "target"
	if UnitExists(theirTarget) and UnitIsUnit(theirTarget, "player") then
		Detect:NoteEngaged(name, true)
	end

	local ok, dead = pcall(UnitIsDead, unit)
	if ok and dead then
		Detect:NoteEnemyDeath(name)
	elseif Detect.Dead then
		Detect.Dead[name] = nil -- back on their feet; a later kill counts again
	end
end

function Detect:CountNamePlates()
	local n = 0
	for i = 1, 40 do
		if UnitExists("nameplate" .. i) then n = n + 1 end
	end
	return n
end

-- A sweep catches plates that were already up when we logged in or zoned, and
-- refreshes "last seen" for everyone still on screen so the list ages honestly.
function Detect:SweepNamePlates()
	if not SquawkSpy.db.DetectNameplates then return end
	for i = 1, 40 do
		Detect:ScanUnit("nameplate" .. i, "nameplate")
	end
end

function Detect:SweepGroupTargets()
	if not SquawkSpy.db.DetectGroupTargets then return end
	local members = GetNumGroupMembers and GetNumGroupMembers() or 0
	if members == 0 then return end
	local inRaid = IsInRaid and IsInRaid()
	local prefix = inRaid and "raid" or "party"
	local count = inRaid and members or (members - 1)
	for i = 1, count do
		Detect:ScanUnit(prefix .. i .. "target", "group")
	end
	Detect:ScanUnit("targettarget", "group")
end

-- ---------------------------------------------------------------------------
-- chat detection
-- ---------------------------------------------------------------------------

-- A chat message only proves the sender exists, not which side they are on.
-- The sender's GUID does: GetPlayerInfoByGUID gives their race, and race maps
-- to faction exactly, so friendly players are never added by mistake.
function Detect:ScanChatSender(name, guid)
	if not SquawkSpy.db.DetectChat or not SquawkSpy.EnabledInZone then return end
	name = normalizeName(name)
	if not name or not guid or type(GetPlayerInfoByGUID) ~= "function" then return end

	local ok, _, class, _, race = pcall(GetPlayerInfoByGUID, guid)
	if not ok or not race then return end

	local faction = ENEMY_RACE[race]
	if not faction or faction ~= SquawkSpy.EnemyFactionName then return end

	local info = position()
	info.class = class
	info.race = race
	info.faction = faction
	info.source = "chat"
	info.isGuess = true

	Detect.DetectionCount = Detect.DetectionCount + 1
	SquawkSpy:PlayerDetected(name, info)
end

-- ---------------------------------------------------------------------------
-- addon comms: share sightings with other SquawkSpy users
-- ---------------------------------------------------------------------------

local PREFIX = "SquawkSpy"

function Detect:Broadcast(name)
	if not SquawkSpy.db.DetectComms or not SquawkSpy.Caps.addonMessage then return end
	local player = SquawkSpy:GetPlayer(name)
	if not player then return end
	local payload = table.concat({
		"D", name, tostring(player.level or 0), player.class or "UNKNOWN",
		SquawkSpy:GetLocationText(),
	}, "\001")

	local channel
	if IsInRaid and IsInRaid() then channel = "RAID"
	elseif IsInGroup and IsInGroup() then channel = "PARTY"
	elseif IsInGuild() then channel = "GUILD" end
	if not channel then return end
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, channel)
end

function Detect:ReceiveComm(payload, sender)
	if not SquawkSpy.db.DetectComms then return end
	local kind, name, level, class, location = strsplit("\001", payload)
	if kind ~= "D" or not name then return end
	sender = normalizeName(sender)
	if sender == SquawkSpy.CharacterName then return end

	local info = {
		level = tonumber(level),
		class = class,
		source = "comm",
		isGuess = true,
		zone = location,
	}
	SquawkSpy:PlayerDetected(normalizeName(name), info, sender or "party")
end

-- ---------------------------------------------------------------------------
-- combat log (only if a build ever re-opens it)
-- ---------------------------------------------------------------------------

local COMBAT_LOG_PLAYER = 0x00000400 -- COMBATLOG_OBJECT_TYPE_PLAYER
local COMBAT_LOG_HOSTILE = 0x00000040 -- COMBATLOG_OBJECT_REACTION_HOSTILE

function Detect:CombatLogEvent()
	if not SquawkSpy.EnabledInZone or not SquawkSpy.db.DetectCombatLog then return end
	local _, _, _, _, srcName, srcFlags, _, _, dstName, dstFlags = CombatLogGetCurrentEventInfo()

	local function consider(name, flags)
		if not name or not flags then return end
		if bit.band(flags, COMBAT_LOG_PLAYER) == 0 then return end
		if bit.band(flags, COMBAT_LOG_HOSTILE) == 0 then return end
		local info = position()
		info.source = "combatlog"
		info.isGuess = true
		Detect.DetectionCount = Detect.DetectionCount + 1
		SquawkSpy:PlayerDetected(normalizeName(name), info)
	end

	consider(srcName, srcFlags)
	consider(dstName, dstFlags)
end

-- ---------------------------------------------------------------------------
-- wiring
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")

function Detect:Initialize()
	events:SetScript("OnEvent", function(_, event, ...)
		local handler = Detect[event]
		if handler then handler(Detect, ...) end
	end)

	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	events:RegisterEvent("UNIT_TARGET")
	events:RegisterEvent("ZONE_CHANGED")
	events:RegisterEvent("ZONE_CHANGED_INDOORS")
	events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("UNIT_FACTION")
	events:RegisterEvent("CHAT_MSG_ADDON")
	pcall(events.RegisterEvent, events, "PLAYER_FOCUS_CHANGED")

	for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }) do
		pcall(events.RegisterEvent, events, e)
	end

	-- win/loss tracking, see below
	pcall(events.RegisterEvent, events, "CHAT_MSG_COMBAT_HONOR_GAIN")
	events:RegisterEvent("PLAYER_DEAD")

	if SquawkSpy.Caps.addonMessage and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end

	if SquawkSpy.Caps.combatLog and SquawkSpy.CombatLogFrame then
		SquawkSpy.CombatLogFrame:SetScript("OnEvent", function() Detect:CombatLogEvent() end)
	end

	-- Sweep once a second: cheap (40 UnitExists calls) and it keeps timestamps
	-- honest for plates that stay on screen without firing further events.
	C_Timer.NewTicker(1, function()
		if not SquawkSpy.EnabledInZone then return end
		Detect:SweepNamePlates()
		Detect:SweepGroupTargets()
	end)
end

function Detect:NAME_PLATE_UNIT_ADDED(unit)
	if SquawkSpy.db.DetectNameplates then Detect:ScanUnit(unit, "nameplate") end
end

function Detect:PLAYER_TARGET_CHANGED()
	if SquawkSpy.db.DetectTarget then Detect:ScanUnit("target", "target") end
	-- Targeting an enemy player counts as engaging them, so that a kill with no
	-- honour message still lands against the right name.
	if UnitExists("target") and UnitIsPlayer("target") and UnitIsEnemy("player", "target") then
		Detect:NoteEngaged(normalizeName(unitName("target")), false)
	end
	if SquawkSpy.UI then SquawkSpy.UI:UpdateKoSButton() end
end

function Detect:PLAYER_FOCUS_CHANGED()
	if SquawkSpy.db.DetectTarget then Detect:ScanUnit("focus", "focus") end
end

function Detect:UPDATE_MOUSEOVER_UNIT()
	if SquawkSpy.db.DetectMouseover then Detect:ScanUnit("mouseover", "mouseover") end
end

function Detect:UNIT_TARGET(unit)
	if not SquawkSpy.db.DetectGroupTargets or not unit then return end
	if unit:match("^party%d") or unit:match("^raid%d") then
		Detect:ScanUnit(unit .. "target", "group")
	end
end

local function chatHandler(_, _, sender, _, _, _, _, _, _, _, _, _, guid)
	Detect:ScanChatSender(sender, guid)
end

function Detect:CHAT_MSG_SAY(...) chatHandler(nil, ...) end
function Detect:CHAT_MSG_YELL(...) chatHandler(nil, ...) end
function Detect:CHAT_MSG_EMOTE(...) chatHandler(nil, ...) end
function Detect:CHAT_MSG_TEXT_EMOTE(...) chatHandler(nil, ...) end

function Detect:CHAT_MSG_ADDON(prefix, payload, _, sender)
	if prefix == PREFIX then Detect:ReceiveComm(payload, sender) end
end

--[[ Win/loss tracking without a combat log.

	The original read PARTY_KILL and damage events straight from the log.  Here
	a fight has to be reconstructed from what the client still shows:

	  engaged    you targeted them, or their nameplate's target is you
	  win        an honourable-kill message names them, or a player we were
	             engaged with turns up dead on a nameplate
	  loss       we died, and someone we were engaged with was attacking us

	Grey-level kills produce no honour message, which is why the nameplate
	death check exists; the 5 second collapse in RecordEncounter keeps the two
	paths from counting the same kill twice.
]]

Detect.Engaged = {}     -- name -> last time we were in a fight with them
Detect.Aggressors = {}  -- name -> last time they were targeting us

local ENGAGED_WINDOW = 60

function Detect:NoteEngaged(name, theyTargetedUs)
	if not name then return end
	local now = time()
	Detect.Engaged[name] = now
	if theyTargetedUs then Detect.Aggressors[name] = now end
end

-- Called from the nameplate sweep: a plate we were fighting showing a dead
-- unit is a kill.
function Detect:NoteEnemyDeath(name)
	if not name then return end
	local engagedAt = Detect.Engaged[name]
	if not engagedAt or (time() - engagedAt) > ENGAGED_WINDOW then return end
	if Detect.Dead and Detect.Dead[name] then return end
	Detect.Dead = Detect.Dead or {}
	Detect.Dead[name] = time()
	SquawkSpy:RecordEncounter(name, "win")
end

function Detect:CHAT_MSG_COMBAT_HONOR_GAIN(message)
	if type(message) ~= "string" then return end
	-- "<name> dies, honorable kill Rank: ..."
	local name = message:match("^(.-) dies,")
	if not name then return end
	SquawkSpy:RecordEncounter(normalizeName(name), "win")
end

function Detect:PLAYER_DEAD()
	local now = time()
	local killer, killedAt = nil, 0

	-- whoever was attacking us most recently
	for name, seen in pairs(Detect.Aggressors) do
		if (now - seen) <= ENGAGED_WINDOW and seen > killedAt then
			killer, killedAt = name, seen
		end
	end

	-- otherwise fall back to whoever we were pointed at
	if not killer and UnitExists("target") and UnitIsPlayer("target")
		and UnitIsEnemy("player", "target") then
		killer = normalizeName(unitName("target"))
	end

	if killer then SquawkSpy:RecordEncounter(killer, "loss") end
end

function Detect:ZONE_CHANGED() SquawkSpy:ZoneChanged() end
function Detect:ZONE_CHANGED_INDOORS() SquawkSpy:ZoneChanged() end
function Detect:ZONE_CHANGED_NEW_AREA() SquawkSpy:ZoneChanged() end
function Detect:UNIT_FACTION(unit) if unit == "player" then SquawkSpy:ZoneChanged() end end

function Detect:PLAYER_ENTERING_WORLD()
	SquawkSpy:ZoneChanged()
	C_Timer.After(2, function() Detect:SweepNamePlates() end)
end
