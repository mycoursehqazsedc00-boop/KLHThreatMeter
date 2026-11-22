--[[
KTM_ModernAPI.lua
Client-mod integration & compatibility layer for KLHThreatMeter (WoW 1.12 / Turtle WoW).

Strictly Lua 5.0 safe (runs with or without ClassicAPI).
Uses dependency injection against `klhtm` so upstream files need minimal/zero diffs.

Supported client mods (all optional, detected at PLAYER_LOGIN):
  - WeirdUtils (dpslog): preferred COMBAT_LOG_EVENT_UNFILTERED combat feed
  - Nampower:            fallback combat feed (SPELL_DAMAGE_EVENT_SELF, AUTO_ATTACK_SELF, etc.)
  - ClassicAPI:          C_UnitAuras for exact target Sunder Armor stacks (+ CLEU 11-arg fallback)
  - SuperWoW:            GUID resolution & UNIT_CASTEVENT cast confirmation
  - UnitXP SP3:          exact meleeAutoAttack distance for 110%/130% aggro threshold
]]

KTM_ModernAPI = {}
local M = KTM_ModernAPI

M.hasClassicAPI     = false
M.hasSuperWoW       = false
M.hasNampower       = false
M.hasUnitXP3        = false
M.hasWeirdUtils     = false
M.hasDPSLog         = false
M.hasVanillaHelpers = false

M.combatSource      = "stock" -- "dpslog" | "nampower" | "stock"
M.debugTrace        = false
M.targetSunderStacks = nil
M.lastConfirmedCast = nil

local playerGUID = nil
local parserHooked = false
local raidDrawHooked = false

local function Trace(msg)
	if not M.debugTrace then return end
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[KTM_ModernAPI]|r " .. tostring(msg))
end

-------------------------------------------------------------------------
-- Feature detection (called at PLAYER_LOGIN)
-------------------------------------------------------------------------

local function DetectMods()
	M.hasClassicAPI     = (CLASSIC_API_VERSION ~= nil)
	M.hasSuperWoW       = (SUPERWOW_VERSION ~= nil)
	M.hasNampower       = (type(GetNampowerVersion) == "function")
	M.hasWeirdUtils     = (type(GetWeirdUtilsVersion) == "function")
	M.hasDPSLog         = M.hasWeirdUtils and (GetWeirdUtilsVersion("dpslog") ~= nil)
	M.hasVanillaHelpers = (type(UnitDisplayInfo) == "function")

	local ok = pcall(UnitXP, "nop", "nop")
	if ok then
		M.hasUnitXP3 = true
	else
		M.hasUnitXP3 = false
	end
end

-------------------------------------------------------------------------
-- GUID / name / spell helpers
-------------------------------------------------------------------------

function M.GetGUID(unit)
	if not unit then return nil end
	if M.hasSuperWoW then
		local exists, guid = UnitExists(unit)
		if exists and guid then return guid end
	end
	if type(GetUnitGUID) == "function" then
		return GetUnitGUID(unit)
	end
	if type(UnitGUID) == "function" then
		return UnitGUID(unit)
	end
	return nil
end

local function RefreshPlayerGUID()
	playerGUID = M.GetGUID("player")
	return playerGUID
end

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

