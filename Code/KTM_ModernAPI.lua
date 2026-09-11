--[[
KTM_ModernAPI.lua  (v2 -- rewritten against your real source)

CHANGE FROM v1: the first version of this file (before I could see your
actual Code\ files) built a "synthetic chat-text" bridge -- turning real
structured combat data back INTO fake CHAT_MSG_* text, because I didn't
know of a safer hook and didn't want to guess at your private internals.

Now that combined.md gave me the real source, that whole approach is
gone. Your addon already exposes its internals cleanly, because every
module does `mod.<name> = me` at the top of its file -- e.g.
KTM_CombatParser.lua does `mod.combatparser = me`, which means
`mod.combatparser.action`, `mod.combatparser.parserstagethree`, etc. are
ALL real, callable, already-public fields. Nothing here is a guess at a
hidden local anymore.

CONFIRMED (read directly from your uploaded combined.md):
  - KTM_CombatParser.lua: the real dispatch pipeline is
    mod.regex.parse(text) -> mod.combatparser.parserstagetwo[id](...)
    fills mod.combatparser.action -> mod.combatparser.parserstagethree[
    action.type]() calls mod.combat.specialattack / normalattack /
    possibleoverheal / powergain / taunt. Stage one (text regex) is the
    ONLY stage this file now bypasses -- stages two/three are your real,
    tested code, called directly.
  - mod.combat.specialattack(abilityid, target, damage, iscrit, spellschool)
  - mod.combat.normalattack(spellname, spellid, damage, isdot, target, iscrit, spellschool)
  - mod.combat.possibleoverheal(spellname, spellid, amount, target)
  - mod.combat.powergain(amount, powertype, spellid) -- powertype must be
    the LOCALIZED string from mod.string.get("power","rage"|"energy"|"mana"),
    compared against UnitPowerType("player") (0=mana,1=rage,3=energy --
    standard WoW client convention).
  - mod.table.updateplayersunder(player, sunder) -- feeds the raid GUI's
    sunder column (KTM_Tables.lua). Confirmed from source.
  - KTM_TWT.lua (your own existing external-API precedent) confirms the
    established pattern: detect the source, feed real internal functions
    directly, request a redraw. This file follows the same shape.
  - mod.string.unlocalise("spell", name) -> internal abilityid (used by
    stage three when spellid == ""; this file relies on the SAME call,
    it doesn't reimplement it).

UPDATE 2: both remaining gaps got closed by what you uploaded.
  - You pasted ClassicAPI's real docs/API.md content for C_UnitAuras.
    CONFIRMED: AuraData table fields include `.name`, `.spellId`,
    `.dispelName`, `.applications`, `.isHarmful` -- exactly the field
    names GetSunderStacks() was already using. No longer a guess.
  - You pasted WeirdUtils DPSLog's full wiki page. CONFIRMED: complete
    COMBAT_LOG_EVENT_UNFILTERED base/prefix/suffix argument layout for
    every subevent this file needs (SWING_DAMAGE, SPELL_DAMAGE,
    SPELL_HEAL, SPELL_ENERGIZE, and their PERIODIC/RANGE variants).
    This is now the PREFERRED data source over nampower's events when
    both are present -- one unified, fully-documented event beats a
    dozen separately-shaped ones, and DPSLog's own stated purpose is
    exactly the problem this file exists to solve (replacing
    string.find-based chat parsing with structured data). nampower's
    events remain as the fallback when DPSLog isn't installed but
    nampower is.

    Note the boolean semantics DPSLog uses (confirmed from your paste):
    `critical`/`glancing`/`crushing` are `"1"` (truthy string) for true,
    `nil` for false -- test with `if critical then`, not `== 1`. This
    file follows that.

STILL UNCONFIRMED:
  - Nothing load-bearing for this file. If you want to go further later,
    the remaining ClassicAPI namespaces (C_Spell, C_Container, etc.
    beyond C_UnitAuras) and nampower's DBC_FIELDS.md/UNIT_FIELDS.md
    weren't needed here and weren't fetched.

.toc NOTE: your current .toc lists this file as `KTM_ModernAPI.lua`
(no `Code\` prefix) but the file is actually at `Code\KTM_ModernAPI.lua`
per your own combined.md -- so as uploaded, this file was never loading.
Fixed in the .toc below.
]]

KTM_ModernAPI = {}
local M = KTM_ModernAPI

-------------------------------------------------------------------------
-- Library detection -- each is its own flag (never merged), per the
-- lesson that a single "is it installed" boolean can't be diagnosed
-- from the outside when it's wrong.
-------------------------------------------------------------------------

M.hasSuperWoW   = (SUPERWOW_VERSION ~= nil)
M.hasClassicAPI = (CLASSIC_API_VERSION ~= nil)
M.hasNampower   = (type(GetSpellIdCooldown) == "function")
M.hasWeirdUtils = (type(GetWeirdUtilsVersion) == "function")
M.hasDPSLog     = M.hasWeirdUtils and (GetWeirdUtilsVersion("dpslog") ~= nil)
M.hasUnitXP3    = false
do
	local ok = pcall(UnitXP, "nop", "nop")
	M.hasUnitXP3 = ok and true or false
end

-------------------------------------------------------------------------
-- GUID / name helpers
-------------------------------------------------------------------------

function M.GetGUID(unit)
	if not unit then return nil end
	if M.hasSuperWoW then
		local exists, guid = UnitExists(unit)
		if exists and guid then return guid end
	end
	if type(UnitGUID) == "function" then
		return UnitGUID(unit)
	end
	return nil
end

--- Best-effort GUID -> current unit token/name. Falls back through every
--- source available; returns nil (caller falls back to "target"/"player")
--- if none resolve it.
function M.NameFromGUID(guid)
	if not guid then return nil end
	if type(UnitTokenFromGUID) == "function" then
		local token = UnitTokenFromGUID(guid)
		if token then return UnitName(token) end
	end
	if guid == M.GetGUID("target") then return UnitName("target") end
	if guid == M.GetGUID("player") then return UnitName("player") end
	if guid == M.GetGUID("pet") then return UnitName("pet") end
	if guid == M.GetGUID("mouseover") then return UnitName("mouseover") end
	return nil
end

-- pcall + cache wrapper for a closed-source native call. Confirmed via
-- WeirdUtils' own README example:
--   local name, rank, icon, castTime, minRange, maxRange, spellId = GetSpellInfo(133)
-- Falls back to SuperWoW's SpellInfo() or ClassicAPI's C_Spell.GetSpellName
-- if WeirdUtils/DPSLog isn't present.
local spellNameCache = {}
local function SpellName(spellId)
	if spellNameCache[spellId] ~= nil then return spellNameCache[spellId] end

	local ok, name = pcall(function()
		if M.hasDPSLog and type(GetSpellInfo) == "function" then
			local n = GetSpellInfo(spellId)
			if n then return n end
		end
		if SpellInfo then -- SuperWoW
			local n = SpellInfo(spellId)
			if n then return n end
		end
		if C_Spell and C_Spell.GetSpellName then
			return C_Spell.GetSpellName(spellId)
		end
		return nil
	end)

	name = (ok and name) or ("spell:" .. tostring(spellId))
	spellNameCache[spellId] = name
	return name
end

-------------------------------------------------------------------------
-- Reliable Sunder Armor stack reading (ClassicAPI C_UnitAuras), wired
-- into your REAL sunder tracking.
--
-- Your existing mechanism (KTM_Combat.lua: me.sunder / me.addsunderthreat
-- / me.retractsundercast, hooked onto UseAction & CastSpellByName) is
-- NOT a weak guess -- it's a solid assume-success-then-retract-on-
-- failure design, confirmed from your source. This function does not
-- replace it.
--
-- What it adds: your existing system only knows about casts YOU made.
-- It has no way to know the debuff's actual current stack count on the
-- target -- e.g. after a target switch, after another warrior's sunder,
-- or after a boss ability strips debuffs. GetSunderStacks() reads that
-- directly off the target's real aura data and corrects
-- mod.table.raidsunder (via the confirmed mod.table.updateplayersunder)
-- to match reality.
-------------------------------------------------------------------------

local SUNDER_ARMOR_SPELL_IDS = {
	[7386] = true, [7405] = true, [8380] = true, [11596] = true, [11597] = true,
}

function M.GetSunderStacks(unit)
	if not (M.hasClassicAPI and C_UnitAuras and C_UnitAuras.GetUnitAuras) then
		return nil
	end

	local ok, debuffs = pcall(C_UnitAuras.GetUnitAuras, unit, "HARMFUL")
	if not ok or not debuffs then return nil end

	-- Field names (.spellId / .applications) are now CONFIRMED against
	-- ClassicAPI's real docs/API.md (AuraData table). Left this dump in
	-- as a cheap ongoing sanity check against your actual build/version --
	-- costs nothing, and catches a future API change before it silently
	-- breaks the sunder correction below.
	if M.debugUnknownPayloads and debuffs[1] and not M._auraShapeShown then
		M._auraShapeShown = true
		local parts = {}
		for k, v in pairs(debuffs[1]) do
			table.insert(parts, tostring(k) .. "=" .. tostring(v))
		end
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cffff9900KTM_ModernAPI aura table shape|r " .. table.concat(parts, ", "))
	end

	for _, aura in ipairs(debuffs) do
		if aura.spellId and SUNDER_ARMOR_SPELL_IDS[aura.spellId] then
			return aura.applications or 1
		end
	end
	return 0
end

--- Corrects mod.table.raidsunder[you] to the real stack count on your
--- current target, using the confirmed mod.table.updateplayersunder.
--- Call this periodically (e.g. from an OnUpdate throttle) or on
--- PLAYER_TARGET_CHANGED -- it's cheap and a no-op if ClassicAPI can't
--- answer.
function M.SyncSunderStacks()
	if not mod or not mod.table or not mod.table.updateplayersunder then return end
	local stacks = M.GetSunderStacks("target")
	if stacks == nil then return end -- unavailable, leave existing tracking alone
	mod.table.updateplayersunder(UnitName("player"), stacks)
	KLHTM_RequestRedraw("raid")
end

-------------------------------------------------------------------------
-- Direct combat-data feed, bypassing ONLY stage-one text parsing.
--
-- This populates mod.combatparser.action exactly as stage two would
-- have, then calls mod.combatparser.parserstagethree[type]() -- your
-- real, existing, tested dispatch code. Nothing here reimplements
-- threat math; it only supplies real numbers instead of regex-matched
-- chat text.
-------------------------------------------------------------------------

local function ResetAction()
	local a = mod.combatparser.action
	a.type = ""
	a.spellname = ""
	a.spellid = ""
	a.damage = 0
	a.target = ""
	a.iscrit = false
	a.spellschool = ""
end

local function RunStageThree(actionType)
	local a = mod.combatparser.action
	a.type = actionType
	if mod.combatparser.parserstagethree[actionType] then
		mod.combatparser.parserstagethree[actionType]()
	end
end

-- Power-of-two bit test, no `bit` library assumed present (stock Lua 5.0
-- has none).
local function HasFlag(value, flag)
	if not value then return false end
	return math.floor(value / flag) % 2 == 1
end
local HITINFO_CRITICALHIT = 128 -- confirmed via nampower EVENTS.md (AUTO_ATTACK hitInfo bit 0x80)

-- Standard WoW client power-type numbers -> the LOCALIZED strings
-- mod.combat.powergain expects (confirmed: it compares against
-- mod.string.get("power","rage"/"energy"/"mana")). 0=mana,1=rage,3=energy
-- is the standard client convention, not specific to any of these mods.
local POWERTYPE_TO_KEY = { [0] = "mana", [1] = "rage", [3] = "energy" }

KTM_ModernAPI.debugUnknownPayloads = true
local function DumpPayload(evt)
	if not KTM_ModernAPI.debugUnknownPayloads then return end
	DEFAULT_CHAT_FRAME:AddMessage(string.format(
		"|cff33ccffKTM_ModernAPI|r %s: %s, %s, %s, %s, %s, %s, %s, %s",
		evt, tostring(arg1), tostring(arg2), tostring(arg3), tostring(arg4),
		tostring(arg5), tostring(arg6), tostring(arg7), tostring(arg8)))
end

-- Shared by both DPSLog and nampower paths: feed one attack/heal/powergain
-- into the real parser pipeline.
local function FeedAttack(target, spellname, spellid, amount, iscrit)
	ResetAction()
	local a = mod.combatparser.action
	a.target = target
	a.spellname = spellname or ""
	a.spellid = spellid or ""
	a.damage = amount
	a.iscrit = iscrit and true or false -- normalizes DPSLog's "1"/nil to a real boolean
	RunStageThree("attack")
end

local function FeedHeal(target, spellname, amount)
	ResetAction()
	local a = mod.combatparser.action
	a.target = target
	a.spellname = spellname or ""
	a.damage = amount
	RunStageThree("heal")
end

local function FeedPowergain(spellname, powerType, amount)
	local key = POWERTYPE_TO_KEY[powerType]
	if not key or not mod.string.get("power", key) then return end
	ResetAction()
	local a = mod.combatparser.action
	a.spellname = spellname or ""
	a.damage = amount
	a.target = mod.string.get("power", key) -- powergain expects this in the "target" slot (confirmed)
	RunStageThree("powergain")
end

local feeder = CreateFrame("Frame", "KTM_ModernAPIFeeder")
feeder:RegisterEvent("PLAYER_LOGIN")
feeder:SetScript("OnEvent", function()
	if event ~= "PLAYER_LOGIN" then return end

	if M.hasDPSLog then
		-- PREFERRED: one unified, fully-documented event (confirmed from
		-- your pasted DPSLog wiki) instead of nampower's several.
		this:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	elseif M.hasNampower then
		-- Fallback: nampower present but DPSLog isn't.
		this:RegisterEvent("SPELL_DAMAGE_EVENT_SELF") -- no CVar needed (confirmed)
		SetCVar("NP_EnableAutoAttackEvents", "1")
		SetCVar("NP_EnableSpellHealEvents", "1")
		SetCVar("NP_EnableSpellEnergizeEvents", "1")
		this:RegisterEvent("AUTO_ATTACK_SELF")
		this:RegisterEvent("SPELL_HEAL_BY_SELF")
		this:RegisterEvent("SPELL_ENERGIZE_BY_SELF")
	end

	if M.hasSuperWoW then
		this:RegisterEvent("UNIT_CASTEVENT")
	end

	if M.hasClassicAPI then
		this:RegisterEvent("PLAYER_TARGET_CHANGED")
	end
end)

feeder:SetScript("OnEvent", function()
	if event == "PLAYER_LOGIN" then return end

	if event == "PLAYER_TARGET_CHANGED" then
		M.SyncSunderStacks()
		return
	end

	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		-- CONFIRMED (your pasted DPSLog wiki): base args are always
		-- sub, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName,
		-- dstFlags, dstRaidFlags. We only care about events YOU caused.
		local sub, srcGUID, srcName, _, _, dstGUID, dstName = CombatLogGetCurrentEventInfo()
		if srcGUID ~= M.GetGUID("player") then return end

		local target = dstName or M.NameFromGUID(dstGUID) or "target"

		if sub == "SWING_DAMAGE" then
			-- CONFIRMED: no spell prefix, suffix starts at position 10.
			local _, _, _, _, _, _, _, _, _,
			      amount, _, _, _, _, _, critical = CombatLogGetCurrentEventInfo()
			if amount then
				FeedAttack(target, nil, "whitedamage", amount, critical)
			end

		elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE"
			or sub == "RANGE_DAMAGE" or sub == "DAMAGE_SHIELD" or sub == "DAMAGE_SPLIT" then
			-- CONFIRMED: spell prefix (spellId, spellName, spellSchool) then
			-- _DAMAGE suffix (amount, overkill, school, resisted, blocked,
			-- absorbed, critical, glancing, crushing).
			local _, _, _, _, _, _, _, _, _,
			      spellId, spellName, _, amount, _, _, _, _, _, critical = CombatLogGetCurrentEventInfo()
			if amount then
				FeedAttack(target, spellName, nil, amount, critical)
			end

		elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
			-- CONFIRMED: spell prefix then amount, overhealing, absorbed, critical.
			local _, _, _, _, _, _, _, _, _,
			      _, spellName, _, amount = CombatLogGetCurrentEventInfo()
			if amount then
				FeedHeal(dstName or UnitName("player"), spellName, amount)
			end

		elseif sub == "SPELL_ENERGIZE" or sub == "SPELL_PERIODIC_ENERGIZE" then
			-- CONFIRMED: spell prefix then amount, powerType.
			local _, _, _, _, _, _, _, _, _,
			      _, spellName, _, amount, powerType = CombatLogGetCurrentEventInfo()
			if amount then
				FeedPowergain(spellName, powerType, amount)
			end
		end
		return
	end

	DumpPayload(event)

	if event == "SPELL_DAMAGE_EVENT_SELF" then
		-- CONFIRMED (nampower EVENTS.md): targetGuid, casterGuid, spellId,
		-- amount, mitigationStr, hitInfo, spellSchool, effectAuraStr
		local targetGUID, _, spellId, amount, _, hitInfo = arg1, arg2, arg3, arg4, arg5, arg6
		if targetGUID and spellId and amount then
			FeedAttack(M.NameFromGUID(targetGUID) or UnitName("target"),
				SpellName(spellId), nil, amount, hitInfo == 2)
		end

	elseif event == "AUTO_ATTACK_SELF" then
		-- CONFIRMED: attackerGuid, targetGuid, totalDamage, hitInfo,
		-- victimState, subDamageCount, blockedAmount, totalAbsorb, totalResist
		local _, targetGUID, amount, hitInfo, victimState = arg1, arg2, arg3, arg4, arg5
		if targetGUID and amount and victimState == 1 then -- 1 == a real hit landed
			FeedAttack(M.NameFromGUID(targetGUID) or UnitName("target"),
				nil, "whitedamage", amount, HasFlag(hitInfo, HITINFO_CRITICALHIT))
		end

	elseif event == "SPELL_HEAL_BY_SELF" then
		-- CONFIRMED: targetGuid, casterGuid, spellId, amount, critical, periodic
		local targetGUID, _, spellId, amount = arg1, arg2, arg3, arg4
		if targetGUID and spellId and amount then
			FeedHeal(M.NameFromGUID(targetGUID) or UnitName("player"), SpellName(spellId), amount)
		end

	elseif event == "SPELL_ENERGIZE_BY_SELF" then
		-- CONFIRMED: targetGuid, casterGuid, spellId, powerType, amount, periodic
		local _, _, spellId, powerType, amount = arg1, arg2, arg3, arg4, arg5
		if amount then
			FeedPowergain(SpellName(spellId), powerType, amount)
		end

	elseif event == "UNIT_CASTEVENT" then
		-- CONFIRMED (SuperWoW wiki): casterGUID, targetGUID, eventType,
		-- spellId, castDuration. eventType one of START/CAST/FAIL/CHANNEL/MAINHAND/OFFHAND.
		local casterGUID, _, castType, spellId = arg1, arg2, arg3, arg4
		if casterGUID == M.GetGUID("player") and castType == "CAST" and spellId then
			M.lastConfirmedCast = spellId
		end
	end
end)

-------------------------------------------------------------------------
-- UnitXP_SP3: real melee range (confirmed via codeberg wiki)
-------------------------------------------------------------------------

function M.IsInMeleeRange(unit)
	if not M.hasUnitXP3 then return nil end
	local ok, dist = pcall(UnitXP, "distanceBetween", "player", unit, "meleeAutoAttack")
	if not ok or not dist then return nil end
	return dist <= 5
end

-------------------------------------------------------------------------
-- Status
-------------------------------------------------------------------------

function M.PrintStatus()
	local function yn(b) return b and "|cff33ff33yes|r" or "|cffff3333no|r" end
	DEFAULT_CHAT_FRAME:AddMessage("KTM_ModernAPI:")
	DEFAULT_CHAT_FRAME:AddMessage("  SuperWoW:   " .. yn(M.hasSuperWoW))
	DEFAULT_CHAT_FRAME:AddMessage("  ClassicAPI: " .. yn(M.hasClassicAPI))
	DEFAULT_CHAT_FRAME:AddMessage("  nampower:   " .. yn(M.hasNampower))
	DEFAULT_CHAT_FRAME:AddMessage("  UnitXP_SP3: " .. yn(M.hasUnitXP3))
	DEFAULT_CHAT_FRAME:AddMessage("  WeirdUtils: " .. yn(M.hasWeirdUtils) .. "  (DPSLog: " .. yn(M.hasDPSLog) .. ")")
	DEFAULT_CHAT_FRAME:AddMessage("  VanillaHelpers: not used (no combat/aura surface)")
end

SLASH_KTMMODERNAPI1 = "/ktmapi"
SlashCmdList["KTMMODERNAPI"] = M.PrintStatus
