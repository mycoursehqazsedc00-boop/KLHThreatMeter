# KLHThreatMeter (Patched for WoW 1.12 / Turtle WoW)

> Threat meter for Vanilla WoW 1.12 / Turtle WoW (`LaYt` edition) with client-mod integration (`KTM_ModernAPI`), Turtle WoW Threat API (`KTM_TWT`), and performance optimizations.

## Client Mods Used
| Mod | Purpose in this addon | Required? |
|---|---|---|
| WeirdUtils (`dpslog`) | Preferred structured `COMBAT_LOG_EVENT_UNFILTERED` combat feed | Optional |
| Nampower | Fallback structured combat events (`SPELL_DAMAGE_EVENT_SELF`, `AUTO_ATTACK_SELF`, `SPELL_HEAL_BY_SELF`, `SPELL_ENERGIZE_BY_SELF`) | Optional |
| ClassicAPI | `C_UnitAuras.GetUnitAuras` for exact target Sunder Armor stacks & 11-arg `COMBAT_LOG_EVENT_UNFILTERED` support | Optional |
| SuperWoW | GUID resolution (`UnitExists`) & `UNIT_CASTEVENT` cast confirmation | Optional |
| UnitXP SP3 | Exact `meleeAutoAttack` distance check for 110% (melee) vs 130% (ranged) aggro threshold | Optional |

The addon works without optional mods; features that depend on them fall back automatically to stock WoW 1.12 behavior.

## Features
- **Structured Combat Feed (`KTM_ModernAPI.lua`):** Uses WeirdUtils `dpslog` (preferred) or Nampower (fallback) to feed `klhtm.combatparser` directly without regex text parsing or double-counting.
- **Target Sunder Armor Stack Display:** Reads real Sunder Armor stacks (`0/5`–`5/5`) on the current hostile target via ClassicAPI `C_UnitAuras` (or `UnitDebuff` fallback) and displays `[Sunder: X/5]` in the raid threat bottom bar without corrupting per-warrior `raidsunder` / `totalsunder` counters.
- **Accurate Melee/Ranged Aggro Threshold:** Uses UnitXP SP3 `meleeAutoAttack` distance in `KTM_MasterTarget.lua` for the 110% vs 130% aggro-gain bar.
- **Turtle WoW Threat API (`KTM_TWT.lua`):** Zero-allocation parsing of `TWTv4=` server threat updates.

## What Was Added / Improved
- **Fixed (`KTM_ModernAPI.lua`):**
  - Merged duplicate `feeder:SetScript("OnEvent", ...)` calls so `PLAYER_LOGIN` event registration actually runs.
  - Replaced non-existent global `mod` references with `klhtm`.
  - Replaced Lua 5.1 `%` operator with Lua 5.0 `math.mod`.
  - Added selective `klhtm.combatparser.onevent` hook to prevent double-counting threat while preserving non-damaging `special` casts (Taunt, Growl, Feint).
  - Moved feature detection to `PLAYER_LOGIN`, cached `playerGUID`, handled both 9-arg (`dpslog`) and 11-arg (`ClassicAPI`) `COMBAT_LOG_EVENT_UNFILTERED`, fixed `DAMAGE_SHIELD` / `SPELL_PERIODIC_DAMAGE` `spellid`s, fixed `AUTO_ATTACK_SELF` partial blocks (`victimState == 5`), and disabled `debugTrace` by default.
  - Replaced destructive `updateplayersunder(UnitName("player"), stacks)` with non-destructive `[Sunder: X/5]` target stack display on the raid bottom bar.
- **Improved (`KTM_TWT.lua`, `KTM_MasterTarget.lua`, `KTM_Combat.lua`):**
  - Eliminated per-message `explode()` table allocations and moved `KLHTM_RequestRedraw("raid")` outside the player loop in `KTM_TWT.lua`.
  - Integrated `KTM_ModernAPI.IsInMeleeRange()` (UnitXP SP3) into `KTM_MasterTarget.lua` aggro-gain calculation.
  - Throttled `KTM_Combat.lua` `recentattacks` cleanup to `0.1s` instead of running every frame.

## Usage
- `/ktmapi` — Show detected client mods and active combat feed source (`dpslog` / `nampower` / `stock`).
- `/ktmapi trace` — Toggle debug trace messages for `KTM_ModernAPI`.

## Credits & License
- Original addon: Kenco@Perenolde, Plask, LaYt (`KLHThreatMeter`)
- Client-mod integration & fixes: `KTM_ModernAPI` contributors
- License: Same as original addon unless stated otherwise.