local spellNameCache = {}
local function SpellName(spellId)
	if not spellId then return "" end
	if spellNameCache[spellId] ~= nil then return spellNameCache[spellId] end

	local ok, name = pcall(function()
		if M.hasDPSLog and type(GetSpellInfo) == "function" then
			local n = GetSpellInfo(spellId)
			if n then return n end
		end
		if type(SpellInfo) == "function" then
			local n = SpellInfo(spellId)
			if n then return n end
		end
		if type(GetSpellNameAndRankForId) == "function" then
			local n = GetSpellNameAndRankForId(spellId)
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
-- Target Sunder Armor stack tracking (non-destructive to raidsunder)
-------------------------------------------------------------------------

local SUNDER_ARMOR_SPELL_IDS = {
	[7386] = true, [7405] = true, [8380] = true, [11596] = true, [11597] = true,
}

function M.GetSunderStacks(unit)
	if not unit or not UnitExists(unit) or not UnitCanAttack("player", unit) then
		return nil
	end

	-- 1) Preferred: ClassicAPI C_UnitAuras
	if M.hasClassicAPI and C_UnitAuras and C_UnitAuras.GetUnitAuras then
		local ok, debuffs = pcall(C_UnitAuras.GetUnitAuras, unit, "HARMFUL")
		if ok and debuffs then
			local i
			for i = 1, table.getn(debuffs) do
				local aura = debuffs[i]
				if aura and aura.spellId and SUNDER_ARMOR_SPELL_IDS[aura.spellId] then
					return aura.applications or 1
				end
			end
			return 0
		end
	end

	-- 2) Fallback: stock UnitDebuff (also returns spellId on SuperWoW)
	local i = 1
	while i <= 16 do
		local texture, count, _, auraId = UnitDebuff(unit, i)
		if not texture then break end
		if auraId and SUNDER_ARMOR_SPELL_IDS[auraId] then
			return count or 1
		end
		if texture == "Interface\\Icons\\Ability_Warrior_Sunder" then
			return count or 1
		end
		i = i + 1
	end

	return 0
end

local function ApplySunderToRaidBottomBar()
	if not KLHTM_RaidFrameBottomMasterTargetText then return end
	if M.targetSunderStacks == nil then return end
	if not UnitExists("target") or not UnitCanAttack("player", "target") then return end

	local base = ""
	if klhtm and klhtm.target and klhtm.target.mastertarget then
		base = klhtm.target.mastertarget
	end

	local tag = string.format("[Sunder: %d/5]", M.targetSunderStacks)
	if base ~= "" then
		KLHTM_RaidFrameBottomMasterTargetText:SetText(base .. "  " .. tag)
	else
		KLHTM_RaidFrameBottomMasterTargetText:SetText(tag)
	end
end

function M.SyncSunderStacks()
	local stacks = M.GetSunderStacks("target")
	if stacks == M.targetSunderStacks then return end
	M.targetSunderStacks = stacks
	Trace("Target Sunder stacks: " .. tostring(stacks))
	if type(KLHTM_RequestRedraw) == "function" then
		KLHTM_RequestRedraw("raid")
	end
	ApplySunderToRaidBottomBar()
end

local function HookRaidDraw()
	if raidDrawHooked or type(KLHTM_DrawRaidFrame) ~= "function" then return end
	raidDrawHooked = true
	local origDraw = KLHTM_DrawRaidFrame
	KLHTM_DrawRaidFrame = function()
		origDraw()
		ApplySunderToRaidBottomBar()
	end
end

-------------------------------------------------------------------------
-- Direct combat-data feed into klhtm.combatparser.parserstagethree
-------------------------------------------------------------------------

local function HasFlag(value, flag)
	if not value then return false end
	return math.mod(math.floor(value / flag), 2) == 1
end
local HITINFO_CRITICALHIT = 128 -- 0x80

local POWERTYPE_TO_KEY = { [0] = "mana", [1] = "rage", [3] = "energy" }

-- Combat log school bitmask (CLEU) and enum index (Nampower) -> localized SPELL_SCHOOL*_CAP
local SCHOOL_MASK_TO_CAP = {
	[1]  = SPELL_SCHOOL0_CAP, -- Physical
	[2]  = SPELL_SCHOOL1_CAP, -- Holy
	[4]  = SPELL_SCHOOL2_CAP, -- Fire
	[8]  = SPELL_SCHOOL3_CAP, -- Nature
	[16] = SPELL_SCHOOL4_CAP, -- Frost
	[32] = SPELL_SCHOOL5_CAP, -- Shadow
	[64] = SPELL_SCHOOL6_CAP, -- Arcane
}

