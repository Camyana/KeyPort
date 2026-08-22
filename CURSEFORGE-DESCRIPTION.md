# CurseForge project page: copy/paste material

## Project fields

| Field | Value |
| --- | --- |
| **Name** | KeyPort |
| **URL slug** | `keyport` |
| **Summary** | Pick a keystone from your group and put the dungeon teleport on everyone's screen. Built for premade Mythic+ keys. |
| **Game** | World of Warcraft (Retail) |
| **Categories** | Group & Raid (secondary: Miscellaneous) |
| **Project ID** | 1662985 (in `KeyPort.toc` as `X-Curse-Project-ID`) |
| **Game versions** | Match the ids in `KeyPort.toc`; current is `120100` |
| **License** | All Rights Reserved (see `LICENSE.txt`) |
| **Dependencies** | None. LibStub and LibKeystone are embedded, not required installs |
| **Avatar** | `design/keyport-icon-400.png` |
| **Gallery** | `design/keyport-gallery-picker.png` (primary), `design/keyport-gallery-command.png`, `design/keyport-gallery-codes.png`, `design/keyport-banner.png` |

**Summary** is 122 characters (CurseForge allows up to 255).

Shorter alternative, if you want it to fit on one line in listings:

> One command puts the dungeon teleport on every group member's screen. For premade keys.

---

## Description

The same text is in `curseforge-description.html`. Paste **that** into the
description editor's HTML/source view, since the editor does not render Markdown.
Insert `keyport-banner.png` full width above the first paragraph.

---

Everyone's in the group, the key's in the bag, and the run stalls anyway: *"which
dungeon is it again?"*, three people hearth, one flies the wrong way.

Group Finder addons pop a teleport reminder when you join a **listed** group.
Nothing does it for the premade key you put together in guild chat or Discord.

**KeyPort** closes that gap with one command:

```
/kp KR 10
```

Kings' Rest, +10, a one-click teleport button, on your screen and on the screen
of every group member who also runs KeyPort. No chat spam, no links to click, no
alt-tabbing to look up which dungeon a keystone belongs to.

### Pick a key, send it

> Insert `keyport-gallery-picker.png` here.

`/kp` opens the group's keystones: every party member with their portrait,
their dungeon and its icon, their key level, and their name in class colour. Click one, hit **Send to Party**, and
that dungeon's teleport lands on everyone's screen with the owner named on it.

**Party and Guild tabs**, so you can see what your guildmates are carrying as
well, a **Mythic+ score** column, and a resize grip in the bottom right: taller
for more rows, narrower for a compact list. Size and position are saved.

A level shows **green with an up arrow** when the key is above your own season
best for that dungeon, or in a dungeon you have never completed; gold when it is
at or below your best. Each person sees it against their own record.

Sending a key also posts one line in party chat, so the people without KeyPort
know which dungeon was picked: `KeyPort: Kings' Rest +12 (Bobbo's key)`.

Keys arrive over LibKeystone, the library DBM and BigWigs already embed, so the
list fills in from party members running any of those. Only *you* need KeyPort
to raise the reminder.

Prefer to type it? Every command below still works.

### Commands

```
/kp <dungeon> <keystone level>
```

The number is the **keystone level**: `/kp kr 10` means Kings' Rest, key level 10.

| Command | What it does |
| --- | --- |
| `/kp kr 10` | Reminder for Kings' Rest at key level 10, for you and your party or raid |
| `/kp kings rest 12` | Match by name; partial names work too (`/kp murder`) |
| `/kp kr10` | Level glued to the code, if you type fast |
| `/kp` | Opens the group's keystone list |
| `/kp mine` | Uses the keystone in your own bags |
| `/kp me KR 10` | Shows it only for you, no broadcast |
| `/kp hide` | Closes the popup for the whole group |
| `/kp list` | This season's codes (`/kp list all` for every dungeon) |
| `/kp share` | Toggle whether you receive reminders from your group |
| `/kp announce` | Toggle the party chat line sent when a key goes out |
| `/kp guild` | Open the list on the guild tab |
| `/kp keys off\|auto\|force` | Whether `/keys` opens KeyPort |
| `/kp scale 1.2` | Resize the popup |
| `/kp map <dungeon> <spellID>` | Teach KeyPort a teleport it doesn't know yet (a teleport spell id, not a key level) |

`/keyport` is an alias for `/kp`.

### Codes you don't have to learn

Short codes are generated from the dungeon's own name **as your client spells
it**, so they work in every language and there is no list to memorise or
maintain:

`KR` Kings' Rest · `DoN` Den of Nalorakk · `BV` The Blinding Vale ·
`HoV` Halls of Valor · `CoS` Court of Stars · `Sky` Skyreach

Type the code, part of the name, or the whole name. The current season wins ties,
and if a query is still ambiguous KeyPort lists the candidates instead of
guessing.

### Details

- Drag the popup anywhere; position and scale are saved.
- The teleport button shows the real spell icon and its cooldown swipe, and greys
  out with *Teleport not learned* if you haven't earned that teleport yet.
- Auto-hides when you enter the dungeon, leave the group, or enter combat.
- The footer tells you where it came from: *Sent to your party*, or
  *Shared by \<name\>*.
- Nothing runs on a timer, and no addon is required: LibKeystone rides along
  inside KeyPort.

### Quiet and safe by design

- **One line of chat, not a stream.** Sending a key posts a single party chat
  line so members without KeyPort know the dungeon; it never fires on selecting
  a row, never repeats itself, and `/kp announce` turns it off entirely.
- Communication uses the `KeyPort` addon channel on PARTY / RAID /
  INSTANCE_CHAT only, and an incoming message can only *select* an entry from
  your own local dungeon table. A spell ID KeyPort doesn't recognise is dropped,
  so nobody can put an arbitrary spell on your teleport button.
- Secure-frame correct: the teleport button is built once at login out of
  combat, and any attribute write, show or hide that lands mid-combat is queued
  until combat ends. No taint, no blocked actions.

### The /keys command

`/keys` opens KeyPort, even if another addon already registered it. If you
would rather keep that addon's window, `/kp keys auto` yields to whoever has it
and `/kp keys off` leaves it alone; KeyPort remembers the previous owner, so it
hands `/keys` straight back.

### When it stays out of the way

- **Raid groups.** KeyPort is a five-player tool, so in a raid every command is
  refused.
- **During a Mythic+ run.** Nothing fires once the key is in, and starting a run
  closes anything already open.
- **In combat.** Your command is not thrown away, it waits: the keystone list
  opens, and a queued reminder appears, the moment combat ends.

### New season, new dungeon?

The dungeon pool comes from the game client, so a new season just works. If
Blizzard adds a brand-new dungeon before an update ships, teach it yourself:

```
/kp map <dungeon> <spellID>
```

and it's stored in your SavedVariables.

### Requirements

Retail World of Warcraft. Nothing else: KeyPort has no dependencies.

Found a bug, or want it to do something it doesn't? Leave a comment.
