# Squawk Spy

Enemy player detection and a shared Kill on Sight list for the **World of
Warcraft: Forever** beta.

Made by **Avoid Me** of **&lt;Squawk&gt;**.

Inspired by [Spy](https://www.curseforge.com/wow/addons/spy) by **Immolation**
and **Slipjack**. This is a rebuild, not a port: the windows, lists and
workflow are deliberately Spy's, but the detection engine underneath is new,
because Spy's cannot work on this client.

## Why the original Spy cannot simply be fixed

Forever runs Classic content on the **Midnight (12.x) addon API**, and two
changes there break Spy at the root:

| Change | Effect |
| --- | --- |
| `COMBAT_LOG_EVENT_UNFILTERED` errors on `RegisterEvent` and `CombatLogGetCurrentEventInfo` is gone | Spy's primary detector is gone with it. It saw *every* enemy who acted anywhere in combat-log range, through walls and terrain, before they were ever rendered. Nothing available to an addon replaces that reach. |
| SavedVariables are written but never restored | The KoS list, settings and player history would reset every session. |

`WOW_PROJECT_ID` also reports retail here, so Classic-only libraries silently
never load. This addon therefore has no Ace3, no LibStub and no external
libraries at all.

Be clear-eyed about what that costs: detection here is **line of sight and
render range**, not combat-log range. You will not get the old "someone is
fighting two hills away" warning. Everything below is what can still be done.

## Detection

Every source funnels into one handler, so an enemy seen twice is one entry:

- **Nameplates** — the backbone. Each hostile player plate gives name, level,
  class, race and guild. A one-second sweep of `nameplate1..40` keeps *last
  seen* honest and catches plates that were already up when you arrived.
  `/spy plates` turns enemy plates on at the furthest draw distance the client
  will accept (it probes 100, 80, 60, 41 and takes the first that sticks).
- **Your target, focus, mouseover and their targets** — including every group
  member's target, which is how you learn about the enemy your teammate is
  fighting before you can see them.
- **Chat** — say, yell, emote and the Battleground channels name players who
  are nearby but not yet rendered.
- **Group sync** — party, raid and guild members running the addon share their
  detections over an addon channel, so the group sees what any one member sees.

Stealthed players are flagged separately, because a rogue you can see is worth
a different noise than a hunter you can see.

## Kill on Sight

- **Personal KoS** — mark anyone, with a note. Right-click any name in the
  window, use the target button, or `/spy kos <name>`.
- **Guild KoS — shared across the whole guild.** Mark someone Guild KoS and
  they are broadcast to every guildmate running the addon, note included, and
  they keep it. The first person in the guild to get ganked warns everyone.
  - Keyed per guild, so an alt elsewhere does not inherit a list that means
    nothing there.
  - Every entry carries the time it was set and the **newest write wins**, so
    two people marking the same target at once settle on one answer.
  - New clients ask for the list once at login; replies are staggered and stop
    as soon as somebody else answers, so a guild logging in after a raid does
    not flood the channel.
  - Tooltips show the note and who added it.
- Separate alert sound and colour for a KoS hit, so you know before you read.

## Windows

- **Main window** — nearby / last hour / all, class-coloured, with level,
  guild and time since seen, and a count in the title bar. Movable, resizable,
  scales.
- **Alerts** — pop-up on detection, with its own placement, size and duration,
  and different treatment for stealth, KoS and guild KoS.
- **Statistics** — who you have seen, how often, kills and deaths against each
  player, sortable, with a footer summary.
- **Target KoS button** — one click to mark or unmark your current target.
- **Minimap and world map notes** for where a player was last seen.

## Installing

Copy the `SquawkSpy` folder into:

```
World of Warcraft\_classic_beta_\Interface\AddOns\
```

Then run `Setup-SavedVariables.ps1` from inside it — see below, it matters on
this client.

### Artwork and sounds are not included

`Textures\` and `Sounds\` are the original Spy addon's assets and are **not
redistributed here**. The addon does not need them: every texture it would
have used falls back to a stock Blizzard one, and an alert sound simply stays
silent if the file is absent.

If you own Spy and want its exact look and its alert sounds, copy Spy's
`Textures` and `Sounds` folders into `SquawkSpy\` and they are picked up
automatically — the resolver prefers Spy's file whenever it is actually there.

### Settings do not persist without the shim

The Forever beta **writes SavedVariables correctly but never restores them**,
so every addon starts each session with an empty database. This addon works
around it: `SV1`, `SV2` and `SV3` inside the addon folder are directory
junctions pointing at your `WTF\Account\<id>\SavedVariables` folders, and the
TOC loads `SV*\SquawkSpy.lua` as an ordinary addon file, which puts last
session's KoS list and settings back before `Core.lua` runs. `Restore1-3.lua`
park each snapshot so the next one cannot clobber it.

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-SavedVariables.ps1
```

Junctions need no administrator rights.

## Upgrading from SpyF

An earlier version of this addon was called SpyF. The TOC reads the old saved
file once and adopts any list that has no counterpart under the new name, so
your KoS list and history carry over on the first login. It says so in chat
when it happens.

## Commands

```
/spy                 toggle the main window (also /squawkspy)
/spy config          options
/spy stats           statistics window
/spy kos <name>      mark a player Kill on Sight
/spy unkos <name>    clear one
/spy gkos <name>     mark a player GUILD Kill on Sight
/spy ungkos <name>   clear one, for the whole guild
/spy gsync           ask the guild for the shared list now
/spy plates          turn enemy nameplates on at the furthest distance allowed
/spy clear           empty the current list
/spy diag            what this client actually exposes to the addon
/spy reset           back to defaults
```

`/spy diag` exists because this client is a moving target — it reports the
combat log, nameplate API, addon messaging and the restore shim in a few
lines, and will usually say why something is not working.

## Files

| File | Contents |
| --- | --- |
| `Core.lua` | database, restore shim, lists, alerts, capability probing, slash commands |
| `Detect.lua` | every detection source and the one handler they funnel into |
| `Guild.lua` | the guild-wide Kill on Sight list and its sync protocol |
| `UI.lua` | main window, alert popup, target button, map notes |
| `Menu.lua` | right-click menus |
| `Stats.lua` | statistics window |
| `Options.lua` | options panel |

## Credits

Rebuilt by **Avoid Me** of **&lt;Squawk&gt;**.

Inspired by, and modelled on, **Spy** by **Immolation** and **Slipjack**. The
original addon's artwork and sounds remain theirs and are not included here.

Released under the MIT licence.
