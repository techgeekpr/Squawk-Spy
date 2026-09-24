--[[ Guild Kill on Sight: one shared list for the whole guild.

	Marking someone Guild KoS broadcasts them to every guildmate running the
	addon, note included, and they keep it.  A guild list survives your
	logout, spreads without anyone maintaining it, and means the first person
	to get ganked warns everyone else.

	The protocol is deliberately small, because an addon message is 255 bytes
	and the guild channel is shared with every other addon:

	  ADD  name | note | who | stamp     someone marked a player
	  DEL  name | who | stamp            someone cleared a player
	  REQ                                a client asking for the list
	  ONE  name | note | who | stamp     one entry, in reply to REQ

	Every entry carries the time it was set, and the newest write wins, so two
	people marking the same target at once settle on one answer without
	anybody arbitrating.  Replies to REQ are staggered by a random delay and
	suppressed once somebody else answers, so twenty guildies logging in after
	a raid do not each send the whole list.
]]

local SquawkSpy = SquawkSpy
local Guild = {}
SquawkSpy.Guild = Guild

local PREFIX = "SquawkSpyG"
local SEP = "\001"
local MAX_NOTE = 100

Guild.pendingReply = nil
Guild.lastRequest = 0

-- ---------------------------------------------------------------------------
-- storage
-- ---------------------------------------------------------------------------

-- Keyed by guild so that swapping guilds, or an alt in another guild, does
-- not inherit a list that means nothing there.
function Guild:GuildKey()
	local name = GetGuildInfo and select(1, GetGuildInfo("player")) or nil
	if type(name) ~= "string" or name == "" then return nil end
	return name .. " - " .. (GetRealmName() or "?")
end

function Guild:List()
	local key = Guild:GuildKey()
	if not key then return nil end
	SquawkSpyDB.guildKOS = SquawkSpyDB.guildKOS or {}
	SquawkSpyDB.guildKOS[key] = SquawkSpyDB.guildKOS[key] or {}
	return SquawkSpyDB.guildKOS[key], key
end

function Guild:IsKoS(name)
	local list = Guild:List()
	return list and list[name] or nil
end

function Guild:Count()
	local list = Guild:List()
	if not list then return 0 end
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	return n
end

-- ---------------------------------------------------------------------------
-- sending
-- ---------------------------------------------------------------------------

local function send(message)
	if not SquawkSpy.Caps.addonMessage then return false end
	if not IsInGuild() then return false end
	return pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, "GUILD")
end

local function encode(kind, name, note, who, stamp)
	return table.concat({ kind, name or "", note or "", who or "", tostring(stamp or time()) }, SEP)
end

-- ---------------------------------------------------------------------------
-- the two things a player does
-- ---------------------------------------------------------------------------

function Guild:Add(name, note, silent)
	if not name or name == "" then return end
	local list, key = Guild:List()
	if not list then
		SquawkSpy:Print("you are not in a guild, so there is no guild list to add to.")
		return
	end

	note = (note or ""):sub(1, MAX_NOTE)
	local entry = {
		reason = note,
		addedBy = SquawkSpy.CharacterName,
		time = time(),
	}
	list[name] = entry

	if not silent then
		send(encode("ADD", name, note, entry.addedBy, entry.time))
		SquawkSpy:PlayMedia("list-add.mp3")
		SquawkSpy:Print(("%s added to the |cffff8000guild|r Kill on Sight list%s")
			:format(name, note ~= "" and (": " .. note) or "."))
	end
	SquawkSpy:RefreshCurrentList()
	if SquawkSpy.Stats then SquawkSpy.Stats:Update() end
end

function Guild:Remove(name, silent)
	local list = Guild:List()
	if not list or not list[name] then return end
	list[name] = nil

	if not silent then
		send(encode("DEL", name, nil, SquawkSpy.CharacterName, time()))
		SquawkSpy:PlayMedia("list-remove.mp3")
		SquawkSpy:Print(name .. " removed from the guild Kill on Sight list.")
	end
	SquawkSpy:RefreshCurrentList()
	if SquawkSpy.Stats then SquawkSpy.Stats:Update() end
