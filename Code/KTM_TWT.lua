

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
local function explode(str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = find(str, delimiter, from, 1, true)
    while delim_from do
        tinsert(result, substr(str, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = find(str, delimiter, from, true)
    end
    tinsert(result, substr(str, from))
    return result
end

me.processthreatupdate = function(message)

	local playersString = substr(message, find(message, me.threatApi) + slen(me.threatApi), slen(message))

    local players = explode(playersString, ';')

    for _, tData in players do

        local msgEx = explode(tData, ':')

        -- udts handling
        if msgEx[1] and msgEx[2] and msgEx[3] and msgEx[4] and msgEx[5] then

            local player = msgEx[1]
            local tank = msgEx[2] == '1'
            local threat = tonumber(msgEx[3])
            local perc = tonumber(msgEx[4])
            local melee = msgEx[5] == '1'

			mod.table.updateplayerthreat(player, threat)
			KLHTM_RequestRedraw("raid")
		end
	end
	
	return
end


me.onload = function()
	local _, build , _ = GetBuildInfo()
	me.tWOW  = tonumber(build) > 6000
end

