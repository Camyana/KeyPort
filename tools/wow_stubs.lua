-- ---------------------------------------------------------------------------
--  A small World of Warcraft stand-in, enough to load and drive KeyPort.lua
--  outside the game. Frames record what was set on them so tests can assert on
--  it; every API here mimics the shape the real one returns, because a stub
--  that is wrong in shape hides the bug it was meant to catch.
--
--  Anything a test needs to steer is a global: SetParty, AdvanceClock, fire,
--  CHALLENGE_ACTIVE, and so on.
-- ---------------------------------------------------------------------------

local realprint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    realprint(table.concat(parts, " "))
end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function unpack(t) return table.unpack(t) end
tinsert = table.insert
strmatch = string.match
format = string.format
geterrorhandler = function() return function(e) error(e) end end
securecallfunction = function(f, ...) return f(...) end
WOW_PROJECT_ID = 1
UISpecialFrames = {}
hash_SlashCmdList = {}
SlashCmdList = {}

-- ---------------------------------------------------------------- clocks ---
CLOCK = 100000                     -- GetTime(), seconds since boot
NOW = 1750000000                   -- time(), unix seconds
function GetTime() return CLOCK end
function time() return NOW end
function AdvanceClock(seconds) CLOCK = CLOCK + seconds end

TICKERS = {}
C_Timer = {
    NewTimer = function() return { Cancel = function() end } end,
    After = function() end,
    NewTicker = function(interval, fn)
        local t = { fn = fn, cancelled = false }
        t.Cancel = function(self) (self or t).cancelled = true end
        TICKERS[#TICKERS + 1] = t
        return t
    end,
}
function TickAll()
    for _, t in ipairs(TICKERS) do
        if not t.cancelled then t.fn() end
    end
end

-- --------------------------------------------------------------- widgets ---
local function newRegion()
    local r = { _text = "", _shown = true }
    setmetatable(r, { __index = function(t, k)
        local fn
        -- GetText always hands back a string in the game, even when SetText
        -- was given a number, so match that or tests compare the wrong types.
        if k == "SetText" then fn = function(self, v)
                self._text = (v ~= nil) and tostring(v) or ""
            end
        elseif k == "GetText" then fn = function(self) return self._text end
        elseif k == "GetStringWidth" then fn = function(self)
                local t2 = tostring(self._text or "")
                t2 = t2:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A:.-|a", "")
                return #t2 * 6
            end
        elseif k == "SetTextColor" then fn = function(self, r2, g, b) self._colour = { r2, g, b } end
        elseif k == "SetTexture" then fn = function(self, v) self._texture = v end
        elseif k == "GetTexture" then fn = function(self) return self._texture end
        elseif k == "SetTexCoord" then fn = function(self, ...) self._coords = { ... } end
        elseif k == "SetDesaturated" then fn = function(self, v) self._desaturated = v end
        elseif k == "Show" then fn = function(self) self._shown = true end
        elseif k == "Hide" then fn = function(self) self._shown = false end
        elseif k == "SetShown" then fn = function(self, v) self._shown = v and true or false end
        elseif k == "IsShown" then fn = function(self) return self._shown end
        else fn = function() return nil end end
        rawset(t, k, fn); return fn
    end })
    return r
end

FRAMES = {}
COMBAT = false

function CreateFrame(kind, name, parent, template)
    local f = { _events = {}, _scripts = {}, _shown = false, _attrs = {},
                _w = 320, _h = 260, _secure = template ~= nil }
    setmetatable(f, { __index = function(t, k)
        local fn
        if k == "SetScript" then fn = function(self, e, cb) self._scripts[e] = cb end
        elseif k == "GetScript" then fn = function(self, e) return self._scripts[e] end
        elseif k == "RegisterEvent" then fn = function(self, e) self._events[e] = true end
        elseif k == "UnregisterEvent" then fn = function(self, e) self._events[e] = nil end
        elseif k == "Show" then fn = function(self)
                if COMBAT and self._hasSecureChild then error("BLOCKED: Show in combat") end
                self._shown = true end
        elseif k == "Hide" then fn = function(self)
                if COMBAT and self._hasSecureChild then error("BLOCKED: Hide in combat") end
                self._shown = false end
        elseif k == "IsShown" then fn = function(self) return self._shown end
        elseif k == "CreateTexture" or k == "CreateFontString" or k == "CreateMaskTexture" then
            fn = function() return newRegion() end
        elseif k == "SetAttribute" then fn = function(self, a, v)
                if COMBAT then error("BLOCKED: SetAttribute in combat") end
                self._attrs[a] = v end
        elseif k == "GetAttribute" then fn = function(self, a) return self._attrs[a] end
        elseif k == "SetPoint" then fn = function(self, point, rel, relPoint, x, y)
                self._point = { point, relPoint, x, y } end
        elseif k == "GetPoint" then fn = function() return nil end
        elseif k == "SetSize" then fn = function(self, w, h) self._w, self._h = w, h end
        elseif k == "SetWidth" then fn = function(self, w) self._w = w end
        elseif k == "SetHeight" then fn = function(self, h) self._h = h end
        elseif k == "GetWidth" then fn = function(self) return self._w end
        elseif k == "GetHeight" then fn = function(self) return self._h end
        elseif k == "SetEnabled" then fn = function(self, v) self._enabled = v and true or false end
        elseif k == "IsEnabled" then fn = function(self) return self._enabled ~= false end
        else fn = function() return nil end end
        rawset(t, k, fn); return fn
    end })
    if template and parent then parent._hasSecureChild = true end
    FRAMES[#FRAMES + 1] = f
    if name then _G[name] = f end
    return f
end

--- Deliver an event to every frame listening for it.
function fire(event, ...)
    for _, f in ipairs(FRAMES) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
GameTooltip = setmetatable({}, { __index = function() return function() end end })
function CreateColor(r, g, b, a) return { r, g, b, a } end
UIParent = CreateFrame("Frame")

-- ------------------------------------------------------------- the player ---
local PARTY = {}
PLAYER_NAME, PLAYER_REALM, PLAYER_CLASS = "Camyana", "Draenor", "WARRIOR"
IN_GROUP, IN_RAID, IN_INSTANCE_GROUP = false, false, false
CHALLENGE_ACTIVE = false
OWNED_MAP, OWNED_LEVEL, OWN_RATING = 587, 14, 2500

--- SetParty{ {name = "Bobbo", class = "MAGE"}, ... }
function SetParty(list)
    for i = 1, 4 do PARTY["party" .. i] = nil end
    for i, m in ipairs(list or {}) do PARTY["party" .. i] = m end
    IN_GROUP = #(list or {}) > 0
end

function UnitName(unit)
    if unit == "player" then return PLAYER_NAME end
    local m = PARTY[unit]
    return m and m.name or nil
end
function UnitNameUnmodified(unit) return UnitName(unit) end
function UnitExists(unit) return unit == "player" or PARTY[unit] ~= nil end
function UnitClass(unit)
    if unit == "player" then return PLAYER_CLASS, PLAYER_CLASS end
    local m = PARTY[unit]
    if m then return m.class, m.class end
end
function GetRealmName() return PLAYER_REALM end
function IsInGroup(category)
    if category == 2 then return IN_INSTANCE_GROUP end
    return IN_GROUP
end
function IsInRaid() return IN_RAID end
function IsInInstance() return INSTANCE_TYPE ~= nil, INSTANCE_TYPE end
function GetNumGroupMembers()
    if not IN_GROUP then return 1 end
    local n = 1
    for i = 1, 4 do if PARTY["party" .. i] then n = n + 1 end end
    return n
end
function InCombatLockdown() return COMBAT end
function Ambiguate(name, mode)
    if mode == "none" then return name end            -- LibKeystone wants the realm kept
    return (name:match("^([^%-]+)")) or name
end

RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
    ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
    DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
}
CLASS_ICON_TCOORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49, 0, 0.25 },
    DRUID = { 0.75, 0.98, 0.25, 0.5 }, ROGUE = { 0.49, 0.75, 0, 0.25 },
    PRIEST = { 0.49, 0.75, 0.25, 0.5 }, HUNTER = { 0, 0.25, 0.25, 0.5 },
}
function SetPortraitTexture(texture, unit)
    if not unit or not UnitExists(unit) then error("no such unit") end
    texture._portrait = unit
    texture._texture = "portrait:" .. unit
