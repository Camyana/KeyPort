-------------------------------------------------------------------------------
--  KeyPort
--  A dungeon-teleport reminder you can raise on demand for your whole group.
--
--      /kp              -> the group's keystones, pick one, send it
--      /kp KR 10        -> "Kings' Rest +10" popup, with a one-click teleport,
--                          on your screen and on every group member's screen
--                          that also runs KeyPort.
--
--  Group Finder addons pop a teleport reminder when you join a listed group;
--  nothing does it for a premade key you put together in guild chat or Discord.
--  That is the gap this fills.
--
--  Structure
--    GUARDS     when KeyPort refuses to act (raid, active run) or waits (combat)
--    DATA       teleport spell per challenge-mode map (see TELEPORTS)
--    CATALOG    runtime index: map -> name/spell/codes, rebuilt when the
--               season list changes. Short codes are generated from the
--               localized dungeon name, so they work in every client language.
--    UI         one popup frame, built once at login, out of combat
--    COMMS      addon channel share/hide, validated against the local catalog
--    KEYSTONES  the group's keys via LibKeystone, and the picker window
--    SLASH      /kp
--
--  Secure-frame rules (important when editing): the teleport button is a
--  SecureActionButtonTemplate. Its "type" attribute is written once at build
--  time; only "spell" is rewritten later, and never during combat. The popup
--  parents that button, so popup:Hide() is a protected call too. Anything that
--  lands mid-combat is queued and flushed on PLAYER_REGEN_ENABLED.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local KeyPort = {}
_G.KeyPort = KeyPort

local LibKeystone = LibStub and LibStub("LibKeystone", true)

local COMM_PREFIX   = "KeyPort"
local PROTO_SHOW    = "S1"      -- S1:<spellID>:<level>              (1.0, still accepted)
local PROTO_OWNED   = "S2"      -- S2:<spellID>:<level>:<key owner>
local PROTO_HIDE    = "H1"
local ACCENT        = "|cff58c8ff"
local LEVEL_COLOR   = "|cffffd100"
local INSTANCE_CAT  = (Enum and Enum.PartyCategory and Enum.PartyCategory.Instance)
                      or LE_PARTY_CATEGORY_INSTANCE or 2

local function Print(msg)
    print(ACCENT .. "KeyPort|r  " .. msg)
end

-- Defined down in the slash section, used from the login handler.
local ClaimKeysCommand

-------------------------------------------------------------------------------
--  GUARDS
--  KeyPort is a five-player tool for getting a premade key started. It stays
--  out of the way in a raid, and once the run is underway there is nothing
--  left to coordinate, so both are refused outright. Combat is different: the
--  request is still valid, it just cannot be honoured yet (teleports do not
--  cast in combat, and secure frames are locked), so it waits for the pull to
--  end rather than being thrown away.
-------------------------------------------------------------------------------
local function ChallengeModeActive()
    if C_ChallengeMode then
        if C_ChallengeMode.IsChallengeModeActive then
            local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
            if ok and active then return true end
        end
        -- Fallback for clients where IsChallengeModeActive is missing: an
        -- active keystone run always reports a challenge map id.
        if C_ChallengeMode.GetActiveChallengeMapID then
            local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
            if ok and mapID and mapID ~= 0 then return true end
        end
    end
    return false
end

-- Returns a reason string when KeyPort must not act, or nil when it may.
local function BlockedReason()
    if IsInRaid() then
        return "this is a party tool, so it stays quiet in raid groups."
    end
    if ChallengeModeActive() then
        return "not while a Mythic+ run is in progress."
    end
    return nil
end

-------------------------------------------------------------------------------
--  DATA
--  [challengeMapID] = teleportSpellID
--
--  Keys are challenge-mode map IDs, the same IDs C_ChallengeMode.GetMapTable()
--  returns, so the current season's pool is whatever the client reports and
--  only this lookup is static. Dungeon names are never hardcoded -- they come
--  from C_ChallengeMode.GetMapUIInfo(), already localized.
--
--  Adding a dungeon: find its challenge map ID and teleport spell ID and add a
--  line. In game you can also do it without a patch:
--      /kp map <dungeon> <spellID>
--  which stores the pair in your SavedVariables.
-------------------------------------------------------------------------------
local TELEPORTS = {
    -- Warlords of Draenor
    [161] = 159898,   -- Skyreach
    -- Legion
    [198] = 424163,   -- Darkheart Thicket
    [199] = 424153,   -- Black Rook Hold
    [200] = 393764,   -- Halls of Valor
    [206] = 410078,   -- Neltharion's Lair
    [210] = 393766,   -- Court of Stars
    [227] = 373262,   -- Return to Karazhan: Lower
    [234] = 373262,   -- Return to Karazhan: Upper
    [239] = 1254551,  -- Seat of the Triumvirate
    -- Battle for Azeroth
    [249] = 1286831,  -- Kings' Rest
    [250] = 1286828,  -- Temple of Sethraliss
    -- Shadowlands
    [378] = 354465,   -- Halls of Atonement
    [391] = 367416,   -- Tazavesh: Streets of Wonder
    [392] = 367416,   -- Tazavesh: So'leah's Gambit
    -- Dragonflight
    [399] = 393256,   -- Ruby Life Pools
    [402] = 393273,   -- Algeth'ar Academy
    -- The War Within
    [499] = 445444,   -- Priory of the Sacred Flame
    [503] = 445417,   -- Ara-Kara, City of Echoes
    [505] = 445414,   -- The Dawnbreaker
    [525] = 1216786,  -- Operation: Floodgate
    [542] = 1237215,  -- Eco-Dome Al'dani
    -- Midnight
    [556] = 1254555,  -- Pit of Saron
    [557] = 1254400,  -- Windrunner Spire
    [558] = 1254572,  -- Magister's Terrace
    [559] = 1254563,  -- Nexus-Point Xenas
    [560] = 1254559,  -- Maisara Caverns
    [584] = 1286801,  -- The Blinding Vale
    [585] = 1286804,  -- Voidscar Arena
    [586] = 1286807,  -- Den of Nalorakk
    [587] = 1286809,  -- Murder Row
    [588] = 1286812,  -- Altar of Fangs
}

-------------------------------------------------------------------------------
--  SAVED VARIABLES
-------------------------------------------------------------------------------
local db

local function InitDB()
    _G.KeyPortDB = _G.KeyPortDB or {}
    db = _G.KeyPortDB
    if db.acceptShares == nil then db.acceptShares = true end
    if db.announce == nil then db.announce = true end
    -- off | auto | force. KeyPort takes /keys by default; keysCommandSet
    -- records that the player picked a mode themselves, so their choice
    -- survives an update that changes this default.
    if db.keysCommandSet then
        db.keysCommand = db.keysCommand or "force"
    else
        db.keysCommand = "force"
    end
    db.scale  = tonumber(db.scale) or 1
    db.custom = db.custom or {}   -- [challengeMapID] = spellID, user supplied
    db.alts   = db.alts   or {}   -- ["Name-Realm"] = this character's keystone
    db.friends = db.friends or {} -- ["Name-Realm"] = a Battle.net friend's key
    if db.friendShare == nil then db.friendShare = true end
    db.recent = nil               -- the recent list became the friends list
    return db
end

-------------------------------------------------------------------------------
--  CATALOG
-------------------------------------------------------------------------------
local catalog = {
    byMap   = {},   -- [mapID]   = entry
    bySpell = {},   -- [spellID] = entry   (whitelist for incoming messages)
    codes   = {},   -- [code]    = entry
    codeList = {},  -- ordered codes, for deterministic prefix matching
    season  = {},   -- entries in this season's pool, in Blizzard's order
    all     = {},   -- every entry we know a name for
}
local catalogReady = false

-- Strip case, punctuation and whitespace: "Kings' Rest" -> "kingsrest".
local function Squash(text)
    return (tostring(text):lower():gsub("%s*%b()%s*$", ""):gsub("[^%w]", ""))
end

-- Leading article, in the client's language where we can tell. English "the"
-- is stripped so "The Blinding Vale" yields the code players actually type.
local function StripArticle(name)
    return (name:gsub("^[Tt][Hh][Ee]%s+", ""))
end

