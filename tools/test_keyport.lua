-- ---------------------------------------------------------------------------
--  KeyPort's test suite. Run it with:  python tools/run_tests.py
--
--  It loads the real addon (and the real LibKeystone) against the stubs in
--  wow_stubs.lua and drives it the way the game would: firing events, clicking
--  rows, typing slash commands. Anything that has been fixed once has a test
--  here, so it cannot come back quietly.
-- ---------------------------------------------------------------------------

local passed, groups, group = 0, 0, "?"
local function section(name) group = name; groups = groups + 1; print("== " .. name) end
local function check(condition, message)
    if not condition then error(("[%s] %s"):format(group, message), 2) end
    passed = passed + 1
end

-- ------------------------------------------------------------ load it up ---
SetParty({})
assert(loadfile(LIBS .. "LibStub/LibStub.lua"))()
assert(loadfile(LIBS .. "LibKeystone/LibKeystone.lua"))()
assert(loadfile(ADDON .. "KeyPort.lua"))("KeyPort")

fire("ADDON_LOADED", "KeyPort")
fire("PLAYER_LOGIN")

local panel = _G.KeyPortPopup
local button = _G.KeyPortTeleportButton
local run = SlashCmdList["KEYPORT"]

-- The picker is built the first time it opens, so open it once to get a handle.
run("")
local list = _G.KeyPortKeyList
list:Hide()
local function spell() return button:GetAttribute("spell") end
local function dungeonText() return tostring(panel.dungeon:GetText()) end
local function footer() return tostring(panel.footer:GetText()) end

local KINGS_REST, MURDER_ROW, BLINDING_VALE = 1286831, 1286809, 1286801
local SETHRALISS, COURT_OF_STARS = 1286828, 393766

local function row(named)
    for i = 1, #list.rows do
        local r = list.rows[i]
        if r._shown and r.player:GetText() == named then return r end
    end
end
local function click(r, button_) r:GetScript("OnClick")(r, button_ or "LeftButton") end

