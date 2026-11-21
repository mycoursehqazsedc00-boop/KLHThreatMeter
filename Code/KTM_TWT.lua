

--if not tWOW then return end

local mod = klhtm
local me = {}
mod.twt = me

--[[
TWT.lua
v0.1 by LaYt, public domain

Module for TurtleWOW Treat API

]]

local find, substr , slen = string.find, string.sub, string.len
local tinsert, tonumber = table.insert, tonumber

me.isenabled = true
me.myevents = { "CHAT_MSG_ADDON"}
me.lclass, me.class = UnitClass("player")

me.UDTS = 'TWT_UDTSv4';
me.threatApi = 'TWTv4=';

me.lastupdatetime = 0.0			-- return value of GetTime()
me.longupdateinterval = 0.5 	-- at least this time in seconds will pass between long updates

--[[  
onupdate() function, called from Core.lua
]]
me.onupdate = function()
	
	if not me.tWOW then return end
	
	-- check for long updates
	local timenow = GetTime()
	
	-- long updates
	if timenow > me.lastupdatetime + me.longupdateinterval then
		me.lastupdatetime = timenow
		local party, raid = GetNumPartyMembers(), GetNumRaidMembers()
		-- update combat state
		if party == 0 and raid == 0 then
			return false
		end
		if UnitAffectingCombat('player') and UnitAffectingCombat('target') then
			if raid > 0 then
				SendAddonMessage(me.UDTS , "limit=" .. KLHTM_GuiOptions.raid.rows, "RAID")
			elseif party > 0 then
				SendAddonMessage(me.UDTS , "limit=" .. KLHTM_GuiOptions.raid.rows, "PARTY")
			end
		end
	end
end

me.onevent = function()
	
	
	if event == 'CHAT_MSG_ADDON' and find(arg2, me.threatApi, 1, true) then
		me.processthreatupdate(arg2)
		return 
	end

end
me.processthreatupdate = function(message)
	local startPos = find(message, me.threatApi, 1, true)
	if not startPos then return end

	local from = startPos + slen(me.threatApi)
	local len = slen(message)
	local updated = false

	while from <= len do
		local semi = find(message, ";", from, true)
		local entryEnd
		if semi then
			entryEnd = semi - 1
		else
			entryEnd = len
		end

		if entryEnd >= from then
			local c1 = find(message, ":", from, true)
			if c1 and c1 < entryEnd then
				local c2 = find(message, ":", c1 + 1, true)
				if c2 and c2 < entryEnd then
					local c3 = find(message, ":", c2 + 1, true)
					if c3 and c3 < entryEnd then
						local c4 = find(message, ":", c3 + 1, true)
						if c4 and c4 <= entryEnd then
							local player = substr(message, from, c1 - 1)
							local threat = tonumber(substr(message, c2 + 1, c3 - 1))
							if player ~= "" and threat then
								mod.table.updateplayerthreat(player, threat)
								updated = true
							end
						end
					end
				end
			end
		end

		if not semi then break end
		from = semi + 1
	end

	if updated then
		KLHTM_RequestRedraw("raid")
	end
end


me.onload = function()
	local _, build , _ = GetBuildInfo()
	me.tWOW  = tonumber(build) > 6000
end

