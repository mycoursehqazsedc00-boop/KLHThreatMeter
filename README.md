# KTM_ModernAPI — client-mod compat patch for KLHThreatMeter

An optional, standalone patch that adds support for a few community client
mods to [laytya/KLHThreatMeter](https://github.com/laytya/KLHThreatMeter)
(itself a fork of
[KenKaprielian/KLHThreatMeter](https://github.com/KenKaprielian/KLHThreatMeter)),
so it can pull real structured combat data instead of relying entirely on
regex-parsed chat text.

**This repo is not a fork of KLHThreatMeter.** It contains only the new
file and the one-line `.toc` change needed to apply it — kept separate on
purpose, so it stays easy to diff and easy to reapply whenever you pull a
fresh copy of the upstream addon.

## What's in this repo

```
KTM_ModernAPI/
├── KTM_ModernAPI.lua     <-- drop into KLHThreatMeter/Code/
├── toc_patch.txt         <-- the exact line to add, and where
└── README.md             <-- this file
```

## What it does

`KTM_ModernAPI.lua` detects a set of community client mods at load, and — only
when present — feeds the addon's real combat-parser pipeline
(`mod.combatparser`) with structured data instead of chat text. It does
**not** reimplement any threat logic; it only replaces where the numbers
come from. With none of these mods installed, it detects their absence and
KLHThreatMeter behaves exactly as stock.

| Mod | What it's used for |
|---|---|
| [WeirdUtils](https://codeberg.org/MarcelineVQ/WeirdUtils) (DPSLog) | **Preferred** combat data source — one unified `COMBAT_LOG_EVENT_UNFILTERED` event covering damage, heals, and power gains |
| [nampower](https://github.com/brues-code/nampower) | Fallback combat data source, used only if DPSLog isn't installed |
| [ClassicAPI](https://github.com/brues-code/ClassicAPI) | `C_UnitAuras` — reads the real current Sunder Armor stack count off a target, correcting the raid sunder display |
| [SuperWoW](https://github.com/balakethelock/SuperWoW/wiki) | Real GUIDs and `UNIT_CASTEVENT` for confirmed cast landings |
| [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3/wiki) | Real distance checks (melee range) |

**[VanillaHelpers](https://github.com/isfir/VanillaHelpers) is deliberately
not used** — nothing in it touches combat, auras, or unit identity, so
there's no gap in KLHThreatMeter it would fill.

## Applying the patch

1. Clone or download [laytya/KLHThreatMeter](https://github.com/laytya/KLHThreatMeter)
   as normal, and install it in `Interface/Addons/` per its own instructions.
2. Copy `KTM_ModernAPI.lua` from this repo into
   `KLHThreatMeter/Code/KTM_ModernAPI.lua`.
3. Open `KLHThreatMeter.toc` and add one line — see `toc_patch.txt` in this
   repo for the exact placement:
   ```
   Code\KTM_Core.lua
   Code\KTM_ModernAPI.lua        <-- add this line
   ...
   Code\KTM_Combat.lua
   Code\KTM_CombatParser.lua
   ```
   The entry must read exactly `Code\KTM_ModernAPI.lua` — a version without
   the `Code\` prefix will fail to load silently, with no error.
4. `/reload` or relog.

### Reapplying after an upstream update

Since this stays separate from the addon's own repo, updating
KLHThreatMeter is just re-cloning/re-downloading it and repeating steps 2–3
above — nothing to merge or rebase. If upstream ever renames or restructures
`Code\KTM_Combat.lua` / `KTM_CombatParser.lua`, this patch may need updating
to match (see "How it works" below for exactly which internals it depends
on).

## Setup for the client mods themselves

1. Get a DLL loader — [VanillaFixes](https://github.com/hannesmann/vanillafixes)
   is the standard one. Put it in your WoW 1.12 folder alongside `WoW.exe`.
2. Download each DLL you want and place it in that same folder:
   - `WeirdUtils.dll` — **DPSLog is bundled inside this**, it is not a
     separate DLL despite what some copies of its own docs say
   - `nampower.dll` (optional fallback if you skip WeirdUtils)
   - `ClassicAPI.dll`
   - `SuperWoW.dll`
   - `UnitXP_SP3.dll`
3. Create/edit `dlls.txt` in that folder, one filename per line:
   ```
   WeirdUtils.dll
   ClassicAPI.dll
   SuperWoW.dll
   UnitXP_SP3.dll
   ```
4. Launch via `VanillaFixes.exe`, not `WoW.exe` directly.

### Checking what's detected

In-game:

```
/ktmapi
```

Prints which mods were detected at load. If something you installed shows
"no," check `dlls.txt` and confirm you launched via `VanillaFixes.exe`.

## How it works (what this patch actually depends on in upstream)

- **Combat data:** when DPSLog is present, this patch listens for
  `COMBAT_LOG_EVENT_UNFILTERED`, filters to events the player caused, and
  writes directly into `mod.combatparser.action` before calling
  `mod.combatparser.parserstagethree[type]()` — KLHThreatMeter's own real
  dispatch code, exposed because `KTM_CombatParser.lua` does
  `mod.combatparser = me`. Only the chat-text-parsing stage is bypassed.
  nampower's events are used the same way as a fallback.
- **Sunder Armor:** KLHThreatMeter's existing cast-then-verify tracking
  (`KTM_Combat.lua`'s `sunder`/`addsunderthreat`/`retractsundercast`) is
  left completely untouched — it's a solid design on its own. This patch
  adds a correction on top: on target change, it reads the real current
  stack count via ClassicAPI and syncs it into the raid sunder display via
  `mod.table.updateplayersunder()` (from `KTM_Tables.lua`), catching cases
  cast-tracking alone can't (a different warrior's sunder, a target switch,
  a boss stripping debuffs).

Because it depends on those specific upstream internals staying stable,
this is the section to check first if a future KLHThreatMeter update breaks
the patch.

## Status

Everything this patch reads from an external mod is confirmed against that
mod's own documentation (DPSLog's full event spec, ClassicAPI's `AuraData`
field names, nampower's `EVENTS.md`, SuperWoW's and UnitXP_SP3's wikis) —
nothing here is a guess presented as fact. It has not been run against a
live client. If something misbehaves, `/ktmapi` plus a note of which mods
are installed is the fastest way to narrow it down.

## Credits

- [laytya/KLHThreatMeter](https://github.com/laytya/KLHThreatMeter) /
  [KenKaprielian/KLHThreatMeter](https://github.com/KenKaprielian/KLHThreatMeter) —
  the addon this patches. Not affiliated with this repo.
- [WeirdUtils](https://codeberg.org/MarcelineVQ/WeirdUtils),
  [nampower](https://github.com/brues-code/nampower),
  [ClassicAPI](https://github.com/brues-code/ClassicAPI),
  [SuperWoW](https://github.com/balakethelock/SuperWoW),
  [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3) — the client mods
  this patch builds on.