-- ============================================================== the popup ===
section("a dungeon code raises the popup and broadcasts it")
SetParty({ { name = "Bobbo", class = "MAGE" } })
fire("GROUP_ROSTER_UPDATE")
run("kr 10")
check(panel._shown, "the popup did not appear")
check(spell() == KINGS_REST, "wrong teleport: " .. tostring(spell()))
check(dungeonText():find("Kings' Rest"), "wrong dungeon: " .. dungeonText())
check(dungeonText():find("%+10"), "the level is missing: " .. dungeonText())
check(lastSent() == "S1:1286831:10", "wrong payload: " .. lastSent())
check(SENT[#SENT].channel == "PARTY", "wrong channel")

section("dungeons resolve by code, name, partial name and glued level")
run("kings rest 12"); check(spell() == KINGS_REST, "full name failed")
run("kr12");          check(spell() == KINGS_REST, "glued level failed")
run("murder");        check(spell() == MURDER_ROW, "partial name failed")
run("+5 tos");        check(spell() == SETHRALISS, "leading level failed")
run("bv");            check(spell() == BLINDING_VALE, "article-stripped code failed")
run("cos");           check(spell() == COURT_OF_STARS, "off-season dungeon failed")

section("the keystone level says whether it beats your season best")
run("kr 12")   -- season best there is 10
check(dungeonText():find("cff40e070", 1, true), "a new best should be green")
check(dungeonText():find("bags%-greenarrow"), "the arrow is missing")
run("mr 14")   -- exactly the season best
check(dungeonText():find("cffffd100", 1, true), "matching your best should stay gold")

section("/kp me shows locally without broadcasting")
local before = #SENT
run("me kr 20")
check(#SENT == before, "a local-only command was broadcast")
check(footer() == "Only you can see this", "wrong footer: " .. footer())

section("a sent key is announced once in party chat")
before = #CHAT
run("tos 9")
check(#CHAT == before + 1, "no chat line")
check(lastChat() == "KeyPort: Temple of Sethraliss +9", "wrong wording: " .. lastChat())
before = #CHAT
run("tos 9")
check(#CHAT == before, "the same line was posted twice")
run("announce")
before = #CHAT
run("bv 4")
check(#CHAT == before, "announced while switched off")
run("announce")

-- ================================================================= comms ===
section("an incoming share is honoured, and credited")
fire("CHAT_MSG_ADDON", "KeyPort", "S2:1286812:11:Zed", "PARTY", "Bobbo-Draenor")
check(footer() == "Zed's key, via Bobbo", "wrong credit: " .. footer())
fire("CHAT_MSG_ADDON", "KeyPort", "S2:1286812:9:Bobbo", "PARTY", "Bobbo-Draenor")
check(footer() == "Bobbo's key", "wrong self-credit: " .. footer())

section("hostile or malformed messages are dropped")
local held = spell()
fire("CHAT_MSG_ADDON", "KeyPort", "S1:999999:11", "PARTY", "Bobbo-Draenor")
check(spell() == held, "an unknown spell id reached the button")
fire("CHAT_MSG_ADDON", "KeyPort", "S1:393256:2", "WHISPER", "Bobbo-Draenor")
fire("CHAT_MSG_ADDON", "Other", "S1:393256:2", "PARTY", "Bobbo-Draenor")
fire("CHAT_MSG_ADDON", "KeyPort", "junk", "PARTY", "Bobbo-Draenor")
fire("CHAT_MSG_ADDON", "KeyPort", "S1:393256:2", "PARTY", "Camyana-Draenor")  -- our own echo
check(spell() == held, "a rejected message got through")

section("markup in a name from the wire is stripped")
fire("CHAT_MSG_ADDON", "KeyPort", "S2:1286812:6:|cffff0000Evil|r", "PARTY", "Bobbo-Draenor")
check(not footer():find("|", 1, true), "markup survived: " .. footer())
check(footer():find("Evil"), "the name was lost: " .. footer())

-- ================================================================ guards ===
section("a raid group refuses everything")
IN_RAID = true
before = #SENT
run("kr 10")
check(#SENT == before, "broadcast from a raid")
run("")
check(not list._shown, "the list opened in a raid")
IN_RAID = false

section("an active run refuses everything, and closes what is open")
run("kr 10")
CHALLENGE_ACTIVE = true
before = #SENT
run("kr 11")
check(#SENT == before, "broadcast during a run")
CHALLENGE_ACTIVE = false
run("kr 10")
check(panel._shown, "setup: the popup should be up")
fire("CHALLENGE_MODE_START")
check(not panel._shown, "the popup survived the run starting")

section("combat defers rather than discards")
COMBAT = true
run("kr 15")
check(not panel._shown, "the popup appeared during combat")
COMBAT = false
fire("PLAYER_REGEN_ENABLED")
check(panel._shown and spell() == KINGS_REST, "the deferred popup never arrived")
COMBAT = true
fire("PLAYER_REGEN_DISABLED")
check(panel._shown, "hiding should wait for combat to end")
COMBAT = false
fire("PLAYER_REGEN_ENABLED")
check(not panel._shown, "the deferred hide never happened")

section("entering the dungeon or leaving the group puts it away")
run("kr 10")
INSTANCE_TYPE = "party"
fire("ZONE_CHANGED_NEW_AREA")
check(not panel._shown, "it survived entering the dungeon")
INSTANCE_TYPE = nil
run("kr 10")
SetParty({})
fire("GROUP_ROSTER_UPDATE")
check(not panel._shown, "it survived leaving the group")

-- ============================================================= the picker ===
section("the list shows the party's keys, with portraits and dungeon icons")
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" } })
fire("GROUP_ROSTER_UPDATE")
run("")
check(list._shown, "the list did not open")
fire("CHAT_MSG_ADDON", "LibKS", "12,249,3184", "PARTY", "Bobbo-Draenor")
fire("CHAT_MSG_ADDON", "LibKS", "8,584,2100", "PARTY", "Cira-Draenor")
KeyPort.RefreshKeyList()
check(row("Camyana") and row("Bobbo") and row("Cira"), "a party member is missing")
check(row("Camyana").avatar._portrait == "player", "no portrait for the player")
check(row("Bobbo").avatar._portrait == "party1", "no portrait for a party member")
check(row("Bobbo").dungeonIcon._texture == 4000249, "wrong dungeon icon")
check(row("Cira").dungeonIcon._texture == 900000 + BLINDING_VALE,
      "the spell icon should stand in when a map has no art")
check(row("Bobbo").score:GetText() == "3184", "the score column is wrong")

section("a failing portrait falls back to the class icon")
local realPortrait = SetPortraitTexture
SetPortraitTexture = function() error("unavailable") end
KeyPort.RefreshKeyList()
check(tostring(row("Bobbo").avatar._texture):find("Icons-Classes", 1, true),
      "no class icon fallback")
SetPortraitTexture = realPortrait
KeyPort.RefreshKeyList()

section("picking a key sends it, credited to its owner")
click(row("Bobbo"))
check(tostring(list.choice:GetText()):find("Bobbo"), "the selection is not named")
KeyPort.SendSelection()
check(lastSent() == "S2:1286831:12:Bobbo", "wrong payload: " .. lastSent())
check(footer() == "Bobbo's key, sent to your party", "wrong footer: " .. footer())
check(not list._shown, "the list should close after sending")

section("the window grows when more rows arrive")   -- regression, 1.7.0
KeyPortDB.listSize = nil
SetParty({})
fire("GROUP_ROSTER_UPDATE")
run("")
local small = list:GetHeight()
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" },
           { name = "Thessa", class = "ROGUE" }, { name = "Marn", class = "PRIEST" } })
fire("GROUP_ROSTER_UPDATE")
KeyPort.RefreshKeyList()
local drawn = 0
for i = 1, #list.rows do if list.rows[i]._shown then drawn = drawn + 1 end end
check(drawn == 5, "a full party should draw five rows, drew " .. drawn)
check(list:GetHeight() > small, "the window did not grow")

section("the window is resizable, and remembers its size")
list.grip:GetScript("OnMouseDown")(list.grip)
list:SetSize(420, 420)
list.grip:GetScript("OnMouseUp")(list.grip)
check(KeyPortDB.listSize and KeyPortDB.listSize.w == 420, "the size was not saved")
KeyPortDB.listSize = nil
list:SetSize(320, 260)
KeyPort.RefreshKeyList()

-- ================================================================= tabs =====
section("the alts tab records this character and greys out old keys")
KeyPortDB.alts = {}
KeyPort.RecordOwnKeystone()
local mine = KeyPortDB.alts["Camyana-Draenor"]
check(mine and mine.mapID == 587 and mine.level == 14, "this character was not recorded")
KeyPortDB.alts["Bankalt-Draenor"] = { name = "Bankalt", realm = "Draenor",
    classFile = "PRIEST", mapID = 249, level = 9, rating = 1200, updated = NOW - 86400 }
KeyPortDB.alts["Oldtimer-Draenor"] = { name = "Oldtimer", realm = "Draenor",
    classFile = "ROGUE", mapID = 584, level = 20, rating = 3000, updated = NOW - 10 * 86400 }
KeyPort.OpenKeyList("ALTS")
check(row("Oldtimer").dungeon:GetText() == "last week's key", "a stale key is not marked")
check(row("Oldtimer").selectable == false, "a stale key should not be selectable")
check(row("Bankalt").selectable == true, "this week's key should be selectable")

section("an alt's key can be sent, and right-click forgets a character")
SetParty({ { name = "Bobbo", class = "MAGE" } })
fire("GROUP_ROSTER_UPDATE")
KeyPort.OpenKeyList("ALTS")
click(row("Bankalt"))
KeyPort.SendSelection()   -- regression, 1.7.0: this used to be dropped on refresh
check(lastSent() == "S2:1286831:9:Bankalt", "an alt's key was not sent: " .. lastSent())
KeyPort.OpenKeyList("ALTS")
click(row("Oldtimer"), "RightButton")
check(KeyPortDB.alts["Oldtimer-Draenor"] == nil, "right-click did not forget")

section("the guild tab collects guild keys separately")
GUILD_ROSTER = { { "Camyana-Draenor", "WARRIOR" }, { "Gorm-Draenor", "PRIEST" } }
fire("CHAT_MSG_ADDON", "LibKS", "9,587,2450", "GUILD", "Gorm-Draenor")
KeyPort.OpenKeyList("GUILD")
check(row("Gorm"), "the guild key is missing")
SetParty({})
fire("GROUP_ROSTER_UPDATE")
KeyPort.OpenKeyList("GUILD")
check(row("Gorm"), "guild keys should survive leaving a party")

section("battle.net friends are asked, and answer")
KeyPortDB.friends = {}
KeyPortDB.friendShare = true
BN_FRIENDS = {
    { accountName = "Zara", gameAccountInfo = { isOnline = true, clientProgram = "WoW",
                                                gameAccountID = 501 } },
    { accountName = "Milo", gameAccountInfo = { isOnline = false, clientProgram = "WoW",
                                                gameAccountID = 502 } },
    { accountName = "Dia", gameAccountInfo = { isOnline = true, clientProgram = "D3",
                                               gameAccountID = 503 } },
}
BN_SENT = {}
KeyPort.OpenKeyList("FRIENDS")
check(#BN_SENT == 1 and BN_SENT[1].id == 501, "only online WoW friends should be asked")
check(BN_SENT[1].payload == "FQ1", "wrong request: " .. BN_SENT[1].payload)
fire("BN_CHAT_MSG_ADDON", "KeyPort", "FA1:249:14:3300:MAGE:Zaramage-Draenor", "WHISPER", 501)
local friend = KeyPortDB.friends["Zaramage-Draenor"]
check(friend and friend.level == 14 and friend.classFile == "MAGE", "the answer was not stored")
check(friend.account == "Zara", "the account name is missing")

section("we answer a friend who asks")
BN_SENT = {}
fire("BN_CHAT_MSG_ADDON", "KeyPort", "FQ1", "WHISPER", 501)
check(#BN_SENT == 1 and BN_SENT[1].payload:find("^FA1:587:14:"), "we did not answer properly")

section("a friend's nonsense is dropped")   -- regression, 1.7.0
fire("BN_CHAT_MSG_ADDON", "KeyPort", "FA1:999999:14:3300:MAGE:Faker-Realm", "WHISPER", 501)
local faker = KeyPortDB.friends["Faker-Realm"]
check(faker.mapID == nil, "an unknown dungeon was stored")
check(faker.level == 0, "a level survived without a dungeon")
fire("BN_CHAT_MSG_ADDON", "KeyPort", "FA1:249:999:3300:NOPE:Weird-Realm", "WHISPER", 501)
check(KeyPortDB.friends["Weird-Realm"].level == 0, "an impossible level was stored")
check(KeyPortDB.friends["Weird-Realm"].classFile == nil, "an unknown class was stored")

-- ================================================================= vote =====
section("a vote is built before it is sent")
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" } })
fire("GROUP_ROSTER_UPDATE")
KeyPort.OpenKeyList("PARTY")
fire("CHAT_MSG_ADDON", "LibKS", "12,249,3000", "PARTY", "Bobbo-Draenor")
fire("CHAT_MSG_ADDON", "LibKS", "8,584,2100", "PARTY", "Cira-Draenor")
KeyPort.RefreshKeyList()
before = #SENT
list.vote:GetScript("OnClick")()
check(#SENT == before, "pressing Vote should not send anything")
check(list.vote.label:GetText() == "Start 3", "wrong candidate count: "
      .. list.vote.label:GetText())
click(row("Cira"))
check(list.vote.label:GetText() == "Start 2", "unpicking a key did not register")
list.vote:GetScript("OnClick")()
check(lastSent():find("^VS1:"), "no ballot was sent: " .. lastSent())
check(not lastSent():find("Cira"), "an unpicked key reached the ballot")

section("ballots are tallied and the winner is sent when the clock runs out")
local voteID = lastSent():match("^VS1:([^:]+):")
click(row("Bobbo"))
KeyPort.CastVote()
check(row("Bobbo").score:GetText() == "1", "our own vote was not tallied")
fire("CHAT_MSG_ADDON", "KeyPort", "VB1:" .. voteID .. ":2", "PARTY", "Bobbo-Draenor")
fire("CHAT_MSG_ADDON", "KeyPort", "VB1:" .. voteID .. ":99", "PARTY", "Cira-Draenor")
KeyPort.RefreshKeyList()
check(row("Bobbo").score:GetText() == "2", "a party ballot was not counted")
AdvanceClock(31)
TickAll()
check(lastSent():find("^S2:1286831:12:Bobbo"), "the winner was not sent: " .. lastSent())
check(spell() == KINGS_REST, "the winner did not raise the popup")

section("a vote from a party member opens here, and only they can end it")
fire("CHAT_MSG_ADDON", "KeyPort",
     "VS1:Bobbo-42:30:1286831,12,Bobbo;1286809,9,Camyana", "PARTY", "Bobbo-Draenor")
check(tostring(list.choice:GetText()):find("Vote:"), "the ballot did not open")
fire("CHAT_MSG_ADDON", "KeyPort", "VE1:Bobbo-42:1", "PARTY", "Cira-Draenor")
check(tostring(list.choice:GetText()):find("Vote:"), "an impostor ended the vote")
fire("CHAT_MSG_ADDON", "KeyPort", "VE1:Bobbo-42:1", "PARTY", "Bobbo-Draenor")
check(not tostring(list.choice:GetText()):find("Vote:"), "the starter could not end it")

-- ================================================================= /keys ====
section("/keys is taken from another addon, without breaking its other commands")
InstallRivalKeysAddon()
check(TypeSlash("/keys") == "ran" and RIVAL_RAN, "setup: the rival should own /keys")
KeyPortDB.keysCommand, KeyPortDB.keysCommandSet = nil, nil
fire("PLAYER_LOGIN")
list:Hide(); RIVAL_RAN = nil
TypeSlash("/keys")
check(not RIVAL_RAN and list._shown, "/keys did not come to KeyPort")
RIVAL_RAN = nil
check(TypeSlash("/ekeys") == "ran" and RIVAL_RAN, "/ekeys was collateral damage")
RIVAL_RAN = nil
check(TypeSlash("/key") == "ran" and RIVAL_RAN, "/key was collateral damage")

section("a hash rebuild cannot hand /keys back")   -- regression, 1.3.2
ChatFrame_ImportAllListsToHash()
list:Hide(); RIVAL_RAN = nil
TypeSlash("/keys")
check(not RIVAL_RAN and list._shown, "a rebuild gave /keys away")

section("/kp keys off hands every alias back")
run("keys off")
RIVAL_RAN = nil
check(TypeSlash("/keys") == "ran" and RIVAL_RAN, "off did not restore /keys")
fire("PLAYER_ENTERING_WORLD")
RIVAL_RAN = nil
check(TypeSlash("/keys") == "ran" and RIVAL_RAN, "off was overridden by the default")
run("keys force")

-- ========================================================== group finder ====
section("a listing does not pop until the group is full")
KeyPortDB.fullPopup = true
SetParty({ { name = "Bobbo", class = "MAGE" } })    -- two of five
fire("GROUP_ROSTER_UPDATE")
panel:Hide()
fire("LFG_LIST_JOINED_GROUP", 77)
check(not panel._shown, "it popped before the group was full")

section("it pops the listing's dungeon when the group completes")
fire("CHAT_MSG_ADDON", "LibKS", "13,249,3000", "PARTY", "Bobbo-Draenor")
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" },
           { name = "Thessa", class = "ROGUE" }, { name = "Marn", class = "PRIEST" } })
before = #SENT
fire("GROUP_ROSTER_UPDATE")
check(panel._shown, "the group filled and nothing appeared")
check(spell() == KINGS_REST, "wrong dungeon: " .. tostring(spell()))
check(dungeonText():find("%+13"), "the party's key level was not used: " .. dungeonText())
check(footer() == "Bobbo's key, group is full", "wrong footer: " .. footer())
check(#SENT == before, "the group-full popup went out over the wire")

section("it fires once per listing")
panel:Hide()
fire("GROUP_ROSTER_UPDATE")
check(not panel._shown, "it popped again on the next roster change")

section("our own listing counts, and leaving the group forgets it")
panel:Hide()
LFG_ACTIVE_ENTRY = { activityID = 9001 }
fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
check(panel._shown and spell() == KINGS_REST, "our own listing did not pop")
LFG_ACTIVE_ENTRY = nil
fire("LFG_LIST_JOINED_GROUP", 77)
SetParty({})
fire("GROUP_ROSTER_UPDATE")
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" },
           { name = "Thessa", class = "ROGUE" }, { name = "Marn", class = "PRIEST" } })
panel:Hide()
fire("GROUP_ROSTER_UPDATE")
check(not panel._shown, "a forgotten listing still popped")

section("a listing with no teleport, or the feature off, stays quiet")
panel:Hide()
fire("LFG_LIST_JOINED_GROUP", 78)      -- a raid listing
fire("GROUP_ROSTER_UPDATE")
check(not panel._shown, "it popped for an activity with no teleport")
run("full")
panel:Hide()
fire("LFG_LIST_JOINED_GROUP", 77)
fire("GROUP_ROSTER_UPDATE")
check(not panel._shown, "it popped while switched off")
run("full")

section("joining a group stands the current popup down")   -- 1.7.1
run("kr 10")
check(panel._shown, "setup: the popup should be up")
fire("LFG_LIST_JOINED_GROUP", 78)
check(not panel._shown, "a stale key survived joining another group")

section("the default position avoids EllesmereUI's reminder")   -- 1.7.1
EUI_QOL_LOADED = false
run("reset")
local alone = panel._point and panel._point[4]
EUI_QOL_LOADED = true
run("reset")
local shared = panel._point and panel._point[4]
check(alone == 150, "the standalone default moved: " .. tostring(alone))
check(math.abs(alone - shared) >= 143, "the two popups would still overlap")
EUI_QOL_LOADED = false

-- ===================================================== who gets credited ===
section("a player who left is never credited")   -- regression, 1.8.1
panel:Hide()
KeyPortDB.fullPopup = true
GROUP_LEADER_UNIT = nil
SetParty({ { name = "Spreist", class = "PRIEST" }, { name = "Cira", class = "DRUID" } })
fire("GROUP_ROSTER_UPDATE")
fire("CHAT_MSG_ADDON", "LibKS", "15,249,3300", "PARTY", "Spreist-Draenor")
SetParty({ { name = "Cira", class = "DRUID" } })          -- Spreist leaves
fire("GROUP_ROSTER_UPDATE")
fire("LFG_LIST_JOINED_GROUP", 77)
SetParty({ { name = "Cira", class = "DRUID" }, { name = "Bobbo", class = "MAGE" },
           { name = "Thessa", class = "ROGUE" }, { name = "Marn", class = "HUNTER" } })
fire("CHAT_MSG_ADDON", "LibKS", "12,249,3000", "PARTY", "Bobbo-Draenor")
fire("GROUP_ROSTER_UPDATE")
check(panel._shown, "setup: the group filled and nothing appeared")
check(not footer():find("Spreist"), "credited a player who left: " .. footer())
check(footer() == "Bobbo's key, group is full", "wrong credit: " .. footer())
check(dungeonText():find("%+12"), "the leaver's level was used: " .. dungeonText())

section("the leader's key wins over a higher one")   -- regression, 1.8.1
panel:Hide()
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" } })
fire("GROUP_ROSTER_UPDATE")
fire("CHAT_MSG_ADDON", "LibKS", "11,249,3000", "PARTY", "Bobbo-Draenor")
fire("CHAT_MSG_ADDON", "LibKS", "16,249,3000", "PARTY", "Cira-Draenor")
GROUP_LEADER_UNIT = "party1"                               -- Bobbo listed it
fire("LFG_LIST_JOINED_GROUP", 77)
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" },
           { name = "Thessa", class = "ROGUE" }, { name = "Marn", class = "HUNTER" } })
fire("GROUP_ROSTER_UPDATE")
check(footer() == "Bobbo's key, group is full", "the leader was passed over: " .. footer())
check(dungeonText():find("%+11"), "the higher key's level was used: " .. dungeonText())
GROUP_LEADER_UNIT = nil

section("with no leader's key, the highest in the group is credited")
panel:Hide()
fire("LFG_LIST_JOINED_GROUP", 77)
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" },
           { name = "Thessa", class = "ROGUE" } })
fire("GROUP_ROSTER_UPDATE")
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" },
           { name = "Thessa", class = "ROGUE" }, { name = "Marn", class = "HUNTER" } })
fire("GROUP_ROSTER_UPDATE")
check(footer() == "Cira's key, group is full", "wrong fallback credit: " .. footer())

section("a name still resolving does not cost anyone their key")
local keep = SetParty
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Unknown", class = "DRUID" } })
fire("GROUP_ROSTER_UPDATE")
SetParty({ { name = "Bobbo", class = "MAGE" }, { name = "Cira", class = "DRUID" } })
fire("GROUP_ROSTER_UPDATE")
KeyPort.OpenKeyList("PARTY")
check(row("Cira") and tostring(row("Cira").dungeon:GetText()):find("%+16"),
      "a key was pruned while its owner's name was still loading")

print(("%d checks passed across %d groups"):format(passed, groups))
print("ALL TESTS PASSED")
