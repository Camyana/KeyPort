# KeyPort

Raise a dungeon teleport reminder for your **whole group**, on demand.

```
/kp KR 10
```

Kings' Rest, +10, a one-click teleport button on your screen and on every group
member's screen who also runs KeyPort.

Group Finder addons pop a teleport reminder when you join a listed group.
Nothing does it for the premade key you put together in guild chat or Discord.
That is the gap KeyPort fills.

## The keystone list

`/kp` on its own opens the group's keystones: every party member with their
portrait, their dungeon and its icon, their key level, and their name in class
colour. Click a key to select it,
then **Send to Party** puts that dungeon's teleport on everyone's screen, with
the owner named on the popup.

The window has **Party**, **Guild**, **Alts** and **Friends** tabs, a **Mythic+ score** column, and a
grip in the bottom right to resize it. Make it taller for more rows (the guild
list scrolls with the wheel), narrower to fall back to short dungeon codes.
Size and position are saved.

## Putting it to a vote

Hit **Vote** (or `/kp vote`) and you build the ballot first: every key starts
ticked, click rows to take keys off or put them back, then **Start** sends it.
Nothing reaches the party until you do. `/kp vote all` skips that step.

From there every party member running KeyPort sees the ballot with a live
tally, clicks one and casts. Votes can be changed until the clock runs out, and
the winner is then sent to the party as if it had been picked by hand.

A tie goes to the higher key, and only the player who started the vote declares
the result, so nobody sees a different winner. `/kp vote 45` sets the length.

A keystone level shows **green with an up arrow** when it is above your own
season best for that dungeon, or in a dungeon you have not completed at all, and
gold when it is at or below your best. The comparison is per viewer, so the same
shared popup reads green only for the people it is new ground for. Hover a row
for the detail.

Keys arrive over LibKeystone, the same library DBM and BigWigs embed, so the
list fills in from party members running any of those. Only *you* need KeyPort
to raise the reminder.

## Commands

```
/kp <dungeon> <keystone level>
```

The number is the **keystone level**: `/kp kr 10` is Kings' Rest, key level 10.

| Command | What it does |
| --- | --- |
| `/kp kr 10` | Reminder for Kings' Rest, key level 10, for you and your party/raid |
| `/kp kings rest 12` | Match by name; partial names work (`/kp murder`) |
| `/kp kr10` | Level glued to the code |
| `/kp` | Opens the group's keystone list: pick a key, send it |
| `/kp mine` | Uses the keystone in your own bags |
| `/kp me KR 10` | Shows it only for you, no broadcast |
| `/kp hide` | Closes the popup for the whole group |
| `/kp list` / `/kp list all` | This season's codes / every dungeon KeyPort knows |
| `/kp share` | Toggle whether you receive reminders from your group |
| `/kp announce` | Toggle the party chat line sent when a key goes out |
| `/kp vote` | Choose keys for a ballot, then Start (`/kp vote 45` sets the length) |
| `/kp vote all` | Skip the choosing and put every key up |
| `/kp guild` | Open the list on the guild tab |
| `/kp alts` | Your other characters' keystones (`/kp alts clear` forgets them) |
| `/kp friends` | Your Battle.net friends' keystones (`share` opts out, `clear` forgets) |
| `/kp keys off\|auto\|force` | Whether `/keys` opens KeyPort |
| `/kp scale 1.2` | Resize the popup |
| `/kp map <dungeon> <spellID>` | Teach it a teleport it doesn't know yet (a teleport *spell id*, not a key level) |

`/keyport` is an alias for `/kp`.

## Dungeon codes

Codes are generated from the dungeon's own localized name, so they work in every
client language and there is no code list to maintain:

* `KR` Kings' Rest, `DoN` Den of Nalorakk, `BV` The Blinding Vale
* `HoV` Halls of Valor, `CoS` Court of Stars, `PotSF` Priory of the Sacred Flame
* Single-word dungeons use three letters: `Sky` Skyreach

Full names, partial names and the current season's pool all resolve; when a
query is ambiguous the current season wins, and if it is still ambiguous KeyPort
lists the candidates instead of guessing.

## Behaviour

* Drag to move; position and scale are saved.
* The teleport button shows the spell icon and cooldown swipe, and greys out
  with "Teleport not learned" if you haven't earned that teleport.
* Auto-hides when you enter the dungeon, leave the group, or enter combat.
* Footer shows where it came from: *Sent to your party*, or *Shared by \<name\>*.

## Your alts

Every character that logs in with KeyPort records the keystone it is holding,
so the **Alts** tab answers "which of mine has the good key?" without logging
in to find out. Keys from before the weekly reset are shown as *last week's
key* rather than pretending to still exist. Right-click a character to forget
it.

## Battle.net friends

The **Friends** tab asks your Battle.net friends who are online in WoW what key
they are holding. Only friends who also run KeyPort can answer, since the
library the party and guild tabs use does not reach across Battle.net.

Records grey out once they predate the weekly reset and their key reads *last
week's key*, because that is all a cached keystone is worth by then. The tooltip
shows the friend's account name and when they last answered, and right-click
forgets one. `/kp friends share` opts out of the exchange entirely, in both
directions.

## When KeyPort stays out of the way

* **Raid groups.** It is a five-player tool, so in a raid every command is
  refused.
* **During a Mythic+ run.** Nothing fires once the key is in; starting a run
  closes anything already open.
* **In combat.** The request is not thrown away, it waits: the keystone list
  opens, and a queued reminder appears, the moment combat ends.

## The /keys command

Several addons register `/keys` for their own keystone window, so KeyPort will
not simply take it. `/kp keys` controls that:

* `force` (default) takes `/keys` from whichever addon holds it, and re-claims
  it on zone changes so a late-loading addon cannot take it back.
* `auto` claims `/keys` only if nothing else has it when you log in.
* `off` leaves it alone entirely.

KeyPort takes the `/keys` alias off the other addon rather than competing for
it, so the result does not depend on load order. That addon's other commands
are untouched, `off` restores every alias exactly as it was, and a mode you set
yourself is never overridden by a future default.

## Notes

* Group members only see the popup if they also run KeyPort, which is why one
  line goes to party chat when a key is sent: everyone else at least learns
  which dungeon was picked. `/kp announce` turns that line off. Their
  *keystones* show up in your list regardless, as long as they run KeyPort,
  DBM, BigWigs or similar.
* Messages use the `KeyPort` addon channel on PARTY / RAID / INSTANCE_CHAT only.
  An incoming message can only *select* an entry from your own local table, and
  a spell ID KeyPort doesn't know is dropped, so a group member can never put an
  arbitrary spell on your teleport button.
* Secure-frame safe: the teleport button is built once at login out of combat,
  and any attribute write, show or hide that lands mid-combat is queued and
  flushed when combat ends.

## Season updates

The dungeon pool comes from the client (`C_ChallengeMode.GetMapTable`), so a new
season needs no update unless a *new dungeon* is added, which needs one line
in `TELEPORTS` in `KeyPort.lua`. Until that ships you can add it yourself:

```
/kp map <dungeon> <spellID>
```

which stores the pair in your SavedVariables.
