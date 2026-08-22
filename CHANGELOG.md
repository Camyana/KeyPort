# Changelog

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