local SCHOOL_INDEX_TO_CAP = {
	[0] = SPELL_SCHOOL0_CAP,
	[1] = SPELL_SCHOOL1_CAP,
	[2] = SPELL_SCHOOL2_CAP,
	[3] = SPELL_SCHOOL3_CAP,
	[4] = SPELL_SCHOOL4_CAP,
	[5] = SPELL_SCHOOL5_CAP,
	[6] = SPELL_SCHOOL6_CAP,
}

local function ResetAction()
	if not klhtm or not klhtm.combatparser then return false end
	local a = klhtm.combatparser.action
	a.type = ""
	a.spellname = ""
	a.spellid = ""
	a.damage = 0
	a.target = ""
	a.iscrit = false
	a.spellschool = ""
	return true
end

local function RunStageThree(actionType)
	local cp = klhtm and klhtm.combatparser
	if not cp then return end
	cp.action.type = actionType
	if cp.parserstagethree and cp.parserstagethree[actionType] then
		cp.parserstagethree[actionType]()
	end
end

local function FeedAttack(target, spellname, spellid, amount, iscrit, spellschool)
	if not amount or amount <= 0 then return end
	if not ResetAction() then return end
	local a = klhtm.combatparser.action
	a.target = target or UnitName("target") or "Unknown"
	a.spellname = spellname or ""
	a.spellid = spellid or ""
	a.damage = amount
	a.spellschool = spellschool or ""
	if iscrit then
		a.iscrit = true
	else
		a.iscrit = false
	end
	RunStageThree("attack")
end

local function FeedHeal(target, spellname, amount)
	if not amount or amount <= 0 then return end
	if not ResetAction() then return end
	local a = klhtm.combatparser.action
	a.target = target or UnitName("player")
	a.spellname = spellname or ""
	a.damage = amount
	RunStageThree("heal")
end

local function FeedPowergain(spellname, powerType, amount)
	if not amount or amount <= 0 then return end
	if not klhtm or not klhtm.string or not klhtm.string.get then return end
	local key = POWERTYPE_TO_KEY[powerType]
	if not key then return end
	local localizedPower = klhtm.string.get("power", key)
	if not localizedPower then return end
	if not ResetAction() then return end
	local a = klhtm.combatparser.action
	a.spellname = spellname or ""
	a.damage = amount
	a.target = localizedPower
	RunStageThree("powergain")
end

-------------------------------------------------------------------------
-- Prevent double-counting with stock CHAT_MSG_* parser
-------------------------------------------------------------------------

local function NoOp() end

local function HookCombatParser()
	if parserHooked then return end
	if not klhtm or not klhtm.combatparser or not klhtm.combatparser.onevent then return end
	parserHooked = true

	local cp = klhtm.combatparser
	local origOnevent = cp.onevent

	cp.onevent = function()
		if M.combatSource == "stock" then
			origOnevent()
			return
		end

		-- Keep CHAT_MSG_SPELL_SELF_DAMAGE only for non-damaging "special" casts
		-- (Taunt, Growl, Feint, etc.) by temporarily disabling stage-three "attack".
		if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
			local stage3 = cp.parserstagethree
			local origAttack = stage3.attack
			stage3.attack = NoOp
			local ok, err = pcall(origOnevent)
			stage3.attack = origAttack
			if not ok then
				error(err)
			end
			return
		end

		-- All other CHAT_MSG_* events (white hits, dots, heals, powergains,
		-- damage shields) are supplied directly by DPSLog / Nampower.
	end
end

-------------------------------------------------------------------------
-- COMBAT_LOG_EVENT_UNFILTERED handler (handles 9-arg DPSLog & 11-arg ClassicAPI)
-------------------------------------------------------------------------

