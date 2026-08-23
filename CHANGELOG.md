# Changelog

## 1.6.0

- **A Recent tab.** Players you group with are remembered along with the key
  they were carrying, their rating and their class, newest first. `/kp recent`
  opens it.
- **Records past the weekly reset are greyed out**, portrait and all, and their
  key reads *last week's key* rather than pretending to still exist. The
  tooltip says when the player was last seen.
- A recent player's key can be selected and sent like any other, and
  right-click forgets a player. `/kp recent clear` empties the list.
- The list keeps the fifty most recent players, so it cannot grow forever.

## 1.5.0

- **An Alts tab.** Every character on the account that has logged in with
  KeyPort is listed with the keystone it is holding, its level and its Mythic+
  rating, so you can see at a glance which alt is carrying the key you want.
  `/kp alts` opens it.
- Keystones reset weekly, so a key recorded before the last reset is shown as
  *last week's key* rather than pretending to still exist, and cannot be sent.
- An alt's key can be selected and sent to the party like any other, which is
  handy when the answer to "whose key?" is "give me a minute, I'll swap".
- Right-click a character to forget it, or `/kp alts clear` to forget all but
  the one you are on. Characters are recorded at login, on opening the tab, and
  a few seconds after finishing a run.

## 1.4.1

- **You now choose which keys go on the ballot.** Vote no longer puts every key
  up immediately: it starts a ballot with all of them ticked, you click rows to
  take keys off or put them back, and Start sends it. Cancel throws it away.
  Nothing reaches the party until you press Start.
- `/kp vote all` keeps the old behaviour of putting every key up in one step.

## 1.4.0

- **Put the key to a vote.** The Vote button, or `/kp vote`, turns the party's
  keystones into a ballot: everyone running KeyPort sees the list with a live
  tally, clicks the key they want and casts. You can change your mind until the
  clock runs out. The winner is sent to the party exactly as if someone had
  picked it by hand, popup and chat line included.
- The starter takes a snapshot of the keys on offer and sends it as the ballot,
  so every client votes on the same list even where their keystone data differs.
  Ballots are broadcast and tallied locally, so the count moves in real time on
  every screen.
- A tie goes to the higher key, then to the name, and only the player who
  started the vote declares the result, so nobody sees a different winner.
- `/kp vote 45` sets how long a vote runs (10 to 120 seconds, 30 by default).
- Votes are cancelled by a run starting or by the group breaking up, and every
  incoming ballot is validated against your own dungeon table like any other
  KeyPort message.

## 1.3.3

- The keystone level now sits beside the dungeon name rather than in a column
  of its own, which frees the width the name was being clipped in.
- Row text is a point smaller.
- When a name and its level will not fit together, the short dungeon code
  stands in rather than the level being cut off. The window measures the text
  instead of guessing from its width, so it adapts to long names and to
  languages with longer ones.

## 1.3.2

- **Fixed `/keys` still opening another addon's window.** Writing our own entry
  into the chat system's command hash was not enough: that hash is rebuilt from
  every `SLASH_<NAME><n>` global, so two addons claiming `/keys` raced and the
  winner came down to table order. KeyPort now takes the alias off the other
  addon instead of competing with it, which is deterministic. The other addon's
  remaining aliases are shifted down so they keep working, and `/kp keys off`
  restores every alias exactly as it was.

## 1.3.1

First CurseForge release. No changes to the addon itself: this version wires up
the CurseForge project so that tagging a release publishes it automatically.

## 1.3.0

- **A guild tab.** The window now has Party and Guild tabs; the guild tab lists
  the keystones your guildmates are carrying, with class colours read from the
  guild roster. `/kp guild` opens straight to it. A guildmate's key can be
  selected and sent to your party like any other.
- **Mythic+ score column**, in Blizzard's own rating rarity colour, for both
  tabs. It also appears in the row tooltip.
