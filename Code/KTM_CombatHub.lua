--[[
    KLHThreatMeter - CombatHub Adapter
    Routes KTM_ModernAPI combat and UNIT_CASTEVENT traffic through CombatHub
    without modifying upstream KTM_ModernAPI.lua.
    Strict Lua 5.0.
]]

if not CombatHub or type(CombatHub.OnPostLogin) ~= "function" then
    return
end

CombatHub:OnPostLogin(function()
    local M = KTM_ModernAPI
    local feeder = getglobal("KTM_ModernAPIFeeder")
    if not M or not feeder then return end

    local origOnEvent = feeder:GetScript("OnEvent")
    if type(origOnEvent) ~= "function" then return end

    local function dispatch(ev, a1, a2, a3, a4, a5, a6, a7, a8, a9)
        CombatHub:InvokeFrameOnEvent(feeder, origOnEvent, ev, a1, a2, a3, a4, a5, a6, a7, a8, a9)
    end

    if M.combatSource == "dpslog" then
        feeder:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        CombatHub:Subscribe("KTM_Combat", "KLHThreatMeter (CLEU)", {
            "COMBAT_LOG_EVENT_UNFILTERED",
        }, dispatch, nil)
    elseif M.combatSource == "nampower" then
        local npEvents = {
            "SPELL_DAMAGE_EVENT_SELF",
            "AUTO_ATTACK_SELF",
            "SPELL_HEAL_BY_SELF",
            "SPELL_ENERGIZE_BY_SELF",
        }
        local i
        for i = 1, table.getn(npEvents) do
            feeder:UnregisterEvent(npEvents[i])
        end
        CombatHub:Subscribe("KTM_Combat", "KLHThreatMeter (Nampower)", npEvents, dispatch, nil)
    end

    if M.hasSuperWoW then
        feeder:UnregisterEvent("UNIT_CASTEVENT")
        CombatHub:Subscribe("KTM_Cast", "KLHThreatMeter (Cast)", {
            "UNIT_CASTEVENT",
        }, dispatch, "self")
    end
end)