local function HandleCLEU()
	local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11,
	      a12, a13, a14, a15, a16, a17, a18, a19, a20, a21 = CombatLogGetCurrentEventInfo()

	local sub, srcGUID, dstGUID, dstName
	local p1, p2, p3, p4, p5, p6, p7, p8, p9, p10

	if type(a1) == "number" then
		-- 11-arg base (ClassicAPI): timestamp, sub, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags
		sub = a2
		srcGUID = a4
		dstGUID = a8
		dstName = a9
		p1, p2, p3, p4, p5, p6, p7, p8, p9, p10 = a12, a13, a14, a15, a16, a17, a18, a19, a20, a21
	else
		-- 9-arg base (WeirdUtils DPSLog): sub, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags
		sub = a1
		srcGUID = a2
		dstGUID = a6
		dstName = a7
		p1, p2, p3, p4, p5, p6, p7, p8, p9, p10 = a10, a11, a12, a13, a14, a15, a16, a17, a18, a19
	end

	local meGUID = playerGUID or RefreshPlayerGUID()
	if not meGUID or srcGUID ~= meGUID then return end

	local target = dstName or M.NameFromGUID(dstGUID) or "target"

	if sub == "SWING_DAMAGE" then
		-- p1=amount, p7=critical
		if p1 then
			FeedAttack(target, nil, "whitedamage", p1, p7)
		end

	elseif sub == "SPELL_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "DAMAGE_SPLIT" then
		-- p1=spellId, p2=spellName, p3=spellSchool, p4=amount, p10=critical
		if p4 then
			FeedAttack(target, p2, nil, p4, p10, SCHOOL_MASK_TO_CAP[p3])
		end

	elseif sub == "SPELL_PERIODIC_DAMAGE" then
		if p4 then
			FeedAttack(target, p2, "dot", p4, p10, SCHOOL_MASK_TO_CAP[p3])
		end

	elseif sub == "DAMAGE_SHIELD" then
		if p4 then
			FeedAttack(target, p2, "damageshield", p4, p10, SCHOOL_MASK_TO_CAP[p3])
		end

	elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
		-- p1=spellId, p2=spellName, p4=amount
		if p4 then
			FeedHeal(dstName or UnitName("player"), p2, p4)
		end

	elseif sub == "SPELL_ENERGIZE" or sub == "SPELL_PERIODIC_ENERGIZE" then
		-- Only count power gained by the player
		if dstGUID == meGUID and p4 and p5 then
			FeedPowergain(p2, p5, p4)
		end
	end
end

-------------------------------------------------------------------------
-- Single unified event frame
-------------------------------------------------------------------------