end

function Guild:Note(name)
	local entry = Guild:IsKoS(name)
	if not entry then return nil end
	if entry.reason and entry.reason ~= "" then return entry.reason end
	return nil
end

-- ---------------------------------------------------------------------------
-- receiving
-- ---------------------------------------------------------------------------

local function applyRemote(kind, name, note, who, stamp)
	local list = Guild:List()
	if not list or not name or name == "" then return end
	stamp = tonumber(stamp) or time()

	local existing = list[name]
	-- Newest write wins; an older message cannot undo a newer decision.
	if existing and (existing.time or 0) > stamp then return end

	if kind == "ADD" then
		local isNew = not existing
		list[name] = { reason = note or "", addedBy = who or "?", time = stamp }
		if isNew and SquawkSpy.db.announceGuildKoS then
			SquawkSpy:Print(("|cffff8000guild KoS|r: %s added %s%s")
				:format(who or "someone", name, (note and note ~= "") and (" - " .. note) or ""))
		end
	elseif kind == "DEL" then
		if existing then
			list[name] = nil
			if SquawkSpy.db.announceGuildKoS then
				SquawkSpy:Print(("|cffff8000guild KoS|r: %s cleared %s"):format(who or "someone", name))
			end
		end
	end

	SquawkSpy:RefreshCurrentList()
end

-- Answer a REQ with one message per entry, spread out, and stop if somebody
-- else is clearly already answering.
function Guild:SendFullList()
	local list = Guild:List()
	if not list then return end

	local entries = {}
	for name, entry in pairs(list) do
		entries[#entries + 1] = { name = name, entry = entry }
	end
	if #entries == 0 then return end

	local index = 0
	local ticker
	ticker = C_Timer.NewTicker(0.4, function()
		index = index + 1
		local item = entries[index]
		if not item or Guild.suppressReply then
			ticker:Cancel()
			Guild.suppressReply = nil
			return
		end
		send(encode("ONE", item.name, item.entry.reason, item.entry.addedBy, item.entry.time))
	end, #entries)
end

function Guild:OnMessage(payload, sender)
	if sender and Ambiguate and Ambiguate(sender, "none") == SquawkSpy.CharacterName then return end

	local kind, name, note, who, stamp = strsplit(SEP, payload)

	if kind == "ADD" or kind == "DEL" then
		applyRemote(kind, name, note, who, stamp)
	elseif kind == "ONE" then
		-- Someone is answering a request; stop ours and take their data.
		Guild.suppressReply = true
		applyRemote("ADD", name, note, who, stamp)
	elseif kind == "REQ" then
		-- Stagger, so a whole guild logging in does not answer at once.
		Guild.suppressReply = nil
		C_Timer.After(1 + math.random() * 4, function()
			if not Guild.suppressReply then Guild:SendFullList() end
		end)
	end
end

function Guild:RequestSync()
	if not IsInGuild() then return end
	local now = GetTime()
	if now - Guild.lastRequest < 60 then return end
	Guild.lastRequest = now
	send("REQ")
end

-- ---------------------------------------------------------------------------
-- setup
-- ---------------------------------------------------------------------------

function Guild:Initialize()
	if SquawkSpy.Caps.addonMessage and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("CHAT_MSG_ADDON")
	events:RegisterEvent("PLAYER_GUILD_UPDATE")
	events:SetScript("OnEvent", function(_, event, ...)
		if event == "CHAT_MSG_ADDON" then
			local prefix, payload, _, sender = ...
			if prefix == PREFIX then Guild:OnMessage(payload, sender) end
		else
			C_Timer.After(5, function() Guild:RequestSync() end)
		end
	end)

	-- Ask once, a little after login, when the guild roster is actually there.
	C_Timer.After(8, function() Guild:RequestSync() end)
end