-- Player-facing short code, in the spelling players already use:
--   "Den of Nalorakk"   -> "DoN"   (each word's own first letter, own case)
--   "The Blinding Vale" -> "BV"    (leading article dropped)
--   "Skyreach"          -> "Sky"   (one word: initials would be a single letter)
local function WordsOf(text)
    local words = {}
    for word in text:gmatch("[%w']+") do words[#words + 1] = word end
    return words
end

local function InitialsOf(name)
    local words = WordsOf(StripArticle(name))
    -- Dropping the article left a single word ("The Dawnbreaker"): put it back
    -- rather than reduce the dungeon to one letter.
    if #words < 2 then words = WordsOf(name) end
    if #words == 0 then return "" end
    if #words == 1 then return words[1]:sub(1, 3) end
    local out = {}
    for i, word in ipairs(words) do out[i] = word:sub(1, 1) end
    return table.concat(out)
end

local function AddCode(code, entry)
    if code == "" or catalog.codes[code] then return end
    catalog.codes[code] = entry
    catalog.codeList[#catalog.codeList + 1] = code
end

local function TeleportFor(mapID)
    return (db and db.custom and db.custom[mapID]) or TELEPORTS[mapID]
end

local function MakeEntry(mapID, inSeason)
    if not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
    -- name, id, timeLimit, texture, backgroundTexture
    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
    if type(name) ~= "string" or name == "" then return nil end
    return {
        mapID    = mapID,
        name     = name,
        icon     = (type(texture) == "number" and texture ~= 0) and texture or nil,
        spellID  = TeleportFor(mapID),
        code     = InitialsOf(name),
        inSeason = inSeason or false,
    }
end

local function IndexEntry(entry)
    catalog.byMap[entry.mapID] = entry
    catalog.all[#catalog.all + 1] = entry
    if entry.spellID then catalog.bySpell[entry.spellID] = entry end
    AddCode(Squash(entry.code), entry)
    AddCode(Squash(entry.name), entry)
    AddCode(Squash(StripArticle(entry.name)), entry)
end

-- Season dungeons are indexed first so their codes win any collision with an
-- older dungeon that shares the same initials.
local function BuildCatalog()
    wipe(catalog.byMap); wipe(catalog.bySpell); wipe(catalog.codes)
    wipe(catalog.codeList); wipe(catalog.season); wipe(catalog.all)

    local pool = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
    if type(pool) == "table" then
        for _, mapID in ipairs(pool) do
            local entry = MakeEntry(mapID, true)
            if entry then
                catalog.season[#catalog.season + 1] = entry
                IndexEntry(entry)
            end
        end
    end

    local extra = {}
    for mapID in pairs(TELEPORTS) do
        if not catalog.byMap[mapID] then extra[#extra + 1] = mapID end
    end
    if db then
        for mapID in pairs(db.custom) do
            if not catalog.byMap[mapID] then extra[#extra + 1] = mapID end
        end
    end
    table.sort(extra)
    for _, mapID in ipairs(extra) do
        local entry = MakeEntry(mapID, false)
        if entry then IndexEntry(entry) end
    end

    catalogReady = #catalog.all > 0
    return catalogReady
end

-- Challenge-mode names are not always available the instant we log in, so the
-- build is retried until it yields something.
local function Catalog()
    if not catalogReady then BuildCatalog() end
    return catalogReady
end

-- Exact code, then unique prefix, then unique substring. Season dungeons take
-- precedence when a query matches both a current and an older dungeon.
local function Lookup(query)
    if not Catalog() then return nil end
    local q = Squash(query)
    if q == "" then return nil end

    local exact = catalog.codes[q]
    if exact then return exact end

    local function collect(test)
        local hits, seen = {}, {}
        for _, code in ipairs(catalog.codeList) do
            if test(code) then
                local entry = catalog.codes[code]
                if not seen[entry] then seen[entry] = true; hits[#hits + 1] = entry end
            end
        end
        return hits
    end

    local hits = collect(function(code) return code:sub(1, #q) == q end)
    if #hits == 0 then
        hits = collect(function(code) return code:find(q, 1, true) ~= nil end)
    end
    if #hits > 1 then
        local seasonHits = {}
        for _, entry in ipairs(hits) do
            if entry.inSeason then seasonHits[#seasonHits + 1] = entry end
        end
        if #seasonHits > 0 then hits = seasonHits end
    end

    if #hits == 1 then return hits[1] end
    return nil, hits
end

-------------------------------------------------------------------------------
--  SEASON BESTS
--  "Is this key above what I have already cleared?" is answered per viewer, so
--  the same shared popup reads differently for each member of the party: green
--  for the people it would be a personal best for, gold for everyone else.
-------------------------------------------------------------------------------
local ABOVE_COLOR = "|cff40e070"
local bestByMap = {}      -- [mapID] = best level completed this season, any timing

local function RefreshSeasonBests()
    wipe(bestByMap)
    if not (C_MythicPlus and C_MythicPlus.GetSeasonBestForMap) then return end
    for _, entry in ipairs(catalog.all) do
        -- Returns intimeInfo, overtimeInfo; either may be nil. A key you only
        -- ever depleted still counts as "done", so both are considered.
        local ok, intime, overtime = pcall(C_MythicPlus.GetSeasonBestForMap, entry.mapID)
        if ok then
            local best = 0
            if type(intime) == "table" and type(intime.level) == "number" then
                best = math.max(best, intime.level)
            end
            if type(overtime) == "table" and type(overtime.level) == "number" then
                best = math.max(best, overtime.level)
            end
            if best > 0 then bestByMap[entry.mapID] = best end
        end
    end
end

-- Returns isAbove, bestLevel. A dungeon never completed this season counts as
-- above, because any key in it is new ground.
local function AboveSeasonBest(mapID, level)
    if not mapID or not level or level <= 0 then return false, nil end
    local best = bestByMap[mapID]
    if not best then return true, nil end
    return level > best, best
end

-- The up-arrow is decoration: if no suitable atlas exists on this client, the
-- colour still carries the meaning.
local upAtlas
local function UpArrowMarkup()
    if upAtlas == nil then
        upAtlas = false
        if C_Texture and C_Texture.GetAtlasInfo then
            for _, name in ipairs({ "bags-greenarrow", "NPE_ArrowUp", "poi-door-arrow-up" }) do
                local ok, info = pcall(C_Texture.GetAtlasInfo, name)
                if ok and info then upAtlas = name; break end
            end
        end
    end
    return upAtlas and ("|A:" .. upAtlas .. ":12:12|a") or ""
end

-- "+12" coloured, with an arrow when it beats the viewer's own best.
local function LevelMarkup(mapID, level)
    if not level or level <= 0 then return "" end
    local above = AboveSeasonBest(mapID, level)
    if above then
        return ABOVE_COLOR .. UpArrowMarkup() .. "+" .. level .. "|r"
    end
    return LEVEL_COLOR .. "+" .. level .. "|r"
end

-------------------------------------------------------------------------------
--  UI
-------------------------------------------------------------------------------
local PANEL_W    = 220
local HEADER_H   = 26
local EDGE       = 10
local NAME_Y     = HEADER_H + 8
local NAME_H     = 24
local BUTTON_Y   = NAME_Y + NAME_H
local BUTTON_H   = 54
local ICON_SZ    = 38
local FOOTER_Y   = BUTTON_Y + BUTTON_H + 7
local FOOTER_H   = 14
local PANEL_H    = FOOTER_Y + FOOTER_H + 9

local panel, teleportBtn

-- Current popup contents. Every value here is derived from the local catalog,
-- never from a network payload.
local shown = { spellID = nil, mapID = nil, name = nil, level = 0, footer = "" }

-- Work that combat blocked, flushed on PLAYER_REGEN_ENABLED.
local queued = { build = false, attr = nil, show = false, hide = false }

local UIFont = select(1, GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"

local function Label(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(UIFont, size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetTextColor(r or 1, g or 1, b or 1, 1)
    return fs
end

-- Four 1px textures rather than a backdrop: no template dependency and it stays
-- crisp at any UI scale.
local function Outline(frame, r, g, b, a)
    local edges = {}
    for i = 1, 4 do
        local tex = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(r, g, b, a)
        edges[i] = tex
    end
    edges[1]:SetPoint("TOPLEFT");     edges[1]:SetPoint("TOPRIGHT");    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT");  edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT");     edges[3]:SetPoint("BOTTOMLEFT");  edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT");    edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    return edges
end

local function SavePosition()
    if not panel then return end
    local point, _, relPoint, x, y = panel:GetPoint()
    if point then db.pos = { point = point, relPoint = relPoint, x = x, y = y } end
end

-- EllesmereUI's LFG Reminder defaults to CENTER, 0, 150, and so did this, so
-- the two landed exactly on top of each other: two teleport buttons in the same
-- place, one of them stale, both looking right. Sit clear of it when that addon
-- is present rather than fighting over the spot.
local function DefaultAnchorY()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
    if loaded then
        local ok, present = pcall(loaded, "EllesmereUIQoL")
        if ok and present then return -20 end
    end
    return 150
end

-- Declared as a local up here because /kp reset, far below, calls it.
local RestorePosition
RestorePosition = function()
    if not panel then return end
    panel:ClearAllPoints()
    local pos = db and db.pos
    if pos and pos.point then
        panel:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, DefaultAnchorY())
    end
end

local function BuildPanel()
    if panel then return panel end

    panel = CreateFrame("Frame", "KeyPortPopup", UIParent)
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.94)

    local sheen = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(PANEL_H * 0.6)
    sheen:SetColorTexture(1, 1, 1, 1)
    if sheen.SetGradient and CreateColor then
        sheen:SetGradient("VERTICAL", CreateColor(0.10, 0.14, 0.18, 0), CreateColor(0.16, 0.24, 0.32, 0.55))
    else
        sheen:SetColorTexture(0.12, 0.18, 0.24, 0.25)
    end

    Outline(panel, 0, 0, 0, 1)

    local header = panel:CreateTexture(nil, "BORDER")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    header:SetColorTexture(0, 0, 0, 0.45)

    local accentLine = panel:CreateTexture(nil, "ARTWORK")
    accentLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(1)
    accentLine:SetColorTexture(0.35, 0.78, 1, 0.55)

    local title = Label(panel, 11, 0.35, 0.78, 1)
    title:SetPoint("LEFT", header, "LEFT", EDGE, 0)
    title:SetText("KeyPort")

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(HEADER_H - 8, HEADER_H - 8)
    close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    local closeText = Label(close, 13, 0.55, 0.55, 0.55)
    closeText:SetAllPoints()
    closeText:SetJustifyH("CENTER")
    closeText:SetText("\195\151")   -- multiplication sign
    close:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.35, 0.35) end)
    close:SetScript("OnLeave", function() closeText:SetTextColor(0.55, 0.55, 0.55) end)
    close:SetScript("OnClick", function() KeyPort.Hide() end)

    local dungeon = Label(panel, 13, 1, 1, 1)
    dungeon:SetPoint("TOPLEFT", EDGE, -NAME_Y)
    dungeon:SetPoint("TOPRIGHT", -EDGE, -NAME_Y)
    dungeon:SetJustifyH("CENTER")
    dungeon:SetWordWrap(true)
    panel.dungeon = dungeon

    -- Secure button: "type" is set here and never touched again.
    teleportBtn = CreateFrame("Button", "KeyPortTeleportButton", panel, "SecureActionButtonTemplate")
    teleportBtn:SetSize(PANEL_W - EDGE * 2, BUTTON_H)
    teleportBtn:SetPoint("TOP", panel, "TOP", 0, -BUTTON_Y)
    teleportBtn:RegisterForClicks("AnyUp", "AnyDown")
    teleportBtn:SetAttribute("type", "spell")

    local btnBg = teleportBtn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints()
    btnBg:SetColorTexture(0.02, 0.02, 0.03, 0.9)
    Outline(teleportBtn, 0.35, 0.78, 1, 0.35)

    local icon = teleportBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    teleportBtn.icon = icon

    local caption = Label(teleportBtn, 12, 1, 1, 1)
    caption:SetPoint("LEFT", icon, "RIGHT", 9, 0)
    caption:SetPoint("RIGHT", -6, 0)
    caption:SetJustifyH("LEFT")
    caption:SetWordWrap(false)
    caption:SetText("Teleport")
    teleportBtn.caption = caption

    local highlight = teleportBtn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.10)

    -- Anchored to the button frame, not to the icon texture: a cooldown frame
    -- inherits the button's protection and cannot be parented to a region.
    local cooldown = CreateFrame("Cooldown", nil, teleportBtn, "CooldownFrameTemplate")
    cooldown:SetPoint("LEFT", teleportBtn, "LEFT", 8, 0)
    cooldown:SetSize(ICON_SZ, ICON_SZ)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetDrawSwipe(true)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(false)
    teleportBtn.cooldown = cooldown

    teleportBtn:SetScript("OnEnter", function(self)
        local spellID = shown.spellID
        if not spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("KeyPort", 0.35, 0.78, 1)
        if not IsPlayerSpell(spellID) then
            GameTooltip:AddLine("You have not learned this teleport yet.", 1, 0.4, 0.4, true)
        else
            local cd = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
            if cd and cd.duration and cd.duration > 0 then
                GameTooltip:AddLine("Teleport is on cooldown.", 1, 0.8, 0.2, true)
            else
                GameTooltip:AddLine("Click to teleport to " .. (shown.name or "the dungeon") .. ".", 1, 1, 1, true)
            end
        end
        GameTooltip:Show()
    end)
    teleportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local footer = Label(panel, 10, 0.55, 0.55, 0.55)
    footer:SetPoint("TOPLEFT", EDGE, -FOOTER_Y)
    footer:SetPoint("TOPRIGHT", -EDGE, -FOOTER_Y)
    footer:SetJustifyH("CENTER")
    footer:SetWordWrap(false)
    panel.footer = footer

    panel:SetScale(db.scale or 1)
    RestorePosition()
    panel:Hide()
    return panel
end

local function PaintText()
    if not panel then return end
    local text = shown.name or ""
    if (shown.level or 0) > 0 then
        -- Coloured against *this* player's season best, so the same shared
        -- popup reads green only for the people it is new ground for.
        text = text .. "  " .. LevelMarkup(shown.mapID, shown.level)
    end
    panel.dungeon:SetText(text)
    panel.footer:SetText(shown.footer or "")
end

local function PaintButton()
    if not teleportBtn or not shown.spellID then return end
    local spellID = shown.spellID
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if info and info.iconID then teleportBtn.icon:SetTexture(info.iconID) end

    local known = IsPlayerSpell(spellID)
    teleportBtn.icon:SetDesaturated(not known)
    teleportBtn.icon:SetAlpha(known and 1 or 0.35)
    teleportBtn.caption:SetText(known and "Teleport" or "Teleport not learned")
    local tint = known and 1 or 0.5
    teleportBtn.caption:SetTextColor(tint, tint, tint)

    local cd = known and C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    if cd and cd.startTime and cd.duration and cd.duration > 0 then
        teleportBtn.cooldown:SetCooldown(cd.startTime, cd.duration)
    else
        teleportBtn.cooldown:Clear()
    end
end

-------------------------------------------------------------------------------
--  EVENTS  (declared before Show/Hide, which register cooldown/combat events)
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")

--- Raise the popup for a catalog entry.
-- @param entry  a catalog entry (never a value taken from a network payload)
-- @param level  keystone level, 0 for none
-- @param footer small text under the button
function KeyPort.Show(entry, level, footer)
    if not entry or not entry.spellID then return end

    RefreshSeasonBests()
    shown.spellID = entry.spellID
    shown.mapID   = entry.mapID
    shown.name    = entry.name
    shown.level   = tonumber(level) or 0
    shown.footer  = footer or ""

    if not panel then
        if InCombatLockdown() then
            -- Building writes a secure attribute: wait for combat to end.
            queued.build, queued.show, queued.hide = true, true, false
            queued.attr = shown.spellID
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        BuildPanel()
    end

    PaintText()

    if InCombatLockdown() then
        queued.attr, queued.show, queued.hide = shown.spellID, true, false
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    teleportBtn:SetAttribute("spell", shown.spellID)
    queued.attr, queued.hide = nil, false
    PaintButton()
    panel:Show()
    events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
end

function KeyPort.Hide()
    queued.show = false
    events:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    if not (panel and panel:IsShown()) then queued.hide = false; return end
    if InCombatLockdown() then
        -- panel parents a secure button, so Hide() is protected in combat.
        queued.hide = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    queued.hide = false
    panel:Hide()
end

function KeyPort.Refresh()
    if not panel then return end
    panel:SetScale(db.scale or 1)
    PaintText()
    PaintButton()
end

-------------------------------------------------------------------------------
--  COMMS
-------------------------------------------------------------------------------
local recentMessages = {}   -- ["sender\0payload"] = GetTime()
local lastStaleWarning = 0

-- Party channels only: a raid group is refused by BlockedReason, so there is
-- deliberately no RAID case here.
local function GroupChannel()
    if IsInRaid() then return nil end
    if IsInGroup(INSTANCE_CAT) then return "INSTANCE_CHAT" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function Broadcast(payload)
    local channel = GroupChannel()
    if not channel then return nil end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, payload, channel)
        return channel
    end
    return nil
end

-- One line in party chat when a key is sent, so members without KeyPort still
-- learn which dungeon was picked. Off with /kp announce.
local lastAnnounce = { text = nil, at = 0 }

local function AnnounceToParty(dungeon, level, owner)
    if not db.announce then return end
    if type(dungeon) ~= "string" or dungeon == "" then return end
    local channel = GroupChannel()
    if not channel or not SendChatMessage then return end

    local text = dungeon
    if level and level > 0 then text = text .. " +" .. level end
    if owner and owner ~= "" then text = text .. " (" .. owner .. "'s key)" end
    text = "KeyPort: " .. text

    -- Never say the same thing twice in a row within a couple of seconds, so a
    -- double-click on Send cannot double-post.
    local now = GetTime()
    if lastAnnounce.text == text and (now - lastAnnounce.at) < 3 then return end
    lastAnnounce.text, lastAnnounce.at = text, now

    SendChatMessage(text, channel)
end

local function ShortName(sender)
    if not sender then return "?" end
    return (Ambiguate and Ambiguate(sender, "short")) or sender:match("^([^%-]+)") or sender
end

local function IsFromSelf(sender)
    return ShortName(sender) == UnitName("player")
end

-- A name arriving over the wire is display-only, but it still lands in a
-- FontString, so strip anything that could turn into markup (|c colour codes,
-- |H hyperlinks, |T textures) and cap the length.
local HandleVoteMessage   -- defined with the voting section, below

local function CleanName(raw)
    if type(raw) ~= "string" then return nil end
    local name = raw
        :gsub("|c%x%x%x%x%x%x%x%x", "")   -- colour open
        :gsub("|r", "")                    -- colour close
        :gsub("|H.-|h(.-)|h", "%1")        -- hyperlink, keep the visible text
        :gsub("|T.-|t", "")                -- inline texture
        :gsub("|", "")                     -- anything else pipe-shaped
        :gsub("%c", "")
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    if #name > 24 then name = name:sub(1, 24) end
    return name
end

-- Footer line for a share: whose key it is, and who put it on screen.
local function CreditLine(owner, sender)
    if owner and owner ~= "" then
        if owner == sender then return owner .. "'s key" end
        return owner .. "'s key, via " .. sender
    end
    return "Shared by " .. sender
end

local function HandleMessage(payload, sender)
    if not db.acceptShares then return end
    if not IsInGroup() then return end
    if IsFromSelf(sender) then return end   -- our own broadcast echoes back
    if BlockedReason() then return end      -- raid group, or a run in progress

    -- Drop a repeat of the same payload, but never swallow a different one:
    -- correcting the key or hiding right after a share has to get through.
    local now = GetTime()
    local fingerprint = sender .. "\0" .. payload
    if recentMessages[fingerprint] and (now - recentMessages[fingerprint]) < 2 then return end
    recentMessages[fingerprint] = now

    if HandleVoteMessage(payload, sender) then return end

    if payload == PROTO_HIDE then
        KeyPort.Hide()
        return
    end

    -- S2 carries the key's owner; S1 (1.0.0) did not, and is still accepted.
    local rawSpell, rawLevel, rawOwner = payload:match("^" .. PROTO_OWNED .. ":(%d+):(%d+):(.+)$")
    if not rawSpell then
        rawSpell, rawLevel = payload:match("^" .. PROTO_SHOW .. ":(%d+):(%d+)$")
    end
    if not rawSpell then return end

    local owner = CleanName(rawOwner)
    local spellID = tonumber(rawSpell)
    local level   = tonumber(rawLevel) or 0
    if level < 0 or level > 100 then level = 0 end
    if not spellID or not Catalog() then return end

    -- The payload only selects a local entry. An id we do not know is dropped,
    -- so a group member cannot put an arbitrary spell on the button.
    local entry = catalog.bySpell[spellID]
    if not entry then
        if (now - lastStaleWarning) > 60 then
            lastStaleWarning = now
            Print(ShortName(sender) .. " shared a dungeon this version does not know. "
                  .. "Update KeyPort, or add it with " .. ACCENT .. "/kp map|r.")
        end
        return
    end

    KeyPort.Show(entry, level, CreditLine(owner, ShortName(sender)))
end

-------------------------------------------------------------------------------
--  GROUP AND GUILD KEYSTONES
--  Keys come from LibKeystone, the same library DBM, BigWigs and friends embed,
--  so both lists fill up from anyone running one of those; they do not need
--  KeyPort. We answer their requests in return, by virtue of embedding it.
-------------------------------------------------------------------------------
local ACCENT_RGB   = { 0.35, 0.78, 1 }
local MIN_W        = 240
local DEFAULT_W    = 320
local MAX_W        = 560
local ROW_H        = 26
local MIN_ROWS     = 3
local MAX_ROWS     = 24         -- the guild list can be long; the party caps at 5
local PARTY_SIZE   = 5
local AVATAR_SZ    = 20
local DUNGEON_SZ   = 18
local LIST_PAD     = 8          -- inset from the window edge to a row
local TAB_H        = 22
local COLHDR_H     = 14
local SCORE_W      = 36
local NAME_W       = 64
local ROW_FONT     = 10

local keystones = {}            -- party: [short name] = { mapID, level, rating, at }
local guildKeys = {}            -- guild: same shape
local guildClass = {}           -- [short name] = classFile, from the guild roster
local keyList                   -- the picker frame
local selection                 -- { name, mapID, level, tab }
local activeTab = "PARTY"
local scrollOffset = 0

-- Voting state lives here because the list reads it; the logic that drives it
-- is in the VOTING section, further down.
local vote = { active = false }
-- Composing is the step before a vote: the ballot is being put together
-- locally and nothing has been sent yet.
local composing = false
local ballotPick = {}          -- [owner name] = true, the keys going on it
local VoteRows, VoteStatusText, ClearVote
local visibleRows = PARTY_SIZE

local function ShortUnitName(unit)
    return UnitName(unit)
end

local function Store(tab)
    return tab == "GUILD" and guildKeys or keystones
end

-- The unit token behind a party member's name, for portraits and colours.
local function UnitForName(name)
    if not name then return nil end
    for i = 0, PARTY_SIZE - 1 do
        local unit = (i == 0) and "player" or ("party" .. i)
        if UnitExists(unit) and ShortUnitName(unit) == name then return unit end
    end
    return nil
end

-- Keystones reset weekly, so anything recorded before this week's reset is
-- last week's key and no longer real.
local function WeekStart()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, secs = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(secs) == "number" and secs > 0 then
            return (time and time() or 0) + secs - 604800
        end
    end
    return 0
end

local function FullName(name, realm)
    realm = (realm and realm ~= "" and realm) or (GetRealmName and GetRealmName()) or "?"
    return name .. "-" .. (realm:gsub("%s+", ""))
end

local FRIEND_LIMIT = 60   -- keep the list from growing forever

-- Rough, friendly age of a record.
local function TimeAgo(stamp)
    if not stamp or stamp <= 0 then return "unknown" end
    local seconds = ((time and time()) or 0) - stamp
    if seconds < 120 then return "just now" end
    if seconds < 5400 then return math.floor(seconds / 60) .. " min ago" end
    if seconds < 172800 then return math.floor(seconds / 3600) .. " hours ago" end
    return math.floor(seconds / 86400) .. " days ago"
end

-- Drop the oldest entries once the list gets long.
local function PruneFriends()
    local order = {}
    for full, rec in pairs(db.friends) do order[#order + 1] = { full = full, at = rec.seen or 0 } end
    if #order <= FRIEND_LIMIT then return end
    table.sort(order, function(a, b) return a.at > b.at end)
    for i = FRIEND_LIMIT + 1, #order do db.friends[order[i].full] = nil end
end

--- Record what a Battle.net friend answered with.
local function RecordFriend(fullName, classFile, level, mapID, rating, account)
    if not db or not db.friends or not fullName then return end
    local previous = db.friends[fullName] or {}
    db.friends[fullName] = {
        name = fullName:match("^([^%-]+)") or fullName,
        realm = fullName:match("%-(.+)$") or previous.realm,
        classFile = classFile or previous.classFile,
        account = account or previous.account,
        mapID = (mapID or 0) > 0 and mapID or nil,
        level = level or 0,
        rating = rating or previous.rating or 0,
        seen = (time and time()) or 0,
    }
    PruneFriends()
    if keyList and keyList:IsShown() and activeTab == "FRIENDS" then
        KeyPort.RefreshKeyList()
    end
end

-------------------------------------------------------------------------------
--  Battle.net friends
--  LibKeystone only speaks PARTY and GUILD, so friends are asked directly over
--  Battle.net game data. Only friends who also run KeyPort can answer; there is
--  no way to read a keystone off someone who is not broadcasting it.
-------------------------------------------------------------------------------
local FRIEND_ASK, FRIEND_TELL = "FQ1", "FA1"
local FRIEND_ASK_THROTTLE = 20
local MAX_FRIENDS_ASKED = 40
local lastFriendAsk = 0

local function OwnKeystoneReport()
    local mapID = (C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID
                   and C_MythicPlus.GetOwnedKeystoneChallengeMapID()) or 0
    local level = (C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel
                   and C_MythicPlus.GetOwnedKeystoneLevel()) or 0
    local rating = 0
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        if ok and type(summary) == "table" and type(summary.currentSeasonScore) == "number" then
            rating = summary.currentSeasonScore
        end
    end
    local _, classFile = UnitClass("player")
    local name = UnitName("player") or "?"
    local realm = (GetRealmName and GetRealmName() or ""):gsub("%s+", "")
    return ("%s:%d:%d:%d:%s:%s-%s"):format(FRIEND_TELL, mapID or 0, level or 0, rating,
                                           classFile or "", name, realm)
end

local function SendToFriend(gameAccountID, payload)
    if not (BNSendGameData and gameAccountID) then return end
    pcall(BNSendGameData, gameAccountID, COMM_PREFIX, payload)
end

--- Ask every Battle.net friend playing WoW what key they are holding.
local function AskFriends(force)
    if not db.friendShare then return 0 end
    local now = GetTime()
    if not force and (now - lastFriendAsk) < FRIEND_ASK_THROTTLE then return 0 end
    lastFriendAsk = now

    local total = (BNGetNumFriends and BNGetNumFriends()) or 0
    local asked = 0
    for i = 1, total do
        if asked >= MAX_FRIENDS_ASKED then break end
        local account = C_BattleNet and C_BattleNet.GetFriendAccountInfo
                        and C_BattleNet.GetFriendAccountInfo(i)
        local game = account and account.gameAccountInfo
        if game and game.isOnline and game.gameAccountID
           and game.clientProgram == (BNET_CLIENT_WOW or "WoW") then
            SendToFriend(game.gameAccountID, FRIEND_ASK)
            asked = asked + 1
        end
    end
    return asked
end

--- A friend's addon spoke to us. Everything is validated before it is stored.
local function HandleFriendMessage(payload, bnSenderID)
    if type(payload) ~= "string" then return end
    if not db.friendShare then return end

    if payload == FRIEND_ASK then
        local account = C_BattleNet and C_BattleNet.GetAccountInfoByID
                        and C_BattleNet.GetAccountInfoByID(bnSenderID)
        local game = account and account.gameAccountInfo
        if game and game.gameAccountID then SendToFriend(game.gameAccountID, OwnKeystoneReport()) end
        return
    end

    local rawMap, rawLevel, rawRating, class, who =
        payload:match("^" .. FRIEND_TELL .. ":(%d+):(%d+):(%d+):(%a*):(.+)$")
    if not rawMap then return end

    local mapID, level, rating = tonumber(rawMap), tonumber(rawLevel), tonumber(rawRating)
    local fullName = CleanName(who)
    if not fullName or fullName == "" then return end
    if not level or level < 0 or level > 100 then level = 0 end
    if not rating or rating < 0 or rating > 100000 then rating = 0 end
    -- A dungeon we do not know is dropped, and the level goes with it: half a
    -- keystone would sort as if it were real and display as if it were not.
    if mapID and mapID > 0 and not catalog.byMap[mapID] then mapID, level = 0, 0 end
    -- The class only matters as a colour key, so anything unknown is dropped.
    local colours = (_G.CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
    if class == "" or not (colours and colours[class]) then class = nil end

    local account = C_BattleNet and C_BattleNet.GetAccountInfoByID
                    and C_BattleNet.GetAccountInfoByID(bnSenderID)
    RecordFriend(fullName, class, level, mapID, rating,
                 account and (account.accountName or account.battleTag))
end

--- Record this character's keystone in the account-wide list.
function KeyPort.RecordOwnKeystone()
    if not db or not C_MythicPlus then return end
    local name = UnitName("player")
    if not name then return end

    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID
                  and C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0
    local level = C_MythicPlus.GetOwnedKeystoneLevel
                  and C_MythicPlus.GetOwnedKeystoneLevel() or 0
    local rating = 0
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        if ok and type(summary) == "table" and type(summary.currentSeasonScore) == "number" then
            rating = summary.currentSeasonScore
        end
    end
    local _, classFile = UnitClass("player")

    db.alts[FullName(name)] = {
        name = name,
        realm = (GetRealmName and GetRealmName()) or "?",
        classFile = classFile,
        mapID = (mapID or 0) > 0 and mapID or nil,
        level = level or 0,
        rating = rating,
        updated = (time and time()) or 0,
    }
end

-- Everyone in the party, player first, in roster order.
local function Roster()
    local members = { { name = ShortUnitName("player"), unit = "player" } }
    for i = 1, PARTY_SIZE - 1 do
        local unit = "party" .. i
        if UnitExists(unit) then
            members[#members + 1] = { name = ShortUnitName(unit), unit = unit }
        end
    end
    return members
end

-- Guild members are not units, so their class comes from the roster instead.
local function RefreshGuildRoster()
    wipe(guildClass)
    if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return end
    local total = GetNumGuildMembers()
    for i = 1, (total or 0) do
        local full, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if full and classFile then
            local short = (Ambiguate and Ambiguate(full, "short")) or full:match("^([^%-]+)")
            if short then guildClass[short] = classFile end
        end
    end
end

local function ClassRGBFor(unit, classFile)
    local class = classFile
    if not class and unit and UnitExists(unit) then
        local _, c = UnitClass(unit)
        class = c
    end
    local colours = (_G.CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
    local col = class and colours and colours[class]
    if col then return col.r, col.g, col.b end
    return 0.85, 0.85, 0.85
end

-- Class icon from the shared sheet, used when no portrait is available.
local function ApplyClassIcon(texture, unit, classFile)
    local class = classFile
    if not class and unit and UnitExists(unit) then
        local _, c = UnitClass(unit)
        class = c
    end
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        texture:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
        texture:SetTexCoord(unpack(coords))
        return true
    end
    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return false
end

-- A real unit portrait where one exists, the class icon otherwise. Guild rows
-- never have a unit, so they always land on the class icon.
local function ApplyAvatar(texture, unit, classFile)
    if unit and UnitExists(unit) and SetPortraitTexture then
        local ok = pcall(SetPortraitTexture, texture, unit)
        if ok then
            texture:SetTexCoord(0.12, 0.88, 0.12, 0.88)
            return
        end
    end
    ApplyClassIcon(texture, unit, classFile)
end

-- name, teleport spell, dungeon icon. The icon falls back to the teleport's own
-- spell icon so a row is never left blank.
local function DungeonName(mapID)
    local entry = catalog.byMap[mapID]
    if entry then
        local icon = entry.icon
        if not icon and entry.spellID and C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(entry.spellID)
            icon = info and info.iconID
        end
        return entry.name, entry.spellID, icon, entry.code
    end
    if not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
    if type(name) ~= "string" or name == "" then return nil end
    return name, nil, (type(texture) == "number" and texture ~= 0) and texture or nil, nil
end

-- Mythic+ rating, in Blizzard's own rarity colour where the API offers one.
local function ScoreColour(score)
    if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
        local ok, col = pcall(C_ChallengeMode.GetDungeonScoreRarityColor, score)
        if ok and col and col.r then return col.r, col.g, col.b end
    end
    return 0.9, 0.9, 0.9
end

-- LibKeystone hands us one player's key. A level or map of 0 means "no key".
local function StoreKeystone(level, mapID, rating, name, channel)
    name = CleanName(name and ShortName(name))
    if not name then return end
    local store = Store(channel == "GUILD" and "GUILD" or "PARTY")
    if type(level) ~= "number" or type(mapID) ~= "number" or level <= 0 or mapID <= 0 then
        -- Keep the rating even when there is no key: it is still worth showing.
        store[name] = (type(rating) == "number" and rating > 0)
                      and { mapID = nil, level = 0, rating = rating, at = GetTime() } or nil
    else
        store[name] = { mapID = mapID, level = level, rating = rating or 0, at = GetTime() }
    end
    if keyList and keyList:IsShown() then KeyPort.RefreshKeyList() end
end

local function RequestKeystones(channel)
    channel = channel or "PARTY"
    if LibKeystone then
        LibKeystone.Request(channel)   -- also reports our own key straight back
        return true
    end
    if channel == "PARTY" and C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
        StoreKeystone(C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or 0,
                      C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0, 0,
                      ShortUnitName("player"), "PARTY")
    end
    return false
end

-------------------------------------------------------------------------------
--  The picker window
-------------------------------------------------------------------------------
local function ListButton(parent, width, height, caption)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.09, 0.11, 0.95)
    btn.bg = bg
    Outline(btn, ACCENT_RGB[1], ACCENT_RGB[2], ACCENT_RGB[3], 0.35)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)

    local label = Label(btn, 11, 1, 1, 1)
    label:SetPoint("CENTER")
    label:SetText(caption)
    btn.label = label

    function btn:SetActive(active)
        self:SetEnabled(active)
        local tint = active and 1 or 0.4
        self.label:SetTextColor(tint, tint, tint, 1)
        self.bg:SetColorTexture(0.08, 0.09, 0.11, active and 0.95 or 0.6)
    end
    return btn
end

local function TabButton(parent, caption, tab)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(TAB_H)
    btn.tab = tab

    local label = Label(btn, 11, 0.62, 0.66, 0.72)
    label:SetPoint("CENTER", 0, 1)
    label:SetText(caption)
    btn.label = label
    btn:SetWidth(math.max(52, (label:GetStringWidth() or 0) + 22))

    local underline = btn:CreateTexture(nil, "ARTWORK")
    underline:SetPoint("BOTTOMLEFT", 4, 0)
    underline:SetPoint("BOTTOMRIGHT", -4, 0)
    underline:SetHeight(2)
    underline:SetColorTexture(ACCENT_RGB[1], ACCENT_RGB[2], ACCENT_RGB[3], 1)
    btn.underline = underline

    btn:SetScript("OnEnter", function(self)
        if activeTab ~= self.tab then self.label:SetTextColor(0.88, 0.92, 0.96) end
    end)
    btn:SetScript("OnLeave", function(self)
        if activeTab ~= self.tab then self.label:SetTextColor(0.62, 0.66, 0.72) end
    end)
    btn:SetScript("OnClick", function(self) KeyPort.SetTab(self.tab) end)

    function btn:SetActive(active)
        self.underline:SetShown(active)
        self.label:SetTextColor(active and ACCENT_RGB[1] or 0.62,
                                active and ACCENT_RGB[2] or 0.66,
                                active and ACCENT_RGB[3] or 0.72)
    end
    return btn
end

-- Chrome is everything that is not a row: header, tabs, column titles, the
-- selection line and the buttons.
local function ChromeHeight()
    return HEADER_H + TAB_H + COLHDR_H + 8 + 22 + 30 + LIST_PAD
end

local function RowsThatFit(height)
    local room = height - ChromeHeight()
    return math.max(MIN_ROWS, math.min(MAX_ROWS, math.floor(room / ROW_H)))
end

local function SaveGeometry()
    if not keyList then return end
    local point, _, relPoint, x, y = keyList:GetPoint()
    if point then db.listPos = { point = point, relPoint = relPoint, x = x, y = y } end
end

local function BuildRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H - 2)

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(1, 1, 1, 0.04)
    row.bg = rowBg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    row.mark = {}
    for _ = 1, 4 do
        local tex = row:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(ACCENT_RGB[1], ACCENT_RGB[2], ACCENT_RGB[3], 0.9)
        tex:Hide()
        row.mark[#row.mark + 1] = tex
    end
    row.mark[1]:SetPoint("TOPLEFT");    row.mark[1]:SetPoint("TOPRIGHT");    row.mark[1]:SetHeight(1)
    row.mark[2]:SetPoint("BOTTOMLEFT"); row.mark[2]:SetPoint("BOTTOMRIGHT"); row.mark[2]:SetHeight(1)
    row.mark[3]:SetPoint("TOPLEFT");    row.mark[3]:SetPoint("BOTTOMLEFT");  row.mark[3]:SetWidth(2)
    row.mark[4]:SetPoint("TOPRIGHT");   row.mark[4]:SetPoint("BOTTOMRIGHT"); row.mark[4]:SetWidth(1)

    row.avatar = row:CreateTexture(nil, "ARTWORK")
    row.avatar:SetSize(AVATAR_SZ, AVATAR_SZ)
    row.avatar:SetPoint("LEFT", 3, 0)
    local ok, mask = pcall(function()
        local m = row:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                     "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(row.avatar)
        row.avatar:AddMaskTexture(m)
        return m
    end)
    row.avatarMask = ok and mask or nil

    row.player = Label(row, ROW_FONT, 1, 1, 1)
    row.player:SetJustifyH("LEFT")
    row.player:SetWordWrap(false)

    row.dungeonIcon = row:CreateTexture(nil, "ARTWORK")
    row.dungeonIcon:SetSize(DUNGEON_SZ, DUNGEON_SZ)
    row.dungeonIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.dungeonEdge = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.dungeonEdge:SetSize(DUNGEON_SZ + 2, DUNGEON_SZ + 2)
    row.dungeonEdge:SetPoint("CENTER", row.dungeonIcon, "CENTER")
    row.dungeonEdge:SetColorTexture(0, 0, 0, 0.55)

    row.dungeon = Label(row, ROW_FONT, 1, 1, 1)
    row.dungeon:SetJustifyH("LEFT")
    row.dungeon:SetWordWrap(false)

    row.score = Label(row, ROW_FONT, 0.9, 0.9, 0.9)
    row.score:SetJustifyH("RIGHT")
    row.score:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if not self.owner then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local mine = (self.owner == ShortUnitName("player"))
        GameTooltip:AddLine(mine and "Your keystone" or (self.owner .. "'s keystone"),
                            0.35, 0.78, 1)
        if self.dungeonName and (self.keyLevel or 0) > 0 then
            GameTooltip:AddLine(self.dungeonName .. " +" .. self.keyLevel, 1, 1, 1)
            if self.above then
                if self.best then
                    GameTooltip:AddLine("Above your best here (+" .. self.best .. ")",
                                        0.25, 0.88, 0.44, true)
                else
                    GameTooltip:AddLine("You have not completed this dungeon this season.",
                                        0.25, 0.88, 0.44, true)
                end
            elseif self.best then
                GameTooltip:AddLine("You have already completed +" .. self.best .. " here.",
                                    0.7, 0.7, 0.7, true)
            end
        else
            GameTooltip:AddLine("No keystone this week.", 0.7, 0.7, 0.7)
        end
        if (self.rating or 0) > 0 then
            GameTooltip:AddLine("Mythic+ rating: " .. self.rating, 0.7, 0.7, 0.7)
        end
        if self.seen then
            GameTooltip:AddLine("Last seen " .. TimeAgo(self.seen), 0.5, 0.52, 0.56)
        end
        if self.account then
            GameTooltip:AddLine(self.account, 0.35, 0.78, 1)
        end
        if self.realm then
            GameTooltip:AddLine(self.realm, 0.5, 0.52, 0.56)
            GameTooltip:AddLine("Right-click to forget this character.", 0.6, 0.63, 0.68, true)
        end
        if self.selectable then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to select, then Send to Party.", 0.6, 0.63, 0.68, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local store = (activeTab == "ALTS" and db.alts)
                          or (activeTab == "FRIENDS" and db.friends)
            if store and self.fullName and store[self.fullName] then
                store[self.fullName] = nil
                if selection and selection.name == self.owner then selection = nil end
                Print("forgot " .. self.owner .. ".")
                KeyPort.RefreshKeyList()
            end
            return
        end
        if not self.selectable then return end
        if composing then
            ballotPick[self.owner] = (not ballotPick[self.owner]) or nil
            KeyPort.RefreshKeyList()
            return
        end
        selection = { name = self.owner, mapID = self.mapID, level = self.keyLevel,
                      tab = activeTab, candidate = self.candidate }
        KeyPort.RefreshKeyList()
    end)
    row:Hide()
    return row
end

-- Anchor a row's widgets for the current window width.
local function LayoutRow(row, width)
    local inner = width - LIST_PAD * 2
    row:SetWidth(inner)

    local xName = 3 + AVATAR_SZ + 5
    row.player:ClearAllPoints()
    row.player:SetPoint("LEFT", xName, 0)
    row.player:SetWidth(NAME_W)

    local xIcon = xName + NAME_W + 4
    row.dungeonIcon:ClearAllPoints()
    row.dungeonIcon:SetPoint("LEFT", xIcon, 0)

    row.score:ClearAllPoints()
    row.score:SetPoint("RIGHT", -4, 0)
    row.score:SetWidth(SCORE_W)

    local xDungeon = xIcon + DUNGEON_SZ + 4
    local dungeonWidth = math.max(28, inner - xDungeon - SCORE_W - 10)
    row.dungeon:ClearAllPoints()
    row.dungeon:SetPoint("LEFT", xDungeon, 0)
    row.dungeon:SetWidth(dungeonWidth)
    row.dungeonWidth = dungeonWidth
end

local function LayoutList()
    if not keyList then return end
    local width = keyList:GetWidth()
    visibleRows = RowsThatFit(keyList:GetHeight())

    for i = 1, visibleRows do
        if not keyList.rows[i] then keyList.rows[i] = BuildRow(keyList, i) end
        local row = keyList.rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", LIST_PAD, -(HEADER_H + TAB_H + COLHDR_H + (i - 1) * ROW_H))
        LayoutRow(row, width)
    end
    for i = visibleRows + 1, #keyList.rows do
        keyList.rows[i]:Hide()
    end

    keyList.colKey:ClearAllPoints()
    keyList.colKey:SetPoint("TOPLEFT", LIST_PAD + 3 + AVATAR_SZ + 5 + NAME_W + 4,
                            -(HEADER_H + TAB_H + 2))
    keyList.colScore:ClearAllPoints()
    keyList.colScore:SetPoint("TOPRIGHT", -(LIST_PAD + 4), -(HEADER_H + TAB_H + 2))
end

local function BuildKeyList()
    if keyList then return keyList end

    keyList = CreateFrame("Frame", "KeyPortKeyList", UIParent)
    keyList:SetSize(db.listSize and db.listSize.w or DEFAULT_W,
                    db.listSize and db.listSize.h or (ChromeHeight() + PARTY_SIZE * ROW_H))
    keyList:SetFrameStrata("DIALOG")
    keyList:SetClampedToScreen(true)
    keyList:SetMovable(true)
    keyList:EnableMouse(true)
    keyList:EnableMouseWheel(true)
    keyList:RegisterForDrag("LeftButton")
    keyList:SetScript("OnDragStart", function(self) self:StartMoving() end)
    keyList:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveGeometry() end)
    tinsert(UISpecialFrames, "KeyPortKeyList")

    if keyList.SetResizable then keyList:SetResizable(true) end
    if keyList.SetResizeBounds then
        keyList:SetResizeBounds(MIN_W, ChromeHeight() + MIN_ROWS * ROW_H,
                                MAX_W, ChromeHeight() + MAX_ROWS * ROW_H)
    end

    local bg = keyList:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.96)
    Outline(keyList, 0, 0, 0, 1)

    local header = keyList:CreateTexture(nil, "BORDER")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    header:SetColorTexture(0, 0, 0, 0.45)

    local rule = keyList:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(ACCENT_RGB[1], ACCENT_RGB[2], ACCENT_RGB[3], 0.55)

    local title = Label(keyList, 11, ACCENT_RGB[1], ACCENT_RGB[2], ACCENT_RGB[3])
    title:SetPoint("LEFT", header, "LEFT", LIST_PAD, 0)
    title:SetText("Keystones")

    local close = CreateFrame("Button", nil, keyList)
    close:SetSize(HEADER_H - 8, HEADER_H - 8)
    close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    local closeText = Label(close, 13, 0.55, 0.55, 0.55)
    closeText:SetAllPoints()
    closeText:SetJustifyH("CENTER")
    closeText:SetText("\195\151")
    close:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.35, 0.35) end)
    close:SetScript("OnLeave", function() closeText:SetTextColor(0.55, 0.55, 0.55) end)
    close:SetScript("OnClick", function() keyList:Hide() end)

    keyList.tabs = {
        TabButton(keyList, "Party", "PARTY"),
        TabButton(keyList, "Guild", "GUILD"),
        TabButton(keyList, "Alts", "ALTS"),
        TabButton(keyList, "Friends", "FRIENDS"),
    }
    keyList.tabs[1]:SetPoint("TOPLEFT", LIST_PAD - 2, -(HEADER_H + 1))
    keyList.tabs[2]:SetPoint("LEFT", keyList.tabs[1], "RIGHT", 2, 0)
    keyList.tabs[3]:SetPoint("LEFT", keyList.tabs[2], "RIGHT", 2, 0)
    keyList.tabs[4]:SetPoint("LEFT", keyList.tabs[3], "RIGHT", 2, 0)

    keyList.colPlayer = Label(keyList, 9, 0.45, 0.5, 0.56)
    keyList.colPlayer:SetPoint("TOPLEFT", LIST_PAD + 3, -(HEADER_H + TAB_H + 2))
    keyList.colPlayer:SetText("PLAYER")
    keyList.colKey = Label(keyList, 9, 0.45, 0.5, 0.56)
    keyList.colKey:SetText("KEYSTONE")
    keyList.colScore = Label(keyList, 9, 0.45, 0.5, 0.56)
    keyList.colScore:SetJustifyH("RIGHT")
    keyList.colScore:SetText("SCORE")

    keyList.rows = {}

    keyList.empty = Label(keyList, 10, 0.6, 0.63, 0.68)
    keyList.empty:SetJustifyH("CENTER")
    keyList.empty:SetWordWrap(true)
    keyList.empty:Hide()

    keyList.choice = Label(keyList, 11, 0.75, 0.79, 0.84)
    keyList.choice:SetJustifyH("CENTER")
    keyList.choice:SetWordWrap(false)

    keyList.send = ListButton(keyList, 140, 22, "Send to Party")
    keyList.send:SetScript("OnClick", function()
        if composing then KeyPort.CancelBallot() else KeyPort.SendSelection() end
    end)

    keyList.vote = ListButton(keyList, 72, 22, "Vote")
    keyList.vote:SetScript("OnClick", function()
        if vote.active then
            KeyPort.CastVote()
        elseif composing then
            KeyPort.StartVote()
        else
            KeyPort.BeginBallot()
        end
    end)

    keyList.refresh = ListButton(keyList, 74, 22, "Refresh")
    keyList.refresh:SetScript("OnClick", function()
        RequestKeystones(activeTab)
        if activeTab == "GUILD" then RefreshGuildRoster() end
        KeyPort.RefreshKeyList()
    end)

    -- Resize grip, bottom right.
    local grip = CreateFrame("Button", nil, keyList)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function()
        keyList.userSized = true
        keyList:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        keyList:StopMovingOrSizing()
        db.listSize = { w = keyList:GetWidth(), h = keyList:GetHeight() }
        SaveGeometry()
        LayoutList()
        KeyPort.RefreshKeyList()
    end)
    keyList.grip = grip

    keyList:SetScript("OnSizeChanged", function() LayoutList() end)
    keyList:SetScript("OnMouseWheel", function(_, delta)
        local total = keyList.rowCount or 0
        local maxOffset = math.max(0, total - visibleRows)
        local wanted = math.min(maxOffset, math.max(0, scrollOffset - delta))
        if wanted ~= scrollOffset then
            scrollOffset = wanted
            KeyPort.RefreshKeyList()
        end
    end)

    keyList:ClearAllPoints()
    local pos = db.listPos
    if pos and pos.point then
        keyList:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        keyList:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    keyList:SetScale(db.scale or 1)
    LayoutList()
    keyList:Hide()
    return keyList
end

function KeyPort.SetTab(tab)
    if tab ~= "PARTY" and tab ~= "GUILD" and tab ~= "ALTS" and tab ~= "FRIENDS" then return end
    if activeTab == tab then return end
    activeTab = tab
    scrollOffset = 0
    if tab == "GUILD" then
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        RefreshGuildRoster()
    elseif tab == "ALTS" then
        KeyPort.RecordOwnKeystone()
    elseif tab == "FRIENDS" then
        AskFriends()
    end
    if tab == "PARTY" or tab == "GUILD" then RequestKeystones(tab) end
    KeyPort.RefreshKeyList()
end

-- Build the sorted dataset for the active tab.
local function CollectRows()
    if vote.active and activeTab == "PARTY" then return VoteRows() end
    local rows = {}
    if activeTab == "PARTY" then
        for _, member in ipairs(Roster()) do
            local key = keystones[member.name]
            rows[#rows + 1] = {
                name  = member.name,
                unit  = member.unit,
                mapID = key and key.mapID,
                level = key and key.level or 0,
                rating = key and key.rating or 0,
            }
        end
    elseif activeTab == "FRIENDS" then
        local fresh = WeekStart()
        for fullName, rec in pairs(db.friends or {}) do
            local stale = (rec.seen or 0) < fresh
            rows[#rows + 1] = {
                name = rec.name or fullName,
                fullName = fullName,
                unit = UnitForName(rec.name),
                classFile = rec.classFile,
                mapID = (not stale) and rec.mapID or nil,
                level = (not stale) and (rec.level or 0) or 0,
                rating = rec.rating or 0,
                stale = stale and (rec.level or 0) > 0,
                dim = stale,
                realm = rec.realm,
                account = rec.account,
                seen = rec.seen,
            }
        end
        -- Keys first, then the highest, then whoever answered most recently.
        table.sort(rows, function(a, b)
            if (a.level > 0) ~= (b.level > 0) then return a.level > 0 end
            if a.level ~= b.level then return a.level > b.level end
            return (a.seen or 0) > (b.seen or 0)
        end)
        return rows
    elseif activeTab == "ALTS" then
        local fresh = WeekStart()
        local me = ShortUnitName("player")
        for fullName, alt in pairs(db.alts or {}) do
            local stale = (alt.updated or 0) < fresh
            rows[#rows + 1] = {
                name = alt.name or fullName,
                fullName = fullName,
                unit = (alt.name == me) and "player" or nil,
                classFile = alt.classFile,
                mapID = (not stale) and alt.mapID or nil,
                level = (not stale) and (alt.level or 0) or 0,
                rating = alt.rating or 0,
                stale = stale and (alt.level or 0) > 0,
                realm = alt.realm,
                updated = alt.updated,
            }
        end
    else
        for name, key in pairs(guildKeys) do
            rows[#rows + 1] = {
                name = name,
                classFile = guildClass[name],
                mapID = key.mapID,
                level = key.level or 0,
                rating = key.rating or 0,
            }
        end
    end
    -- Keys first, highest level at the top; keyless players fall to the bottom.
    table.sort(rows, function(a, b)
        if (a.level > 0) ~= (b.level > 0) then return a.level > 0 end
        if a.level ~= b.level then return a.level > b.level end
        if a.rating ~= b.rating then return a.rating > b.rating end
        return (a.name or "") < (b.name or "")
    end)
    return rows
end

-- Repaint from the store; keeps the selection if it still exists.
function KeyPort.RefreshKeyList()
    if not keyList then return end
    Catalog()
    RefreshSeasonBests()

    local rows = CollectRows()
    keyList.rowCount = #rows

    -- Size to the data before drawing. Sizing afterwards, from the number of
    -- rows actually drawn, could only ever shrink: a window showing three rows
    -- stayed three rows tall no matter how many keys arrived.
    if not db.listSize then
        local want = ChromeHeight() + math.max(MIN_ROWS, math.min(MAX_ROWS, #rows)) * ROW_H
        if math.abs(keyList:GetHeight() - want) > 0.5 then
            keyList:SetHeight(want)
            LayoutList()
        end
    end

    -- Drop a selection whose key changed or whose owner is gone.
    -- Only the live tabs are re-validated. Alts and friends are stored records,
    -- not something LibKeystone refreshes, so there is nothing to check them
    -- against and doing so would silently drop the selection.
    if selection and selection.tab ~= "PARTY" and selection.tab ~= "GUILD" then
        -- stored record: leave it alone
    elseif selection and not vote.active then
        local key = Store(selection.tab or "PARTY")[selection.name]
        if not key or key.mapID ~= selection.mapID or key.level ~= selection.level then
            selection = nil
        end
    end

    local maxOffset = math.max(0, #rows - visibleRows)
    if scrollOffset > maxOffset then scrollOffset = maxOffset end

    local shown_count = 0
    for i = 1, visibleRows do
        local row = keyList.rows[i]
        if not row then break end
        local data = rows[i + scrollOffset]
        if not data then
            row:Hide()
        else
            shown_count = shown_count + 1
            row.owner, row.mapID, row.keyLevel = data.name, data.mapID, data.level
            row.rating = data.rating
            row.realm, row.fullName = data.realm, data.fullName
            row.seen, row.account = data.seen, data.account
            row.player:SetText(data.name or "?")
            local pr, pg, pb = ClassRGBFor(data.unit, data.classFile)
            if data.dim then
                -- Cached from before the weekly reset: shown, but visibly past it.
                pr, pg, pb = pr * 0.5, pg * 0.5, pb * 0.5
            end
            row.player:SetTextColor(pr, pg, pb)
            ApplyAvatar(row.avatar, data.unit, data.classFile)
            row.avatar:SetDesaturated(data.dim and true or false)
            row.avatar:SetAlpha(data.dim and 0.5 or 1)

            row.candidate = data.candidate
            if data.candidate then
                -- During a vote the score column carries the tally instead.
                row.score:SetText(data.votes > 0 and tostring(data.votes) or "-")
                if vote.mine == data.candidate then
                    row.score:SetTextColor(0.25, 0.88, 0.44)
                else
                    row.score:SetTextColor(ACCENT_RGB[1], ACCENT_RGB[2], ACCENT_RGB[3])
                end
            elseif (data.rating or 0) > 0 then
                row.score:SetText(data.rating)
                row.score:SetTextColor(ScoreColour(data.rating))
            else
                row.score:SetText("")
            end

            local above, best = AboveSeasonBest(data.mapID, data.level)
            row.above, row.best = above, best or false
            -- The level sits with the name rather than in its own column, so
            -- its colour and arrow travel inline.
            local levelText = LevelMarkup(data.mapID, data.level)

            local dungeon, spellID, icon, code
            if data.mapID then dungeon, spellID, icon, code = DungeonName(data.mapID) end

            if icon and data.level > 0 then
                row.dungeonIcon:SetTexture(icon)
                row.dungeonIcon:SetDesaturated(not spellID)
                row.dungeonIcon:SetAlpha(spellID and 1 or 0.45)
                row.dungeonIcon:Show()
                row.dungeonEdge:Show()
            else
                row.dungeonIcon:Hide()
                row.dungeonEdge:Hide()
            end

            if data.stale then
                row.selectable = false
                row.dungeon:SetText("last week's key")
                row.dungeon:SetTextColor(0.45, 0.47, 0.5)
            elseif not data.mapID or data.level <= 0 then
                row.selectable = false
                row.dungeon:SetText("no keystone")
                row.dungeon:SetTextColor(0.45, 0.47, 0.5)
            elseif not dungeon then
                row.selectable = false
                row.dungeon:SetText("unknown dungeon  " .. levelText)
                row.dungeon:SetTextColor(0.45, 0.47, 0.5)
            else
                local suffix = spellID and "" or " (no teleport)"
                row.selectable = spellID and true or false
                row.dungeon:SetTextColor(spellID and 0.92 or 0.55,
                                         spellID and 0.94 or 0.5,
                                         spellID and 0.96 or 0.45)
                -- Prefer the full name, but never at the cost of the level:
                -- if the pair does not fit, the short code stands in. Measured
                -- rather than guessed from the window width, because the name
                -- lengths vary wildly between dungeons and languages.
                row.dungeon:SetText(dungeon .. suffix .. "  " .. levelText)
                if code and (row.dungeon:GetStringWidth() or 0) > (row.dungeonWidth or 0) then
                    row.dungeon:SetText(code .. suffix .. "  " .. levelText)
                end
            end
            row.dungeonName = dungeon

            local chosen
            if composing then
                chosen = row.selectable and ballotPick[data.name] or false
            else
                chosen = selection and selection.name == data.name
                         and selection.tab == activeTab
            end
            for _, tex in ipairs(row.mark) do tex:SetShown(chosen and true or false) end
            row.bg:SetColorTexture(1, 1, 1, chosen and 0.10 or 0.04)
            row:Show()
        end
    end

    for _, tab in ipairs(keyList.tabs) do tab:SetActive(tab.tab == activeTab) end

    local listTop = HEADER_H + TAB_H + COLHDR_H
    local listBottom = listTop + math.max(shown_count, MIN_ROWS) * ROW_H
    if #rows == 0 then
        keyList.empty:ClearAllPoints()
        keyList.empty:SetPoint("TOPLEFT", LIST_PAD, -(listTop + 8))
        keyList.empty:SetPoint("TOPRIGHT", -LIST_PAD, -(listTop + 8))
        local blank = "Waiting for keystones."
        if activeTab == "GUILD" then
            blank = "No guild keystones yet.\nGuildmates need KeyPort, DBM, BigWigs or\nanother addon that shares keys."
        elseif activeTab == "ALTS" then
            blank = "No characters recorded yet.\nLog in on an alt with KeyPort installed and it\nwill appear here."
        elseif activeTab == "FRIENDS" then
            blank = db.friendShare
                and "No answers yet.\nBattle.net friends appear here if they are online\nand also running KeyPort."
                or "Sharing with friends is off.\nTurn it back on with /kp friends share."
        end
        keyList.empty:SetText(blank)
        keyList.empty:Show()
    else
        keyList.empty:Hide()
    end

    local base = keyList:GetHeight() - (30 + 22 + LIST_PAD)
    keyList.choice:ClearAllPoints()
    keyList.choice:SetPoint("TOPLEFT", LIST_PAD, -base)
    keyList.choice:SetPoint("TOPRIGHT", -LIST_PAD, -base)
    local status = VoteStatusText()
    if composing then
        local n = 0
        for _ in pairs(ballotPick) do n = n + 1 end
        keyList.choice:SetText(ACCENT .. "Building a ballot|r   " .. n ..
                               " keys picked, click rows to add or remove")
    elseif status then
        keyList.choice:SetText(ACCENT .. status .. "|r")
    elseif selection then
        local dungeon = DungeonName(selection.mapID) or "?"
        keyList.choice:SetText(("%s %s  (%s%s|r)"):format(
            dungeon, LevelMarkup(selection.mapID, selection.level), ACCENT, selection.name))
    else
        keyList.choice:SetText(#rows > 0 and "Click a keystone to select it" or "")
    end

    local inParty = GroupChannel() ~= nil
    local voteW, refreshW = 72, 74
    local sendW = math.max(84, keyList:GetWidth() - LIST_PAD * 2 - 14 - voteW - refreshW - 12)
    keyList.send:ClearAllPoints()
    keyList.send:SetPoint("BOTTOMLEFT", LIST_PAD, LIST_PAD)
    keyList.send:SetWidth(sendW)
    keyList.vote:ClearAllPoints()
    keyList.vote:SetPoint("BOTTOMLEFT", LIST_PAD + sendW + 6, LIST_PAD)
    keyList.vote:SetWidth(voteW)
    keyList.refresh:ClearAllPoints()
    keyList.refresh:SetPoint("BOTTOMRIGHT", -LIST_PAD - 14, LIST_PAD)
    keyList.refresh:SetWidth(refreshW)

    if composing then
        local n = 0
        for _ in pairs(ballotPick) do n = n + 1 end
        keyList.send:SetActive(true)
        keyList.send.label:SetText("Cancel")
        keyList.vote.label:SetText("Start " .. n)
        keyList.vote:SetActive(n >= 2)
    elseif vote.active then
        keyList.send:SetActive(false)
        keyList.send.label:SetText("Voting...")
        keyList.vote.label:SetText("Cast")
        keyList.vote:SetActive(selection ~= nil and selection.candidate ~= nil)
    else
        keyList.send:SetActive(selection ~= nil and inParty)
        keyList.send.label:SetText(inParty and "Send" or "No party")
        keyList.vote.label:SetText("Vote")
        keyList.vote:SetActive(inParty and activeTab == "PARTY")
    end
end

-- Just the countdown, so the ticker does not repaint the whole list.
function KeyPort.UpdateVoteStatus()
    if not keyList then return end
    local status = VoteStatusText()
    if status then keyList.choice:SetText(ACCENT .. status .. "|r") end
end

-- Put the selected key on everyone's screen.
function KeyPort.SendSelection()
    if not selection then return end
    local blocked = BlockedReason()
    if blocked then Print(blocked); return end

    local entry = catalog.byMap[selection.mapID]
    if not entry or not entry.spellID then
        local name = DungeonName(selection.mapID) or ("map " .. tostring(selection.mapID))
        Print("no teleport is known for " .. name .. ". Add it with "
              .. ACCENT .. "/kp map <dungeon> <spellID>|r.")
        return
    end

    local owner = selection.name
    local channel = Broadcast(PROTO_OWNED .. ":" .. entry.spellID .. ":" .. selection.level
                              .. ":" .. owner)
    local mine = (owner == ShortUnitName("player"))
    local footer
    if not channel then
        footer = mine and "Your key" or (owner .. "'s key")
    elseif mine then
        footer = "Your key, sent to your party"
    else
        footer = owner .. "'s key, sent to your party"
    end

    KeyPort.Show(entry, selection.level, footer)
    if channel then AnnounceToParty(entry.name, selection.level, owner) end
    if keyList then keyList:Hide() end
end

function KeyPort.OpenKeyList(tab)
    local blocked = BlockedReason()
    if blocked then Print(blocked); return end
    if InCombatLockdown() then
        queued.keyList = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        Print("in combat -- the keystone list will open when you leave combat.")
        return
    end
    BuildKeyList()
    if tab then activeTab = tab end
    if activeTab == "GUILD" then
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        RefreshGuildRoster()
    elseif activeTab == "ALTS" then
        KeyPort.RecordOwnKeystone()
    elseif activeTab == "FRIENDS" then
        AskFriends()
    end
    -- LibKeystone only knows PARTY and GUILD; the alts list is local data.
    if activeTab == "PARTY" or activeTab == "GUILD" then RequestKeystones(activeTab) end
    LayoutList()
    KeyPort.RefreshKeyList()
    keyList:Show()
end

-------------------------------------------------------------------------------
--  VOTING
--  "Whose key are we doing?" put to the party. The starter takes a snapshot of
--  the keys on offer and sends it as the ballot, so every client votes on the
--  same list even if their own keystone data differs slightly. Ballots are
--  broadcast, so everyone tallies locally and sees the count move in real time;
--  the starter declares the winner at the end, which keeps ties from being
--  broken two different ways on two different screens.
--
--  Wire format (all validated on arrival, like every other KeyPort message):
--    VS1:<id>:<seconds>:<spell>,<level>,<owner>;...   start, with the ballot
--    VB1:<id>:<index>                                 one ballot
--    VE1:<id>:<winning index>                         result, from the starter
-------------------------------------------------------------------------------
local VOTE_START, VOTE_BALLOT, VOTE_END = "VS1", "VB1", "VE1"
local MAX_CANDIDATES = 8
local DEFAULT_VOTE_SECONDS = 30

vote = {
    active = false,
    id = nil,
    starter = nil,
    candidates = nil,   -- { { spellID, level, owner, mapID } }
    ballots = nil,      -- [voter name] = candidate index
    endsAt = 0,
    mine = nil,         -- the index this player voted for
}
local voteTicker

local function VoteSeconds()
    local n = tonumber(db.voteSeconds) or DEFAULT_VOTE_SECONDS
    if n < 10 then n = 10 elseif n > 120 then n = 120 end
    return n
end

local function VoteRemaining()
    return math.max(0, math.ceil(vote.endsAt - GetTime()))
end

local function StopVoteTicker()
    if voteTicker then voteTicker:Cancel(); voteTicker = nil end
end

ClearVote = function()
    composing = false
    wipe(ballotPick)
    StopVoteTicker()
    vote.active, vote.id, vote.starter = false, nil, nil
    vote.candidates, vote.ballots, vote.mine = nil, nil, nil
    vote.endsAt = 0
end

local function Tally()
    local counts, total = {}, 0
    if not vote.candidates then return counts, total end
    for i = 1, #vote.candidates do counts[i] = 0 end
    for _, index in pairs(vote.ballots or {}) do
        if counts[index] then counts[index] = counts[index] + 1; total = total + 1 end
    end
    return counts, total
end

-- Most votes wins; a tie goes to the higher key, then to the name, so the
-- result never depends on table order.
local function WinningIndex()
    local counts = Tally()
    local best
    for i, candidate in ipairs(vote.candidates or {}) do
        local c = counts[i] or 0
        if not best then
            best = i
        else
            local bc = counts[best] or 0
            local other = vote.candidates[best]
            if c > bc
               or (c == bc and candidate.level > other.level)
               or (c == bc and candidate.level == other.level and candidate.owner < other.owner) then
                best = i
            end
        end
    end
    return best
end

-- Rows for the list while a vote is running: the ballot, not the roster.
VoteRows = function()
    local counts = Tally()
    local rows = {}
    for i, candidate in ipairs(vote.candidates) do
        rows[#rows + 1] = {
            name = candidate.owner,
            unit = UnitForName(candidate.owner),
            mapID = candidate.mapID,
            level = candidate.level,
            votes = counts[i] or 0,
            candidate = i,
        }
    end
    return rows
end

local function CandidatesFromParty()
    local list = {}
    for _, member in ipairs(Roster()) do
        local key = keystones[member.name]
        if key and key.mapID and (key.level or 0) > 0 then
            local entry = catalog.byMap[key.mapID]
            if entry and entry.spellID then
                list[#list + 1] = {
                    spellID = entry.spellID,
                    level = key.level,
                    owner = member.name,
                    mapID = key.mapID,
                }
            end
        end
        if #list >= MAX_CANDIDATES then break end
    end
    return list
end

local function EncodeCandidates(list)
    local parts = {}
    for _, c in ipairs(list) do
        parts[#parts + 1] = c.spellID .. "," .. c.level .. "," .. c.owner
    end
    return table.concat(parts, ";")
end

-- Every field is checked against the local catalog, so a malformed or hostile
-- ballot can only produce fewer candidates, never a bad teleport.
local function DecodeCandidates(payload)
    local list = {}
    for record in tostring(payload):gmatch("[^;]+") do
        local rawSpell, rawLevel, rawOwner = record:match("^(%d+),(%d+),(.+)$")
        local spellID, level, owner = tonumber(rawSpell), tonumber(rawLevel), CleanName(rawOwner)
        local entry = spellID and catalog.bySpell[spellID]
        if entry and owner and level and level > 0 and level <= 100 then
            list[#list + 1] = {
                spellID = spellID, level = level, owner = owner, mapID = entry.mapID,
            }
        end
        if #list >= MAX_CANDIDATES then break end
    end
    return list
end

VoteStatusText = function()
    if not vote.active then return nil end
    local _, total = Tally()
    local voters = math.max(1, GetNumGroupMembers and GetNumGroupMembers() or 1)
    return ("Vote: %ds left   %d/%d cast"):format(VoteRemaining(), total, voters)
end

local function StartVoteTicker()
    StopVoteTicker()
    if not (C_Timer and C_Timer.NewTicker) then return end
    voteTicker = C_Timer.NewTicker(1, function()
        if not vote.active then StopVoteTicker(); return end
        if keyList and keyList:IsShown() then KeyPort.UpdateVoteStatus() end
        if VoteRemaining() <= 0 then
            StopVoteTicker()
            -- Only the starter declares, so everyone gets the same answer.
            if vote.starter == ShortUnitName("player") then KeyPort.FinishVote() end
        end
    end)
end

local function BeginVote(id, starter, seconds, candidates)
    ClearVote()
    vote.active = true
    vote.id, vote.starter = id, starter
    vote.candidates, vote.ballots = candidates, {}
    vote.endsAt = GetTime() + seconds
    StartVoteTicker()
    if keyList then
        activeTab = "PARTY"
        KeyPort.RefreshKeyList()
    end
end

--- Start choosing which keys go on the ballot. Nothing is sent yet.
function KeyPort.BeginBallot()
    local blocked = BlockedReason()
    if blocked then Print(blocked); return end
    if vote.active then Print("a vote is already running."); return end
    if not GroupChannel() then Print("you are not in a party."); return end

    local pool = CandidatesFromParty()
    if #pool < 2 then
        Print("a vote needs at least two keystones to choose between.")
        return
    end

    -- Everything starts ticked: taking a key off is the rarer intent.
    wipe(ballotPick)
    for _, candidate in ipairs(pool) do ballotPick[candidate.owner] = true end
    composing = true
    selection = nil
    KeyPort.OpenKeyList("PARTY")
    KeyPort.RefreshKeyList()
    Print("pick the keys for the ballot, then press Start.")
end

--- Drop the half-built ballot.
function KeyPort.CancelBallot()
    if not composing then return end
    composing = false
    wipe(ballotPick)
    KeyPort.RefreshKeyList()
end

--- Send the ballot to the party. Uses the picked keys when one was composed,
--- and every key in the party otherwise.
function KeyPort.StartVote(useEveryKey)
    local blocked = BlockedReason()
    if blocked then Print(blocked); return end
    if vote.active then Print("a vote is already running."); return end
    if not GroupChannel() then Print("you are not in a party."); return end

    local candidates = CandidatesFromParty()
    if composing and not useEveryKey then
        local picked = {}
        for _, candidate in ipairs(candidates) do
            if ballotPick[candidate.owner] then picked[#picked + 1] = candidate end
        end
        candidates = picked
    end
    composing = false
    wipe(ballotPick)

    if #candidates < 2 then
        Print("a vote needs at least two keystones to choose between.")
        return
    end

    local me = ShortUnitName("player")
    local id = me .. "-" .. math.floor(GetTime() * 10) % 100000
    local seconds = VoteSeconds()
    Broadcast(VOTE_START .. ":" .. id .. ":" .. seconds .. ":" .. EncodeCandidates(candidates))
    BeginVote(id, me, seconds, candidates)
    Print("vote started: " .. #candidates .. " keys, " .. seconds .. " seconds.")
    AnnounceToParty("vote: which key?", nil, nil)
    KeyPort.OpenKeyList("PARTY")
end

--- Cast, or change, this player's ballot.
function KeyPort.CastVote(index)
    if not vote.active then return end
    index = index or (selection and selection.candidate)
    if not index or not vote.candidates[index] then
        Print("pick a keystone in the list first.")
        return
    end
    local me = ShortUnitName("player")
    if vote.ballots[me] == index then return end
    vote.ballots[me] = index
    vote.mine = index
    Broadcast(VOTE_BALLOT .. ":" .. vote.id .. ":" .. index)
    KeyPort.RefreshKeyList()
end

--- Close the vote and act on the winner. Called on the starter's client.
function KeyPort.FinishVote()
    if not vote.active then return end
    local index = WinningIndex()
    local winner = index and vote.candidates[index]
    Broadcast(VOTE_END .. ":" .. vote.id .. ":" .. (index or 0))
    KeyPort.ApplyVoteResult(index)
    if winner then
        -- Reuse the ordinary send path so the result behaves like any other
        -- shared key, including the chat line and the popup.
        selection = { name = winner.owner, mapID = winner.mapID,
                      level = winner.level, tab = "PARTY" }
        KeyPort.SendSelection()
    end
end

--- Show the outcome locally. Everyone runs this; only the starter sends it.
function KeyPort.ApplyVoteResult(index)
    local winner = index and vote.candidates and vote.candidates[index]
    local counts = Tally()
    if winner then
        local entry = catalog.byMap[winner.mapID]
        Print(("vote: %s +%d (%s's key) wins with %d %s."):format(
            (entry and entry.name) or "the key", winner.level, winner.owner,
            counts[index] or 0, (counts[index] == 1) and "vote" or "votes"))
    else
        Print("vote ended with nothing chosen.")
    end
    ClearVote()
    if keyList and keyList:IsShown() then KeyPort.RefreshKeyList() end
end

-- Incoming vote traffic. Returns true when the payload was a vote message.
HandleVoteMessage = function(payload, sender)
    local kind = payload:match("^(V[SBE]1):")
    if not kind then return false end
    if BlockedReason() then return true end

    local short = ShortName(sender)

    if kind == VOTE_START then
        local id, seconds, list = payload:match("^VS1:([^:]+):(%d+):(.+)$")
        if not id or #id > 32 then return true end
        if not db.acceptShares then return true end
        local candidates = DecodeCandidates(list)
        if #candidates < 2 then return true end
        seconds = math.min(120, math.max(10, tonumber(seconds) or DEFAULT_VOTE_SECONDS))
        BeginVote(id, short, seconds, candidates)
        Print(short .. " started a vote on which key to run.")
        KeyPort.OpenKeyList("PARTY")
        return true
    end

    if not vote.active then return true end

    if kind == VOTE_BALLOT then
        local id, index = payload:match("^VB1:([^:]+):(%d+)$")
        index = tonumber(index)
        if id == vote.id and index and vote.candidates[index] then
            vote.ballots[short] = index
            if keyList and keyList:IsShown() then KeyPort.RefreshKeyList() end
        end
        return true
    end

    if kind == VOTE_END then
        local id, index = payload:match("^VE1:([^:]+):(%d+)$")
        index = tonumber(index)
        -- Only the player who started it gets to call the result.
        if id == vote.id and short == vote.starter then
            KeyPort.ApplyVoteResult(index and index > 0 and index or nil)
        end
        return true
    end
    return true
end

-------------------------------------------------------------------------------
--  SLASH
-------------------------------------------------------------------------------
local function Usage()
    Print("usage: " .. ACCENT .. "/kp <dungeon> <keystone level>|r")
    print("  e.g. " .. ACCENT .. "/kp kr 10|r  =  Kings' Rest, keystone level 10")
    Print("commands:")
    print("  " .. ACCENT .. "/kp|r  open the group's keystone list and pick one")
    print("  " .. ACCENT .. "/kp KR 10|r  raise the reminder for you and your group")
    print("  " .. ACCENT .. "/kp mine|r  use the keystone in your own bags")
    print("  " .. ACCENT .. "/kp me KR 10|r  show it only for yourself")
    print("  " .. ACCENT .. "/kp hide|r  close it for the whole group")
    print("  " .. ACCENT .. "/kp list|r  dungeon codes")
    print("  " .. ACCENT .. "/kp share|r  toggle receiving your group's reminders")
    print("  " .. ACCENT .. "/kp vote|r  pick keys for a ballot, then Start")
    print("  " .. ACCENT .. "/kp vote all|r  skip the picking and put every key up")
    print("     (" .. ACCENT .. "/kp vote 45|r sets how long a vote runs)")
    print("  " .. ACCENT .. "/kp guild|r  open the list on the guild tab")
    print("  " .. ACCENT .. "/kp alts|r  your other characters' keystones (" ..
          ACCENT .. "/kp alts clear|r forgets them)")
    print("  " .. ACCENT .. "/kp friends|r  your Battle.net friends' keystones")
    print("     (" .. ACCENT .. "/kp friends share|r opts out, " ..
          ACCENT .. "/kp friends clear|r forgets them)")
    print("  " .. ACCENT .. "/kp announce|r  toggle the party chat line when a key is sent")
    print("  " .. ACCENT .. "/kp keys off|auto|force|r  whether /keys opens KeyPort")
    print("  " .. ACCENT .. "/kp scale 1.2|r  resize the popup")
    print("  " .. ACCENT .. "/kp reset|r  put both windows back where they started")
    print("  " .. ACCENT .. "/kp map <dungeon> <spellID>|r  teach it a missing teleport")
    print("     (a teleport spell id, not a keystone level)")
end

local function ListDungeons(showAll)
    if not Catalog() then
        Print("dungeon list is not available yet -- try again in a moment.")
        return
    end
    local function row(entry)
        local mark = entry.spellID and "" or "  |cffff8080(no teleport known)|r"
        print("  " .. ACCENT .. entry.code .. "|r  " .. entry.name .. mark)
    end

    Print("this season:")
    for _, entry in ipairs(catalog.season) do row(entry) end

    local others = {}
    for _, entry in ipairs(catalog.all) do
        if not entry.inSeason then others[#others + 1] = entry end
    end
    if #others == 0 then return end
    if showAll then
        Print("older dungeons:")
        for _, entry in ipairs(others) do row(entry) end
    else
        Print(#others .. " older dungeons also work -- " .. ACCENT .. "/kp list all|r to see them.")
    end
end

-- Pulls an optional keystone level out of the arguments: "10", "+10", "kr10".
local function SplitQuery(text)
    local words, level = {}, nil
    for word in text:gmatch("%S+") do
        local digits = word:match("^%+?(%d+)$")
        if digits and not level then
            level = tonumber(digits)
        else
            words[#words + 1] = word
        end
    end
    if not level and #words > 0 then
        local base, digits = words[#words]:match("^(%a[%a'%-]*)(%d+)$")
        if base then
            words[#words] = base
            level = tonumber(digits)
        end
    end
    return table.concat(words, " "), level
end

local function OwnKeystone()
    if not (C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID) then return nil end
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if not mapID or mapID == 0 then return nil end
    if not Catalog() then return nil end
    local level = (C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()) or 0
    return catalog.byMap[mapID], level
end

local function ResolveOrComplain(query)
    local entry, hits = Lookup(query)
    if entry then return entry end
    if hits and #hits > 1 then
        local names = {}
        for _, hit in ipairs(hits) do names[#names + 1] = hit.code .. " (" .. hit.name .. ")" end
        Print("\"" .. query .. "\" matches " .. table.concat(names, ", ") .. ".")
    else
        Print("no dungeon matched \"" .. query .. "\". Try " .. ACCENT .. "/kp list|r.")
    end
    return nil
end

-- /kp map <dungeon> <spellID>
local function TeachTeleport(rest)
    local query, spellID = rest:match("^(.-)%s+(%d+)$")
    spellID = tonumber(spellID)
    if not query or query == "" or not spellID then
        Print("usage: " .. ACCENT .. "/kp map <dungeon> <spellID>|r"
              .. "  -- the teleport's spell id, not a keystone level")
        return
    end
    local entry = ResolveOrComplain(query)
    if not entry then return end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if not info then
        Print("spell " .. spellID .. " does not exist on this client.")
        return
    end
    db.custom[entry.mapID] = spellID
    BuildCatalog()
    Print(entry.name .. " now teleports with " .. (info.name or spellID) .. ".")
end

local function HandleSlash(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local first = input:match("^(%S+)") or ""
    local rest  = input:sub(#first + 1):gsub("^%s+", "")
    local verb  = first:lower()

    if verb == "help" or verb == "?" then
        Usage(); return
    elseif verb == "list" or verb == "codes" then
        ListDungeons(rest:lower() == "all"); return
    elseif verb == "hide" or verb == "close" then
        KeyPort.Hide()
        if Broadcast(PROTO_HIDE) then Print("closed for the group.") end
        return
    elseif verb == "vote" then
        local seconds = tonumber(rest)
        if seconds then
            db.voteSeconds = math.min(120, math.max(10, seconds))
            Print("votes now run for " .. db.voteSeconds .. " seconds.")
            return
        end
        if rest:lower() == "all" then
            KeyPort.StartVote(true)     -- skip the picking, put every key up
        else
            KeyPort.BeginBallot()
        end
        return
    elseif verb == "guild" then
        KeyPort.OpenKeyList("GUILD"); return
    elseif verb == "friends" then
        local option = rest:lower()
        if option == "clear" then
            wipe(db.friends)
            Print("forgot every friend's keystone.")
            if keyList and keyList:IsShown() then KeyPort.RefreshKeyList() end
            return
        elseif option == "share" then
            db.friendShare = not db.friendShare
            Print("sharing keystones with Battle.net friends: " ..
                  (db.friendShare and "|cff40ff40on|r" or "|cffff4040off|r"))
            return
        end
        KeyPort.OpenKeyList("FRIENDS"); return
    elseif verb == "alts" then
        if rest:lower() == "clear" then
            wipe(db.alts)
            KeyPort.RecordOwnKeystone()
            Print("forgot every character except this one.")
            if keyList and keyList:IsShown() then KeyPort.RefreshKeyList() end
            return
        end
        KeyPort.OpenKeyList("ALTS"); return
    elseif verb == "keys" then
        local mode = rest:lower()
        if mode ~= "off" and mode ~= "auto" and mode ~= "force" then
            Print("/keys is currently |cffffd100" .. (db.keysCommand or "force") .. "|r. "
                  .. "Use " .. ACCENT .. "/kp keys off|auto|force|r.")
            print("     force = take it from whichever addon has it (default),")
            print("     auto = take it only if no other addon claimed it,")
            print("     off = leave /keys alone")
            return
        end
        db.keysCommand = mode
        db.keysCommandSet = true
        if mode == "off" then
            ClaimKeysCommand()
            Print("/keys left to other addons.")
        elseif ClaimKeysCommand() then
            Print("/keys now opens KeyPort.")
        else
            Print("/keys belongs to another addon. Use " .. ACCENT .. "/kp keys force|r to take it.")
        end
        return
    elseif verb == "announce" or verb == "say" then
        db.announce = not db.announce
        Print("party chat announcement: " ..
              (db.announce and "|cff40ff40on|r" or "|cffff4040off|r"))
        return
    elseif verb == "share" or verb == "accept" then
        db.acceptShares = not db.acceptShares
        Print("reminders from your group: " ..
              (db.acceptShares and "|cff40ff40on|r" or "|cffff4040off|r"))
        return
    elseif verb == "reset" then
        -- For a window dragged off-screen, or one sitting on top of another
        -- addon's popup.
        db.pos, db.listPos, db.listSize = nil, nil, nil
        if panel then RestorePosition() end
        if keyList then
            keyList:ClearAllPoints()
            keyList:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
            keyList:SetSize(DEFAULT_W, ChromeHeight() + PARTY_SIZE * ROW_H)
            LayoutList()
            KeyPort.RefreshKeyList()
        end
        Print("windows moved back where they started.")
        return
    elseif verb == "scale" then
        local value = tonumber(rest)
        if not value or value < 0.5 or value > 3 then
            Print("usage: " .. ACCENT .. "/kp scale 1.2|r  (0.5 - 3)")
            return
        end
        db.scale = value
        KeyPort.Refresh()
        Print("scale set to " .. value .. ".")
        return
    elseif verb == "map" then
        TeachTeleport(rest); return
    end

    -- Bare /kp opens the group's keystone list; everything else names a dungeon.
    if input == "" then
        KeyPort.OpenKeyList()
        return
    end

    local localOnly = (verb == "me" or verb == "self")
    local useOwnKey = (verb == "mine" or verb == "own")
    local args = (localOnly or useOwnKey) and rest or input

    local blocked = BlockedReason()
    if blocked then Print(blocked); return end

    if not Catalog() then
        Print("dungeon list is not available yet -- try again in a moment.")
        return
    end

    local entry, level
    if args == "" then
        entry, level = OwnKeystone()
        if not entry then
            Print("no keystone in your bags. Try " .. ACCENT .. "/kp KR 10|r, or "
                  .. ACCENT .. "/kp list|r for codes.")
            return
        end
    else
        local query
        query, level = SplitQuery(args)
        entry = ResolveOrComplain(query)
        if not entry then return end
    end

    if not entry.spellID then
        Print("no teleport is known for " .. entry.name .. ". Add it with "
              .. ACCENT .. "/kp map " .. entry.code .. " <spellID>|r.")
        return
    end

    level = level or 0
    if localOnly then
        KeyPort.Show(entry, level, "Only you can see this")
        return
    end

    KeyPort.Show(entry, level, "")

    -- /kp mine is a specific person's key, so it travels with an owner; a
    -- dungeon typed by hand belongs to nobody in particular.
    local payload
    if useOwnKey then
        payload = PROTO_OWNED .. ":" .. entry.spellID .. ":" .. level .. ":" .. UnitName("player")
    else
        payload = PROTO_SHOW .. ":" .. entry.spellID .. ":" .. level
    end

    local channel = Broadcast(payload)
    if channel then
        AnnounceToParty(entry.name, level, useOwnKey and UnitName("player") or nil)
        shown.footer = useOwnKey and "Your key, sent to your party" or "Sent to your party"
    else
        shown.footer = useOwnKey and "Your key" or "You are not in a group"
    end
    PaintText()
end

SLASH_KEYPORT1 = "/kp"
SLASH_KEYPORT2 = "/keyport"
SlashCmdList["KEYPORT"] = HandleSlash

-------------------------------------------------------------------------------
--  /keys takeover
--  Several addons register /keys for their own keystone window, and the chat
--  system resolves a command through hash_SlashCmdList, which is rebuilt from
--  every SLASH_<NAME><n> global. Two addons claiming /keys therefore race, and
--  the winner comes down to the pairs() order over SlashCmdList: writing our
--  own hash entry is not enough, because the next rebuild can undo it.
--
--  So instead of competing we take the name off the other addon: /keys is
--  removed from its alias list (its remaining aliases are shifted down so the
--  importer, which stops at the first gap, still sees them) and registered to
--  us. Their other commands keep working, and any later rebuild can only
--  resolve /keys to KeyPort. It is all remembered, so /kp keys off puts every
--  alias back exactly as it was.
-------------------------------------------------------------------------------
local KEYS_ALIAS = "/keys"
local displacedAliases = {}   -- [slash name] = { original alias list }

-- The aliases registered under one SlashCmdList name, in order.
local function AliasesOf(name)
    local list = {}
    for i = 1, 32 do
        local alias = _G["SLASH_" .. name .. i]
        if not alias then break end
        list[#list + 1] = alias
    end
    return list
end

local function WriteAliases(name, list)
    for i = 1, 32 do
        _G["SLASH_" .. name .. i] = list[i] or nil
    end
end

-- Every registration except ours that answers to /keys.
local function OtherKeysOwners()
    local owners = {}
    for name in pairs(SlashCmdList) do
        if name ~= "KEYPORT" then
            for _, alias in ipairs(AliasesOf(name)) do
                if type(alias) == "string" and alias:lower() == KEYS_ALIAS then
                    owners[#owners + 1] = name
                    break
                end
            end
        end
    end
    return owners
end

local function ReleaseKeys()
    for name, original in pairs(displacedAliases) do
        WriteAliases(name, original)
        displacedAliases[name] = nil
    end
    for i = 1, 32 do
        if _G["SLASH_KEYPORT" .. i] == KEYS_ALIAS then _G["SLASH_KEYPORT" .. i] = nil end
    end
    if _G.hash_SlashCmdList then _G.hash_SlashCmdList["/KEYS"] = nil end
    if _G.ChatFrame_ImportAllListsToHash then pcall(_G.ChatFrame_ImportAllListsToHash) end
end

ClaimKeysCommand = function()
    local mode = db.keysCommand or "force"
    local mine = SlashCmdList["KEYPORT"]

    if mode == "off" then
        if next(displacedAliases) then ReleaseKeys() end
        return false
    end

    local owners = OtherKeysOwners()
    if mode == "auto" and #owners > 0 and not next(displacedAliases) then
        return false   -- someone else got there first and we are being polite
    end

    -- Take /keys off everyone else, keeping their other aliases contiguous.
    for _, name in ipairs(owners) do
        local original = AliasesOf(name)
        if not displacedAliases[name] then
            local copy = {}
            for i, alias in ipairs(original) do copy[i] = alias end
            displacedAliases[name] = copy
        end
        local kept = {}
        for _, alias in ipairs(original) do
            if alias:lower() ~= KEYS_ALIAS then kept[#kept + 1] = alias end
        end
        WriteAliases(name, kept)
    end

    -- Register it to us, on the first free SLASH_KEYPORT slot.
    local slot
    for i = 1, 32 do
        local existing = _G["SLASH_KEYPORT" .. i]
        if existing == KEYS_ALIAS then slot = i; break end
        if not existing then slot = slot or i end
    end
    _G["SLASH_KEYPORT" .. (slot or 3)] = KEYS_ALIAS

    -- Point the live hash at us now, then let the importer confirm it.
    if _G.hash_SlashCmdList then _G.hash_SlashCmdList["/KEYS"] = mine end
    if _G.ChatFrame_ImportAllListsToHash then pcall(_G.ChatFrame_ImportAllListsToHash) end
    return true
end

-------------------------------------------------------------------------------
--  EVENT HANDLING
-------------------------------------------------------------------------------
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON_NAME then return end
        InitDB()
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_LOGIN")
        return
    end

    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
        end
        if C_ChallengeMode and C_ChallengeMode.RequestMapInfo then
            C_ChallengeMode.RequestMapInfo()
        end
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then
            C_MythicPlus.RequestMapInfo()
        end
        BuildCatalog()
        RefreshSeasonBests()
        KeyPort.RecordOwnKeystone()
        BuildPanel()   -- login is always out of combat: safe to build the secure button
        if LibKeystone then
            -- Party keys only; the library also reports guild keys, which are
            -- none of KeyPort's business.
            LibKeystone.Register(KeyPort, function(level, mapID, rating, name, channel)
                StoreKeystone(level, mapID, rating, name, channel)
            end)
        end
        ClaimKeysCommand()
        self:RegisterEvent("CHAT_MSG_ADDON")
        self:RegisterEvent("BN_CHAT_MSG_ADDON")
        self:RegisterEvent("LFG_LIST_JOINED_GROUP")
        self:RegisterEvent("GUILD_ROSTER_UPDATE")
        self:RegisterEvent("CHALLENGE_MODE_START")
        self:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        return

    elseif event == "CHAT_MSG_ADDON" then
        -- a1 prefix, a2 payload, a3 channel, a4 sender
        if a1 ~= COMM_PREFIX or type(a2) ~= "string" then return end
        if a3 ~= "PARTY" and a3 ~= "INSTANCE_CHAT" then return end
        HandleMessage(a2, a4)
        return

    elseif event == "BN_CHAT_MSG_ADDON" then
        -- a1 prefix, a2 payload, a3 channel, a4 Battle.net sender id
        if a1 ~= COMM_PREFIX or type(a2) ~= "string" then return end
        HandleFriendMessage(a2, a4)
        return

    elseif event == "GUILD_ROSTER_UPDATE" then
        if keyList and keyList:IsShown() then KeyPort.RefreshKeyList() end
        return

    elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
        BuildCatalog()
        RefreshSeasonBests()
        return

    elseif event == "CHALLENGE_MODE_START" then
        if vote.active then ClearVote() end
        -- The run is under way; there is nothing left to coordinate.
        queued.keyList = false
        if keyList then keyList:Hide() end
        KeyPort.Hide()
        return

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- The new key lands a moment after the run ends.
        if C_Timer and C_Timer.After then
            C_Timer.After(3, KeyPort.RecordOwnKeystone)
        end
        -- Everyone is about to be handed a new keystone; drop the stale ones.
        -- The run just finished may also have raised our own season best.
        RefreshSeasonBests()
        wipe(keystones)
        selection = nil
        if keyList and keyList:IsShown() then KeyPort.RefreshKeyList() end
        return

    elseif event == "LFG_LIST_JOINED_GROUP" then
        -- You just joined someone else's group, so whatever key was on screen
        -- (a vote result, a shared key) is about the group you were in a moment
        -- ago. Stand down and leave the field to the Group Finder reminder,
        -- which is the one that is right now.
        KeyPort.Hide()
        return

    elseif event == "PLAYER_REGEN_DISABLED" then
        KeyPort.Hide()   -- teleports cannot be cast in combat
        if keyList and keyList:IsShown() then
            queued.keyList = true    -- reopen it once the pull is over
            keyList:Hide()
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return

    elseif event == "PLAYER_REGEN_ENABLED" then
        if queued.build then
            queued.build = false
            BuildPanel()
            PaintText()
        end
        if queued.attr and teleportBtn then
            teleportBtn:SetAttribute("spell", queued.attr)
            queued.attr = nil
        end
        if queued.show and shown.spellID then
            queued.show = false
            PaintButton()
            if panel then panel:Show() end
            self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        end
        if queued.hide then
            queued.hide = false
            if panel and panel:IsShown() then panel:Hide() end
        end
        if queued.keyList then
            queued.keyList = false
            KeyPort.OpenKeyList()
        end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        return

    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if panel and panel:IsShown() then PaintButton() end
        return

    elseif event == "GROUP_ROSTER_UPDATE" then
        if not IsInGroup() then
            wipe(recentMessages)
            wipe(keystones)      -- guild keys are not group state, so they stay
            if vote.active then ClearVote() end
            selection = nil
            if keyList then keyList:Hide() end
            KeyPort.Hide()
        elseif keyList and keyList:IsShown() then
            KeyPort.RefreshKeyList()   -- someone joined or left mid-pick
        end
        return

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- Addons that register /keys late (load-on-demand ones) would
        -- otherwise take it back after login.
        if event == "PLAYER_ENTERING_WORLD" then ClaimKeysCommand() end
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType == "party" then KeyPort.Hide() end
        return
    end
end)