end
function IsPlayerSpell(id) return KNOWN_SPELLS == nil or KNOWN_SPELLS[id] == true end
KNOWN_SPELLS = nil                                     -- nil means "knows everything"

-- ---------------------------------------------------------------- comms ----
SENT = {}                                              -- addon messages
CHAT = {}                                              -- SendChatMessage
BN_SENT = {}                                           -- BNSendGameData
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return 0 end,
    SendAddonMessage = function(prefix, msg, channel)
        SENT[#SENT + 1] = { prefix = prefix, msg = msg, channel = channel }
    end,
}
function SendChatMessage(text, channel) CHAT[#CHAT + 1] = { text = text, channel = channel } end
function lastSent() return SENT[#SENT] and SENT[#SENT].msg or "-" end
function lastChat() return CHAT[#CHAT] and CHAT[#CHAT].text or "-" end

BNET_CLIENT_WOW = "WoW"
BN_FRIENDS = {}
function BNGetNumFriends() return #BN_FRIENDS end
function BNSendGameData(gameAccountID, prefix, payload)
    BN_SENT[#BN_SENT + 1] = { id = gameAccountID, prefix = prefix, payload = payload }
end
C_BattleNet = {
    GetFriendAccountInfo = function(i) return BN_FRIENDS[i] end,
    GetAccountInfoByID = function(id)
        for _, f in ipairs(BN_FRIENDS) do
            if f.gameAccountInfo.gameAccountID == id then return f end
        end
    end,
}

-- --------------------------------------------------------------- guild -----
GUILD_ROSTER = {}
function IsInGuild() return #GUILD_ROSTER > 0 end
function GetNumGuildMembers() return #GUILD_ROSTER end
function GetGuildRosterInfo(i)
    local m = GUILD_ROSTER[i]
    if not m then return nil end
    return m[1], nil, nil, nil, nil, nil, nil, nil, nil, nil, m[2]
end
C_GuildInfo = { GuildRoster = function() end }

-- ------------------------------------------------------------- dungeons ----
-- This season's pool, plus names for every challenge map KeyPort knows.
SEASON = { 584, 585, 586, 587, 588, 399, 250, 249 }
MAP_NAMES = {
    [161] = "Skyreach", [198] = "Darkheart Thicket", [199] = "Black Rook Hold",
    [200] = "Halls of Valor", [206] = "Neltharion's Lair", [210] = "Court of Stars",
    [227] = "Return to Karazhan: Lower", [234] = "Return to Karazhan: Upper",
    [239] = "Seat of the Triumvirate", [249] = "Kings' Rest",
    [250] = "Temple of Sethraliss", [378] = "Halls of Atonement",
    [391] = "Tazavesh: Streets of Wonder", [392] = "Tazavesh: So'leah's Gambit",
    [399] = "Ruby Life Pools", [402] = "Algeth'ar Academy",
    [499] = "Priory of the Sacred Flame", [503] = "Ara-Kara, City of Echoes",
    [505] = "The Dawnbreaker", [525] = "Operation: Floodgate",
    [542] = "Eco-Dome Al'dani", [556] = "Pit of Saron", [557] = "Windrunner Spire",
    [558] = "Magister's Terrace", [559] = "Nexus-Point Xenas", [560] = "Maisara Caverns",
    [584] = "The Blinding Vale", [585] = "Voidscar Arena", [586] = "Den of Nalorakk",
    [587] = "Murder Row", [588] = "Altar of Fangs",
}
MAP_TEXTURES = {}
for id in pairs(MAP_NAMES) do MAP_TEXTURES[id] = 4000000 + id end
MAP_TEXTURES[584] = nil            -- no map art: the spell icon must stand in

C_ChallengeMode = {
    GetMapTable = function() return SEASON end,
    -- name, id, timeLimit, texture, backgroundTexture
    GetMapUIInfo = function(id) return MAP_NAMES[id], id, 1800, MAP_TEXTURES[id], nil end,
    RequestMapInfo = function() end,
    IsChallengeModeActive = function() return CHALLENGE_ACTIVE end,
    GetDungeonScoreRarityColor = function() return { r = 0.6, g = 0.4, b = 0.9 } end,
}

SEASON_BEST = { [249] = 10, [587] = 14 }               -- [mapID] = level cleared
C_MythicPlus = {
    GetOwnedKeystoneChallengeMapID = function() return OWNED_MAP end,
    GetOwnedKeystoneLevel = function() return OWNED_LEVEL end,
    RequestMapInfo = function() end,
    GetSeasonBestForMap = function(mapID)
        local best = SEASON_BEST[mapID]
        if not best then return nil, nil end
        return { level = best, durationSec = 1500 }, nil
    end,
}
C_PlayerInfo = {
    GetPlayerMythicPlusRatingSummary = function() return { currentSeasonScore = OWN_RATING } end,
}
C_Spell = {
    GetSpellInfo = function(id)
        return (id and id < 2000000) and { name = "Spell " .. id, iconID = 900000 + id } or nil
    end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
}
C_Texture = {
    GetAtlasInfo = function(name)
        return name == "bags-greenarrow" and { width = 16, height = 16 } or nil
    end,
}
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 3 * 86400 end }
EUI_QOL_LOADED = false
C_AddOns = { IsAddOnLoaded = function(name)
    return name == "EllesmereUIQoL" and EUI_QOL_LOADED or false
end }
PlayerIsTimerunning = function() return false end
C_Container = { GetContainerNumSlots = function() return 0 end,
                GetContainerItemID = function() return nil end,
                GetContainerItemLink = function() return nil end }
C_Item = { IsItemKeystoneByID = function() return false end }

-- ---------------------------------------------------------- group finder ---
LFG_ACTIVITIES = {
    [9001] = { fullName = "Kings' Rest (Mythic Keystone)", maxNumPlayers = 5 },
    [9002] = { fullName = "Some Raid (Heroic)", maxNumPlayers = 20 },
}
LFG_RESULTS = { [77] = { activityID = 9001 }, [78] = { activityID = 9002 } }
LFG_ACTIVE_ENTRY = nil
C_LFGList = {
    GetSearchResultInfo = function(id) return LFG_RESULTS[id] end,
    GetActivityInfoTable = function(id) return LFG_ACTIVITIES[id] end,
    GetActiveEntryInfo = function() return LFG_ACTIVE_ENTRY end,
}

-- --------------------------------------------------- slash command plumbing --
--- Rebuild the command hash the way ChatFrame does, from the SLASH_ globals.
function ChatFrame_ImportAllListsToHash()
    for k in pairs(hash_SlashCmdList) do hash_SlashCmdList[k] = nil end
    for name in pairs(SlashCmdList) do
        for i = 1, 32 do
            local alias = _G["SLASH_" .. name .. i]
            if not alias then break end
            hash_SlashCmdList[alias:upper()] = SlashCmdList[name]
        end
    end
end

--- Stand in for another addon that owns /keys, /ekeys and /key.
function InstallRivalKeysAddon()
    for i = 1, 32 do
        if _G["SLASH_KEYPORT" .. i] == "/keys" then _G["SLASH_KEYPORT" .. i] = nil end
    end
    SLASH_RIVALKEYS1, SLASH_RIVALKEYS2, SLASH_RIVALKEYS3 = "/keys", "/ekeys", "/key"
    RIVAL_RAN = nil
    SlashCmdList["RIVALKEYS"] = function() RIVAL_RAN = true end
    ChatFrame_ImportAllListsToHash()
end

--- Type a slash command the way the chat box resolves one.
function TypeSlash(cmd)
    local fn = hash_SlashCmdList[cmd:upper()]
    if not fn then return "unknown" end
    fn("", { GetText = function() return cmd end })
    return "ran"
end