- **Narrower, and resizable.** The default window is a good deal tighter, and
  the grip in the bottom right resizes it. A taller window shows more rows (the
  guild list scrolls with the mouse wheel); a narrow one falls back to short
  dungeon codes, with the full name still in the tooltip. Size and position are
  saved.
- **`/keys` opens KeyPort.** It is claimed on login even if another addon
  already registered it, and re-claimed on zone changes so a late-loading addon
  cannot take it back. `/kp keys off|auto|force` changes that: `auto` yields to
  an addon that already has it, `off` leaves it alone entirely. KeyPort
  remembers the previous owner, so `off` hands `/keys` straight back, and a
  mode you set yourself is never overridden by a future default.

## 1.2.0

- **One line in party chat when a key is sent**, so members without KeyPort
  still learn which dungeon was picked: `KeyPort: Kings' Rest +12 (Bobbo's
  key)`. It only fires on a deliberate send, never on selecting a row, and the
  same line will not post twice in a row. Turn it off with `/kp announce`.
- **Keystone levels say whether the key beats what you have already cleared.**
  A level above your season best for that dungeon, or in a dungeon you have not
  completed at all, shows green with an up arrow; anything at or below your best
  stays gold. The comparison is per viewer, so the same shared popup reads green
  only for the people it is new ground for.
- Hovering a row explains the colour: whose key it is, the dungeon and level,
  and either "Above your best here (+9)" or "You have already completed +12
  here".

## 1.1.0

- **`/kp` now opens the group's keystone list.** Every party member's key is
  listed with the owner's name in class colour, the dungeon and the level;
  click one to select it, then **Send to Party** puts that teleport on
  everyone's screen. The popup and the selection line both name whose key it
  is.
- Each row carries the player's **portrait** and the **dungeon's own icon**
  (the challenge-mode map art, falling back to the teleport's spell icon). A
  portrait that cannot be fetched falls back to the class icon.
- Keys come from LibKeystone, the library DBM and BigWigs embed, so the list
  fills in from party members running any of those. They do not need KeyPort.
- The share message now carries the key's owner, so everyone sees *"Bobbo's
  key"* rather than just who pressed the button. Messages from 1.0.0 are still
  understood.
- `/kp mine` keeps the old behaviour of using the keystone in your own bags.
- Guards:
  - KeyPort stays quiet in a **raid group**; it is a five-player tool.
  - Nothing fires while a **Mythic+ run is active**, and starting a run closes
    anything already on screen.
  - A command typed **in combat** is not thrown away: the keystone list opens,
    and a queued reminder appears, as soon as combat ends.
- Finishing a run clears the stored keystones, since everyone is about to be
  handed a new one.

## 1.0.0

Initial release.

- `/kp <dungeon> <level>` raises a dungeon teleport reminder for you and every
  group member running KeyPort. Built for premade keys, where Group Finder
  never fires one.
- Dungeon codes are generated from the client's own localized dungeon names
  (`KR`, `DoN`, `BV`, `HoV`, `PotSF`, `Sky`…), so they work in every language and
  need no maintenance. Full names, partial names and this season's pool all
  resolve; ambiguous queries list the candidates instead of guessing.
- Keystone level accepted as `10`, `+10`, or glued to the code (`kr10`).
- `/kp` with no arguments uses the keystone in your bags.
- `/kp me` shows locally without broadcasting; `/kp hide` closes the popup for
  the whole group; `/kp list` / `/kp list all` print the codes; `/kp share`
  toggles receiving; `/kp scale` resizes.
- `/kp map <dungeon> <spellID>` teaches KeyPort a teleport it doesn't know yet,
  so a new dungeon never has to wait for an update.
- Teleport button shows the spell icon and cooldown swipe, and greys out when
  the teleport is not learned.
- Movable popup with saved position; auto-hides on entering the dungeon,
  leaving the group, or entering combat.
- Incoming addon messages can only select an entry from your local table, so a
  group member cannot place an arbitrary spell on your teleport button.