local feeder = CreateFrame("Frame", "KTM_ModernAPIFeeder")
feeder:RegisterEvent("PLAYER_LOGIN")
feeder:SetScript("OnEvent", function()
	if event == "PLAYER_LOGIN" then
		DetectMods()
		RefreshPlayerGUID()
		HookRaidDraw()

		if M.hasDPSLog then
			M.combatSource = "dpslog"
			this:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
			HookCombatParser()
		elseif M.hasNampower then
			M.combatSource = "nampower"
			this:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")
			this:RegisterEvent("AUTO_ATTACK_SELF")
			this:RegisterEvent("SPELL_HEAL_BY_SELF")
			this:RegisterEvent("SPELL_ENERGIZE_BY_SELF")
			HookCombatParser()
		else
			M.combatSource = "stock"
		end

		if M.hasSuperWoW then
			this:RegisterEvent("UNIT_CASTEVENT")
		end

		this:RegisterEvent("PLAYER_TARGET_CHANGED")
		this:RegisterEvent("UNIT_AURA")
		M.SyncSunderStacks()
		return
	end

	if event == "PLAYER_TARGET_CHANGED" then
		M.SyncSunderStacks()
		return
	end

	if event == "UNIT_AURA" then
		if arg1 == "target" then
			M.SyncSunderStacks()
		end
		return
	end

	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		HandleCLEU()
		return
	end

	if event == "SPELL_DAMAGE_EVENT_SELF" then
		-- targetGuid, casterGuid, spellId, amount, mitigationStr, hitInfo, spellSchool, effectAuraStr
		local targetGUID, _, spellId, amount, _, hitInfo, spellSchool = arg1, arg2, arg3, arg4, arg5, arg6, arg7
		if targetGUID and spellId and amount then
			FeedAttack(M.NameFromGUID(targetGUID) or UnitName("target"),
				SpellName(spellId), nil, amount, hitInfo == 2, SCHOOL_INDEX_TO_CAP[spellSchool])
		end

	elseif event == "AUTO_ATTACK_SELF" then
		-- attackerGuid, targetGuid, totalDamage, hitInfo, victimState
		local _, targetGUID, amount, hitInfo, victimState = arg1, arg2, arg3, arg4, arg5
		if targetGUID and amount and amount > 0 and (victimState == 1 or victimState == 5) then
			FeedAttack(M.NameFromGUID(targetGUID) or UnitName("target"),
				nil, "whitedamage", amount, HasFlag(hitInfo, HITINFO_CRITICALHIT))
		end

	elseif event == "SPELL_HEAL_BY_SELF" then
		-- targetGuid, casterGuid, spellId, amount
		local targetGUID, _, spellId, amount = arg1, arg2, arg3, arg4
		if targetGUID and spellId and amount then
			FeedHeal(M.NameFromGUID(targetGUID) or UnitName("player"), SpellName(spellId), amount)
		end

	elseif event == "SPELL_ENERGIZE_BY_SELF" then
		-- targetGuid, casterGuid, spellId, powerType, amount
		local targetGUID, _, spellId, powerType, amount = arg1, arg2, arg3, arg4, arg5
		local meGUID = playerGUID or RefreshPlayerGUID()
		if meGUID and targetGUID == meGUID and amount then
			FeedPowergain(SpellName(spellId), powerType, amount)
		end

	elseif event == "UNIT_CASTEVENT" then
		local casterGUID, _, castType, spellId = arg1, arg2, arg3, arg4
		local meGUID = playerGUID or RefreshPlayerGUID()
		if meGUID and casterGUID == meGUID and castType == "CAST" and spellId then
			M.lastConfirmedCast = spellId
		end
	end
end)

-------------------------------------------------------------------------
-- UnitXP SP3: exact melee range
-------------------------------------------------------------------------

function M.IsInMeleeRange(unit)
	if not M.hasUnitXP3 or not unit or not UnitExists(unit) then return nil end
	local ok, dist = pcall(UnitXP, "distanceBetween", "player", unit, "meleeAutoAttack")
	if not ok or not dist then return nil end
	return dist <= 5
end

-------------------------------------------------------------------------
-- Slash command: /ktmapi [trace]
-------------------------------------------------------------------------

function M.PrintStatus(msg)
	if msg == "trace" then
		M.debugTrace = not M.debugTrace
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffKTM_ModernAPI|r trace: " .. (M.debugTrace and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
		return
	end
	local function yn(b) return b and "|cff33ff33yes|r" or "|cffff3333no|r" end
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffKTM_ModernAPI|r (combat source: |cffffff00" .. M.combatSource .. "|r):")
	DEFAULT_CHAT_FRAME:AddMessage("  ClassicAPI:     " .. yn(M.hasClassicAPI))
	DEFAULT_CHAT_FRAME:AddMessage("  Nampower:       " .. yn(M.hasNampower))
	DEFAULT_CHAT_FRAME:AddMessage("  SuperWoW:       " .. yn(M.hasSuperWoW))
	DEFAULT_CHAT_FRAME:AddMessage("  UnitXP_SP3:     " .. yn(M.hasUnitXP3))
	DEFAULT_CHAT_FRAME:AddMessage("  WeirdUtils:     " .. yn(M.hasWeirdUtils) .. "  (DPSLog: " .. yn(M.hasDPSLog) .. ")")
	DEFAULT_CHAT_FRAME:AddMessage("  VanillaHelpers: " .. yn(M.hasVanillaHelpers) .. " (unused for combat)")
end

SLASH_KTMMODERNAPI1 = "/ktmapi"
SlashCmdList["KTMMODERNAPI"] = M.PrintStatus
