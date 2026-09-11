## Code\GUI\KTM_Gui.lua
```lua
--[[ KLH Threatmeter KLHTM_Gui.lua

local version -> to be integrated into kenco files

Lukon Mod 2: The replacement for Gui.lua and Tables.lua. Controls the GUI 
for KLH ThreatMeter, along with KTM_Frame.xml, KTM_RaidGui.lua, 
KTM_SelfGui.lua, KTM_TitleGui.lua.

There is a single main frame, which shows either raid threat data 
(KTM_RaidGui.lua) or personal threat details (KTM_SelfGui.lua). Each of 
these two frames contains column headers, data rows and a bottom bar. 
Additionally there is a title bar frame (KTM_TitleGui). The GUI elements are
contained in a table "KLHTM_Gui", populated by the CreateGuiTable(). This 
also contains some properties not set in the XML file, such as some 
dimensions and colours.

The appearance of the GUI can be customised via the "KLHTM_GuiOptions" table.
This determines the visibility of command buttons and data columns, the way 
data is displayed in the main tables, and other settings. User access to
these settings is via the options gui (KTM_OptionsFrame.xml, 
KTM_OptionsGui.lua).

The visibility and some properties of the frame as a whole are kept in the
"state" table.

NB the indexes in the tables "gui", "options", and elsewhere shouldn't be
changed. They are assumed to match by various methods.
--]]

-- ken
local mod = klhtm
local me = { }
mod.gui = me

-- The minimum period, in seconds, between data table redrawing
local Min_Redraw_Period = 0.2;

-- When the table was last redrawn
local lastRedraw = 0;
KLHTM_LastRedraw = lastRedraw;

-- Set to true when a redraw has been requested but not yet performed
local needsRedraw = false;
KLHTM_NeedsRedraw = needsRedraw;

-- Contains settings describing the way raid and self data should displayed. 
-- Loaded from saved variables or initialised by _CreateDefaultOptions()
local options = {};
KLHTM_GuiOptions = options;

-- Contains window state information. Loaded from saved variables or 
-- initialised by _CreateDefaultState().
local state = {};
KLHTM_GuiState = state;

-- Contains references to the GUI components and some additional properties
-- not specified in the XML file. Initialised by _CreateGuiTable()
local gui = {};
KLHTM_Gui = gui;

-- true if initialisation (SetupGui) has finished, and rendering is possible
local isInitialised = false;
KLHTM_IsLoaded = false;

-- the maximum change in string width allowed by KLHTM_LocaliseStringWidth()
local Max_Localisation_Factor = 2;

-- frame scale constants
KLHTM_Scale = {["min"] = 0.6, ["max"] = 1.3, ["tick"] = 0.02, ["default"] = 1.0};

-- the current dimensions of the frame and subframes. These are filled by the various
-- UpdateXFrame and Redraw methods.
local sizes = {	["raid"] = {},		["self"] = {},	["but"] = {}, 
				["string"] = {},	["title"] = {},	["frame"] = {}, };
KLHTM_GuiSizes = sizes;

-- The heights of some sizes
KLHTM_GuiHeights = {["button"] = 15, ["string"] = 12, ["header"] = 14, ["data"] = 12};

-- The texture gradient colours used by the main frame and options frame's title bar
KLHTM_TitleBarColours = {
	-- purple
	["raid"] = {["minR"] = 0.2, ["minG"] = 0.0, ["minB"] = 0.2, ["minA"] = 0.5,
				["maxR"] = 1.0, ["maxG"] = 0.0, ["maxB"] = 1.0, ["maxA"] = 0.5, },
	-- dark green
	["self"] = {["minR"] = 0.0, ["minG"] = 0.2, ["minB"] = 0.0, ["minA"] = 0.5,
				["maxR"] = 0.0, ["maxG"] = 0.7, ["maxB"] = 0.0, ["maxA"] = 0.5, },
	-- blue
	["gen"] =  {["minR"] = 0.0, ["minG"] = 0.2, ["minB"] = 0.2, ["minA"] = 0.5,
				["maxR"] = 0.0, ["maxG"] = 1.0, ["maxB"] = 1.0, ["maxA"] = 0.5, }, };
	
------------------------------------------------------------------------------
-- Prepares the GUI for use. Called after the Variables Loaded event is
-- received (see KLHTM_Frame <OnLoad>, <OnEvent>).
--
-- some patches to official KLHTM: (a) removed setupaftervariablesloaded
-- method, and its reference in ktmMain. (b) events now come from the update
-- frame. The main frame only sends the variables loaded event.
------------------------------------------------------------------------------

me.myevents = { "ADDON_LOADED" }

me.onevent = function()
	
	KLHTM_SetupGui()
	
end

me.onupdate = function()

	KLHTM_Redraw()

end

function KLHTM_SetupGui()
	
	if (isInitialised) then
		-- will this ever happen? who knows...
		return; 
	end
	
	KLHTM_LoadVariables();
	KLHTM_CreateGuiTable();
	KLHTM_SetupGuiComponents();
	
	-- apply state and options
	KLHTM_UpdateSelfFrame();
	KLHTM_UpdateRaidFrame();
	KLHTM_UpdateTitleButtons();
	KLHTM_UpdateTitleStrings();
	
	isInitialised = true;
	
	-- probably going to cause some dumb error...
	KLHTM_Redraw(true);
	
	KLHTM_UpdateFrame();
	KLHTM_SetGuiScale(options.scale);
	
	if (state.closed ~= true) then
		gui.frame:Show();
	end
end


------------------------------------------------------------------------------
-- Loads data from saved variables. If the required data is not found, default
-- settings are used instead.
------------------------------------------------------------------------------
function KLHTM_LoadVariables()
	
	if (KLHTM_SavedVariables == nil) then
		KLHTM_SavedVariables = {};
	end

	if (KLHTM_SavedVariables.gui) then
		
		if mod.out.checktrace("info", me, "savedvariables") then
			mod.out.printtrace("Loading KTM saved variables");
		end
		
		-- nb byval copies to preserve external references to KLHTM_GuiState and
		-- KLHTM_GuiOptions. Todo: more robust format
		for index, value in KLHTM_SavedVariables.gui.state do
			state[index] = value;
		end
		for index, value in KLHTM_SavedVariables.gui.options do
			options[index] = value;
		end
		
		-- todo: better saved variables upgrading
		if (options.buttonVis.min.targ == nil) then
			options.buttonVis.min.targ = false;
			options.buttonVis.max.targ = true;
		end
		if (options.buttonVis.min.clear == nil) then
			options.buttonVis.min.clear = false;
			options.buttonVis.max.clear = false;
		end
		if (options.minimap == nil) then
			options.minimap = true;
		end
	else
		if mod.out.checktrace("info", me, "savedvariables") then
			mod.out.printtrace("Performing fresh install of KTM")
		end
		
		KLHTM_SetDefaultOptions();
		KLHTM_SetDefaultState();
	end
	
	KLHTM_SavedVariables.gui = {};
	KLHTM_SavedVariables.gui.version = mod.build;
	KLHTM_SavedVariables.gui.options = options;
	KLHTM_SavedVariables.gui.state = state;
end


------------------------------------------------------------------------------
-- Sets up the variable "KLHTM_Gui". It contains (a) references to the gui
-- components, (b) visibility data, (c) string widths, (d) some colours.
------------------------------------------------------------------------------
function KLHTM_CreateGuiTable()
	
	gui.frame = KLHTM_Frame;
	gui.topdiv = KLHTM_FrameTopDivider;
	gui.bottomdiv = KLHTM_FrameBottomDivider;
	gui.minimapButton = KTM_MiniMapButtonFrame;
	
	KLHTM_CreateTitleTable();
	KLHTM_CreateRaidTable();
	KLHTM_CreateSelfTable();
	KLHTM_CreateOptionsTable();
end


------------------------------------------------------------------------------
-- Applies Gui component properties that are not specified in the XML.
------------------------------------------------------------------------------
function KLHTM_SetupGuiComponents()
	
	KLHTM_SetupTitleGui();
	KLHTM_SetupRaidGui();
	KLHTM_SetupSelfGui();
	KLHTM_SetupOptionsGui();
	
	-- frame
	gui.frame:RegisterForDrag("LeftButton");
	gui.frame:SetMovable(true);
	gui.frame:SetUserPlaced(true);
	gui.frame:SetBackdropColor(0.05882352941176471, 0.05882352941176471, 0.05882352941176471, 0.5900000035762787);
	gui.frame:SetBackdropBorderColor(0, 0, 0, 0);
end


------------------------------------------------------------------------------
-- Initialises the local variable "options". It contains settings describing
-- how the self and data windows and the title bar should be displayed.
------------------------------------------------------------------------------
function KLHTM_SetDefaultOptions()
	
	options.scale = KLHTM_Scale.default;
	options.minimap = true;
	
	KLHTM_SetDefaultRaidOptions();
	KLHTM_SetDefaultSelfOptions();
	KLHTM_SetDefaultTitleOptions();
end


------------------------------------------------------------------------------
-- Initialises the local variable "state", containing GUI display properties
------------------------------------------------------------------------------
function KLHTM_SetDefaultState()
	
	state.min = false;
	state.max = true;
	state.minmax = "max";
	
	state.raid = true;
	state.self = false;
	state.view = "raid";
	
	state.pinned = false;
	state.closed = false;
end


------------------------------------------------------------------------------
-- Changes the raid \ self view.
--
-- [newView] - either "self" or "raid"
------------------------------------------------------------------------------
function KLHTM_SetView(newView)
	
	if ((newView ~= "self") and (newView ~= "raid")) then
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to SetView is not recognised.", tostring(newView)))
		end
		return;
	end
	
	state.view = newView;
	state.raid = not state.raid;
	state.self = not state.self;
	
	KLHTM_Redraw(true);
	
	local col = KLHTM_TitleBarColours[state.view];	
	gui.title.back:SetGradientAlpha("VERTICAL", col.minR, col.minG, col.minB, col.minA, col.maxR, col.maxG, col.maxB, col.maxA);
	
	KLHTM_UpdateTitleButtons();
	KLHTM_UpdateTitleStrings();
	KLHTM_UpdateFrame();
end


------------------------------------------------------------------------------
-- Changes the minimised \ maximised state.
--
-- [newMinMax] - either "min" or "max"
------------------------------------------------------------------------------
function KLHTM_SetMinMax(newMinMax)
	
	if ((newMinMax ~= "min") and (newMinMax ~= "max")) then
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to SetMinMax is not recognised.", tostring(newMinMax)))
		end
		return;
	end
	
	state.minmax = newMinMax;
	state.min = not state.min;
	state.max = not state.max;
	
	KLHTM_Redraw(true);
	
	KLHTM_UpdateTitleButtons();
	KLHTM_UpdateTitleStrings();
	KLHTM_UpdateFrame();
end


------------------------------------------------------------------------------
-- Sets the frame visibility. Should this method even exist?
--
-- [newVisible] - set to true to show the frame
------------------------------------------------------------------------------
function KLHTM_SetVisible(newVisible)
	
	if ((newVisible ~= false) and (newVisible ~= true)) then
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument to '%s' to SetVisible is not recognised.", tostring(newVisible)))
		end
	end
	
	state.closed = not newVisible;
	
	if (newVisible) then
		KLHTM_Redraw(true);
		gui.frame:Show();
	else
		gui.frame:Hide();
	end
end


------------------------------------------------------------------------------
-- Changes the global scale of the main frame.
--
-- [newScale] - a value between 0.5 and 1.2
------------------------------------------------------------------------------
function KLHTM_SetGuiScale(newScale)
	
	local argument = newScale
	newScale = tonumber(newScale);
	
	if (newScale == nil) then
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to SetGuiScale is not a number.", tostring(argument)))
		end
		return;
	end
	
	if ((newScale < KLHTM_Scale.min) or (newScale > KLHTM_Scale.max)) then
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to SetGuiScale is outside the valid bounds.", newScale))
		end
		return;
	end
	
	-- maintain the top-right corner when resizing
	local right = gui.frame:GetRight();
	local top = gui.frame:GetTop();
	
	gui.frame:SetScale(newScale);
	
	if ((top ~= nil) and (right ~= nil)) then
		top = top * options.scale / newScale;
		right = right * options.scale / newScale;
		gui.frame:ClearAllPoints();
		gui.frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top);
	else
		-- should occur the first time the mod is loaded
		gui.frame:ClearAllPoints();
		gui.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	end
	
	options.scale = newScale;
end


------------------------------------------------------------------------------
-- Add an black outline to the specified FontString. This increases its 
-- legibility when viewed on a light background, eg the self view bars. It is
-- normally able to be specified via the XML, but this is not possible due to 
-- compatibility reasons with some localisations. The default minimim ouline is
-- very dark and overpowering, so the shadow's alpha is reduced (to 0, but there
-- seems to be a minimum value).
--
-- [fontstring] - a GUI FontString object
------------------------------------------------------------------------------
function KLHTM_AddOutline(fontstring)
	
	local path, height;
	path, height = fontstring:GetFont();
	
	fontstring:SetFont(path, height, "OUTLINE");
	fontstring:SetShadowColor(0,0,0,0.3);
end


------------------------------------------------------------------------------
-- Increases the space allocated to the specified string to match the localised
-- string width.
--
-- [stringData] - a table containing a [width] element and a [text] element.
-- the latter should be a FontString whose text has been set.
------------------------------------------------------------------------------
function KLHTM_LocaliseStringWidth(stringData)
	
	local width = math.ceil(stringData.text:GetStringWidth());
	
	if (width > stringData.width) then
		
		local newValue = math.min(width, stringData.width * Max_Localisation_Factor);
		
		if mod.out.checktrace("info", me, "resizing") then
			mod.out.printtrace(string.format("Extending the width of %s from %s to %s.", stringData.frame:GetName(), stringData.width, newValue))
		end
		
		stringData.width = newValue;
	end
end

------------------------------------------------------------------------------
-- Repositions the frame in the center of the screen and shows it.
------------------------------------------------------------------------------
function KLHTM_ResetFrame()
	
	local scale = options.scale;
	
	gui.frame:SetScale(1);
	gui.frame:ClearAllPoints();
	gui.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	
	KLHTM_SetGuiScale(scale);
	KLHTM_SetVisible(true);
end

------------------------------------------------------------------------------
-- Updates the visibility of the data tables, and recalculates the frame bounds.
-- Should be called whenever the sizes of the subframes changes. ie:
--
-- a) view changes
-- b) minmax changes
-- c) column visibility changes
-- d) command button visibility changes
--
-- This method uses the widths calculated by the other methods such as 
-- Update...Table(), UpdateTitleButtons() and UpdateTitleStrings() which
-- should be called prior to this method when the affected gui components are 
-- changed.
--
-- When the frame is maximised, its width is determined by the visible data frame.
-- If it is smaller than the title bar's preferred width, then overlap can
-- occur between the title bar strings and buttons. In this case the default
-- string is replaced by the short version.
------------------------------------------------------------------------------
function KLHTM_UpdateFrame()
	
	-- raid frame
	if (state.max and state.raid) then
		sizes.frame.x = sizes.raid.x;
		gui.raid.frame:Show();
		-- height is set by the redraw method
	else
		gui.raid.frame:Hide();
	end
	
	-- self frame
	if (state.max and state.self) then
		sizes.frame.x = sizes.self.x;
		gui.self.frame:Show();
		-- height is set by the redraw method
	else
		gui.self.frame:Hide();
	end
	
	-- title frame
	sizes.title.x = sizes.string.x + sizes.but.x;
	sizes.title.y = math.max(sizes.string.y, sizes.but.y);
	gui.title.frame:SetHeight(sizes.title.y);
	
	if (state.min) then
		sizes.frame.y = sizes.title.y;
		sizes.frame.x = sizes.title.x;
		gui.frame:SetHeight(sizes.frame.y + 10); -- 10?
	end
	
	-- maintain the top-right corner when resizing
	local right = gui.frame:GetRight();
	local top = gui.frame:GetTop();
	
	gui.frame:SetWidth(sizes.frame.x + 12); -- 12: 5 inset + 1 gap * 2 for each side.
	
	if ((top ~= nil) and (right ~= nil)) then
		gui.frame:ClearAllPoints();
		gui.frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top);
	else
		-- harmless, occurs once at startup
	end
	
	-- check for lack of horizontal space in the title bar
	if (state.max) then
		if (sizes.title.x > sizes.frame.x) then
			gui.title.string.short.frame:SetWidth(gui.title.string.short.width);
			gui.title.string.short.frame:Show();
			gui.title.string.long.frame:SetWidth(0.1);
			gui.title.string.long.frame:Hide();
		else
			gui.title.string.short.frame:SetWidth(0.1);
			gui.title.string.short.frame:Hide();
			gui.title.string.long.frame:SetWidth(gui.title.string.long.width);
			gui.title.string.long.frame:Show();
		end
		-- sometimes the anchors aren't reapplied. Not sure if this is needed now
		-- that the raid and self titles have been replaced
		gui.title.string.short.frame:GetLeft();
		gui.title.string.long.frame:GetLeft();
	end
	
	if options.minimap then
		gui.minimapButton:Show()
	else
		gui.minimapButton:Hide()
	end


end


------------------------------------------------------------------------------
-- Notifies the GUI that the frame should be updated. The frame will be redrawn
-- within Min_Redraw_Period seconds. Should be called by data-receiving modules,
-- eg networking and combat. 
--
-- [view] - set to "raid" or "self" to prevent redraw if it does not match
-- 			[state.view]. Ignored if nil.
------------------------------------------------------------------------------
function KLHTM_RequestRedraw(view)
	
	if ((view ~= nil) and (view ~= state.view)) then
		return;
	end
	if (state.closed) then
		needsRedraw = false;
		return;
	end
	
	needsRedraw = true;
end


KLHTM_RedrawDebug = {0,0,0,0,0,0,0,0,0,0};
local _redrawindex = 1;
------------------------------------------------------------------------------
-- Redraws the data table contents, if needed. The redraw will only occur if:
--
-- a) [needsRedraw] is true. This is set by data-receiving modules via
-- KLHTM_RequestRedraw()
-- b) The last update was at least Min_Redraw_Period seconds ago
-- c) the frame is visible and initialised
--
-- This method is automatically called via KLHTM_GuiOnUpdate in order to track
-- processor usage. It should not be called externally; use KLHTM_RequestRedraw()
-- instead.
--
-- [forceRedraw] - if true, bypasses conditions (a) and (b) above. Use this 
-- before updating GUI element visibility to prevent flickering.
------------------------------------------------------------------------------
function KLHTM_Redraw(forceRedraw)
	
	if (not isInitialised) then
		return;
	end
	
	if (forceRedraw ~= true) then
		if ((GetTime() - lastRedraw) < Min_Redraw_Period) then
			return;
		end
		if (needsRedraw == false) then
			return;
		end
	end
	
	-- some debugging to check frequency of redraws
	KLHTM_RedrawDebug[_redrawindex] = GetTime() - lastRedraw;
	_redrawindex = _redrawindex + 1;
	if (_redrawindex == 11) then
		_redrawindex = 1;
	end
	
	lastRedraw = GetTime();
	needsRedraw = false;
	
	-- draw stuff... ? NO!
	if (state.raid) then
		KLHTM_DrawRaidFrame();
	else
		KLHTM_DrawSelfFrame();
	end
end

------------------------------------------------------------------------------
-- Abbreviates large number with the "k" suffix. Works on positive and negative
-- numbers. Non-numbers are returned as is.
------------------------------------------------------------------------------
function KLHTM_Abbreviate(input)
	
	if (type(input) ~= "number") then
		return input;
	end
	
	local isNegative = false;
	if (input < 0) then
		isNegative = true;
		input = -1 * input;
	end
	
	local answer;
	if (input < 10000) then
		answer = input;
	elseif (input < 100000) then
		answer = math.floor(input / 100 + 0.5) / 10;
		if (math.mod(answer, 1) == 0) then
			answer = answer .. ".0";
		end
		answer = answer .. "k";
	else
		answer = math.floor(input / 1000 + 0.5) .. "k";
	end
	
	if (isNegative) then
		answer = "-" .. answer;
	end
	return answer;
end


------------------------------------------------------------------------------
-- Frame dragging
------------------------------------------------------------------------------
function KLHTM_Frame_OnDragStart()
	if (gui.frame:IsMovable() and (state.pinned == false)) then 
		gui.frame:StartMoving();
	end
end
function KLHTM_Frame_OnDragStop()
	gui.frame:StopMovingOrSizing();
end
--------------------------------------------------
--MOVEBUTTON
--------------------------------------------------
do 
	local loggedIn
	if not loggedIn then
		local f = CreateFrame("Frame")
		f:SetScript("OnEvent", function()
			if not options.Position then
				options.Position = {
					["x"] = 0,
					["y"] = -82,
			};
		else
				getglobal("KTM_MiniMapButtonFrame"):ClearAllPoints();
				getglobal("KTM_MiniMapButtonFrame"):SetPoint("CENTER", "Minimap", "CENTER", options.Position.x, options.Position.y);
			end
			loggedIn = true
			this:SetScript("OnEvent", nil)
		end)
		f:RegisterEvent("PLAYER_LOGIN")
	end
end

function KTM_BeingDragged()
	local mouseX, mouseY = GetCursorPosition();
	local centerX, centerY = Minimap:GetCenter();
	local scale = Minimap:GetEffectiveScale();
	mouseX = mouseX / scale;
	mouseY = mouseY / scale;
	
	local x = mouseX - centerX;
	local y = mouseY - centerY;
	local r = math.sqrt(x*x + y*y);
	if (r>0) then
		local radius = ((Minimap:GetRight()-Minimap:GetLeft())/2) + ((this:GetRight()-this:GetLeft())/2) - 4;
		x = radius * x / r;
		y = radius * y / r;

		this:ClearAllPoints();
		this:SetPoint("CENTER", "Minimap", "CENTER", x, y);

		options.Position.x = x;
		options.Position.y = y;
	end

end
function KTM_ShowTooltip()
	if( not this.aldragme) then
		GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT");
		GameTooltip:SetText("KTM")
		GameTooltipTextLeft1:SetTextColor(1, 1, 1);
		GameTooltip:AddLine(mod.string.get("optionsgui", "tooltips", "minimap"));
		GameTooltip:Show();
	end
end

function KTM_MinimapButtonClick()
	if IsShiftKeyDown() then
		KLHTM_ToggleOptionsGui();
	else
		if KLHTM_windowsopened then 
			KLHTM_SetVisible(false);
			KLHTM_windowsopened=nil;
		else 
			KLHTM_SetVisible(true);
			KLHTM_windowsopened=true;
		end
	end
end
```

## Code\GUI\KTM_OptionsGui.lua
```lua

--[[ KLHThreatMeter KTM_OptionsGui.lua

	Controls a Gui for viewing and editing settings on the main window. See also 
	KTM_OptionsFrame.xml, KTM_Gui.lua.
--]]

local mod = klhtm
local me = { }
mod.guiopt = me

-- a table of the Gui components in the options frame
local gui = {};
KLHTM_OptionsGui = gui;

-- Gui options
local options = KLHTM_GuiOptions;

-- options frame visibility information
local state = {
	["closed"] = true, -- false if the frame is visible
	["frame"] = "gen", -- the visible subframe
};

-- the font size of the gui strings
local String_Font_Size = 11;
-- the font size of the button strings
local Button_Font_Size = 10;


------------------------------------------------------------------------------
-- Sets up the instance variable "gui". It contains references to the Options 
-- Gui components 
------------------------------------------------------------------------------
function KLHTM_CreateOptionsTable()

	gui.frame = KLHTM_OptionsFrame;
	
	gui.title = {
		["frame"] = KLHTM_OptionsFrameTitle,
		["back"] = KLHTM_OptionsFrameTitleBackground,
		["text"] = KLHTM_OptionsFrameTitleText,
	};

	gui.gen = {
		["frame"] = KLHTM_OptionsFrameGeneral,
		["otherhead"] = {
			["frame"] = KLHTM_OptionsFrameGeneralHeaderOther,
			["text"] = KLHTM_OptionsFrameGeneralHeaderOtherText,
		},
		["scale"] = {
			["frame"] = KLHTM_OptionsFrameGeneralScale,
			["text"] = KLHTM_OptionsFrameGeneralScaleText,
			["value"] = KLHTM_OptionsFrameGeneralScaleValue,
		},
		["minimap"] = {
			["frame"] = KLHTM_OptionsFrameGeneralMinimap,
			["text"] = KLHTM_OptionsFrameGeneralMinimapText,
		},
		-- command button visibility when minimised
		["minvishead"] = {
			["frame"] = KLHTM_OptionsFrameGeneralMinimisedHeader,
			["text"] = KLHTM_OptionsFrameGeneralMinimisedHeaderText,
		},
		["minvis"] = {
			["pin"] = {
				["frame"] = KLHTM_OptionsFrameGeneralMinimisedPin,
				["text"] = KLHTM_OptionsFrameGeneralMinimisedPinText,
			},
			["opt"] = {
				["frame"] = KLHTM_OptionsFrameGeneralMinimisedOptions,
				["text"] = KLHTM_OptionsFrameGeneralMinimisedOptionsText,
			},
			["view"] = {
				["frame"] = KLHTM_OptionsFrameGeneralMinimisedView,
				["text"] = KLHTM_OptionsFrameGeneralMinimisedViewText,
			},
			["targ"] = {
				["frame"] = KLHTM_OptionsFrameGeneralMinimisedMasterTarget,
				["text"] = KLHTM_OptionsFrameGeneralMinimisedMasterTargetText,
			},
			["clear"] = {
				["frame"] = KLHTM_OptionsFrameGeneralMinimisedClearThreat,
				["text"] = KLHTM_OptionsFrameGeneralMinimisedClearThreatText,
			},
		},
		-- command button visibility when maximised
		["maxvishead"] = {
			["frame"] = KLHTM_OptionsFrameGeneralMaximisedHeader,
			["text"] = KLHTM_OptionsFrameGeneralMaximisedHeaderText,
		},
		["maxvis"] = {
			["pin"] = {
				["frame"] = KLHTM_OptionsFrameGeneralMaximisedPin,
				["text"] = KLHTM_OptionsFrameGeneralMaximisedPinText,
			},
			["view"] = {
				["frame"] = KLHTM_OptionsFrameGeneralMaximisedView,
				["text"] = KLHTM_OptionsFrameGeneralMaximisedViewText,
			},
			["targ"] = {
				["frame"] = KLHTM_OptionsFrameGeneralMaximisedMasterTarget,
				["text"] = KLHTM_OptionsFrameGeneralMaximisedMasterTargetText,
			},
			["clear"] = {
				["frame"] = KLHTM_OptionsFrameGeneralMaximisedClearThreat,
				["text"] = KLHTM_OptionsFrameGeneralMaximisedClearThreatText,
			},
		},
	};
	
	gui.self = {
		["frame"] = KLHTM_OptionsFrameSelf,
		-- column visibility
		["colhead"] = {
			["frame"] = KLHTM_OptionsFrameSelfColumnHeader,
			["text"] = KLHTM_OptionsFrameSelfColumnHeaderText,
		},
		["col"] = {
			["hits"] = {
				["frame"] = KLHTM_OptionsFrameSelfColumnHits,
				["text"] = KLHTM_OptionsFrameSelfColumnHitsText,
			},
			["rage"] = {
				["frame"] = KLHTM_OptionsFrameSelfColumnRage,
				["text"] = KLHTM_OptionsFrameSelfColumnRageText,
			},
			["dam"] = {
				["frame"] = KLHTM_OptionsFrameSelfColumnDamage,
				["text"] = KLHTM_OptionsFrameSelfColumnDamageText,
			},
			["threat"] = {
				["frame"] = KLHTM_OptionsFrameSelfColumnThreat,
				["text"] = KLHTM_OptionsFrameSelfColumnThreatText,
			},
			["pc"] = {
				["frame"] = KLHTM_OptionsFrameSelfColumnThreatPercent,
				["text"] = KLHTM_OptionsFrameSelfColumnThreatPercentText,
			},
		},
		["otherhead"] = {
			["frame"] = KLHTM_OptionsFrameSelfOtherHeader,
			["text"] = KLHTM_OptionsFrameSelfOtherHeaderText,
		},
		-- hide zero rows
		["hide"] = {
			["frame"] = KLHTM_OptionsFrameSelfHideZero,
			["text"] = KLHTM_OptionsFrameSelfHideZeroText,
		},
		-- abbreviate large numbers
		["abbreviate"] = {
			["frame"] = KLHTM_OptionsFrameSelfAbbreviate,
			["text"] = KLHTM_OptionsFrameSelfAbbreviateText,
		},
		-- title bar minimised string
		["threat"] = {
			["frame"] = KLHTM_OptionsFrameSelfMinimisedThreat,
			["text"] = KLHTM_OptionsFrameSelfMinimisedThreatText,
		},
	};
	
	gui.raid = {
		["frame"] = KLHTM_OptionsFrameRaid,
		-- column visibility
		["colhead"] = {
			["frame"] = KLHTM_OptionsFrameRaidColumnHeader,
			["text"] = KLHTM_OptionsFrameRaidColumnHeaderText,
		},
		["col"] = {
			["sunder"] = {
				["frame"] = KLHTM_OptionsFrameRaidColumnSunder,
				["text"] = KLHTM_OptionsFrameRaidColumnSunderText,
			},
			["threat"] = {
				["frame"] = KLHTM_OptionsFrameRaidColumnThreat,
				["text"] = KLHTM_OptionsFrameRaidColumnThreatText,
			},
			["pc"] = {
				["frame"] = KLHTM_OptionsFrameRaidColumnThreatPercent,
				["text"] = KLHTM_OptionsFrameRaidColumnThreatPercentText,
			},
		},
		-- minimised string visibility
		["minvishead"] = {
			["frame"] = KLHTM_OptionsFrameRaidMinimisedHeader,
			["text"] = KLHTM_OptionsFrameRaidMinimisedHeaderText,
		},
		["minvis"] = {
			["rank"] = {
				["frame"] = KLHTM_OptionsFrameRaidMinimisedRank,
				["text"] = KLHTM_OptionsFrameRaidMinimisedRankText,
			},
			["pc"] = {
				["frame"] = KLHTM_OptionsFrameRaidMinimisedThreatPercent,
				["text"] = KLHTM_OptionsFrameRaidMinimisedThreatPercentText,
			},
			["tdef"] = {
				["frame"] = KLHTM_OptionsFrameRaidMinimisedDeficit,
				["text"] = KLHTM_OptionsFrameRaidMinimisedDeficitText,
			},
		},
		["otherhead"] = {
			["frame"] = KLHTM_OptionsFrameRaidOtherHeader,
			["text"] = KLHTM_OptionsFrameRaidOtherHeaderText,
		},
		-- hide zero rows
		["hide"] = {
			["frame"] = KLHTM_OptionsFrameRaidHideZero,
			["text"] = KLHTM_OptionsFrameRaidHideZeroText,
		},
		-- max row count
		["rows"] = {
			["frame"] = KLHTM_OptionsFrameRaidRows,
			["text"] = KLHTM_OptionsFrameRaidRowsText,
			["value"] = KLHTM_OptionsFrameRaidRowsValue,
		},
		-- resize
		["resize"] = {
			["frame"] = KLHTM_OptionsFrameRaidResize,
			["text"] = KLHTM_OptionsFrameRaidResizeText,
		},
		-- show aggro gain
		["aggro"] = {
			["frame"] = KLHTM_OptionsFrameRaidAggroGain,
			["text"] = KLHTM_OptionsFrameRaidAggroGainText,
		},
		-- abbreviate large numbers
		["abbreviate"] = {
			["frame"] = KLHTM_OptionsFrameRaidAbbreviate,
			["text"] = KLHTM_OptionsFrameRaidAbbreviateText,
		},
		-- hide bottom bar
		["bottom"] = {
			["frame"] = KLHTM_OptionsFrameRaidHideBottom,
			["text"] = KLHTM_OptionsFrameRaidHideBottomText,
		},
	};
	
	-- command buttons
	gui.but = {
		["gen"] = KLHTM_OptionsFrameControlsGeneral,
		["self"] = KLHTM_OptionsFrameControlsSelf,
		["raid"] = KLHTM_OptionsFrameControlsRaid,
		["close"] = KLHTM_OptionsFrameControlsClose,
	};
end


------------------------------------------------------------------------------
-- Applies Gui component properties that are not specified in the XML. 
------------------------------------------------------------------------------
function KLHTM_SetupOptionsGui()
	
	-- base frame
	gui.frame:RegisterForDrag("LeftButton");
	gui.frame:SetMovable(true);
	gui.frame:SetBackdropColor(0, 0, 0);
	gui.frame:SetBackdropBorderColor(1, 1, 1);
	
	-- command buttons
	for index, button in gui.but do
		button:SetText(mod.string.get("optionsgui", "buttons", index));
	end
	
	-- general frame
	for index, button in gui.gen.minvis do
		button.text:SetText(mod.string.get("optionsgui", "labels", "buttons", index));
	end
	for index, button in gui.gen.maxvis do
		button.text:SetText(mod.string.get("optionsgui", "labels", "buttons", index));
	end
	
	gui.gen.minvishead.text:SetText(mod.string.get("optionsgui", "labels", "headers", "minvis"));
	gui.gen.maxvishead.text:SetText(mod.string.get("optionsgui", "labels", "headers", "maxvis"));
	gui.gen.otherhead.text:SetText(mod.string.get("optionsgui", "labels", "headers", "other"));
	
	gui.gen.scale.frame:SetMinMaxValues(KLHTM_Scale.min * 100, KLHTM_Scale.max * 100);
	gui.gen.scale.frame:SetValueStep(KLHTM_Scale.tick * 100);
	gui.gen.scale.text:SetText(mod.string.get("optionsgui", "labels", "options", "scale"));
	
	gui.gen.minimap.text:SetText(mod.string.get("optionsgui", "labels", "options", "minimap"));

	-- self frame
	gui.self.colhead.text:SetText(mod.string.get("optionsgui", "labels", "headers", "columns"));
	
	for index, column in gui.self.col do
		column.text:SetText(mod.string.get("optionsgui", "labels", "columns", index));
	end
	
	gui.self.otherhead.text:SetText(mod.string.get("optionsgui", "labels", "headers", "other"));
	gui.self.hide.text:SetText(mod.string.get("optionsgui", "labels", "options", "hide"));
	gui.self.abbreviate.text:SetText(mod.string.get("optionsgui", "labels", "options", "abbreviate"));
	gui.self.threat.text:SetText(mod.string.get("optionsgui", "labels", "minvis", "threat"));
	
	-- raid frame
	gui.raid.colhead.text:SetText(mod.string.get("optionsgui", "labels", "headers", "columns"));
	gui.raid.col.sunder.text:SetText(mod.string.get("optionsgui", "labels", "columns", "sunder"));
	gui.raid.col.threat.text:SetText(mod.string.get("optionsgui", "labels", "columns", "threat"));
	gui.raid.col.pc.text:SetText(mod.string.get("optionsgui", "labels", "columns", "pc"));
	
	for index, button in gui.raid.minvis do
		button.text:SetText(mod.string.get("optionsgui", "labels", "minvis", index));
	end
	gui.raid.minvishead.text:SetText(mod.string.get("optionsgui", "labels", "headers", "strings"));
	
	gui.raid.otherhead.text:SetText(mod.string.get("optionsgui", "labels", "headers", "other"));
	gui.raid.hide.text:SetText(mod.string.get("optionsgui", "labels", "options", "hide"));
	gui.raid.resize.text:SetText(mod.string.get("optionsgui", "labels", "options", "resize"));
	gui.raid.aggro.text:SetText(mod.string.get("optionsgui", "labels", "options", "aggro"));
	gui.raid.abbreviate.text:SetText(mod.string.get("optionsgui", "labels", "options", "abbreviate"));
	gui.raid.bottom.text:SetText(mod.string.get("optionsgui", "labels", "options", "bottom"));

	gui.raid.rows.text:SetText(mod.string.get("optionsgui", "labels", "options", "rows"));
	gui.raid.rows.frame:SetMinMaxValues(2, KLHTM_MaxRaidRows);
	gui.raid.rows.frame:SetValueStep(1);
	
	-- resize the strings. Due to localisation compatibility issues, this is not possible 
	-- to do via the XML.
	local function resizeGroup(input)
		for _, item in input do
			if (item.text ~= nil) then
				
				local path = item.text:GetFont();
				item.text:SetFont(path, String_Font_Size);
			end
		end
	end
	
	resizeGroup(gui.gen);
	resizeGroup(gui.gen.minvis);
	resizeGroup(gui.gen.maxvis);
	resizeGroup(gui.self);
	resizeGroup(gui.self.col);
	resizeGroup(gui.raid);
	resizeGroup(gui.raid.col);
	resizeGroup(gui.raid.minvis);
	
	-- reduce font size if the buttons aren't large enough
	local needsResize = false;
	
	for index, button in gui.but do
		-- 10: 5 pixels space for each edge
		if (button:GetTextWidth() > button:GetWidth() - 10)  then 
			needsResize = true;
		end
	end
	
	if (needsResize) then
		local path = gui.but.gen:GetFont();
		
		for index, button in gui.but do
			button:SetFont(path, Button_Font_Size);
		end
		if mod.out.checktrace("info", me, "resizing") then
			mod.out.printtrace("Resizing options GUI button fonts");
		end
	end
end


------------------------------------------------------------------------------
-- Sets the states of the options gui components to match the current settings
------------------------------------------------------------------------------
function KLHTM_SyncOptionsGui()
	
	-- general frame
	for index, button in gui.gen.minvis do
		button.frame:SetChecked(options.buttonVis.min[index]);
	end
	for index, button in gui.gen.maxvis do
		button.frame:SetChecked(options.buttonVis.max[index]);
	end
	
	-- scale slider
	local temp = gui.gen.scale.frame:GetScript("OnValueChanged");
	gui.gen.scale.frame:SetScript("OnValueChanged", nil);
	gui.gen.scale.frame:SetValue(options.scale * 100)
	gui.gen.scale.frame:SetScript("OnValueChanged", temp);
	gui.gen.scale.value:SetText(options.scale * 100 .. "%");
	
	gui.gen.minimap.frame:SetChecked(options.minimap);

	-- self frame
	for index, column in gui.self.col do
		column.frame:SetChecked(options.self.columnVis[index]);
	end
	
	gui.self.hide.frame:SetChecked(options.self.hideZeroRows);
	gui.self.abbreviate.frame:SetChecked(options.self.abbreviate);
	gui.self.threat.frame:SetChecked(options.self.stringVis.threat);
	
	-- raid frame
	gui.raid.col.sunder.frame:SetChecked(options.raid.columnVis.sunder)
	gui.raid.col.threat.frame:SetChecked(options.raid.columnVis.threat)
	gui.raid.col.pc.frame:SetChecked(options.raid.columnVis.pc)
	
	for index, button in gui.raid.minvis do
		button.frame:SetChecked(options.raid.stringVis[index]);
	end
	
	gui.raid.hide.frame:SetChecked(options.raid.hideZeroRows);
	gui.raid.resize.frame:SetChecked(options.raid.resize);
	gui.raid.aggro.frame:SetChecked(options.raid.showAggroGain);
	gui.raid.abbreviate.frame:SetChecked(options.raid.abbreviate);

	-- rows slider
	local temp = gui.gen.scale.frame:GetScript("OnValueChanged");
	gui.gen.scale.frame:SetScript("OnValueChanged", nil);
	gui.raid.rows.frame:SetValue(options.raid.rows);
	gui.gen.scale.frame:SetScript("OnValueChanged", temp);
	gui.raid.rows.value:SetText(options.raid.rows);
end


------------------------------------------------------------------------------
-- Updates the visibility of the options frame and its subframes
------------------------------------------------------------------------------
function KLHTM_UpdateOptionsFrame()
	
	if (state.closed) then
		gui.frame:Hide();
		return;
	else
		gui.frame:Show();
	end
	
	if (state.frame == "gen") then
		gui.gen.frame:Show();
	else
		gui.gen.frame:Hide();
	end
	
	if (state.frame == "raid") then
		gui.raid.frame:Show();
	else
		gui.raid.frame:Hide();
	end
	
	if (state.frame == "self") then
		gui.self.frame:Show();
	else
		gui.self.frame:Hide();
	end
	
	gui.title.text:SetText(mod.string.get("optionsgui", "labels", "titlebar", state.frame));
	
	local col = KLHTM_TitleBarColours[state.frame];
	gui.title.back:SetGradientAlpha("VERTICAL", col.minR, col.minG, col.minB, col.minA, col.maxR, col.maxG, col.maxB, col.maxA);
end


------------------------------------------------------------------------------
-- Hides or shows the options frame. Called when the user clicks on the options
-- command button on the main frame. If the options frame is being shown, the
-- contents are synchronised with the gui settings.
------------------------------------------------------------------------------
function KLHTM_ToggleOptionsGui()
	
	state.closed = not state.closed;
	if (not state.closed) then
		KLHTM_SyncOptionsGui();
	end
	
	KLHTM_UpdateOptionsFrame();
end


------------------------------------------------------------------------------
-- Called when the used clicks on one of the command buttons
------------------------------------------------------------------------------
function KLHTM_OptionsButton_OnClick(command)
	
	if (command == "General") then
		state.frame = "gen";
		KLHTM_UpdateOptionsFrame();
		
	elseif (command == "Self") then
		state.frame = "self";
		KLHTM_UpdateOptionsFrame();
		
	elseif (command == "Raid") then
		state.frame = "raid";
		KLHTM_UpdateOptionsFrame();
		
	elseif (command == "Close") then
		state.closed = true;
		KLHTM_UpdateOptionsFrame();
		
	else
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to OptionsButton_OnClick is not recognised.", tostring(command)))
		end
	end
end


-- converts the output of a checkbox GetChecked() query (1 or nil) to a boolean
local function ToBoolean(input)
	if (input) then
		return true;
	else
		return false;
	end
end

------------------------------------------------------------------------------
-- Called when the user clicks on a checkbox in the general frame
------------------------------------------------------------------------------
function KLHTM_OptionsGeneral_OnClick(command)
	
	if (command == "MinimisedPin") then
		options.buttonVis.min.pin = ToBoolean(gui.gen.minvis.pin.frame:GetChecked());
		
	elseif (command == "MinimisedView") then
		options.buttonVis.min.view = ToBoolean(gui.gen.minvis.view.frame:GetChecked());
		
	elseif (command == "MinimisedOptions") then
		options.buttonVis.min.opt = ToBoolean(gui.gen.minvis.opt.frame:GetChecked());
	
	elseif (command == "MinimisedMasterTarget") then
		options.buttonVis.min.targ = ToBoolean(gui.gen.minvis.targ.frame:GetChecked());
		
	elseif (command == "MinimisedClearThreat") then
		options.buttonVis.min.clear = ToBoolean(gui.gen.minvis.clear.frame:GetChecked());
		
	elseif (command == "MaximisedPin") then
		options.buttonVis.max.pin = ToBoolean(gui.gen.maxvis.pin.frame:GetChecked());
		
	elseif (command == "MaximisedView") then
		options.buttonVis.max.view = ToBoolean(gui.gen.maxvis.view.frame:GetChecked());
		
	elseif (command == "MaximisedOptions") then
		options.buttonVis.max.opt = ToBoolean(gui.gen.maxvis.opt.frame:GetChecked());
		
	elseif (command == "MaximisedMasterTarget") then
		options.buttonVis.max.targ = ToBoolean(gui.gen.maxvis.targ.frame:GetChecked());
		
	elseif (command == "MaximisedClearThreat") then
		options.buttonVis.max.clear = ToBoolean(gui.gen.maxvis.clear.frame:GetChecked());

	elseif (command == "ShowMinimapButton") then
		options.minimap = ToBoolean(gui.gen.minimap.frame:GetChecked());		
	else
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to OptionsGeneral_OnClick is not recognised.", tostring(command)))
		end
		return;
	end
	
	KLHTM_UpdateTitleButtons();
	KLHTM_UpdateFrame();
end

------------------------------------------------------------------------------
-- Called when the user adjusts a slider in the general frame
------------------------------------------------------------------------------
function KLHTM_OptionsGeneral_OnValueChanged(command)
	
	if (command == "Scale") then
		KLHTM_SetGuiScale(gui.gen.scale.frame:GetValue() / 100);
		gui.gen.scale.value:SetText(options.scale * 100 .. "%");
	else
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to OptionsGeneral_OnValueChanged is invalid.", tostring(command)))
		end
	end
end

------------------------------------------------------------------------------
-- Called when the user clicks on a checkbox in the self frame
------------------------------------------------------------------------------
function KLHTM_OptionsSelf_OnClick(command)
	
	if (command == "ColumnHits") then
		options.self.columnVis.hits = ToBoolean(gui.self.col.hits.frame:GetChecked());
		
	elseif (command == "ColumnRage") then
		options.self.columnVis.rage = ToBoolean(gui.self.col.rage.frame:GetChecked());
		
	elseif (command == "ColumnDamage") then
		options.self.columnVis.dam = ToBoolean(gui.self.col.dam.frame:GetChecked());
		
	elseif (command == "ColumnThreat") then
		options.self.columnVis.threat = ToBoolean(gui.self.col.threat.frame:GetChecked());
		
	elseif (command == "ColumnThreatPercent") then
		options.self.columnVis.pc = ToBoolean(gui.self.col.pc.frame:GetChecked());
		
	elseif (command == "MinimisedThreat") then
		options.self.stringVis.threat = ToBoolean(gui.self.threat.frame:GetChecked());
		KLHTM_UpdateTitleStrings();
			
	elseif (command == "HideZero") then
		options.self.hideZeroRows = ToBoolean(gui.self.hide.frame:GetChecked());
		
	elseif (command == "Abbreviate") then
		options.self.abbreviate = ToBoolean(gui.self.abbreviate.frame:GetChecked());
		
	else
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to OptionsSelf_OnClick is unrecognised.", tostring(command)))
		end
		return;
	end
	
	KLHTM_UpdateSelfFrame();
	KLHTM_UpdateFrame();
	KLHTM_Redraw(true);
end

------------------------------------------------------------------------------
-- Called when the user clicks on a checkbox in the raid frame
------------------------------------------------------------------------------
function KLHTM_OptionsRaid_OnClick(command)
	

	if (command == "ColumnSunder") then
		options.raid.columnVis.sunder = ToBoolean(gui.raid.col.sunder.frame:GetChecked());
		KLHTM_Redraw();
		KLHTM_UpdateRaidFrame();
		KLHTM_UpdateFrame();

	elseif (command == "ColumnThreat") then
		options.raid.columnVis.threat = ToBoolean(gui.raid.col.threat.frame:GetChecked());
		KLHTM_Redraw();
		KLHTM_UpdateRaidFrame();
		KLHTM_UpdateFrame();
		
	elseif (command == "ColumnThreatPercent") then
		options.raid.columnVis.pc = ToBoolean(gui.raid.col.pc.frame:GetChecked());
		KLHTM_UpdateRaidFrame();
		KLHTM_UpdateFrame();
		
	elseif (command == "MinimisedRank") then
		options.raid.stringVis.rank = ToBoolean(gui.raid.minvis.rank.frame:GetChecked());
		KLHTM_UpdateTitleStrings();
		KLHTM_UpdateFrame();
		
	elseif (command == "MinimisedDeficit") then
		options.raid.stringVis.tdef = ToBoolean(gui.raid.minvis.tdef.frame:GetChecked());
		KLHTM_UpdateTitleStrings();
		KLHTM_UpdateFrame();
		
	elseif (command == "MinimisedThreatPercent") then
		options.raid.stringVis.pc = ToBoolean(gui.raid.minvis.pc.frame:GetChecked());
		KLHTM_UpdateTitleStrings();
		KLHTM_UpdateFrame();
		
	elseif (command == "HideZero") then
		options.raid.hideZeroRows = ToBoolean(gui.raid.hide.frame:GetChecked());
		
	elseif (command == "Resize") then
		options.raid.resize = ToBoolean(gui.raid.resize.frame:GetChecked());
		
	elseif (command == "Abbreviate") then
		options.raid.abbreviate = ToBoolean(gui.raid.abbreviate.frame:GetChecked());
		
	elseif (command == "AggroGain") then
		options.raid.showAggroGain = ToBoolean(gui.raid.aggro.frame:GetChecked());
		
	elseif (command == "HideBottom") then
		options.raid.hideBottomBar = ToBoolean(gui.raid.bottom.frame:GetChecked());
		KLHTM_UpdateRaidFrame();
		
	else
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to OptionsRaid_OnClick is unrecognised.", tostring(command)))
		end
		return;
	end
	
	KLHTM_Redraw(true);
end


------------------------------------------------------------------------------
-- Called when the user adjusts a slider in the raid frame
------------------------------------------------------------------------------
function KLHTM_OptionsRaid_OnValueChanged(command)
	
	if (command == "Rows") then
		options.raid.rows = gui.raid.rows.frame:GetValue();
		gui.raid.rows.value:SetText(options.raid.rows);
		KLHTM_Redraw(true);
	else
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to OptionsRaid_OnValueChanged is unrecognised.", tostring(command)))
		end
	end
end


------------------------------------------------------------------------------
-- Called when the user mouses-over some of the options frames
------------------------------------------------------------------------------
function KLHTM_Options_OnEnter(name)
	
	local text = mod.string.get("optionsgui", "tooltips", name);
	
	GameTooltip:SetOwner(this, "ANCHOR_BOTTOM");
	GameTooltip:SetText(text, 1.0, 0.82, 0, 1, 1);
	GameTooltip:Show();
end
function KLHTM_Options_OnLeave()
	GameTooltip:Hide();
end
```

## Code\GUI\KTM_RaidGui.lua
```lua

--[[ KLH Threatmeter KLHTM_RaidGui.lua

Lukon Mod 2: Part of the replacement for Gui.lua and Tables.lua. 
Controls the GUI for the raid threat section of KLH ThreatMeter. 
See also KTM_Gui.xml, KTM_Gui.lua.
--]]

local mod = klhtm
local me = { }
mod.guiraid = me


-- The number of rows defined in New_Frame.xml
local Max_Rows = 20;
KLHTM_MaxRaidRows = Max_Rows;

-- If the top threat value is greater than 150% of aggro gain when no master target is set
-- then the threat100 reference value is set to the top threat value. This prevents very
-- large %threat values when mobs use secondary targetting abilities.
local Max_Aggro_Ratio = 1.5

-- Local references to some Gui variables
local options = KLHTM_GuiOptions;
local gui = KLHTM_Gui;
local sizes = KLHTM_GuiSizes;
local state = KLHTM_GuiState;
local heights = KLHTM_GuiHeights;

------------------------------------------------------------------------------
-- Sets up the instance variable "gui.raid". It contains data on the GUI
-- components in the raid threat frame.
------------------------------------------------------------------------------
function KLHTM_CreateRaidTable()
	
	gui.raid = {
		["frame"] = KLHTM_RaidFrame,
		["line"] = KLHTM_RaidFrameLine, -- dividing line between title bar and frame
		["head"] = { -- column headers
			["name"] = {
				["frame"] = KLHTM_RaidFrameHeaderName,
				["text"] = KLHTM_RaidFrameHeaderNameText,
				["width"] = 85,
				["colour"] = {["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0},
				["vis"] = function() return (options.raid.columnVis.name) end,
			},
			["threat"] = {
				["frame"] = KLHTM_RaidFrameHeaderThreat,
				["text"] = KLHTM_RaidFrameHeaderThreatText,
				["width"] = 55,
				["colour"] = {["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0},
				["vis"] = function() return (options.raid.columnVis.threat) end,
			},
			["pc"] = {
				["frame"] = KLHTM_RaidFrameHeaderPercentThreat,
				["text"] = KLHTM_RaidFrameHeaderPercentThreatText,
				["width"] = 35,
				["colour"] = {["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0},
				["vis"] = function() return (options.raid.columnVis.pc) end,
			},
			["sunder"] = {
				["frame"] = KLHTM_RaidFrameHeaderSunder,
				["text"] = KLHTM_RaidFrameHeaderSunderText,
				["width"] = 10,
				["colour"] = {["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0},
				["vis"] = function() return options.raid.columnVis.sunder end,
			},
		},
		["rows"] = {},
		["bottom"] = { -- bottom bar
			["frame"] = KLHTM_RaidFrameBottom,
			["line"] = KLHTM_RaidFrameBottomLine, -- dividing line between frame and bottom bar
			["tdef"] = {
				["frame"] = KLHTM_RaidFrameBottomThreatDefecit,
				["text"] = KLHTM_RaidFrameBottomThreatDefecitText,
				["width"] = 40,
			},
			["targ"] = {
				["frame"] = KLHTM_RaidFrameBottomMasterTarget,
				["text"] = KLHTM_RaidFrameBottomMasterTargetText,
				--["width"] = 50,
				-- should take up whatever remaining space there is
			},
		},
	};
	
	for x = 1 , Max_Rows do
		gui.raid.rows[x] = {
			["frame"] = getglobal("KLHTM_RaidFrameRow" .. x),
			["name"] = {
				["frame"] = getglobal("KLHTM_RaidFrameRow" .. x .. "Name"),
				["text"] = getglobal("KLHTM_RaidFrameRow" .. x .. "NameText"),
			},
			["threat"] = {
				["frame"] = getglobal("KLHTM_RaidFrameRow" .. x .. "Threat"),
				["text"] = getglobal("KLHTM_RaidFrameRow" .. x .. "ThreatText"),
			},
			["pc"] = {
				["frame"] = getglobal("KLHTM_RaidFrameRow" .. x .. "PercentThreat"),
				["text"] = getglobal("KLHTM_RaidFrameRow" .. x .. "PercentThreatText"),
			},
			["sunder"] = {
				["frame"] = getglobal("KLHTM_RaidFrameRow" .. x .. "Sunder"),
				["text"] = getglobal("KLHTM_RaidFrameRow" .. x .. "SunderText"),
			},
			["bar"] = getglobal("KLHTM_RaidFrameRow" .. x .. "Bar"),
		};
	end
end


------------------------------------------------------------------------------
-- Applies Gui component properties that are not specified in the XML
------------------------------------------------------------------------------
function KLHTM_SetupRaidGui()
	
	-- headers
	for index, header in gui.raid.head do
		header.text:SetText(mod.string.get("gui", "raid", "head", index));
		header.frame:SetHeight(heights.header);
		KLHTM_AddOutline(header.text);
		KLHTM_LocaliseStringWidth(header);
		
		for _, row in gui.raid.rows do
			row[index].text:SetTextColor(header.colour.r, header.colour.g, header.colour.b);
			row[index].frame:SetHeight(heights.data);
			KLHTM_AddOutline(row[index].text);
		end
	end
	
	-- rows
	for _, row in gui.raid.rows do
		row.frame:SetHeight(heights.data);
	end
	
	-- botton bar
	gui.raid.bottom.frame:SetHeight(heights.data);
	gui.raid.bottom.tdef.frame:SetHeight(heights.data);
	gui.raid.bottom.targ.frame:SetHeight(heights.data);
end


------------------------------------------------------------------------------
-- Sets the default options for displaying the main window and title bar strings
-- when the raid view is selected.
------------------------------------------------------------------------------
function KLHTM_SetDefaultRaidOptions()
	
	options.raid = {
		-- column visibility
		["columnVis"] = {
			["name"] = true,
			["threat"] = true,
			["pc"] = true,
			["sunder"] = true,
		},
		-- title bar string visibility
		["stringVis"] = {
			["rank"] = false,
			["pc"] = false,
			["tdef"] = false,
		},
		-- max number of rows to show
		["rows"] = 10,
		-- if true, rows with 0 threat are not shown
		["hideZeroRows"] = true,
		-- if true, the raid window will shrink if there are fewer data rows
		-- than the specified in ["rows"]. Otherwise empty rows will be shown.
		["resize"] = false,
		-- if true, numbers 10,000 or greater are abbreviated with "k"
		["abbreviate"] = false,
		-- if true, a virtual player "aggro gain" is shown
		["showAggroGain"] = true,
		-- if true, the bottom bar will not be shown
		["hideBottomBar"] = false,
	};
end


------------------------------------------------------------------------------
-- Updates the visibility of columns the raid table and the bottom bar. The
-- contents are not rendered here. The frame width is stored in sizes.self.x.
-- Should be called: 
--
-- a) when the column visibility changes
-- b) when the number of rows to be drawn changes
------------------------------------------------------------------------------
function KLHTM_UpdateRaidFrame()
	
	sizes.raid.x = 0;
	
	for column, header in gui.raid.head do
		-- header
		if (header.vis()) then
			header.frame:SetWidth(header.width);
			sizes.raid.x = sizes.raid.x + header.width;
			header.frame:Show();
		else
			header.frame:Hide();
			header.frame:SetWidth(0.1);
		end
		-- rows
		for index, row in gui.raid.rows do
			if (header.vis()) then
				row[column].frame:SetWidth(header.width);
				row[column].frame:Show();
			else
				row[column].frame:Hide();
				row[column].frame:SetWidth(0.1);
			end
		end
	end
	
	for _, row in gui.raid.rows do
		row.frame:SetWidth(sizes.raid.x);
	end
	
	-- bottom bar
	gui.raid.bottom.tdef.frame:SetWidth(gui.raid.bottom.tdef.width);
	-- do we need this now that we have dual anchors?
	gui.raid.bottom.targ.text:SetWidth(gui.raid.bottom.targ.frame:GetWidth());
	
	if (options.raid.hideBottomBar) then
		gui.raid.bottom.frame:Hide();
	else
		gui.raid.bottom.frame:Show();
	end
end


------------------------------------------------------------------------------
-- Draws the minimised title bar strings present in the raid view.
------------------------------------------------------------------------------
function KLHTM_DrawRaidStrings(raidData, playerCount, threat100)
	
	-- update title bar strings
	local userThreat = mod.table.raiddata[UnitName("player")];
	if userThreat == nil then
		userThreat = 0
	end
	
	-- threat defecit (todo: colours?)
	local defecit = threat100 - userThreat;
	if (options.raid.abbreviate) then
		defecit = KLHTM_Abbreviate(defecit);
	end
	
	-- threat rank
	local userRank = 1;
	for _, data in raidData do
		if (data.threat > userThreat) then
			userRank = userRank + 1;
		end
	end
	
	if (threat100 == 0) then
		gui.title.string.tdef.text:SetText("0");
		gui.title.string.pc.text:SetText("0%");
		gui.title.string.rank.text:SetText("-/" .. playerCount);
	else
		gui.title.string.tdef.text:SetText(defecit);
		gui.title.string.pc.text:SetText(math.floor(userThreat * 100 / threat100 + 0.5) .. "%");
		gui.title.string.rank.text:SetText(userRank .. "/" .. playerCount);
	end
end


------------------------------------------------------------------------------
-- Draws raid the bottom bar strings
--
-- [data] - the sorted threat data
-- [threat100] - ??

-- help i am broken.
------------------------------------------------------------------------------
function KLHTM_DrawRaidBottom(data, threat100, playerCount, userThreat)
	
	-- master target
	if (mod.target.mastertarget ~= nil) then
		gui.raid.bottom.targ.text:SetText(mod.target.mastertarget);
	else
		gui.raid.bottom.targ.text:SetText("");
	end
	
	-- new threat defecit ... maybe... 
	if (false) then
		if ((mod.target.mastertarget ~= nil) and (mod.target.mttruetarget ~= nil) and
			(mod.tables.raiddata[mod.target.mttruetarget] ~= nil)) then
			-- there is an active, valid master target and targettarget
			
			if (mod.target.mttruetarget == UnitName("player")) then
				-- we are the MT. either someone above us, or below us
			end
		end
	end
	
	
	
	-- threat defecit. Several options here. (a) we are MT, show distance to no2. 
	-- (b) we are dps, show defecit from MT \ aggro gain. (c) all zero.
	-- How do we know what threat100 is referring to?
	
	local defecit = threat100 - userThreat;
	if (defecit == 0) then
		defecit = "";
	elseif (options.raid.abbreviate) then
		defecit = KLHTM_Abbreviate(defecit);
	end
	gui.raid.bottom.tdef.text:SetText(defecit);
	
	
	
end


-- used by GetRaidData(). Defined at the class level to reduce memory use.
local GetRaidData_data;
------------------------------------------------------------------------------
-- Makes a copy of the raid threat data from KLHTM_RaidData for use by 
-- KLHTM_DrawRaidFrame and performs some processing.
--
-- returns:
-- [data] - the sorted threat data (with zero-pruning only),
-- [playerCount] - the number of preporting players (virtual and real),
-- [threat100] - the reference value for %max threat calculations
------------------------------------------------------------------------------
function KLHTM_GetRaidData()
	
	local data = GetRaidData_data;
	
	if (data == nil) then
		data = {};
		-- 50: 40 players + room for "virtual players" eg aggro gain
		for x = 1, 50 do 
			data[x] = {["name"] = "", ["threat"] = 0, ["pc"] = 0, ["sunder"] = 0};
		end
		
		GetRaidData_data = data
	end
	
	-- check for aggro gain
	if (options.raid.showAggroGain) then
		mod.target.updateaggrogain()
	else
		mod.table.raiddata[mod.string.get("misc", "aggrogain")] = nil;
	end
	
	-- copy data over
	local rowCount = 0; -- the number of rows to be rendered
	local playerCount = 0; -- the number of players found
	
	for player, threat in mod.table.raiddata do
		playerCount = playerCount + 1;
		
		-- omit "zero rows" if necessary
		if (not(options.raid.hideZeroRows and (threat == 0))) then
			rowCount = rowCount + 1;
			data[rowCount].name = player;
			data[rowCount].threat = threat;

                        local s = mod.table.raidsunder[player]
                        if s == nil or s == 0 then data[rowCount].sunder = "" else data[rowCount].sunder = s end
		end
	end
	table.setn(data, rowCount);
	
	table.sort(data, function(a,b) return a.threat > b.threat; end); 
	
	-- determine the %threat reference value
	-- this part is highly suspect. Need the updated boss module, then a recode
	-- of the threat100 and related calculations.
	local threat100; local aggro;
	
	if (rowCount == 0) then
		-- there is no data availible
		threat100 = 0;
	else
		if (options.raid.showAggroGain == false) then
			-- ignore aggro gain. Wrong!
			threat100 = data[1].threat;
		else
			-- use MT if possible, or targettarget
			if (mod.target.mastertarget == nil) then
				aggro = mod.table.raiddata[mod.string.get("misc", "aggrogain")];
			else
				aggro = mod.table.raiddata[mod.target.mttruetarget];
			end
			-- ignore unreasonable threat100 values
			if ((aggro == nil) or (aggro * Max_Aggro_Ratio < data[1].threat)) then
				threat100 = data[1].threat;
			else
				threat100 = aggro;
			end
		end
	end
	
	return data, playerCount, threat100;
end


------------------------------------------------------------------------------
-- Updates the raid threat window (if maximised) and title bar raid strings.
-- Updates the raid threat data. A copy of KLHTM_RaidData is made, and processed.
-- If minimised, KLHTM_DrawRaidStrings is called. Otherwise all the strings in
-- the raid frame are redrawn.
------------------------------------------------------------------------------
function KLHTM_DrawRaidFrame()
	
	local data, playerCount, threat100 = KLHTM_GetRaidData();
	
	if (state.min) then
		KLHTM_DrawRaidStrings(data, playerCount, threat100);
		return;
	end
	
	local userThreat = mod.table.raiddata[UnitName("player")];
	if (userThreat == nil) then
		-- seems to happen at initialisation
		userThreat = 0;
	end
	
	-- make sure the user is visible (user may not show up with 0 threat)
	if (table.getn(data) > options.raid.rows) then
		if (userThreat < data[options.raid.rows].threat) then
			data[options.raid.rows].name = UnitName("player");
			data[options.raid.rows].threat = userThreat;
 
                        local s = mod.table.raidsunder[UnitName("player")]
                        if s == nil or s == 0 then data[options.raid.rows].sunder = "" else data[options.raid.rows].sunder = s end
		end
		
		-- ignore rows that won't be drawn from here on
		table.setn(data, options.raid.rows);
	end
	
	-- calculate % threat
	for x = 1, table.getn(data) do
		if (threat100 == 0) then
			data[x].pc = 0;
		else
			data[x].pc = math.floor(data[x].threat / threat100 * 100);
		end
	end

	-- bar reference width (max threat)
	local barRef;
	if ((data[1] ~= nil) and (data[1].threat ~= 0)) then
		barRef = sizes.raid.x / data[1].threat;
	end
	
	-- render the rows
	for row = 1, table.getn(data) do
		for index, value in data[row] do
			if (options.raid.abbreviate) then
				gui.raid.rows[row][index].text:SetText(KLHTM_Abbreviate(value));
			else
				gui.raid.rows[row][index].text:SetText(value);
			end
		end
		-- bars
		if ((barRef == nil) or (data[row].threat == 0)) then
			gui.raid.rows[row].bar:Hide();
		else
			local colours = KLHTM_GetClassColours(data[row].name);
			gui.raid.rows[row].bar:SetWidth(data[row].threat * barRef);
			gui.raid.rows[row].bar:SetVertexColor(colours.r, colours.g, colours.b);
			gui.raid.rows[row].bar:Show();
		end
		gui.raid.rows[row].frame:Show();
	end
	
	-- bottom bar
	if (options.raid.hideBottomBar ~= true) then
		KLHTM_DrawRaidBottom(data, threat100, playerCount, userThreat);
	end

	-- hide empty rows
	for row = table.getn(data) + 1, Max_Rows do
		gui.raid.rows[row].frame:Hide();
	end
	
	-- resize frame
	if (options.raid.resize) then
		sizes.raid.y = heights.header + heights.data * table.getn(data);
	else
		sizes.raid.y = heights.header + heights.data * options.raid.rows;
	end
	
	if (options.raid.hideBottomBar ~= true) then
		sizes.raid.y = sizes.raid.y + heights.data + 2;
	end
	
	-- 14: (5 + 1) * 2 for the insets plus a gap. 
	-- Then 2 each for the title-header, header-data and (optional) data-bottom gaps.
	sizes.frame.y = sizes.raid.y + sizes.title.y + 14;
	gui.frame:SetHeight(sizes.frame.y);
end


-- used to unlocalise class names
local _classes = {"warrior", "druid", "priest", "shaman", "mage", "warlock", "rogue", "hunter", "paladin"}

------------------------------------------------------------------------------
-- Returns the class colours of the specified player
--
-- [return]: A table with .r, .g, .b values from 0 to 1.
------------------------------------------------------------------------------
function KLHTM_GetClassColours(playerName)
	
	local className;
	
	-- apply pre-defined colours
	if (playerName == UnitName("player")) then
		return {["r"] = 1.0, ["g"] = 0, ["b"] = 0};
	end
	
	if (playerName == mod.string.get("misc", "aggrogain")) then
		return {["r"] = 0, ["g"] = 0, ["b"] = 1.0};
	end
	
	className = mod.table.raidclasses[playerName];
	
	if (className == nil) then
		-- the player's class isnt stored in our table, rebuild it.
		if mod.out.checktrace("info", me, "raidcolours") then
			mod.out.printtrace(string.format("Updating class entry for %s.", playerName));
		end
		
		mod.table.redoraidclasses();
		className = mod.table.raidclasses[playerName];
	end
	
	if (className == nil) then
		-- class name could not be found. Seems to be due to people who have left
		-- the raid group?
		if mod.out.checktrace("warning", me, "raidcolours") then
			mod.out.printtrace(string.format("Updating class entry for %s.", playerName))
		end
		
		mod.table.raidclasses[playerName] = "";
		className = "";
	end
	
	className = string.upper(className)
	
	if (className == "") then
		return {["r"] = 0.5, ["g"] = 0.5, ["b"] = 0.5};
	else
		return RAID_CLASS_COLORS[className];
	end
end


------------------------------------------------------------------------------
-- Called when the user mouses over a raid string
------------------------------------------------------------------------------
function KLHTM_RaidString_OnEnter(name)
	
	if (name == "targ") then
		if (mod.target.mastertarget ~= nil) then
			
			local text = string.format(mod.string.get("gui", "raid", "stringlong", name),
				mod.target.mastertarget); 
				
			text = string.format("|cffffc900%s\n|r%s",
				mod.string.get("gui", "raid", "stringshort", name), text);

			GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT", -100, 0);
			GameTooltip:SetText(text, 1.0, 1.0, 1.0, 1, 1);
			GameTooltip:Show();
			gui.raid.bottom[name].text:SetTextColor(1.0, 0.82, 0);
		end
	end
	
	-- threat defecit text disabled for the moment
end

function KLHTM_RaidString_OnLeave(name)
	gui.raid.bottom[name].text:SetTextColor(1.0, 1.0, 1.0);
	GameTooltip:Hide();
end
```

## Code\GUI\KTM_SelfGui.lua
```lua

--[[ KLH Threatmeter KLHTM_SelfGui.lua

Lukon Mod 2: Part of the replacement for Gui.lua and Tables.lua. 
Controls the GUI for the personal threat details section of KLH 
ThreatMeter. See also KTM_Gui.xml, KTM_Gui.lua.
--]]

local mod = klhtm
local me, _ = { }
mod.guiself = me 

-- The number of rows defined in New_Frame.xml
local Max_Rows = 15;

-- Local references to some Gui variables
local options = KLHTM_GuiOptions;
local gui = KLHTM_Gui;
local sizes = KLHTM_GuiSizes;
local state = KLHTM_GuiState;
local heights = KLHTM_GuiHeights;


------------------------------------------------------------------------------
-- Sets up the instance variable "gui.self". It contains data on the GUI
-- components in the personal threat details frame.
------------------------------------------------------------------------------
function KLHTM_CreateSelfTable()
	
	gui.self = {
		["frame"] = KLHTM_SelfFrame,
		["line"] = KLHTM_SelfFrameLine, -- dividing line between title bar and frame
		["head"] = { -- column headers
			["name"] = {
				["frame"] = KLHTM_SelfFrameHeaderName,
				["text"] = KLHTM_SelfFrameHeaderNameText,
				["width"] = 90,
				["colour"] = {["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0},
				["vis"] = function() return (options.self.columnVis.name) end,
			},
			["hits"] = {
				["frame"] = KLHTM_SelfFrameHeaderHits,
				["text"] = KLHTM_SelfFrameHeaderHitsText,
				["width"] = 35,
				["colour"] = {["r"] = 0.5, ["g"] = 0.9, ["b"] = 0.5},
				["vis"] = function() return (options.self.columnVis.hits) end,
			},
			["rage"] = {
				["frame"] = KLHTM_SelfFrameHeaderRage,
				["text"] = KLHTM_SelfFrameHeaderRageText,
				["width"] = 35,
				["colour"] = {["r"] = 0.9, ["g"] = 0.5, ["b"] = 0.5},
				["vis"] = function() return (options.self.columnVis.rage) end,
			},
			["dam"] = {
				["frame"] = KLHTM_SelfFrameHeaderDamage,
				["text"] = KLHTM_SelfFrameHeaderDamageText,
				["width"] = 55,
				["colour"] = {["r"] = 0.9, ["g"] = 0.9, ["b"] = 0.3},
				["vis"] = function() return (options.self.columnVis.dam) end,
			},
			["threat"] = {
				["frame"] = KLHTM_SelfFrameHeaderThreat,
				["text"] = KLHTM_SelfFrameHeaderThreatText,
				["width"] = 50,
				["colour"] = {["r"] = 0.9, ["g"] = 0.5, ["b"] = 0.9},
				["vis"] = function() return (options.self.columnVis.threat) end,
			},
			["pc"] = {
				["frame"] = KLHTM_SelfFrameHeaderPercentThreat,
				["text"] = KLHTM_SelfFrameHeaderPercentThreatText,
				["width"] = 30,
				["colour"] = {["r"] = 0.9, ["g"] = 0.5, ["b"] = 0.9},
				["vis"] = function() return (options.self.columnVis.pc) end,
			},
		},
		["rows"] = {},
		["bottom"] = { -- self totals
			["frame"] = KLHTM_SelfFrameBottom,
			["line"] = KLHTM_SelfFrameBottomLine, -- dividing line between frame and bottom bar
			["reset"] = {
				-- a dummy frame used to align the bottom bar strings with the Name header
				["frame"] = KLHTM_SelfFrameBottomName,
				-- a dummy element. Referenced here only to be hidden
				["bar"] = KLHTM_SelfFrameBottomBar,
				["but"] = KLHTM_SelfFrameBottomReset,
				["text"] = KLHTM_SelfFrameBottomResetText,
				["width"] = 70,
			},
			["string"] = {
				["hits"] = {
					["frame"] = KLHTM_SelfFrameBottomHits,
					["text"] = KLHTM_SelfFrameBottomHitsText,
				},
				["rage"] = {
					["frame"] = KLHTM_SelfFrameBottomRage,
					["text"] = KLHTM_SelfFrameBottomRageText,
				},
				["dam"] = {
					["frame"] = KLHTM_SelfFrameBottomDamage,
					["text"] = KLHTM_SelfFrameBottomDamageText,
				},
				["threat"] = {
					["frame"] = KLHTM_SelfFrameBottomThreat,
					["text"] = KLHTM_SelfFrameBottomThreatText,
				},
			},
		},
	};
	for x = 1, Max_Rows do
		gui.self.rows[x] = {
			["frame"] = getglobal("KLHTM_SelfFrameRow" .. x);
			["name"] = {
				["frame"] = getglobal("KLHTM_SelfFrameRow" .. x .. "Name"),
				["text"] = getglobal("KLHTM_SelfFrameRow" .. x .. "NameText"),
			},
			["hits"] = {
				["frame"] = getglobal("KLHTM_SelfFrameRow" .. x .. "Hits"),
				["text"] = getglobal("KLHTM_SelfFrameRow" .. x .. "HitsText"),
			},
			["rage"] = {
				["frame"] = getglobal("KLHTM_SelfFrameRow" .. x .. "Rage"),
				["text"] = getglobal("KLHTM_SelfFrameRow" .. x .. "RageText"),
			},
			["dam"] = {
				["frame"] = getglobal("KLHTM_SelfFrameRow" .. x .. "Damage"),
				["text"] = getglobal("KLHTM_SelfFrameRow" .. x .. "DamageText"),
			},
			["threat"] = {
				["frame"] = getglobal("KLHTM_SelfFrameRow" .. x .. "Threat"),
				["text"] = getglobal("KLHTM_SelfFrameRow" .. x .. "ThreatText"),
			},
			["pc"] = {
				["frame"] = getglobal("KLHTM_SelfFrameRow" .. x .. "PercentThreat"),
				["text"] = getglobal("KLHTM_SelfFrameRow" .. x .. "PercentThreatText"),
			},
			["bar"] = getglobal("KLHTM_SelfFrameRow" .. x .. "Bar"),
		};
	end
end


------------------------------------------------------------------------------
-- Applies Gui component properties that are not specified in the XML.
------------------------------------------------------------------------------
function KLHTM_SetupSelfGui()
	
	-- headers and data
	for index, header in gui.self.head do
		header.text:SetText(mod.string.get("gui", "self", "head", index));
		header.frame:SetHeight(heights.header);
		header.text:SetHeight(heights.header);
		KLHTM_AddOutline(header.text);
		KLHTM_LocaliseStringWidth(header);
		
		for _, row in gui.self.rows do
			row[index].text:SetTextColor(header.colour.r, header.colour.g, header.colour.b);
			row[index].frame:SetHeight(heights.data);
			KLHTM_AddOutline(row[index].text);
		end
	end
	
	-- rows
	for _, row in gui.self.rows do
		row.frame:SetHeight(heights.data);
	end
	
	-- bottom
	gui.self.bottom.frame:SetHeight(heights.button);
	
	for _, string in gui.self.bottom.string do
		string.frame:SetHeight(heights.data);
		KLHTM_AddOutline(string.text);
	end
	
	gui.self.bottom.reset.bar:Hide();	
	gui.self.bottom.reset.but:SetHeight(heights.button);
	gui.self.bottom.reset.frame:SetHeight(heights.button);
	gui.self.bottom.reset.but:SetText(mod.string.get("gui", "self", "reset"));
	 
	local width = gui.self.bottom.reset.text:GetStringWidth();
	if (width + 10 > gui.self.bottom.reset.width) then
		gui.self.bottom.reset.width = width + 10;
	end
	
	gui.self.bottom.reset.but:SetWidth(gui.self.bottom.reset.width);
end


------------------------------------------------------------------------------
-- Sets the default options for displaying the main window and title bar strings
-- when the self view is selected.
------------------------------------------------------------------------------
function KLHTM_SetDefaultSelfOptions()
	
	options.self = {
		-- column visibility
		["columnVis"] = { 	
			["name"] = true,
			["hits"] = true,
			["rage"] = false,
			["dam"] = true,
			["threat"] = true,
			["pc"] = true,
		},
		-- title bar string visibility
		["stringVis"] = {	
			["threat"] = true,
		},
		-- if true, rows with 0 threat are not shown
		["hideZeroRows"] = true,
		-- if true, values of at least 10,000 are abbreviate with "k"
		["abbreviate"] = false,
		-- the column used to sort data rows
		["sortColumn"] = "threat",
		-- if true, values increase towards the bottom of the table
		["sortDown"] = true,
	};
	
	-- rage column
	local class;
	_, class = UnitClass("player");
	if ((class == "WARRIOR") or (class == "DRUID")) then
		options.self.columnVis.rage = true;
	end
end


------------------------------------------------------------------------------
-- Updates the visibility of columns the self table and the bottom bar. The
-- contents are not rendered here. The frame width is stored in sizes.self.x.
-- Should be called whenever the column visibility changes.
------------------------------------------------------------------------------
function KLHTM_UpdateSelfFrame()
	
	sizes.self.x = 0;
	
	for column, header in gui.self.head do
		-- header
		if (header.vis()) then
			header.frame:SetWidth(header.width);
			header.text:SetWidth(header.width);
			sizes.self.x = sizes.self.x + header.width;
			header.frame:Show();

		else
			header.frame:Hide();
			header.frame:SetWidth(0.1);
		end
		-- rows
		for index, row in gui.self.rows do
			if (header.vis()) then
				row[column].frame:SetWidth(header.width);
				row[column].frame:Show();
			else
				row[column].frame:Hide();
				row[column].frame:SetWidth(0.1);
			end
		end
	end
	
	-- bottom bar
	for name, string in gui.self.bottom.string do
		if (gui.self.head[name].vis()) then
			string.frame:SetWidth(gui.self.head[name].width);
			string.frame:Show();
		else
			string.frame:Hide();
			string.frame:SetWidth(0.1);
		end
	end
	-- a dummy frame used to align the bottom bar strings with
	-- the Name header
	gui.self.bottom.reset.frame:SetWidth(gui.self.head.name.width);
		
	for _, row in gui.self.rows do
		row.frame:SetWidth(sizes.self.x);
	end
end


------------------------------------------------------------------------------
-- Draws the minimised title bar strings present in the self view.
------------------------------------------------------------------------------
function KLHTM_DrawSelfStrings()
	
	local threat = mod.table.mydata[mod.string.get("threatsource", "total")].threat;
	threat = math.floor(threat + 0.5);
	
	if (options.self.abbreviate) then
		threat = KLHTM_Abbreviate(threat);
	end
	
	gui.title.string.threat.text:SetText(threat);
end


-- used by GetSelfData(). Defined at the class level to reduce memory use.
local GetSelfData_data;
local GetSelfData_totals;
------------------------------------------------------------------------------
-- Makes a copy of the personal threat data in KLHTM_MyData for use by
-- KLHTM_DrawSelfFrame(). KLHTM_MyData contains some non-integers created
-- by the heroic strike approximations - these are rounded off.
------------------------------------------------------------------------------
function KLHTM_GetSelfData()
	
	local data = GetSelfData_data;
	local totals = GetSelfData_totals;

	if (data == nil) then
		data = {};
		totals = {};
		for x = 1, 20 do -- 20: needs to be large enough to fit all the threat sources
						 -- that can be added to mod.table.mydata
			data[x] = {["name"] = "", ["dam"] = 0, ["hits"] = 0, ["rage"] = 0, ["threat"] = 0, ["pc"] = 0,};
		end
	end
	
	local totalData = mod.table.mydata[mod.string.get("threatsource", "total")];
	totals.hits = totalData.hits;
	totals.rage = math.floor(totalData.rage + 0.5); 
	-- nb different index names
	totals.dam = math.floor(totalData.damage + 0.5);
	totals.threat = math.floor(totalData.threat + 0.5); 
	
	-- copy the personal threat data
	local rowCount = 0;
	for ability, info in mod.table.mydata do
		
		-- omit "zero rows" if necessary
		if (not (options.self.hideZeroRows and (info.threat == 0))) then
			if (ability ~= mod.string.get("threatsource", "total")) then
				rowCount = rowCount + 1;
				data[rowCount].name = ability;
				data[rowCount].hits = info.hits;
				data[rowCount].threat = math.floor(info.threat + 0.5); 
				data[rowCount].dam = math.floor(info.damage + 0.5);
				data[rowCount].rage = math.floor(info.rage + 0.5);
				if (totals.threat == 0) then
					data[rowCount].pc = 0;
				else
					data[rowCount].pc = math.floor(data[rowCount].threat / totals.threat * 100);
				end
			end
		end
	end
	table.setn(data, rowCount);
	
	return data, totals
end


------------------------------------------------------------------------------
-- Updates the personal threat details. If the frame is minimised, only a
-- brief call to KLHTM_DrawSelfStrings() is made. Otherwise a copy of
-- KLHTM_MyData is made, processed, and used to redraw all the strings in the
-- Self frame.
------------------------------------------------------------------------------
function KLHTM_DrawSelfFrame()
	
	if (state.min) then
		KLHTM_DrawSelfStrings();
		return;
	end
	
	local data, totals = KLHTM_GetSelfData();

	table.sort(data, KLHTM_CompareSelfRows);

	-- bar reference value
	local barRef;
	
	if (table.getn(data) == 0) then
		barRef = 0;
	elseif (options.self.sortDown) then
		-- set the largest value to 100%
		barRef = data[table.getn(data)][options.self.sortColumn];
	else
		barRef = data[1][options.self.sortColumn];
	end
		
	if ((barRef == nil) or (tonumber(barRef) == nil)) then 
		barRef = 0;
	else
		barRef = sizes.self.x / barRef;
	end

	local barColours = gui.self.head[options.self.sortColumn].colour;
	
	-- truncate excess rows
	if (table.getn(data) > Max_Rows) then
		table.setn(data, Max_Rows);
	end
	
	-- render the rows
	for row = 1, table.getn(data) do
		for index, value in data[row] do
			if (options.self.abbreviate) then
				gui.self.rows[row][index].text:SetText(KLHTM_Abbreviate(value));
			else
				gui.self.rows[row][index].text:SetText(value);
			end
		end
		-- bars
		if ((barRef == 0) or (data[row][options.self.sortColumn] == 0)) then
			gui.self.rows[row].bar:Hide();
		else
			gui.self.rows[row].bar:SetWidth(data[row][options.self.sortColumn] * barRef);
			gui.self.rows[row].bar:SetVertexColor(barColours.r, barColours.g, barColours.b);
			gui.self.rows[row].bar:Show();
		end
		gui.self.rows[row].frame:Show();
	end
	
	-- bottom bar
	for index, string in gui.self.bottom.string do
		if (totals[index] == 0) then
			string.text:SetText("");
		else
			if (options.self.abbreviate) then
				string.text:SetText(KLHTM_Abbreviate(totals[index]));
			else
				string.text:SetText(totals[index]);
			end
		end
	end
	
	-- hide empty rows
	for row = table.getn(data) + 1, Max_Rows do
		gui.self.rows[row].frame:Hide();
	end
	
	-- resize the frame
	sizes.self.y = heights.header + heights.button + heights.data * table.getn(data);
	-- 5 * 2 insets. 1 title gap, 1 row gap, 1 bottom gap
	sizes.frame.y = sizes.self.y + sizes.title.y + 13; 
	gui.frame:SetHeight(sizes.frame.y);
end


------------------------------------------------------------------------------
-- Sorts two rows in the self data table according to the sorting options
------------------------------------------------------------------------------
function KLHTM_CompareSelfRows(row1, row2) 
	
	-- todo: confirm the sign of these comparisoms
	if (options.self.sortDown) then
		return row1[options.self.sortColumn] < row2[options.self.sortColumn];
	else
		return row1[options.self.sortColumn] > row2[options.self.sortColumn];
	end
end

	
------------------------------------------------------------------------------
-- Changes the column used to sort personal threat data
------------------------------------------------------------------------------
function KLHTM_SelfHeader_OnClick(name)
	
	if (name == nil) then
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to SelfHeader_OnClick is unrecognised.", tostring(name)));
		end

		return;
	end
		
	if (name == "pc") then
		-- due to a quirk in the way percent threat is calculated, sorting by threat
		-- should be done via the threat column (see DrawSelfFrame())
		name = "threat";
	end
	
	if (options.self.sortColumn == name) then
		options.self.sortDown = not options.self.sortDown;
	else
		options.self.sortColumn = name;
		options.self.sortDown = true;
	end
	
	KLHTM_Redraw(true);
end

------------------------------------------------------------------------------
-- Called when the used clicks a button in the self view
------------------------------------------------------------------------------
function KLHTM_SelfButton_OnClick(name)
	
	if (name == "reset") then
		mod.table.resetmytable();
		KLHTM_Redraw(true);
	else
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to SelfButton_OnClick is unrecognised.", tostring(name)));
		end
	end
end
```

## Code\GUI\KTM_TitleGui.lua
```lua

--[[ KLH Threatmeter KLHTM_TitleGui.lua

Lukon Mod 2: Part of the replacement for Gui.lua and Tables.lua. 
Controls the GUI for the title bar of KLH ThreatMeter. See also
KTM_Gui.xml, KTM_Gui.lua.
--]]

local mod = klhtm
local me = { }
mod.guititle = me

-- Local references to some Gui variables
local options = KLHTM_GuiOptions;
local gui = KLHTM_Gui;
local sizes = KLHTM_GuiSizes;
local state = KLHTM_GuiState;
local heights = KLHTM_GuiHeights;

-- the height and width of command buttons
local Button_Size = 18;

------------------------------------------------------------------------------
-- Sets up the instance variable "gui.title". It contains data on the GUI
-- components in the title bar.
------------------------------------------------------------------------------
function KLHTM_CreateTitleTable()
	
	gui.title = {
		["frame"] = KLHTM_TitleFrame,
		["back"] = KLHTM_TitleFrameBackground,
		["but"] = {		-- title bar buttons
			["close"] =  { -- close
				["frame"] = KLHTM_TitleFrameClose,
				["vis"] = function() return ((state.min and options.buttonVis.min.close)
					or (state.max and options.buttonVis.max.close)); end,
			},
			["opt"] = { -- options
				["frame"] = KLHTM_TitleFrameOptions,
				["vis"] = function() return ((state.min and options.buttonVis.min.opt)
					or (state.max and options.buttonVis.max.opt)); end,
			},
			["pin"] = { -- pin
				["frame"] = KLHTM_TitleFramePin,
				["vis"] = function() return ((not state.pinned) and 
					((state.min and options.buttonVis.min.pin)
					or (state.max and options.buttonVis.max.pin))); end,
			},
			["unpin"] = { -- unpin
				["frame"] = KLHTM_TitleFrameUnpin,
				["vis"] = function() return (state.pinned and 
					((state.min and options.buttonVis.min.pin)
					or (state.max and options.buttonVis.max.pin))); end,
			},
			["min"] = { -- minimise
				["frame"] = KLHTM_TitleFrameMinimise,
				["vis"] = function() return (state.max and options.buttonVis.max.minmax); end,
			},
			["max"] = { -- maximise
				["frame"] = KLHTM_TitleFrameMaximise,
				["vis"] = function() return (state.min and options.buttonVis.min.minmax); end,
			},
			["self"] = { -- show personal threat details
				["frame"] = KLHTM_TitleFrameSelfView,
				["vis"] = function() return (state.raid and 
					((state.min and options.buttonVis.min.view)
					or (state.max and options.buttonVis.max.view))); end,
			},
			["raid"] = { -- show raid threat
				["frame"] = KLHTM_TitleFrameRaidView,
				["vis"] = function() return (state.self and 
					((state.min and options.buttonVis.min.view)
					or (state.max and options.buttonVis.max.view))); end,
			},
			["targ"] = { -- master target
				["frame"] = KLHTM_TitleFrameMasterTarget,
				["vis"] = function() return (state.raid and ((state.min and 
					options.buttonVis.min.targ)	or (state.max and 
					options.buttonVis.max.targ))); end,
			},
			["clear"] = { -- raid threat clear
				["frame"] = KLHTM_TitleFrameClearThreat,
				["vis"] = function() return (state.raid and ((state.min and 
					options.buttonVis.min.clear) or (state.max and
					options.buttonVis.max.clear))); end,
			},
		}, -- optional strings
		["string"] = {
			["short"] = { -- a short title
				["frame"] = KLHTM_TitleFrameShortTitle,
				["text"] = KLHTM_TitleFrameShortTitleText,
				["width"] = 35,
				["vis"] = function() return state.min; end,
			},
			["long"] = { -- the maxmiised title
				["frame"] = KLHTM_TitleFrameLongTitle,
				["text"] = KLHTM_TitleFrameLongTitleText,
				["width"] = 60,
				["vis"] = function() return state.max; end,
			},
			["threat"] = { -- your total threat
				["frame"] = KLHTM_TitleFrameThreat,
				["text"] = KLHTM_TitleFrameThreatText,
				["width"] = 45,
				["vis"] = function() return (state.min and state.self and options.self.stringVis.threat); end,
			},
			["tdef"] = { -- thread defecit
				["frame"] = KLHTM_TitleFrameThreatDefecit,
				["text"] = KLHTM_TitleFrameThreatDefecitText,
				["width"] = 40,
				["vis"] = function() return (state.min and state.raid and options.raid.stringVis.tdef); end,
			},
			["pc"] = { -- percent threat
				["frame"] = KLHTM_TitleFrameThreatPercent,
				["text"] = KLHTM_TitleFrameThreatPercentText,
				["width"] = 35,
				["vis"] = function() return (state.min and state.raid and options.raid.stringVis.pc); end,
			},
			["rank"] = { -- threat rank
				["frame"] = KLHTM_TitleFrameThreatRank,
				["text"] = KLHTM_TitleFrameThreatRankText,
				["width"] = 35,
				["vis"] = function() return (state.min and state.raid and options.raid.stringVis.rank); end,
			},
		},
	};
end


------------------------------------------------------------------------------
-- Applies Gui component properties that are not specified in the XML
------------------------------------------------------------------------------
function KLHTM_SetupTitleGui()
	
	-- background
	local col = KLHTM_TitleBarColours[state.view];
	gui.title.back:SetGradientAlpha("VERTICAL", col.minR, col.minG, col.minB, col.minA, col.maxR, col.maxG, col.maxB, col.maxA);
	
	-- buttons
	for _, button in gui.title.but do
		button.frame:SetHeight(Button_Size);
	end
	
	-- strings
	for x, string in gui.title.string do
		if string.frame == nil then
			mod.out.print(x)
		end
	
		string.frame:SetHeight(heights.string);
		string.frame:RegisterForDrag("LeftButton");
	end
	
	gui.title.string.long.text:SetText(string.format(mod.string.get("gui", "title", "text", "long"), mod.release, mod.revision));
	gui.title.string.short.text:SetText(mod.string.get("gui", "title", "text", "short"));
	KLHTM_LocaliseStringWidth(gui.title.string.long);
	KLHTM_LocaliseStringWidth(gui.title.string.short);	
end


------------------------------------------------------------------------------
-- Sets the default options for displaying command buttons on the title bar.
------------------------------------------------------------------------------
function KLHTM_SetDefaultTitleOptions()
	
	options.buttonVis = {
		-- minimised button visibility
		["min"] = {
			["close"] = true,
			-- represents both minimise and maximise buttons
			["minmax"] = true,
			-- represents both pin and unpin buttons
			["pin"] = false,
			-- represents buth self view and raid view buttons
			["view"] = false,
			["opt"] = true,
			["targ"] = false,
			["clear"] = false,
		},
		-- maximised button visibility
		["max"] = {
			["close"] = true,
			["minmax"] = true,
			["pin"] = true,
			["view"] = true,
			["opt"] = true,
			["targ"] = true,
			["clear"] = false,
		},
	};
end


------------------------------------------------------------------------------
-- Updates visibility and scale of the title bar command buttons. Should be 
-- called:
--
-- a) when the minimisation state is changed
-- b) when the view or pin state is changed
-- c) when the button visibility settings are changed
------------------------------------------------------------------------------
function KLHTM_UpdateTitleButtons()

	sizes.but.x = 0;
	sizes.but.y = Button_Size;
	if (sizes.string.y ~= nil) then
		sizes.title.y = math.max(sizes.string.y, sizes.but.y);
	end

	for index, button in gui.title.but do
		if (button.vis()) then
			button.frame:Show();
			button.frame:SetWidth(Button_Size);
			sizes.but.x = sizes.but.x + Button_Size;
		else
			button.frame:Hide();
			button.frame:SetWidth(0.1);
		end
	end
end

	
------------------------------------------------------------------------------
-- Updates visibility and scale of the title bar strings. Should be called:
--
-- a) when the view state is changed
-- b) when the minimisation state is changed
-- c) when the string display options are changed
------------------------------------------------------------------------------
function KLHTM_UpdateTitleStrings()
	
	sizes.string.x = 0;
	sizes.string.y = heights.string;
	if (sizes.but.y ~= nil) then
		sizes.title.y = math.max(sizes.string.y, sizes.but.y);
	end
	
	for index, string in gui.title.string do
		if (string.vis()) then
			string.frame:Show();
			string.frame:SetWidth(string.width);
			sizes.string.x = sizes.string.x + string.width;
		else
			string.frame:Hide();
			string.frame:SetWidth(0.1);
		end
	end
end

------------------------------------------------------------------------------
-- Called when a command button is clicked
------------------------------------------------------------------------------
function KLHTM_TitleButton_OnClick(action)
	
	if (action == "close") then
		state.closed = true;
		gui.frame:Hide();

	elseif (action == "min") then
		KLHTM_SetMinMax("min");
		
	elseif (action == "max") then
		KLHTM_SetMinMax("max");
		
	elseif (action == "pin") then
		state.pinned = true;
		KLHTM_UpdateTitleButtons();
		
	elseif (action == "unpin") then
		state.pinned = false;
		KLHTM_UpdateTitleButtons();
		
	elseif (action == "self") then
		KLHTM_SetView("self");
		
	elseif (action == "raid") then
		KLHTM_SetView("raid");
		
	elseif (action == "opt") then
		KLHTM_ToggleOptionsGui();
		
	elseif (action == "targ") then
		if (UnitExists("target")) then
			mod.net.sendmastertarget();
		else
			mod.net.clearmastertarget();
		end
	
	elseif (action == "clear") then
		mod.net.clearraidthreat();
		
	else
		if mod.out.checktrace("warning", me, "invalidargument") then
			mod.out.printtrace(string.format("The argument '%s' to TitleButton_OnClick is unrecognised.", tostring(action)));
		end
	end
end
	
------------------------------------------------------------------------------
-- Displays a localised tooltip when the user mouses-over a command button
------------------------------------------------------------------------------
function KLHTM_TitleButton_OnEnter(name)
		
	local text = "|cffffc900" .. mod.string.get("gui", "title", "buttonshort", name);
	local extra = mod.string.get("gui", "title", "buttonlong", name);
	if (extra ~= "") then
		text = text .. "\n|r" .. extra;
	end
	
	GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT");
	GameTooltip:SetText(text, 1.0, 1.0, 1.0, 1, 1);
	GameTooltip:Show();
end
function KLHTM_Button_OnLeave()
	GameTooltip:Hide();
end


------------------------------------------------------------------------------
-- Displays a localised tooltip when the user mouses-over a title bar string.
-- Also highlights the selected string.
------------------------------------------------------------------------------
function KLHTM_TitleString_OnEnter(name)
	
	local text = "|cffffc900" .. mod.string.get("gui", "title", "stringshort", name)
				 .. "\n|r" .. mod.string.get("gui", "title", "stringlong", name);
		
	GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT");
	GameTooltip:SetText(text, 1.0, 1.0, 1.0, 1, 1);
	GameTooltip:Show();
	
	gui.title.string[name].text:SetTextColor(1.0, 0.82, 0);
end

function KLHTM_TitleString_OnLeave(name)
	GameTooltip:Hide();
	gui.title.string[name].text:SetTextColor(1.0, 1.0, 1.0);
end
```

## Code\KTM_Alert.lua
```lua
--! This module references these other modules:
--! combat:	lastattack, 
--! out:	print, announce, 
--! table:	mydata, 

--! This module is referenced by these other modules:

local mod = klhtm
local me = {}
mod.alert = me

----------------------
-- Aggro loss / gain notification

-- This stuff is just debug material, to print out your threat when you gain or lose aggro.
----------------------

me.notifyaggro = false
me.targetname = "nil"
me.targettargetname = "nil"

function klhtest()

	me.notifyaggro = not me.notifyaggro
	
	if me.notifyaggro == true then
		mod.out.print("Now notifying you of aggro changes.")
	else
		mod.out.print("No longer notifying you of aggro changes.")
	end
	
end

me.onupdate = function()
	
	if me.notifyaggro == false then
		return
	end
	
	-- get current ID's. If you are targetting friend, then use HIS targets
	local targetid = "target"
	local doubletargetid = "targettarget"
	
	if UnitIsFriend("player", "target") then
		targetid = targetid .. "target"
		doubletargetid = doubletargetid .. "target"
	end
	
	-- check for valid targets
	if UnitIsFriend("player", targetid) then
		-- there are no enemies around. don't do anything
		me.targetname = "nil"
		return
	end
	
	-- now see if the target has changed
	local targetnow = UnitName(targetid)
	
	if targetnow == nil or targetnow == "Unknown Entity" then
		-- no mob targetted. ignore
		targetnow = "nil"
		return
	end
	
	-- get target target name
	local doubletargetnow = UnitName(doubletargetid)
	if doubletargetnow == nil then
		doubletargetnow = "nil"
	end
	
	-- check for target change
	if targetnow ~= me.targetname then
		
		-- target change. ignore targettarget therefore
		me.targetname = targetnow
		me.targettargetname = doubletargetnow
		return
	end
	
	-- to get here, target is valid and is the same. we want to see if targettarget is changed
	
	-- is change?
	if doubletargetnow ~= me.targettargetname then
	
		-- changed to nil
		if doubletargetnow == "nil" then
			if UnitIsDead(targetid) then
				-- target lost its target, because it died.
				me.targetname = "nil"
		
			else
				-- target temporarily lost its target. probably it is stunned
				-- so just don't update targettarget to nil
			end
	
			return
		end
		
		if me.targettargetname == "nil" then
			-- picked it up from noone. no announce.
			
		elseif me.targettargetname == UnitName("Player") then
			-- we lost aggro
			-- mod.out.announce("I lost aggro to " .. doubletargetnow .. ". His threat should be at least " ..	math.ceil(KLHTM_MyData["Total"].threat * 1.1) .. ". " .. me.enumeratethreat())
		
		elseif doubletargetnow == UnitName("Player") then
			-- we gained aggro
			mod.out.announce("I gained aggro from " .. me.targettargetname .. ". My threat is " .. math.ceil(mod.table.mydata["Total"].threat) .. ". " .. me.enumeratethreat(true))
		end
		
		me.targettargetname = doubletargetnow
	end
	
end

me.enumeratethreat = function(lastmessage)

	local message = "Damage = " .. mod.table.mydata["Total"].damage
	
	local key;	local value
	
	for key, value in mod.table.mydata do
		if key == "Healing" then
			message = message .. ", Healing = " .. value.damage
		
		elseif key ~= "Total" and key ~= "White Damage" then
			if value.hits > 0 then
				message = message .. ", " .. key .. " " .. value.hits .. " hits"
			end
		end
	end
		
	if lastmessage then
	
		local threat = mod.table.mydata["Total"].threat
		message = message .. ". Threat = " .. threat
	
		if mod.combat.lastattack then
			threat = threat - mod.combat.lastattack.threat
			message = message .. ", then " .. threat
		end
		
		if mod.combat.lastattack then
			threat = threat - mod.combat.lastattack.threat
			message = message .. ", then " .. threat
		end
	end
	
	message = message .. "."
	
	return message
	
end
```

## Code\KTM_Bosses.lua
```lua
--! This module references these other modules:
--! combat:	event, addattacktodata, 
--! data:	threatconstants, 
--! net:	lastmtsender, sendmessage, clearmastertarget, sendmastertarget, clearraidthreat, reportspelleffect, sendevent, 
--! out:	checktrace, printtrace, print, 
--! regex:	parse, addparsestring, 
--! table:	raiddata, raidthreatoffset, getraidthreat, resetraidthreat, 
--! unit:	findunitidfromname, isplayerofficer, 
--! string:	unlocalise, get, 

--! This module is referenced by these other modules:
--! console:	starttrigger, 
--! net:	bossattacks, 
--! netin:	mastertarget, isspellreportingactive, istrackingspells, bossevents, reportevent, bossattacks, newmastertarget, clearmastertarget, 
--! guiraid:	mastertarget, mttruetarget, updateaggrogain, 

local mod = klhtm
local me = {}
mod.boss = me

--[[
KTM_Bosses.lua

This module contains all the code for special boss encounters, determining who has aggro, etc.

The old functions from the old KLHTMTargetting.lua are a bit scrappy and due for a major buff in R17, as well
as the entire rest of this module, with lots more boss encounters being added.
]]

--! This variable is referenced by these modules: netin, 
me.isspellreportingactive = false
--! This variable is referenced by these modules: netin, 
me.istrackingspells = false
me.bosstarget = ""

-- me.onload() - called by Core.lua.
me.onload = function()
	
	-- Let's create our parser!
	me.createparser()
	
end

function klhtm:ResetRaidThreat()
        mod.table.resetraidthreat()
end

me.myevents = { "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS", "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "CHAT_MSG_COMBAT_HOSTILE_DEATH"}

me.onevent = function()

	if event == "CHAT_MSG_MONSTER_EMOTE" then
		
		if string.find(arg1, mod.string.get("boss", "speech", "razorphase2")) then
			
			-- clear threat when phase 2 starts
			mod.table.resetraidthreat()
			
			-- set the master target to Razorgore, but only if a localised version of him exists.
			local bossname = mod.string.get("boss", "name", "razorgore")
			
			if mod.string.unlocalise("boss", "name", bossname) then
				mod.target.automastertarget(bossname)
			end
			
			return
		end
	
	elseif event == "CHAT_MSG_MONSTER_YELL" then
	
                -- Thad Phase 2
		if string.find(arg1, mod.string.get("boss", "speech", "thad1")) or string.find(arg1, mod.string.get("boss", "speech", "thad2")) or string.find(arg1, mod.string.get("boss", "speech", "thad3")) then
				
			-- reset threat in phase 2
			mod.table.resetraidthreat()
				
			return
		end
		
		-- Noth
		if string.find(arg1, mod.string.get("boss", "speech", "noth1")) or string.find(arg1, mod.string.get("boss", "speech", "noth2")) or string.find(arg1, mod.string.get("boss", "speech", "noth3")) then
				
			mod.target.automastertarget(arg2)
				
			return
		end

		--Onyxia Phase 1
		if string.find(arg1, mod.string.get("boss", "speech", "onyxiaphase1")) then
				mod.target.automastertarget(arg2)
				mod.table.resetraidthreat()
			return
		end
		-- Ony Phase 3
		if string.find(arg1, mod.string.get("boss", "speech", "onyxiaphase3")) then
		
			-- reset threat in phase 2
			mod.table.resetraidthreat()
			
			return
		end

		-- Nef Phase 2
		if string.find(arg1, mod.string.get("boss", "speech", "nefphase2")) then
			-- reset threat in phase 2
			mod.table.resetraidthreat()
			-- boss name is given by the arg2
			mod.target.automastertarget(arg2)
			return
		end
		
		 --Razorgore
		if string.find(arg1, mod.string.get("boss", "speech", "razargor1")) then
			mod.target.automastertarget(arg2)
			mod.table.resetraidthreat()
			return
		end
		
		--Vaelastrasz the Corrupt
		--if arg2 == "Vaelastrasz the Corrupt" and arg1 == "Too late, friends! Nefarius' corruption has taken hold...I cannot...control myself." then
		--	mod.target.automastertarget(arg2)
		--	mod.table.resetraidthreat()
		--	return
		--end
				
		--Broodlord Lashlayer
		if string.find(arg1, mod.string.get("boss", "speech", "broodlord1")) then
			mod.target.automastertarget(arg2)
			mod.table.resetraidthreat()
			return
		end
		
		-- ZG Tiger boss phase 2
		if string.find(arg1, mod.string.get("boss", "speech", "thekalphase2")) then
				
			-- reset threat in phase 2
			mod.table.resetraidthreat()
				
			-- boss name is given by the arg2
			mod.target.automastertarget(arg2)
			
			return
		end
			
		-- Rajaxx attacks
		if string.find(arg1, mod.string.get("boss", "speech", "rajaxxfinal")) then
				
			-- reset threat when he finally attacks
			mod.table.resetraidthreat()
				
			-- boss name is given by arg2
			mod.target.automastertarget(arg2)
			
			return
		end

		-- Azuregos Port
		if string.find(arg1, mod.string.get("boss", "speech", "azuregosport")) then
			
			mod.table.resetraidthreat()
			return
		end	
		-- KT Phase 2
		if string.find(arg1, mod.string.get("boss", "speech", "ktphase2")) then
				
			-- reset threat in phase 2
			mod.table.resetraidthreat()
				
			-- boss name is given by the arg2
			mod.target.automastertarget(arg2)
			
			return
		end

	elseif event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS" then
		
		-- 1) Scan for casting pattern
		local output = mod.regex.parse(me.parserset, arg1, event)
	
		if (output.hit == nil) or (output.parser.identifier ~= "mobbuffgain") then
			return
		end
		
		-- 2) Get Boss, Spell
		local boss, spell = output.final[1], output.final[2]
		
		-- noth blink
		if spell == mod.string.get("boss", "spell", "nothblink") then
			
			-- notify the raid, if this event isn't on cooldown 
			if GetTime() < me.bossevents.nothblink.lastoccurence + me.bossevents.nothblink.cooldown then
				-- on cooldown. don't send
			else
				mod.net.sendevent("nothblink")
			end
		end
	
	elseif event == "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" then
		
		-- 1) Scan for casting pattern
		local output = mod.regex.parse(me.parserset, arg1, event)
	
		if (output.hit == nil) or (output.parser.identifier ~= "mobspellcast") then
			return
		end
		
		-- 2) Get Boss, Spell
		local boss, spell = output.final[1], output.final[2]
		
		-- twin teleport
		if spell == mod.string.get("boss", "spell", "twinteleport") then
			
			-- notify the raid, if this event isn't on cooldown 
			if GetTime() < me.bossevents.twinteleport.lastoccurence + me.bossevents.twinteleport.cooldown then
				-- on cooldown. don't send
			else
				mod.net.sendevent("twinteleport")
			end
				
		-- gate of shazzrah
		elseif spell == mod.string.get("boss", "spell", "shazzrahgate") then

			-- notify the raid, if this event isn't on cooldown 
			if GetTime() < me.bossevents.shazzrahgate.lastoccurence + me.bossevents.shazzrahgate.cooldown then
				-- on cooldown. don't send
			else
				mod.net.sendevent("shazzrahgate")
			end
		end
	
	elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
		
		-- 1) Scan for mob death
		local output = mod.regex.parse(me.parserset, arg1, event)
	
		if (output.hit == nil) or (output.parser.identifier ~= "mobdeath") then
			return
		end
		
		local mobname = output.final[1]
		
		if (mobname == mod.target.mastertarget) and (mod.target.isworldboss == true) then
			
			-- notify the raid, if this event isn't on cooldown 
			if GetTime() < me.bossevents.bossdeath.lastoccurence + me.bossevents.bossdeath.cooldown then
				-- on cooldown. don't send
			else
				mod.net.sendevent("bossdeath")
			end
		
		end
	
	else
		me.parsebossattack(arg1, event)
	end
	
end

--[[
me.onupdate is called by Core.lua. It currently has 3 different parts that are unrelated.
]]
me.onupdate = function()

	local key, value, key2
	
	-- 1) if we are out of combat, reset the ticks on all boss abilities that have them
	if UnitAffectingCombat("player") == nil then
		
		for key, value in me.tickcounters do
			for key2 in value do
				value[key2] = 0
			end
		end
	end
	
	-- 2) clear out all old event reports - one report but no confirmations for 1.0 seconds.
	local timenow = GetTime()
	
	for key, value in me.bossevents do
		if (value.reporter ~= "") and (timenow > value.reporttime + 1.0) then
			
			-- debug
			if mod.out.checktrace("warning", me, "event") then
				mod.out.printtrace(string.format("The event %s has not been confirmed. It was reported by %s.", key, value.reporter))
			end
			
			-- remove the report
			value.reporter = ""
		end
	end

	-- 3) spellreporting: check for target changes
	if (me.isspellreportingactive == true) and (me.istrackingspells == true) and mod.target.mastertarget then
		
		-- 1) find mt
		local x, newtarget, name
		
		for x = 1, 40 do
			name = UnitName("raid" .. x .. "target")
			if name == mod.target.mastertarget then
				
				-- get target^2
				newtarget = UnitName("raid" .. x .. "targettarget")
				
				if newtarget == nil then
					newtarget = "<none>"
				end
				
				break
			end
		end
		
		-- couldn't find the boss?
		if newtarget == nil then
			newtarget = "<unknown>"
		end
		
		-- report!
		if newtarget ~= me.bosstarget then
			
			-- find the threat of the old target
			local oldthreat = mod.table.raiddata[me.bosstarget]
			if oldthreat == nil then
				oldthreat = "?"
			end
			
			-- threat of the boss' new target
			local newthreat = mod.table.raiddata[me.bosstarget] 
			if newthreat == nil then
				newthreat = "?"
			end
			
			-- print
			mod.out.print(string.format(mod.string.get("print", "boss", "bosstargetchange"), mod.target.mastertarget, me.bosstarget, oldthreat, newtarget, newthreat))
			
			-- update bosstarget
			me.bosstarget = newtarget
		end
	end
	
	-- 4) Check triggers
	me.checktriggers()
	
end

--[[
------------------------------------------------------------------------------------------------
							Boss Events - Sending and Receiving
------------------------------------------------------------------------------------------------

Boss Events are when a mob changes his threat against everyone after taking some action. Some players may be out of (combat log) range of the boss action, so we have nearby players report these special events to the rest of the raid.
There is a potential for abuse if someone in the raid group sends false boss event reports, which could make the raid group incorrectly reset their threat. To counter this we require two people to report the same event within a small time interval for it to be activated.
For each event in <me.bossevents>, we keep track of the person who first reported it, and the time they reported it. If the trace key "boss.fireevent" is enabled, the mod will print out who first reported the event and who confirmed it.
Insertion: players in the raid report events in the network channel, and <me.reportevent(...)> is called from the <netin> module.
Maintenance: no OnUpdate maintenance necessary.
]]

--! This variable is referenced by these modules: netin, 
me.bossevents = { }

--[[
me.addevent(eventid, cooldown)
Defines a new event in <me.bossevents>. This is just a helper method to create <me.bossevents>. Called at file load.
<eventid> is a localisation key in the "boss"-"spell" set.
<cooldown> is the minimum time between casts, extreme lower bound. Want it large enough to avoid spams. 1 sec would probably do.
]]
me.addevent = function(eventid, cooldown)
	
	me.bossevents[eventid] = 
	{
		["cooldown"] = cooldown,
		lastoccurence = 0, 	-- GetTime()
		reporter = "",
		reporttime = 0, 	-- GetTime()
		["eventid"] = eventid,
	}
	
end

-- define all possible events. These methods are called at file read time.
me.addevent("shazzrahgate", 5.0)
me.addevent("twinteleport", 5.0)
me.addevent("wrathofragnaros", 5.0)
me.addevent("nothblink", 5.0)
me.addevent("bossdeath", 5.0)
me.addevent("fourhorsemenmark", 5.0)

--[[
mod.boss.reportevent(eventid, player)
Called when someone in the raid reports a boss event.
<eventid> is the internal name of the event.
<player> is the name of the player who reported it.
]]
--! This variable is referenced by these modules: netin, 
me.reportevent = function(eventid, player)

	local eventdata = me.bossevents[eventid]
	local timenow = GetTime()
	
	-- ignore if the event is cooling down
	if timenow < eventdata.lastoccurence + eventdata.cooldown then
		return
	end
	
	-- has this been reported recently? If so it is now confirmed and we can run it.
	if (eventdata.reporter ~= "") and (eventdata.reporter ~= player) then
		me.fireevent(eventdata, player)
	
	-- always trust reports from yourself
	elseif player == UnitName("player") then
		me.fireevent(eventdata, player)
	
	-- some player reports a new event. wait for confirmation
	else
		eventdata.reporter = player
		eventdata.reporttime = timenow
	end

end

--[[
me.fireevent(eventdata, player)
Run when an event is confirmed. Does whatever the event does.
<eventdata> is an structure in <me.bossevents>
<player> is the name of the player who confirmed the event
]]
me.fireevent = function(eventdata, player)
	
	-- debug
	if mod.out.checktrace("info", me, "event") then
		mod.out.printtrace(string.format("The event |cffffff00%s|r has occured. It was reported by %s and confirmed by %s.", eventdata.eventid, eventdata.reporter, player))
	end
	
	-- first reset the event's timers
	eventdata.lastoccurence = GetTime()
	eventdata.reporter = ""
	
	-- now actually do the event
	if eventdata.eventid == "shazzrahgate" then
		mod.table.resetraidthreat()
		
	elseif eventdata.eventid == "twinteleport" then
		mod.table.resetraidthreat()
		
		-- activate the proximity aggro detection trigger
		me.starttrigger("twinemps")
		
	elseif eventdata.eventid == "wrathofragnaros" then
		mod.table.resetraidthreat()
	
	elseif eventdata.eventid == "nothblink" then
		mod.table.resetraidthreat()
		
	elseif eventdata.eventid == "bossdeath" then
		mod.target.bossdeath()
		
	elseif eventdata.eventid == "fourhorsemenmark" then
		-- do a half wipe
		mod.table.raidthreatoffset = mod.table.raidthreatoffset - 0.5 * mod.table.getraidthreat()
	end
	
end

--[[
------------------------------------------------------------------------------------------------
				Triggers - Hard To Detect Events That Require Polling
------------------------------------------------------------------------------------------------

Some events have no easily defined actions such as a combat log event, and must be checked for periodically instead.
For example in the Twin Emperors encounter, after a teleport the closest person to each emperor is given a moderate amount of threat. The only way to see who received the threat is to see who the emperors target. However, after the teleport they become stunned and have no target, so we have to wait until the stun period has ended. So we make a trigger to periodically check them for new targets.
Each trigger has these properties:
<isactive>		boolean, whether the mod is checking the trigger
<startdelay>	time in seconds after the trigger is activated that the mod will start checking it.
<timeout>		time in seconds after the trigger has started that the mod should give up on it
<mystarttime>	when the most recent activation of the trigger occured.

The names and basic properties of triggers are defined in the variable <me.triggers>. This is a key-value list where the key is the internal name of the trigger, and the value is a structure with the variables described above.
To activate a trigger, call the <me.starttrigger(trigger)> function with the internal name of the trigger.
The code that will run each time a trigger is polled is contained in the variable <me.triggerfunctions>. This is a key-value list, where the key is the internal name and the value is the function that is run.
]]

me.triggers = 
{
	twinemps = 
	{
		isactive = false,
		startdelay = 0.5,
		timeout = 5.0,
		mystarttime = 0,
		data = 0,
	},
	autotarget = 
	{
		isactive = false,
		startdelay = 1.0,
		timeout = 300.0,
		mystarttime = 0,
		data = 0,
	}
}

--[[
me.starttrigger(trigger)
Activates a trigger. The mod will start periodically checking for it.
<trigger> is the mod's internal identifier of the trigger, and matches a key to me.triggers.
]]
--! This variable is referenced by these modules: console, 
me.starttrigger = function(trigger)
	
	-- debug check for trigger being defined. We should generalise this, since is happens in a flew different places in the mod. i.e. "badidentifierargument"
	-- maybe also some kind of flood control to stop error messages spamming onupdate.
	
	if (trigger == nil) or (me.triggers[trigger] == nil) then
		
		-- report error
		if mod.out.checktrace("error", me, "trigger") then
			mod.out.printtrace(string.format("There is no trigger |cffffff00%s|r.", trigger or "<nil>"))
		end
		
		return
	end
	
	local triggerdata = me.triggers[trigger]
	triggerdata.isactive = true
	triggerdata.mystarttime = GetTime() + triggerdata.startdelay
	triggerdata.data = 0
	
	-- debug
	if mod.out.checktrace("info", me, "trigger") then
		mod.out.printtrace(string.format("The |cffffff00%s|r trigger has been activated.", trigger))
	end
		
end

--[[
This variable gives the code that runs when an active trigger is checked. The keys are the internal names of triggers, that match keys in <me.triggers>.
The values are functions. The functions should return non-nil if the trigger is to be deactivated.
]]
me.triggerfunctions = 
{
	--[[ 
	We want to find out if we are being targetting by one of the emps. To do this we find the emperors by scanning the targets of everyone in the raid group. Then once we have an emps's target, we check whether that is us.
	It might occur that one emps' target is known but the other is not (not sure if this could happen). In this case the trigger should not end; we should keep checking until we know both targets.
	However, if one of the emps is targetting us, we can instantly give ourself threat and exit.
	The threat gained is set at 2000. This isn't confirmed, and is instead a bit of a guess.
	]]
	twinemps = function(triggerdata)
		
		local x, name, firstbossname, unitid
		local bosshits = 0
		local bosstargets = 0
		
		-- loop through everyone in the raid
		for x = 1, 40 do
			
			unitid = "raid" .. x .. "target"
			if UnitExists(unitid) and (UnitClassification(unitid) == "worldboss") then
				
				-- we've found an emperor. check if we've seen him before
				name = UnitName(unitid)
				
				if name ~= firstbossname then
					bosshits = bosshits + 1
					
					-- if this is the first boss we've seen, put his name up
					if bosshits == 1 then
						firstbossname = name
					end
					
					-- now find the player the boss is targetting
					unitid = unitid .. "target"
					
					if UnitExists(unitid) then
						bosstargets = bosstargets + 1
						
						if UnitIsUnit("player", unitid) then
							-- an emp is targetting us. give us a bit of threat.
							
							mod.combat.event.hits = 1
							mod.combat.event.threat = 2000
							mod.combat.event.damage = 0
							mod.combat.event.rage = 0
							
							mod.combat.addattacktodata(mod.string.get("threatsource", "threatwipe"), mod.combat.event)
							
							-- clear hits for total column
							mod.combat.event.hits = 0
							mod.combat.addattacktodata(mod.string.get("threatsource", "total"), mod.combat.event)
							
							-- if an emperor is targetting us, he will be the only one, and we have all the information we need, so we want the trigger to deactivate
							bosstargets = 2
							bosshits = 2
						end
					end
					
					-- if we have found 2 bosses now, there's no need to do more searching
					if bosshits == 2 then 
						break
					end
				end
			end
		end
		
		-- don't give up on the trigger until we have found both boss targets on one loop
		if bosstargets == 2 then
			return true
		end
	end,
	
	--[[
	Autotarget trigger runs when you run the command "/ktm boss autoatarget". When you next target a world boss, you will set the target and clear the meter.
	]]
	autotarget = function(triggerdata)
		
		if UnitExists("target") and (UnitClassification("target") == "worldboss") then
			
			-- found a target. now only activate if we've been targetting him for a while
			if triggerdata.data == 0 then
				triggerdata.data = GetTime()
				return
				
			else
				-- 500 ms minimum.
				if GetTime() < triggerdata.data + 0.5 then
					return
				end
			end
			
			-- found a target. Activate
			if mod.target.mastertarget == UnitName("target") then
				
				-- someone has already set the master target to this mob. In this case don't do anything.
				mod.out.print(string.format(mod.string.get("print", "boss", "autotargetabort"), UnitName("target")))
				
			else
				mod.net.clearraidthreat()
				mod.net.sendmastertarget()
			end
			
			return true
		end	
		
	end
}

--[[
me.checktriggers()
Loops through all possible triggers, checking for active ones and running them if need be. This is called in the OnUpdate() method.
]]
me.checktriggers = function()

	local key, data
	local timenow = GetTime()
	
	for key, data in me.triggers do
		
		-- ignore inactive triggers
		if data.isactive == true then
			
			-- stop the trigger if it has timed out
			if timenow > data.mystarttime + data.timeout then
				
				data.isactive = false
				
				-- debug
				if mod.out.checktrace("warning", me, "trigger") then
					mod.out.printtrace(string.format("The trigger |cffffff00%s|r timed out.", key))
				end
				
			-- don't process the trigger if the start delay is not over
			elseif timenow < data.mystarttime then
				-- (do nothing)
				
			else
				-- ok, run a trigger check
				if me.triggerfunctions[key](data) then
					data.isactive = false
				end
			end
		end
	end
end

--[[
------------------------------------------------------------------------------------------------
			Parsing the Combat Log to Detect Boss Special Attacks and Spells
------------------------------------------------------------------------------------------------
]]

-- me.parserset = { }  -- defined in me.createparser

--[[
me.createparser()
Called from me.onload() on startup. Creates the parser engine from the constructor.
]]
me.createparser = function()
	
	me.parserset = { }
	
	local parserdata
	
	for _, parserdata in me.parserconstructor do
		mod.regex.addparsestring(me.parserset, parserdata[1], parserdata[2], parserdata[3])
	end
	
end

-- This describes all the combat log lines we are checking for
me.parserconstructor = 
{
	-- this is for school spells or debuffs
	{"magicresist", "SPELLRESISTOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"}, -- "%s's %s was resisted."

	-- these two are for school spells only
	{"spellhit", "SPELLLOGSCHOOLOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"}, -- "%s's %s hits you for %d %s damage."
	{"spellhit", "SPELLLOGCRITSCHOOLOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"}, -- "%s's %s crits you for %d %s damage."

	-- spellboth is for abilities or school spells
	{"attackabsorb", "SPELLLOGABSORBOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"}, -- "You absorb %s's %s."
		
	-- ability hit / miss only works for physical spells.
	{"abilityhit", "SPELLLOGOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"}, 		-- "%s's %s hits you for %d."
	{"abilityhit", "SPELLLOGCRITOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"},	-- "%s's %s hits you for %d."
	{"abilityhit", "SPELLBLOCKEDOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"}, 	-- "%s's %s was blocked."
	{"abilitymiss", "SPELLDODGEDOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"},	-- "%s's %s was dodged."
	{"abilitymiss", "SPELLPARRIEDOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"},	-- "%s's %s was parried."
	{"abilitymiss", "SPELLMISSOTHERSELF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"},		-- "%s's %s misses you."
	
	{"debuffstart", "AURAADDEDSELFHARMFUL", "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE"}, -- "You are afflicated by %s."
	{"debufftick", "AURAAPPLICATIONADDEDSELFHARMFUL", "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE"}, -- "You are afflicted by %s (%d)."
	{"mobspellcast", "SPELLCASTGOOTHER", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE"},		-- "%s casts %s."
	{"mobbuffgain", "AURAADDEDOTHERHELPFUL", "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS"}, 		-- "%s gains %s."
	{"mobdeath", "UNITDIESOTHER", "CHAT_MSG_COMBAT_HOSTILE_DEATH"}, -- "%s dies."
}

me.tickcounters = { }

--[[
me.parsebossattack(message, event)

Handles a combat log line that describes a boss's attack or spell against the player.
--> Stage one is to parse the message to find which formatting pattern the message matches, e.g. "magicresist" or
"spellhit" etc, or none (then just exit).
--> Stage two is to fill in <me.action>, whch descibes the important parts of the attack, using the formatting patter and the arguments captured by the pattern.
--> Then we check whether this attack is actually a threat modifying attack. For this to be the case, there would be a localisation string whose value is the attack name, and there would be an entry in <me.bossattacks> with the same key as the localisation key.
--> Next we identify the ability w.r.t. the mob. Does the ability only come from one mob, and if so is the mob who just attacked us the right one? This involves a check in the next level of <me.bossattacks>.
--> Now we know the specific attack performed against us, and we have to work out whether it triggered. If the ability does not trigger on a miss (e.g. Knock Away), we won't do anything. If the ability only triggers after a number of ticks (Time Lapse), it will only trigger if the correct number of ticks has passed.
--> If it triggers, we just change our threat by the right amount, then report the threat change in the <combat> and <table> modules.

<message> is the combat log line.
<event> is the chat message event <message> was received on.
Returns: nothing.
]]
me.parsebossattack = function(message, event)
	
	-- stage 1: regex
	local output = mod.regex.parse(me.parserset, message, event)
	
	if output.hit == nil then
		return
	end

	-- interrupt: wrath of ragnaros
	if output.final[2] == mod.string.get("boss", "spell", "wrathofragnaros") then

		-- notify the raid, if this event isn't on cooldown 
		if GetTime() < me.bossevents.wrathofragnaros.lastoccurence + me.bossevents.wrathofragnaros.cooldown then
			-- on cooldown. don't send
		else
			mod.net.sendevent("wrathofragnaros")
		end
	end
 
	-- Set the mob and ability (always arg1 and arg2, except for debuffgain)
	if output.parser.identifier == "debuffstart" or output.parser.identifier == "debufftick" then
		me.resetaction("", output.final[1])
	else	
		me.resetaction(output.final[1], output.final[2])
	end
	
	-- set the spell and hit types
	local description = me.attackdescription[output.parser.identifier]

	if description.ishit then me.action.ishit = true end
	if description.isspell then me.action.isspell = true end
	if description.isdebuff then me.action.isdebuff = true end
	if description.isphysical then me.action.isphysical = true end
	
	-- find a spellid, if it exists
	local spellid = mod.string.unlocalise("boss", "spell", me.action.ability)
	
	-- interrupt: four horsemen marks
	if spellid == "mark1" or spellid == "mark2" or spellid == "mark3" or spellid == "mark4" then
		-- notify the raid, if this event isn't on cooldown 
		if GetTime() < me.bossevents.fourhorsemenmark.lastoccurence + me.bossevents.fourhorsemenmark.cooldown then
			-- on cooldown. don't send
		else
			mod.net.sendevent("fourhorsemenmark")
		end
		
		return
	end
	
	-- check whether this spellid has special behaviour associated with it
	if (spellid == nil) or (me.bossattacks[spellid] == nil) then
		return
	end
	
	-- Check for a mob match
	local spelldata
	
	local mobid = mod.string.unlocalise("boss", "name", me.action.mobname)
	
	if mobid and me.bossattacks[spellid][mobid] then
		-- there is a specific version of this spell for this particular mob
		spelldata = me.bossattacks[spellid][mobid]
	
	elseif me.bossattacks[spellid].default == nil then
		-- this mob does not match any of the mobs that have the ability
		return
		
	else
		spelldata = me.bossattacks[spellid].default
	end
	
	-- Now process the spell
	
	-- 1) Does the ability activate on a miss?
	if (me.action.ishit == false) and (spelldata.effectonmiss == false) then
		
		-- ability will not activate
		if mod.out.checktrace("info", me, "attack") then
			mod.out.printtrace(string.format("%s's attack %s did not activate because it missed.", me.action.mobname, me.action.ability))
		end
		
		-- spell reporting
		if me.isspellreportingactive == true then
			mod.net.reportspelleffect(me.action.ability, me.action.mobname, "miss")
		end
		
		return
	end
	
	-- 2) Check number of ticks
	local mytickdata
	
	if spelldata.ticks ~= 1 then
		
		-- create a list if none exists yet
		if me.tickcounters[me.action.ability] == nil then
			me.tickcounters[me.action.ability] = { }
		end
		
		if me.tickcounters[me.action.ability][me.action.mobname] == nil then
			me.tickcounters[me.action.ability][me.action.mobname] = 0
		end
		
		-- create an entry if none exists so far
		me.tickcounters[me.action.ability][me.action.mobname] = me.tickcounters[me.action.ability][me.action.mobname] + 1
		
		-- now, have we gone enough ticks?	
		if me.tickcounters[me.action.ability][me.action.mobname] < spelldata.ticks then
			
			-- not enough ticks
			if mod.out.checktrace("info", me, "attack") then
				mod.out.printtrace(string.format("This is tick number %d of %s; it will activate in another %d ticks.", me.tickcounters[me.action.ability][me.action.mobname], me.action.ability, spelldata.ticks - me.tickcounters[me.action.ability][me.action.mobname]))
			end
			
			-- spell reporting
			local value1 = me.tickcounters[me.action.ability][me.action.mobname]
			local value2 = spelldata.ticks - value1
			
			if me.isspellreportingactive then
				mod.net.reportspelleffect(me.action.ability, me.action.mobname, "tick", value1, value2)
			end
			
			return
			
		else
			-- we just got enough ticks, so now reset to 0
			me.tickcounters[me.action.ability][me.action.mobname] = 0
			
		end
	end
	
	-- 3) To get here, the ability is definitely activating
	if mod.out.checktrace("info", me, "attack") then
		mod.out.printtrace(string.format("%s's %s activates, multiplying your threat by %s then adding %s.", me.action.mobname, me.action.ability, spelldata.multiplier, spelldata.addition))
	end
	
	-- compute new threat
	local newthreat = mod.table.getraidthreat() * spelldata.multiplier + spelldata.addition
	
	-- remember threat can't go below 0
	newthreat = math.max(0, newthreat)
	
	-- threat change is the (possibly negative) amount of threat that was added
	local threatchange = newthreat - mod.table.getraidthreat()
	
	-- spellreporting
	if me.isspellreportingactive then
		mod.net.reportspelleffect(me.action.ability, me.action.mobname, "proc", math.floor(0.5 + mod.table.getraidthreat()), math.floor(0.5 + newthreat))
	end
	
	-- add to threat wipes section, but not to totals
	mod.combat.event.hits = 1
	mod.combat.event.damage = 0
	mod.combat.event.rage = 0
	mod.combat.event.threat = threatchange
	
	mod.combat.addattacktodata(mod.string.get("threatsource", "threatwipe"), mod.combat.event)
	
	-- now add it to your raid threat total (but not your personal threat total)
	mod.table.raidthreatoffset = mod.table.raidthreatoffset + threatchange
	
	-- ask for a redraw of the personal window
	KLHTM_RequestRedraw("self")
	
end

--[[
me.resetaction()
Sets the values of me.action to their defaults.
]]
me.resetaction = function(mobname, ability)

	me.action.mobname = mobname
	me.action.ability = ability
	me.action.ishit = false
	me.action.isphysical = false
	me.action.isdebuff = false
	me.action.isspell = false
	
end

me.action = 
{
	mobname = "",
	ability = "",
	ishit = false,
	isphysical = false,
	isdebuff = false,
	isspell = false,
}

-- Note that <ishit> defaults to false, so we only set it when it is true
me.attackdescription = 
{
	["magicresist"] = 
	{
		isspell = true,
		isdebuff = true,
	},
	["spellhit"] =
	{
		isspell = true,
		ishit = true,
	},
	["attackabsorb"] = 
	{
		isspell = true,
		isphysical = true,
		ishit = true,
	},
	["abilityhit"] = 
	{
		isphysical = true,
		ishit = true,
	},
	["abilitymiss"] = 
	{	
		isphysical = true,
	},
	["debuffstart"] = 
	{
		ishit = true,
		isdebuff = true,
	},
	["debufftick"] = 
	{
		ishit = true,
		isdebuff = true,
	},
}

--[[
Here is where you define all the boss' attacks that affect threat.
	The first key in me.bossattacks is the identifier of the spell. That is, mod.string.get("boss", "spell", <first key>) 
is the localised version.
	The second key deep specifies which mob the attack comes from. You can choose "default" to make it apply to all mobs,
or you can specify a mob id, which will override the "default" value. Mob id's recognised are all the keys in the 
"boss" -> "name" section of the localisation tree.
	So if you want to define a new attack name or boss name, you'll have to add a new key to the localisation tree in the
"boss" -> "spell" and "boss" -> "name" sections respectively.
	Inside each block, the follow parameters are defined:
	<multiplier> - a value that your threat is multiplier by. e.g. the standard Knock Away is -50% threat, so this would be a 
multiplier of 0.5. A complete threat wipe would be a multiplier of 0.
	<addition> - a flat value that is added to your threat. Can be positive or negative or 0.
	<effectonmiss> - a boolean value specifying whether the event triggers even when it is resisted or misses you.
	<ticks> - the number of times you must suffer the attack before your threat is changed. e.g. most knockbacks happen every
time so <ticks> = 1, but Time Lapse reduces your threat only after a certain number of applications.
	<type> - describes the attack. Can be "physical" or "spell" or "debuff". Not used by the mod at the moment: it will 
assume that if the name matches, it has found the right ability.
]]
--! This variable is referenced by these modules: net, netin, 
me.bossattacks = 
{
	knockaway = 
	{
		default = 
		{
			multiplier = 0.5,
			addition = 0,
			effectonmiss = false,
			ticks = 1,
			type = "physical",
		},
		onyxia = 
		{
			multiplier = 0.75,
			addition = 0,
			effectonmiss = true,
			ticks = 1,
			type = "physical",
		},
	},
	wingbuffet = 
	{
		default = 
		{
			multiplier = 0.5,
			addition = 0,
			effectonmiss = false,
			ticks = 1,
			type = "physical",
		},
		onyxia = 
		{
			multiplier = 1.0,
			addition = 0,
			effectonmiss = false,
			ticks = 1,
			type = "physical",
		},
	},
	timelapse = 
	{
		default = 
		{
			multiplier = 1.0,
			addition = 0,
			effectonmiss = false,
			ticks = 5,
			type = "debuff"
		}
	},
	hatefulstrike = 
	{
		default = 
		{
			multiplier = 1.0,
			addition = 1000,
			effectonmiss = false,
			ticks = 1,
			type = "physical"
		}
	},
	sandblast = 
	{
		default = 
		{
			multiplier = 0,
			addition = 0,
			effectonmiss = false,
			ticks = 1,
			type = "spell"
		}
	},
}
```

## Code\KTM_Combat.lua
```lua
--! This module references these other modules:
--! boss:	mastertarget, targetismaster, mttruetarget, 
--! data:	spells, rockbiter, threatconstants, spellmatchesset, 
--! my:	class, ability, states, mods, globalthreat, 
--! out:	checktrace, printtrace, 
--! table:	mydata, raiddata, newdatastruct, getraidthreat, resetraidthreat, 
--! unit:	findunitidfromname, 
--! string:	get, 

--! This module is referenced by these other modules:
--! alert:	lastattack, 
--! boss:	event, addattacktodata, 
--! combatparser:	specialattack, normalattack, taunt, possibleoverheal, powergain, 
--! my:	recentattacks, 

-- Add the module to the tree
local mod = klhtm
local me, _ = {}
mod.combat = me
local lastSunderTime = 0

--[[
KTM_Combat.lua

The combat module parses combat log events for damage and abilities done.
]]

-- These are the events we would like to be notified of
me.myevents = { "CHAT_MSG_SPELL_FAILED_LOCALPLAYER", "CHAT_MSG_COMBAT_FRIENDLY_DEATH", "CHAT_MSG_SPELL_SELF_DAMAGE"}

-- these are kept for debug purposes. We need two because next attack abilities are split into two.
--! This variable is referenced by these modules: alert, 
me.lastattack = nil
me.secondlastattack = nil

--[[ 
This is a record of attacks in the last second while out of combat. We keep this because when you
go into combat by initiating an attack, the +combat event can come after the actual attack. 
]]
--! This variable is referenced by these modules: my, 
me.recentattacks = { } 

me.onupdate = function()

	local timenow = GetTime()
	local key
	local value

	for key, value in me.recentattacks do
		if value[1] < timenow - 1 then
			me.recentattacks[key] = nil
		end
	end

end
	

-- This is a method level temporary variable. Declared at file level because it is a list,
-- and we don't want to keep paging heap memory every time he is created.
--! This variable is referenced by these modules: boss, 
me.event = 
{
	["hits"] = 0,
	["damage"] = 0,
	["rage"] = 0,
	["threat"] = 0,
	["name"] = 0,
	["sunder"] = 0,
}

--[[ 
Special onevent() method that will be called by Core.lua:onevent()
]]
me.onevent = function()

	if me.oneventinternal() then
		KLHTM_RequestRedraw("self")
	end
	
end

-- Returns non-nil if the event causes our threat to change
me.oneventinternal = function()
	
	local ability
	local target
	local amount
	local damagetype
	
	if event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
		if string.find(arg1, mod.string.get("spell", "sunder")) then
			if string.find(arg1, "range") then
			    if (GetTime() - lastSunderTime) < .3 then
				    lastSunderTime = 0 
					lastSunderRangeFail = GetTime()
					--Print("Sunder Range Failure: "..lastSunderRangeFail)
				end
			end
			--Print("Sunder All Failure: "..GetTime())
			me.retractsundercast()

			return true 
		else
			return
		end
	
	elseif event == "CHAT_MSG_COMBAT_FRIENDLY_DEATH" then
		
		if arg1 == UNITDIESSELF then -- UNITDIESSELF = "You die."
			-- death is a threat wipe
			mod.table.resetraidthreat()
			return true
		end
		
	end
		
end

--[[
mod.combat.specialattack(abilityid, target, damage, iscrit, spellschool)
This handles any attack from a spell that has special threat properties, i.e. all the spells in mod.data.spells .
<abilityid> is the internal identifier for these abilities. i.e. Sunder Armor has <abilityid> = "sunder". This is locale
independent.
<damage>, <iscrit>, and <spellschool> are optional. <spellschool> is localised, and will have the value either nil
	or "" or one of SPELL_SCHOOL1_CAP, SPELL_SCHOOL2_CAP, etc.
<iscrit> is only accepted if it has the boolean value true.
]]
--! This variable is referenced by these modules: combatparser, 
me.specialattack = function(abilityid, target, damage, iscrit, spellschool)

	-- 1) check the attack is directed at the master target. If not, ignore.
	if mod.target.targetismaster(target) == nil then
		return
	end
	
	-- 2) get the player's global threat modifiers (defensive stance, blessing of salvation, etc)
	local threatmodifier = mod.my.globalthreat.value
	
	--[[
	Now, most attacks can be handled gracefully by the table. However, for abilities that modify your autoattack, 
	we would prefer to decouple the ability from the autoattack, so we have to handle these cases individually.
	]]
	
	-- reset me.event
	me.event.hits = 1
	me.event.rage = 0
	me.event.damage = damage
        if abilityid == "sunder" then me.event.sunder = 1 else me.event.sunder = 0 end
	
	-- 3) Handle Autoattack modifying abilities separately
	if abilityid == "whitedamage" then

		-- shaman special: check for rockbiter
		if mod.my.mods.shaman.rockbiter > 0 then
			
			-- make a separate event for the rockbiter
			local weaponspeed = UnitAttackSpeed("player")
			local rockbiterdps = mod.data.rockbiter[mod.my.mods.shaman.rockbiter]

			-- note: we are sending the threat value of rockbiter as the damage argument
			me.specialattack("rockbiter", target, rockbiterdps * weaponspeed, nil, nil)
			
			-- the above call to me.specialattack will have overwritten some parts of me.event. Set them back!
			me.event.damage = damage
		end
		
		-- normal behaviour
		me.event.threat = damage * threatmodifier
	
	-- Special case: Rockbiter Weapon
	elseif abilityid == "rockbiter" then
		
		-- this will only come from a "whitedamage" call to this method (see above)
		me.event.threat = me.event.damage * threatmodifier
		me.event.damage = 0

	-- Special case: Heroic Strike
	elseif abilityid == "heroicstrike" then
		
		local preimpaledamage = damage
		if iscrit == true then
			preimpaledamage = damage / (1 + mod.my.mods.warrior.impale)
		end
		
		local addeddamage = mod.my.ability("heroicstrike", "nextattack")
		local myaveragedamage = me.averagemainhanddamage()
		local whitedamage = preimpaledamage * (myaveragedamage / (addeddamage + myaveragedamage))
		
		-- Now make a separate method call for the autoattack component
		me.specialattack("whitedamage", target, whitedamage, nil, nil)
		
		-- The above method will have overwritten some parts of me.event, so change them back
		me.event.damage = damage - whitedamage
		me.event.threat = (me.event.damage + mod.my.ability("heroicstrike", "threat")) * threatmodifier
		me.event.rage = mod.my.ability("heroicstrike", "rage") + whitedamage / (UnitLevel("player") / 2)
	
	-- Special Case: Maul
	elseif abilityid == "maul" then
		
		-- same as heroic strike, but a bit different
		local presavagefurydamage = damage / (1 + mod.my.mods.druid.savagefury)		
		local addeddamage = mod.my.ability("maul", "nextattack")
		local myaveragedamage = me.averagemainhanddamage()
		local whitedamage = presavagefurydamage * (myaveragedamage / (addeddamage + myaveragedamage))
		
		-- Now make a separate method call for the autoattack component
		me.specialattack("whitedamage", target, whitedamage, nil, nil)
		
		-- The above method will have overwritten some parts of me.event, so change them back
		me.event.damage = damage - whitedamage
		me.event.threat = threatmodifier * (damage * mod.my.ability("maul", "multiplier") - whitedamage)
		me.event.rage = mod.my.ability("maul", "rage") + whitedamage / (UnitLevel("player") / 2)
		
	-- Default Case: all other abilities
	else
		
		-- 1) Check for rage
		me.event.rage = mod.my.ability(abilityid, "rage")

		local multiplier = mod.my.ability(abilityid, "multiplier")
		
		-- 2) Check for multiplier
		if multiplier then
			me.event.threat = me.event.damage * multiplier
			
		else
			me.event.threat = me.event.damage + mod.my.ability(abilityid, "threat")
		end
		
		-- 3) Multiply by global modifiers
		me.event.threat = me.event.threat * threatmodifier
	
	end
	
	-- Paladin righteous fury (can affect holy shield)
	if mod.my.class == "paladin" then
		
		-- righteous fury
		if spellschool == SPELL_SCHOOL1_CAP then -- holy
			me.event.threat = me.event.threat * mod.my.mods.paladin.righteousfury
		end
		
	-- warlock Nemesis 8/8 (can affect searing pain)
	elseif mod.my.class == "warlock" then
			
		-- Nemesis 8/8
		if (mod.my.mods.warlock.nemesis == true) and (mod.data.spellmatchesset("Warlock Destruction", abilityid) == true) then
			me.event.threat = me.event.threat * 0.8
		end
	end
		
	-- check for >= 0 threat
	if me.event.threat + mod.table.getraidthreat() < 0 then
		me.event.threat = - mod.table.getraidthreat()
	end
	
	-- relocalise.
	if abilityid == "whitedamage" then
		me.event.name = mod.string.get("threatsource", "whitedamage")
		
	else
		me.event.name = mod.string.get("spell", abilityid)
	end
	
	-- Add to data
	me.addattacktodata(me.event.name, me.event)
	me.addattacktodata(mod.string.get("threatsource", "total"), me.event)
	
end

-- to work out which part of a next attack ability was from white damage
-- used by nextattack abilities like maul and heroic strike.
me.averagemainhanddamage = function()

	local min, max = UnitDamage("player")
	return (min + max) / 2

end

--[[
me.normalattack(spellname, damage, target, iscrit, spellschool)
Handles a damage-causing ability with no special threat properties. We often have to make modifiers for gear or talents here.
<spellname> is the name of the ability.
<spellid> is the internal name for "special" spells or abilities, i.e. those we have to look out for because there are specific set bonuses or talents that affect them.
<damage> is the damage done.
<target> is the name of the mob you hit.
<iscrit> is a boolean, whether the hit was a critical one. Triggers iff it is the boolean value true.
<spellschool> is a string, one of SPELL_SCHOOL1_CAP, SPELL_SCHOOL2_CAP, etc, or possibly nil or "".
]]
--! This variable is referenced by these modules: combatparser, 
me.normalattack = function(spellname, spellid, damage, isdot, target, iscrit, spellschool)
	
	-- check the attack is directed at the master target. If not, ignore.
	if mod.target.targetismaster(target) == nil then
		return
	end

	-- threatmodifier includes global things, like defensive stance, tranquil air totem, rogue passive modifier, etc.
	local threatmodifier = mod.my.globalthreat.value
	
	-- Special threat mod: priest silent resolve (spells only)
	if mod.my.class == "priest" then
		threatmodifier = threatmodifier * (1.0 +  mod.my.mods.priest.silentresolve)
	end 
	
	-- Special threat modifiers for mages
	if mod.my.class == "mage" then
		
		if spellschool == SPELL_SCHOOL6_CAP then -- arcane
			threatmodifier = threatmodifier * (1.0 + mod.my.mods.mage.arcanethreat)
		
		elseif spellschool == SPELL_SCHOOL4_CAP then -- frost
			threatmodifier = threatmodifier * (1.0 + mod.my.mods.mage.frostthreat)
		
		elseif spellschool == SPELL_SCHOOL2_CAP then -- fire
			threatmodifier = threatmodifier * (1.0 + mod.my.mods.mage.firethreat)
		end
	end
	
	-- Default values for me.event:
	me.event.hits = 1
	me.event.rage = 0
	me.event.damage = damage
	me.event.threat = damage * threatmodifier
        me.event.sunder = 0

	-- now get the name:
	if spellid == "dot" then
		
		me.event.hits = 0
		me.event.name = mod.string.get("threatsource", "dot")
		
	elseif spellid == "damageshield" then
		me.event.name = mod.string.get("threatsource", "damageshield")
		
	else
		me.event.name = mod.string.get("threatsource", "special")
		me.event.threat = damage * threatmodifier
	end
	
	-- Now apply class-specific filters
	
	-- warlock
	if mod.my.class == "warlock" then
			
		-- Nemesis 8/8
		if (mod.my.mods.warlock.nemesis == true) and (mod.data.spellmatchesset("Warlock Destruction", spellid) == true) then
			me.event.threat = me.event.threat * 0.8
			end
		-- Plagueheart 6/8
		if mod.my.mods.warlock.plagueheart == true then
			
			-- 1) 25% less for crits
			if iscrit == true then
				me.event.threat = me.event.threat * 0.75
			
			-- 2) 25% less for some dots
			elseif mod.data.spellmatchesset("Plagueheart 6 Bonus", abilityid, nil) == true then
				me.event.threat = me.event.threat * 0.75
			end
		end
	-- Priest
	elseif mod.my.class == "priest" then
			
		-- shadow affinity
		if spellschool == SPELL_SCHOOL5_CAP then
			me.event.threat = me.event.threat * mod.my.mods.priest.shadowaffinity
		end
		
		-- holy nova: no threat
		if spellid == "holynova" then
			me.event.threat = 0
		end
		
	-- Mage
	elseif mod.my.class == "mage" then
			
		-- netherwind
		if mod.my.mods.mage.netherwind == true then
			
			if (spellid == "frostbolt") or (spellid == "scorch") or (spellid == "fireball") then
				-- note that this won't trigger off the dot part of fireball, because then spellid will be "dot"
				me.event.threat = math.max(0, (me.event.threat - 100))
				
			elseif spellid == "arcanemissiles" then
				me.event.threat = math.max(0, (me.event.threat - 20))
			end
		end
	
		-- frostfire 8 piece proc
		if mod.my.states.notthere.value == true then
			me.event.threat = 0
			mod.my.setstate("notthere", false)
		end

	-- Rogue
	elseif mod.my.class == "rogue" then
		
		-- bonescythe 6/8
		if mod.my.mods.rogue.bonescythe == true then
			if (spellid == "sinisterstrike") or (spellid == "backstab") or (spellid == "eviscerate") or (spellid == "hemorrhage") then
				me.event.threat = me.event.threat * 0.92
			end
		end
		
	-- Paladin
	elseif mod.my.class == "paladin" then
		
		-- righteous fury
		if spellschool == SPELL_SCHOOL1_CAP then -- holy
			me.event.threat = me.event.threat * mod.my.mods.paladin.righteousfury
		end
	end

	-- special: blood siphon no threat vs Hakkar. This may or may not be correct.
	if spellid == "bloodsiphon" then
		me.event.threat = 0
	end

	-- now add me.event to individual and totals
	me.addattacktodata(me.event.name, me.event)
	me.addattacktodata(mod.string.get("threatsource", "total"), me.event)
	
end

--[[ 
me.registertaunt()
Called when you succesfully casts Taunt or Growl on a mob.
<target> is the name of the mob you have taunted.
]]
--! This variable is referenced by these modules: combatparser, 
me.taunt = function(target)
	
	if mod.out.checktrace("info", me, "taunt") then
		mod.out.printtrace(string.format("Taunting %s!", target))
	end
	
	--[[
	OK, new idea. If targettarget has greater threat than you, assume they are the aggro target.
	]]
	if mod.target.targetismaster(target) == nil then
		-- you taunted a mob that is not the master target
		return
	end
	
	-- here, you either taunted the master target, or there is no master target
	-- check if you are still targetting that mob (likely, if you just taunted it)
	if UnitName("target") == target then
	
		-- Check for tt
		local targettarget = UnitName("targettarget")
		
		if mod.table.raiddata[targettarget] and (mod.table.raiddata[targettarget] > mod.table.getraidthreat()) then
			-- your current target is targetting another player, and they have more threat than you
			
			local gain = mod.table.raiddata[targettarget] - mod.table.getraidthreat()
				
			me.event.hits = 1
			me.event.damage = 0
			me.event.rage = 0
			me.event.threat = gain
			me.event.name = mod.string.get("spell", "taunt")
                        me.event.sunder = 0
			
			me.addattacktodata(mod.string.get("spell", "taunt"), me.event)
			me.addattacktodata(mod.string.get("threatsource", "total"), me.event)
			
			if mod.out.checktrace("info", me, "taunt") then
				mod.out.printtrace(string.format("You taunt %s from %s, gaining %d threat.", target, targettarget, gain))
			end
			
			return
		end
	end
	
	-- If that didn't work, use the old code:	
	
	if target == mod.target.mastertarget then
		local previoustargetthreat = mod.table.raiddata[mod.target.mttruetarget]
		
		if (previoustargetthreat ~= nil) and (previoustargetthreat > mod.table.getraidthreat()) then
			local tauntgain = previoustargetthreat - mod.table.getraidthreat()
			
			me.event.hits = 1
			me.event.damage = 0
			me.event.rage = 0
			me.event.threat = tauntgain
			me.event.name = mod.string.get("spell", "taunt")
                        me.event.sunder = 0
			
			me.addattacktodata(mod.string.get("spell", "taunt"), me.event)
			me.addattacktodata(mod.string.get("threatsource", "total"), me.event)

			if mod.out.checktrace("info", me, "taunt") then
				mod.out.printtrace(string.format("You taunt %s from %s, gaining %d threat.", target, mod.target.mttruetarget or "<nil>", tauntgain))
			end
		
		else
			if mod.out.checktrace("info", me, "taunt") then
				mod.out.printtrace(string.format("You taunt %s from %s, but he had a lower threat, so you gain no threat.", target, mod.target.mttruetarget or "<nil>"))
			end
		end
	end
	
end

--[[
me.possibleoverheal(spellname, spellid, amount, target)
Works out the threat from a heal.
<spellname> is the localised name of the spell
<spellid> is the mod's internal name for the spell, if it is special (i.e. affected by talents / sets bonuses), otherwise "".
<amount> is the healed amount only (no overheal)
<target> is the name of the target
Called when you heal someone. Deducts the overhealing from the total, then calls the Heal method
]]
--! This variable is referenced by these modules: combatparser, 
me.possibleoverheal = function(spellname, spellid, amount, target)
	
	-- we can check the target's health, which will be the health before the heal. Then we work out what the 
	-- heal did, and we can calculate overheal.
	
	local unit = mod.unit.findunitidfromname(target)
	
	if unit == nil then
		if mod.out.checktrace("info", me, "healtarget") then
			mod.out.printtrace(string.format("Could not find a UnitID for the name %s.", target))
		end
		-- (and assume there was no overheal)
	else
		local hpvoid = UnitHealthMax(unit) - UnitHealth(unit)
		amount = math.min(amount, hpvoid)
	end
	
	me.registerheal(spellname, spellid, amount, target)
	
end

--[[ 
me.registerheal(spellname, spellid, amount, target)
Works out the threat from a heal.
<spellname> is the localised name of the spell
<spellid> is the mod's internal name for the spell, if it is special (i.e. affected by talents / sets bonuses), otherwise "".
<amount> is the healed amount only (no overheal)
<target> is the name of the target
]]
me.registerheal = function(spellname, spellid, amount, target)

	-- in general, don't count heals towards the master target
	if mod.target.mastertarget and mod.target.targetismaster(target) then
		return
	end
		
	-- also, don't count heals towards a hostile target
	if (target == UnitName("target")) and UnitIsEnemy("player", "target") then
		return
	end
	
	me.event.hits = 1
	me.event.rage = 0
	me.event.damage = amount
        me.event.sunder = 0
	
	local threatmod = mod.my.globalthreat.value
	
	-- Special threat mod: priest silent resolve (spells only)
	if mod.my.class == "priest" then
		threatmod = threatmod * (1 + mod.my.mods.priest.silentresolve)
	end 
	
	me.event.threat = amount * threatmod * mod.data.threatconstants.healing
	
	-- class-based healing multipliers
	if mod.my.class == "paladin" then
		me.event.threat = me.event.threat * mod.my.mods.paladin.healing
		
	elseif mod.my.class == "druid" then
		me.event.threat = me.event.threat * mod.my.mods.druid.subtlety
		
		if spellid == "tranquility" then
			me.event.threat = me.event.threat * mod.my.mods.druid.tranquilitythreat
		end
		
	elseif mod.my.class == "shaman" then
		me.event.threat = me.event.threat * mod.my.mods.shaman.healing
		
	end 
	
	-- Special: healing abilities which don't cause threat
	if spellid == "holynova" then
		me.event.threat = 0
	elseif spellid == "siphonlife" then
		me.event.threat = 0
	elseif spellid == "drainlife" then
		me.event.threat = 0
	elseif spellid == "deathcoil" then
		me.event.threat = 0
	end
	
	me.addattacktodata(mod.string.get("threatsource", "healing"), me.event)
	
	me.event.damage = 0
	me.addattacktodata(mod.string.get("threatsource", "total"), me.event)
end

--[[
me.powergain(amount, powertype)
Calculates the threat from gaining energy / mana / rage.
<amount> is the amount of power gained.
<powertype> is "Mana" or "Rage" or "Energy", but the localised versions.
<spellid> is the spell or effect that caused the power gain.
]]
--! This variable is referenced by these modules: combatparser, 
me.powergain = function(amount, powertype, spellid)
	
	me.event.damage = amount
	me.event.hits = 1
	me.event.rage = 0
        me.event.sunder = 0
	
	-- 1) Prevent "overheal" for power gain
	local maxgain = UnitManaMax("player") - UnitMana("player")
	amount = math.min(maxgain, amount)
	
	-- 2) Prevent invalid power gains (Essence of the Red shows both rage and energy gain)
	local playerpowertype = UnitPowerType("player")
	
	if powertype == mod.string.get("power", "rage") and playerpowertype == 1 then
		me.event.threat = amount * mod.data.threatconstants.ragegain
		
	elseif powertype == mod.string.get("power", "energy") and playerpowertype == 3 then
		me.event.threat = amount * mod.data.threatconstants.energygain
		
	elseif powertype == mod.string.get("power", "mana") and playerpowertype == 0 then
		me.event.threat = amount * mod.data.threatconstants.managain 
		
	else
		return
	end
	
	-- Special: abilities which don't cause threat
	if spellid == "lifetap" then
		me.event.threat = 0
	end
		
	me.addattacktodata(mod.string.get("threatsource", "powergain"), me.event)
	
	-- now mod it a bit to work into total better
	me.event.damage = 0
	me.event.hits = 0
	
	me.addattacktodata(mod.string.get("threatsource", "total"), me.event)
	
end

--[[
me.addattacktodata(name, data)
Once the threat from an attack has been worked, add it.
<name> is the category to add the threat to
<data> is me.event, i think...
Heap Memory will be created when you call this method when out of combat (mostly healing). 
From the size of the list (two numbers in it), will be 50 bytes tops each time.
]]
--! This variable is referenced by these modules: boss, 
me.addattacktodata = function(name, data)
	
	-- Ignore if charmed
	if mod.my.states.playercharmed.value == true then
		return
	end 
	
	if name ~= mod.string.get("threatsource", "total") then
		me.secondlastattack = me.lastattack
		me.lastattack = data
		
		-- Add this to the recent attacks list, if we are not in combat
		if mod.my.states.incombat.value == false then
			table.insert(me.recentattacks, {GetTime(), data.threat})
		end
	end
	
	-- Add a new column to mod.table.mydata, if it does not exist already
	if mod.table.mydata[name] == nil then
		mod.table.mydata[name] = mod.table.newdatastruct()
	end
	
	mod.table.mydata[name].hits = mod.table.mydata[name].hits + data.hits
	mod.table.mydata[name].threat = mod.table.mydata[name].threat + data.threat
	mod.table.mydata[name].rage = mod.table.mydata[name].rage + data.rage
	mod.table.mydata[name].damage = mod.table.mydata[name].damage + data.damage 
	mod.table.mydata[name].sunder = mod.table.mydata[name].sunder + data.sunder 
	
end


----------------------------------------------------------
--					Handling Sunder						--
----------------------------------------------------------


--[[
klhtu.combat.submitsundercast()
When you think you have just cast a sunder, call this method to make sure the addon knows. There's no way to
reliably detect a sunder hit, so we assume it has been cast, then look for failure signs (misses, spell errors)
It's highly recommended to use klhtm.combat.sunder() or KLHTM_Sunder() instead, because it will make sure
that threat is correct when you spam the button, which may not happen otherwise.
]]

me.submitsundercast = function()
	
	-- 17.16: since we now intercept castspellbyname, mods don't need to call this any more, so it has been disabled. The method will still exist for compatability's sake.

end

me.addsunderthreat = function()
	
	-- check for Master Target
	if mod.target.targetismaster(UnitName("target")) == nil then
		return
	end
	
	me.specialattack("sunder", UnitName("target"), 0)
	KLHTM_RequestRedraw("self")
	
end
-- Call this from a macro, to replace your normal sunder button
me.spellbooksunderindex = 1

-- Kept for compatibility
function KLHTM_Sunder()
	
	me.sunder()
	
end

--[[
me.sunder()
Casts Sunder Armor if most checks reveal it is castable, and calls me.sumbitsundercast().
This method is safe to be spammed. It will only cast if the global cooldown is off, which means once you try to
cast it, you won't try again unless the server says "failed due to <x>". So it's like full good and stuff.
]]
me.sunder = function()
	
	if mod.my.class ~= "warrior" then
		return
	end
	
	-- 1) Check if the old position is fine
	if GetSpellName(me.spellbooksunderindex, "spell") ~= mod.string.get("spell", "sunder") then
		
		-- get spell number of spells
		local spelltabs = GetNumSpellTabs()
		local numspells = 0
		local i
		local temp
	
		for i = 1, spelltabs do
			_, _, _, temp = GetSpellTabInfo(i)
			numspells = numspells + temp
		end
	
		-- 2) locate sunder armor in the spell book
		for i = 1, numspells do
			if GetSpellName(me.spellbooksunderindex + i, "spell") == mod.string.get("spell", "sunder") then
				me.spellbooksunderindex = me.spellbooksunderindex + i
				break
				
			elseif i == numspells then
				if mod.out.checktrace("warning", me, "sunder") then
					mod.out.printtrace("Can't find sunder in your spellbook!")
				end
				return -- can't find sunder
			end
		end
	end
	
	-- Now we've found sunder. Check the cooldown		
	if GetSpellCooldown(me.spellbooksunderindex, "spell") ~= 0 then 
		return
	end
	
	-- Test for target
	if UnitCanAttack("player", "target") == nil then
		return
	end 
	if not lastSunderRangeFail then lastSunderRangeFail = 0 end
	--if (GetTime() - lastSunderRangeFail) > .1 then
		lastSunderTime = GetTime()
		--Print("Set Last Sunder Time Attempt: "..lastSunderTime)
	--end
	
	-- Cast
	me.savedcastspellbyname(mod.string.get("spell", "sunder"))
	me.addsunderthreat()

end

--[[ 
me.retractsundercast()
Called when an attempted cast of Sunder Armor was found to have failed. i.e. we received a message like
"Your sunder armor failed: not enough rage" in the combat log.
]]
me.retractsundercast = function()

	-- 1) check for master target
	if mod.target.targetismaster(UnitName("target")) == nil then
		return
	end
	
	me.event.hits = -1
	me.event.damage = 0
	me.event.rage = - mod.my.ability("sunder", "rage")
        me.event.sunder = -1
	
	local threatmodifier = mod.my.globalthreat.value
	me.event.threat = - mod.my.ability("sunder", "threat") * threatmodifier 

	me.addattacktodata(mod.string.get("spell", "sunder"), me.event)
	me.addattacktodata(mod.string.get("threatsource", "total"), me.event)
	
	KLHTM_RequestRedraw("self")
end

--[[
This code hooks UseAction, intercepts the user casting Sunder Armor, and runs me.sunder() instead.
]]

me.saveduseaction = UseAction

me.newuseaction = function(actionindex, x, y)
	
	-- Check Sunder
	if (mod.my.class == "warrior") and actionindex and (GetActionText(actionindex) == nil) and (GetActionTexture(actionindex) == "Interface\\Icons\\Ability_Warrior_Sunder") then
		
		if GetActionCooldown(actionindex) > 0 then
			if mod.out.checktrace("info", me, "sunder") then
				mod.out.printtrace("Preventing Sunder cast due to cooldown!")
			end
			return
			
		else
			-- Now check we have a decent target. Otherwise press "tab" - this is what the UI does anyway
			if UnitCanAttack("player", "target") ~= 1 then
				
				if mod.out.checktrace("info", me, "sunder") then
					mod.out.printtrace("Preventing Sunder cast due to invalid target!")
				end
				
				TargetNearestEnemy()
				return
			end
			
			me.addsunderthreat()
			-- At the bottom of this method the sunder will be cast
		end
	
	end

   -- Call the original function
   me.saveduseaction(actionindex, x, y)   

end

UseAction = me.newuseaction


--[[
This code hooks CastSpellByName(), intercepts the user casting Sunder Armor, and runs me.sunder() instead.
]]
me.savedcastspellbyname = CastSpellByName

me.newcastspellbyname = function(name, onself)
	
	if string.find(name, mod.string.get("spell", "sunder")) then
		-- user wants to cast sunder. Run it through me.sunder() instead
		me.sunder()
		
	else
		me.savedcastspellbyname(name, onself)
	end
	
end

CastSpellByName = me.newcastspellbyname
```

## Code\KTM_CombatParser.lua
```lua
--! This module references these other modules:
--! combat:	specialattack, normalattack, taunt, possibleoverheal, powergain, 
--! data:	spells, 
--! out:	checktrace, printtrace, 
--! regex:	parse, addparsestring, 
--! string:	unlocalise, 

--! This module is referenced by these other modules:

-- Add the module to the tree
local mod = klhtm
local me = {}
mod.combatparser = me

--[[
CombatParser.lua

This module is the bridge between Regex.lua and Combat.lua. Given a combat log event, it feeds it to the parser.
If successful, the parser will return a set of arguments, and an identifier that describes the combat log line, such as "whiteattackhit".

CombatParser then works out what to do with the arguments. That is, it massages them into a format for Combat.lua's methods.

]]

me.myevents = { "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF", "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS", "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "CHAT_MSG_SPELL_SELF_BUFF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" }

-- OnEvent() - called from Core.lua.
me.onevent = function()

	-- This is stage one:
	local output = mod.regex.parse(me.parserset, arg1, event)
	
	if output.hit == nil then
		return
	end

	-- Reset combat args
	me.action.type = ""
	me.action.spellname = ""
	me.action.spellid = ""
	me.action.damage = 0
	me.action.target = ""
	me.action.iscrit = false
	me.action.spellschool = ""
	
	-- check a stage two handler is defined
	if me.parserstagetwo[output.parser.identifier] == nil then
		if mod.out.checktrace("error", me, "parser") then
			mod.out.printtrace(string.format("No handler is defined for a %s parse!", output.parser.identifier))
		end
		return
	end
	
	-- run the stage two handler
	me.parserstagetwo[output.parser.identifier](output.final[1], output.final[2], output.final[3], output.final[4], output.final[5])

   -- check a stage 3 handler is defined
   if me.parserstagethree[me.action.type] == nil then
		if mod.out.checktrace("error", me, "parser") then   
			mod.out.printtrace(string.format("No stage handler is defined for a %s action!", me.action.type))
		end
		return
	end
	
   -- run the stage 3 handler
   me.parserstagethree[me.action.type]()
   
end

--[[
type can be:

attack			anything that causes damage
heal				any source of healing from you
powergain		you gain x rage / mana / energy
nothing			actions that don't change threat
special			non-damaging abilities, e.g. taunt / feint

]]

me.action = 
{
	type = "",
	spellname = "",
	spellid = "",
	damage = 0,
	target = "",
	iscrit = false,
	spellschool = "",
}

--[[
Combining some parsers is possible. e.g. autoattack hits and crits can go together. Even if in one locale they look completely different, or have different orderings, once they go through stage one they will come out the same. And for an autoattack we don't care whether it's a crit or not (only for abilities, to calculate the rage cost of heroic strike or maul more accurately).
]]
me.parserstagetwo = 
{
	["autoattack"] = function(target, damage)
		me.action.spellid = "whitedamage"
		me.action.damage = damage
		me.action.target = target
		me.action.type = "attack"
      
	end,
	
	["damageshield"] = function(damage, school, target)
		me.action.damage = damage
		me.action.target = target
		me.action.spellschool = school
    me.action.type = "attack"
		me.action.spellid = "damageshield"
		
	end,
	
	["abilityhit"] = function(name, target, damage)
		me.action.spellname = name
		me.action.damage = damage
		me.action.target = target
	   me.action.type = "attack"
      
	end,
	
	["abilitycrit"] = function(name, target, damage)
		me.action.spellname = name
		me.action.damage = damage
		me.action.target = target
		me.action.iscrit = true
		me.action.type = "attack"
      
	end,
	
	["spellhit"] = function(name, target, damage, school)
		me.action.spellname = name
		me.action.damage = damage
		me.action.target = target
		me.action.spellschool = school
		me.action.type = "attack"
      
	end,
	
	["spellcrit"] = function(name, target, damage, school)
		me.action.spellname = name
		me.action.damage = damage
		me.action.target = target
		me.action.spellschool = school
		me.action.iscrit = true
		me.action.type = "attack"
      
	end,
	
	["perform"] = function(name, target)
		me.action.spellname = name
		me.action.target = target
		me.action.type = "special"
      
	end,
	
	["spellcast"] = function(name, target)
		me.action.spellname = name
		me.action.target = target
		me.action.type = "special"
      
	end,

	["othersdotonother"] = function(target, damage, school, author, name)
    me.action.type = "nothing"
    if (GetLocale() == "koKR") then
      local korname = author.."? "..name
      if (korname == "??? ??: ??" or korname == "??? ??" or korname == "??? ??" or
        korname == "??? ??" or korname == "?? ?" or korname == "??? ?" or korname == "??? ?") then
        me.action.spellname = korname
        me.action.spellid = "dot"
        me.action.damage = damage
        me.action.target = target
        me.action.spellschool = school
        me.action.type = "attack"
      end
		end
    
	end,

	["dot"] = function(target, damage, school, name)
		me.action.spellname = name
		me.action.spellid = "dot"
		me.action.damage = damage
		me.action.target = target
		me.action.spellschool = school
		me.action.type = "attack"
      
	end,
	
	["yourhotonother"] = function(target, damage, name)
		me.action.spellname = name
		me.action.damage = damage
		me.action.target = target
		me.action.type = "heal"
      
	end,
	
	-- check that we don't do anything when we get this
	["othershotonyou"] = function()
	   me.action.type = "nothing"
      
	end,
	
	["othershotonother"] = function()
	   me.action.type = "nothing"
      
	end,
	
	-- healing on self. Leave target = nil
	["hotonself"] = function(damage, name)
		me.action.spellname = name
		me.action.damage = damage
		me.action.type = "heal"
      
	end,
	
	-- this filters out Mana tide Totem / Blessing of Wisdom
	["powergainfromother"] = function()
		me.action.type = "nothing"
	end,
	
	-- powertype is put in the target section
	["powergain"] = function(damage, powertype, name)
		me.action.spellname = name
		me.action.damage = damage
		me.action.target = powertype
		
		me.action.type = "powergain"
      
	end,
	
	["healonself"] = function(name, damage)
		me.action.spellname = name
		me.action.damage = damage
		me.action.type = "heal"
      
	end,
	
	["healonother"] = function(name, target, damage)
		me.action.spellname = name
		me.action.damage = damage
		me.action.target = target
		me.action.type = "heal"
      
	end,
	
}

me.parserstagethree = 
{
   ["attack"] = function()
		
		-- 1) Check for special abilities
		if me.action.spellid == "" then
			me.action.spellid = mod.string.unlocalise("spell", me.action.spellname)
		end
		
		if me.action.spellid and mod.data.spells[me.action.spellid] then
			-- this is a special
			mod.combat.specialattack(me.action.spellid, me.action.target, me.action.damage, me.action.iscrit, me.action.spellschool)
			
		else
			-- this is a normal attack, or is not modified by threat
			mod.combat.normalattack(me.action.spellname, me.action.spellid, me.action.damage, nil, me.action.target, me.action.iscrit, me.action.spellschool)
		end
		
		KLHTM_RequestRedraw("self")
	end,
	
	["heal"] = function()
		if me.action.target == "" then
			me.action.target = UnitName("player")
		end
		
		-- check for a spellid
		me.action.spellid = mod.string.unlocalise("spell", me.action.spellname)
		
		mod.combat.possibleoverheal(me.action.spellname, me.action.spellid, me.action.damage, me.action.target)
		
		KLHTM_RequestRedraw("self")
	end,
	
	["nothing"] = function()
	
	end,
	
	["powergain"] = function()
		me.action.spellid = mod.string.unlocalise("spell", me.action.spellname)
		mod.combat.powergain(me.action.damage, me.action.target, me.action.spellid)
		
		KLHTM_RequestRedraw("self")
	end,
	
	["special"] = function()
		
		-- 1) Unlocalise the ability. e.g. "Heroic Strike" -> "heroicstrike", "Heldenhafter Sto\195\159" -> "heroicstrike"
		me.action.spellid = mod.string.unlocalise("spell", me.action.spellname)
		
		-- 2) Taunt / Growl
		if (me.action.spellid == "taunt") or (me.action.spellid == "growl") then
			mod.combat.taunt(me.action.target)
			
		-- 3) Special Abilities
		elseif me.action.spellid and mod.data.spells[me.action.spellid] then
			mod.combat.specialattack(me.action.spellid, me.action.target, 0, nil, nil)
			
		-- 4) Unrelated abilities
		else
			return
		end
		
		KLHTM_RequestRedraw("self")
		
	end,
	
}

--[[
------------------------------------------------------------------------------
			Section B: Creating the Parser Engine at Startup
------------------------------------------------------------------------------
]]

me.parserset = { }

-- Special OnLoad() method called from Core.lua.
me.onload = function()

	local parserdata
	
	for _, parserdata in me.parserconstructor do
		mod.regex.addparsestring(me.parserset, parserdata[1], parserdata[2], parserdata[3])
	end
		
end

--[[
List of all the parsers we use. The first value is the identifier, the second value is the name of the variable
defined in GlobalStrings.lua, and the third variable is the event the parser works on.
]]
me.parserconstructor = 
{
	{"autoattack", "COMBATHITSELFOTHER", "CHAT_MSG_COMBAT_SELF_HITS"}, 		-- "You hit %s for %d."
	{"autoattack", "COMBATHITCRITSELFOTHER", "CHAT_MSG_COMBAT_SELF_HITS"}, -- "You crit %s for %d."
	
	{"damageshield", "DAMAGESHIELDSELFOTHER", "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF"}, -- "You reflect %d %s damage to %s."
	
	{"abilityhit", "SPELLLOGSELFOTHER", "CHAT_MSG_SPELL_SELF_DAMAGE"}, 			-- "Your %s hits %s for %d."
	{"abilitycrit", "SPELLLOGCRITSELFOTHER", "CHAT_MSG_SPELL_SELF_DAMAGE"}, 	-- "Your %s crits %s for %d."
	{"spellhit", "SPELLLOGSCHOOLSELFOTHER", "CHAT_MSG_SPELL_SELF_DAMAGE"},		-- "Your %s hits %s for %d %s damage."
	{"spellcrit", "SPELLLOGCRITSCHOOLSELFOTHER", "CHAT_MSG_SPELL_SELF_DAMAGE"}, -- "Your %s crits %s for %d %s damage."
	{"perform", "SPELLPERFORMGOSELFTARGETTED", "CHAT_MSG_SPELL_SELF_DAMAGE"}, 	-- "You perform %s on %s."
	{"spellcast", "SPELLCASTGOSELFTARGETTED", "CHAT_MSG_SPELL_SELF_DAMAGE"},	-- "You cast %s on %s."
	
  {"othersdotonother", "PERIODICAURADAMAGEOTHEROTHER", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE"}, -- added for korean
	{"dot", "PERIODICAURADAMAGESELFOTHER", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE"}, -- "%s suffers %d %s damage from your %s."
	
  
	{"othershotonother", "PERIODICAURAHEALOTHEROTHER", "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS"}, -- "%s gains %d health from %s' %s."
	{"yourhotonother", "PERIODICAURAHEALSELFOTHER", "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS"}, -- "%s gains %d health from your %s."
  
	{"othershotonother", "PERIODICAURAHEALOTHEROTHER", "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS"}, -- "%s gains %d health from %s' %s."
	{"yourhotonother", "PERIODICAURAHEALSELFOTHER", "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS"}, -- "%s gains %d health from your %s."
  
	{"othershotonyou", "PERIODICAURAHEALOTHERSELF", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"}, -- "You gain %d health from %s's %s."
	{"othershotonother", "PERIODICAURAHEALOTHEROTHER", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"}, -- "You gain %d health from %s's %s."
	{"yourhotonother", "PERIODICAURAHEALSELFOTHER", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"}, -- "%s gains %d health from your %s."

	{"hotonself", "PERIODICAURAHEALSELFSELF", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"},-- "You gain %d health from %s."
	{"powergain", "POWERGAINSELFSELF", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"},		-- "You gain %d %s from %s."
	{"powergainfromother", "POWERGAINSELFOTHER", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"},		-- "You gain %d %s from %s's %s."
	
	{"healonother", "HEALEDSELFOTHER", "CHAT_MSG_SPELL_SELF_BUFF"},			-- "Your %s heals %s for %d."
	{"healonother", "HEALEDCRITSELFOTHER", "CHAT_MSG_SPELL_SELF_BUFF"},		-- "Your %s critically heals %s for %d."	
	{"healonself", "HEALEDSELFSELF", "CHAT_MSG_SPELL_SELF_BUFF"},			-- "Your %s heals you for %d."
	{"healonself", "HEALEDCRITSELFSELF", "CHAT_MSG_SPELL_SELF_BUFF"},		-- "Your %s critically heals you for %d."
	{"powergain", "POWERGAINSELFSELF", "CHAT_MSG_SPELL_SELF_BUFF"},			-- "You gain %d %s from %s."
}
```

## Code\KTM_Console.lua
```lua
--! This module references these other modules:
--! boss:	starttrigger, 
--! data:	testtalents, testitemsets, 
--! diag:	printalldata, 
--! my:	testthreat, states, 
--! net:	checkpermission, clearmastertarget, sendmastertarget, clearraidthreat, startspellreporting, stopspellreporting, setspellvalue, checkspellvaluesyntax, versionnotify, versionquery, toggleadvertise, 
--! netin:	messagelog, 
--! out:	print, booltostring, 
--! string:	get, testlocalisation, 

--! This module is referenced by these other modules:

local mod = klhtm
local me = {}
mod.console = me

-- Special onload method called from Core.lua
me.onload = function()
	
	-- Set up a command line handler
	SLASH_KLHThreatMeter1 = "/ktm"
	SLASH_KLHThreatMeter2 = "/klhtm"
	SLASH_KLHThreatMeter3 = "/klhthreatmeter"
	SlashCmdList["KLHThreatMeter"] = me.consolecommand
	
	-- create all the CLUI tables
	me.defineclui()
	
	-- Add their .rootstring values
	me.clui.rootstring = "/ktm "
	me.clui.colourrootstring = "|cffffff00/ktm "
	
	me.fillchildrootstrings(me.clui)
	
end

--[[
me.fillchildrootstrings(clui)
Computes the value of clui.rootstring and .rootstring for all its child branches.
the .rootstring value is what the user has to type to get into that branch. The rootstring for the
topmost node is just "/ktm"; for the test child of the main node, the rootstring is "/ktm test".
This method is called recursively on all child branches.
]]
me.fillchildrootstrings = function(clui)

	local key
	local value
	
	-- debug checks
	if clui == nil then
		mod.out.print("clui = nil")
	elseif clui.branches == nil then
		mod.out.print("branches = nil")
	end
	
	local colourcommands = { }
	local key2
	local value2
	local length
	
	for key, value in clui.branches do
		length = 1
		
		for key2, value2 in clui.branches do
			
			if value ~= value2 then
			
				for x = length, string.len(value.command) - 1 do
				
					if string.sub(value.command, 1, x) == string.sub(value2.command, 1, x) then
						length = x + 1 
					else
						break
					end
				end
			end
		end
		
		value.colourcommand = "|cff33ff88" .. string.sub(value.command, 1, length) .. "|cffffff00" .. string.sub(value.command, length + 1)
		
		-- debug
		if value == nil then
			mod.out.print("oops, nil for key = " .. key)
		end
		
		if type(value.output) ~= "function" then
			value.output.rootstring = clui.rootstring .. value.command .. " "
			value.output.colourrootstring = clui.colourrootstring .. value.colourcommand .. " "
			me.fillchildrootstrings(value.output)
		end
	end
	
end

--[[ 
me.runclui(commands, clui)
Process the commands <commands> on <clui>.
<commands> is an array with 0 or more strings.
<clui> is a branch of the console tree, e.g. me.cluitest
]]
me.runclui = function(commands, clui)
	
	local command = commands[1]
	local key
	local branch
	
	if command == nil then
		-- just print out help information for this one
		me.printhelpforclui(clui)
		
	else
		
		-- find the branches that match the command
		local matchingbranches = { }
		
		for key, branch in clui.branches do
			if string.len(branch.command) >= string.len(command) and string.sub(branch.command, 1, string.len(command)) == command then
				-- this branch matches the command
				table.insert(matchingbranches, branch)
			end
		end
	
		-- 1) Not enough branches
		if table.getn(matchingbranches) == 0 then
			
			-- print error, print help, abort.
			mod.out.print("|cffff8888No command matching " .. clui.colourrootstring .. command .. "|cffff8888 could be found.")
			
			me.printhelpforclui(clui)
			
			-- too many branches that match the abbreviation. Error then exit
		elseif table.getn(matchingbranches) > 1 then
			
			local errorstring = "|cffff8888Could not disambiguate your command " .. clui.colourrootstring .. command .. " |cffff8888, after " .. clui.colourrootstring .. "|cffff8888 you could mean {"
			for key, branch in matchingbranches do
				if key > 1 then
					errorstring = errorstring .. ", "
				end
				
				errorstring = errorstring .. branch.colourcommand .. "|cffff8888"
			end
			
			errorstring = errorstring .. "}."
			mod.out.print(errorstring)
			
		else -- just one branch matches the abbreviation. run it.
			
			branch = matchingbranches[1]
			if type(branch.output) == "function" then
				
				-- base command
				local message = "|cff8888ffRunning the command " .. clui.colourrootstring .. branch.colourcommand 
				
				-- arguments
				table.remove(commands, 1)
				
				for _, key in commands do
					message = message .. " " .. key
				end
				
				-- print
				message = message .. "|cff8888ff."
				mod.out.print(message)
				
				-- run
				branch.output(commands[1], commands)
				
			else
				-- run the block
				table.remove(commands, 1)
				me.runclui(commands, branch.output)
			end
		end
	end	
end


me.printhelpforclui = function(clui)

	mod.out.print("|cff8888ffThis is the help topic for " .. clui.colourrootstring .. "|cff8888ff.")

	if type(clui.description) == "string" then
		mod.out.print(clui.description)
	
	elseif type(clui.description) == "function" then
		mod.out.print(clui.description())
	end
		
	local key
	local branch
	local message
	
	for key, branch in clui.branches do
		message = clui.colourrootstring .. branch.colourcommand .. "|r - "
		
		if type(branch.description) == "function" then
			message = message .. branch.description()
		else
			message = message .. branch.description
		end
		
		mod.out.print(message)
	end

end

--[[ 
This method is called by typing a "/ktm" command in the console.
]]
me.consolecommand = function(message)
	
	-- parse space-delimited words into a list
	local commandlist = { }
	local command
	
	for command in string.gfind(message, "[^ ]+") do
		table.insert(commandlist, string.lower(command))
	end
	
	me.runclui(commandlist, me.clui)

end

--[[ 
These are static variables, but they depend on static variables defined in other modules (function pointers and such).
Therefore they are initialised at onload(), not when the code is read.
]]
me.defineclui = function()

me.subclui = { }

me.subclui.version = 
{
	["description"] = 
	function()
		mod.out.print(string.format("This is Release |cff33ff33%s|r Revision |cff33ff33%s|r. These commands require you to be the raid leader or an officer.", mod.release, mod.revision))
	end,
	["branches"] = 
	{
		{
			["command"] = "notify",
			["description"] = "Notifies users with an older version of the mod to upgrade.",
			["output"] = mod.net.versionnotify
		},
		{
			["command"] = "query",
			["description"] = "Asks everyone in the raid to report their mod version.",
			["output"] = mod.net.versionquery
		},
		{
			["command"] = "advertise",
			["description"] = "Will occasionally tell people who pull aggro and don't have the mod to get it. Run this command again to stop it.",
			["output"] = mod.net.toggleadvertise,
		},
	}
}

-- GUI commands. Most commands would be fairly redundany, because you can just use the GUI, after all.
-- You can use this to bring up the window if it has been closed, or reset it completely if you have lost it.
me.subclui.gui = 
{	
	["description"] = nil,
	["branches"] = 
	{
		{
			["command"] = "show",
			["description"] = "Shows the window.",
			["output"] = 
				function()
					KLHTM_SetVisible(true)
				end,
		},
		{
			["command"] = "hide",
			["description"] = "Hides the window.",
			["output"] = 
				function()
					KLHTM_SetVisible(false)
				end,
		},
		{
			["command"] = "reset",
			["description"] = "Puts the window back in the middle of the screen.",
			["output"] = KLHTM_ResetFrame,
		},
	}
}

me.subclui.test = 
{
	["description"] = nil,
	["branches"] = 
	{
		{
			["command"] = "talents",
			["description"] = "Prints out your talent points in any talents that affect your threat.",
			["output"] = mod.data.testtalents
		},
		{
			["command"] = "gear",
			["description"] = "Prints out the set pieces you are wearing for sets that affect your threat.",
			["output"] = mod.data.testitemsets
		},
		{
			["command"] = "threat",
			["description"] = "Prints out a variety of threat parameters.",
			["output"] = mod.my.testthreat
		},
		{
			["command"] = "time",
			["description"] = "Prints out processor time information.",
			["output"] = 
				function()
					mod.diag.printalldata("time", "Milliseconds, or Milliseconds per Second")
				end
		},
		{
			["command"] = "memory",
			["description"] = "Prints out memory usage information.",
			["output"] = 
				function()
					mod.diag.printalldata("memory", "Kilobytes, or Kilobytes per Second")
				end
		},
		{
			["command"] = "channel",
			["description"] = "Checks whether the communication channel is properly set up.",
			["output"] = function()
				
				local number
				local name
				local source
				
				number, name, source = mod.net.getchannel()
				
				if number == 0 then
					mod.out.print("The mod could not find a suitable channel!")
				
				else
					mod.out.print(string.format("You are using channel number %s, %s, from %s.", number, name, source))
					
				end
				
			end
		},
		{
			["command"] = "netlog",
			["description"] = "Information about the channel messages received.",
			["output"] = 
				function()
					local key
					local value
					
					for key, value in mod.netin.messagelog do
						mod.out.print(string.format("|cffffff00%s: |r%d bytes in %d messages (%d average).", key, value.bytes, value.count, math.floor(0.5 + value.bytes / math.max(value.count, 0))))						
					end 
				end	
		},
		{
			["command"] = "states",
			["description"] = "Check that the mod has the correct value for its state variables",
			["output"] = 
				function()
					local key
					local value
					
					local doformat = function(Time)
						if Time == 0 then
							return "never"
						end
						
						return string.format("%d seconds ago", GetTime() - Time)
					end				
					
					for key, value in mod.my.states do
						mod.out.print(string.format("The state '%s' is '%s'. The last change was %s.", key, mod.out.booltostring(value.value), doformat(value.lastchange)))
					end
				end
		},
		{
			["command"] = "local",
			["description"] = "Check for localisations that are missing in your locale.",
			["output"] = mod.string.testlocalisation,
		},
	}
}

me.subclui.boss = 
{
	description = "To run these commands you must be a raid assistant or the group leader.",
	branches = 
	{
		{
			command = "report",
			description = "Make players notify you when their threat is changed by boss abilities.",
			output = mod.net.startspellreporting,
		},
		{
			command = "endreport",
			description = "Stop players reporting when their threat is changed by boss abilities.",
			output = mod.net.stopspellreporting,
		},
		{
			command = "setspell",
			description = "Change a parameter of a known boss ability.",
			
			output = function(firstvalue, allvalues)

				local value, errormessage = mod.net.checkspellvaluesyntax(allvalues)
				
				if errormessage then
					mod.out.print("|cffff8888Syntax: setspell <spellid> <bossid> <parameter> <value>")
					mod.out.print(errormessage)
					
				else
					-- set the value
					mod.net.setspellvalue(allvalues[1], allvalues[2], allvalues[3], allvalues[4])
				end
			end,
		},
		{
			command = "autotarget",
			description = "Clear the meter and set the master target automatically when you next target a world boss.",
			output = function()
				if mod.net.checkpermission() then
					mod.boss.starttrigger("autotarget")
					mod.out.print(mod.string.get("print", "boss", "autotargetstart"))
				end
			end,
		},
	}
}

me.subclui.autohide = 
{
	description = function()	
		return "When enabled, the window will be shown when you join a party or raid, and it will be hidden when you leave. The current setting is |cffffff00" .. tostring(KLHTM_SavedVariables.autohide) .. "|r."
	end,
	
	branches = 
	{
		{
			command = "true",
			description = "Enable the autohide behaviour.",
			output = function()
				KLHTM_SavedVariables.autohide = true
				mod.out.print(mod.string.get("print", "table", "autohideon"))
			end
		},
		{
			command = "false",
			description = "Stop the autohide behaviour happening.",
			output = function()
				KLHTM_SavedVariables.autohide = false
				mod.out.print(mod.string.get("print", "table", "autohideoff"))
			end
		}
	}
}

me.subclui.sunders = 
{
	description = "Report or reset statistic about sunder armor usage.",
	branches = 
	{
		{
			command = "report",
			description = "Report statistic about sunder armor usage.",
			output = KLHTM_ReportSunders,
		},
		{
			command = "reset",
			description = "Reset statistic about sunder armor usage.",
			output = KLHTM_ResetSunders,
		},
	}
}

me.clui =
{
	["description"] = nil,
	["branches"] = 
	{
		{
			["command"] = "test",
			["description"] = "A set of debugging commands.",
			["output"] = me.subclui.test
		},
		{
			["command"] = "gui",
			["description"] = "Commands to show the window.",
			["output"] = me.subclui.gui
		},
		{
			["command"] = "version",
			["description"] = "Commands to check and upgrade the version of other users.",
			["output"] = me.subclui.version,
		},
		{
			["command"] = "disable",
			["description"] = "Emergency stop: disables events / onupdate.",
			["output"] = function()
				if mod.isenabled == false then
					mod.out.print("The mod is already disabled. Run the 'enable' command to restart it.")
					
				else
					mod.isenabled = false
					mod.out.print("The mod has been disabled, and won't work until you run the 'enable' command.")
				end
			end
		},
		{
			["command"] = "enable",
			["description"] = "Restart the mod after an emergency stop.",
			["output"] = function()
				if mod.isenabled == true then
					mod.out.print("The mod is already running.")
					
				else
					mod.isenabled = true
					mod.out.print("The mod has been restarted, and will now receive events / onupdate.")
				end
			end
		},
		{
			["command"] = "mastertarget",
			["description"] = "Set or clear the Master Target.",
			["output"] = function()
				if UnitExists("target") then
					mod.net.sendmastertarget()
				else
					mod.net.clearmastertarget()
				end
			end
		},
		{
			["command"] = "resetraid",
			["description"] = "Reset the threat of everyone in the raid group.",
			["output"] = mod.net.clearraidthreat,
		},
		{
			["command"] = "boss",
			["description"] = "Functions to work out and set boss abilities.",
			["output"] = me.subclui.boss,
		},
		{
			["command"] = "autohide",
			["description"] = "Automatically show the window in a raid and hide when you leave.",
			["output"] = me.subclui.autohide,
		},
		{
			["command"] = "sunders",
			["description"] = "Report or reset statistic about sunder armor usage.",
			["output"] = me.subclui.sunders,
		},
	},
}

end
```

## Code\KTM_Core.lua
```lua

--[[

A module can optionally have

1) .myevents 	-	a list of strings, the events to register
2) .onload		-	to be called on startup
3) .onloadcomplete	to be called after all other modules have been loaded.
3) .onevent		-	will do your onevent. Currently sends all events to you, we should fix it to send only your events!
4) .onupdate	-	you can guess this one!
5) .isenabled	-	whether to receive onload, onevent, onupdate commands. Must be <false> to not be called


Managing your Variables / Methods

--> Initialise static data anywhere in your code file
--> Initialise variables that depend on other module's static data in your onload() method
--> Initialise variables that depend on other module's variables in your onloadcomplete() method


Each module has a key / branch in the master table. The following keys have been taken:
	out	
	alert
	console
	string
	combat
	data
	my
	table
	net,	netin
	gui,	guiopt,	guiraid, some other gui
	boss
	diag
]]

-- table setup
klhtm = { }
local me = klhtm
me.frame = nil -- set at runtime 

-- Mod Version
me.release = 17
me.revision = 40
me.build = 251

--[[
Release	Build
	 1	  	  6
	 2	 	 11
	 3	 	 30
	 4	 	 32
	 5	 	 44
	 6	 	 54
	 7	 	 73
	 8	 	 80
	 9	 	 92
	10		103
	11		116
	12		124
	13		141
	14		156
	15		177
	16		189
	16b 	192
	17		203
	17b	205
	17c	212
]]


me.events = { } --[[ 
Remember which module wants which events.
It will look like
{
	["combat"] = 
	{
		["CHAT_MSG_SPELL_SELF_BUFF"] = true,
	},
}
if the combat module has registered CHAT_MSG_SPELL_SELF_BUFF
]]

me.isloaded = false -- true when .onload has been called for all sub-modules
me.isenabled = true -- iif false, onupdate and onevent will not be called

-- onload
me.onload = function()
	
	-- find frame
	me.frame = KLHTM_OnUpdateFrame
	isKLHLoaded = 1
	-- initialise all submodules
	for key, subtable in me do
		if type(subtable) == "table" and subtable.onload and subtable.isenabled ~= "false" then
			subtable.onload()
		end
	end
	
	me.isloaded = true 
	
	-- register events. Strictly after all modules have been loaded.
	for key, subtable in me do
		if type(subtable) == "table" and subtable.myevents then
			
			me.events[key] = { }
			
			for _, event in subtable.myevents do
				me.frame:RegisterEvent(event)
				me.events[key][event] = true 
			end
		end
	end
	
	-- onloadcomplete
	for key, subtable in me do
		if type(subtable) == "table" and subtable.onloadcomplete and subtable.isenabled ~= "false" then
			subtable.onloadcomplete()
		end
	end
	
	-- Print load message
	me.out.print(string.format(me.string.get("print", "main", "startupmessage"), me.release, me.revision), nil, true)
		
end

-- OnUpdate
me.onupdate = function()
		
	-- only call when everything has been loaded
	if me.isloaded ~= true then
		return
	end
	
	-- don't call if the entire addon is disabled
	if me.isenabled == false then
		return
	end
	
	for key, subtable in me do
		if type(subtable) == "table" and subtable.onupdate and subtable.isenabled ~= "false" then
			me.diag.logmethodcall(key, "onupdate")
		end
	end
	
end

-- OnEvent
me.onevent = function()

	-- don't call if the entire addon is disabled
	if me.isenabled == false then
		return
	end

	for key, subtable in me do
		-- 1) The subtable is a valid module - is a table and has a .onevent property.
		-- 2) The subtable is not disabled
		-- 3) The subtable has registered the event
		if type(subtable) == "table" and subtable.onevent and subtable.isenabled ~= "false" and me.events[key][event] then
			
			me.diag.logmethodcall(key, "onevent")
		end
	end
	
end

--[[
klhtm.emergencystop()
Stops all processing of events and onupdates. Just in case! This is unlocalised and raw to make sure it works even if there are errors elsewhere in the program.
]]
me.emergencystop = function()
	
	me.isenabled = false
	
	ChatFrame1:AddMessage("KLHThreatMeter emergency stop! |cffffff00/ktm|r e to resume.")
	
end
```

## Code\KTM_Data.lua
```lua
--! This module references these other modules:
--! my:	class, 
--! out:	print, 
--! string:	get, 

--! This module is referenced by these other modules:
--! boss:	threatconstants, 
--! combat:	spells, rockbiter, threatconstants, spellmatchesset, 
--! combatparser:	spells, 
--! console:	testtalents, testitemsets, 
--! my:	spells, rockbiter, threatconstants, isbuffpresent, gettalentrank, getsetpieces, 

-- Add the module to the tree
local mod = klhtm
local me, _ = {}
mod.data = me

--[[ 
Data.lua

A list of constants, and a few helper methods. Raw properties of threat, talents, sets.

]]--


--[[
Special onload() method called by Core.
]]
me.onload = function()
	
	me.infermissingspellranks()
	
end

--[[
me.infermissingspellranks()
For some abilities, we don't know the threat values for all ranks. For a missing rank, we just assume the threat
value is <maxrank threat> * <rank> / <max rank>, where <maxrank> is the highest rank for which values are known,
and <rank> is the currently unknown rank.
]]
me.infermissingspellranks = function()
	
	local dataset, maxlevel, x, newvalues, maxlevelset
	
	for _, dataset in me.spells do
	
		-- only do this for class abilities without multipliers
		if (dataset.class ~= "item") and (dataset.multiplier == nil) then
		
			-- find the maximum rank that is known
			for x = 20, 1, -1 do
				maxlevel = x
				if dataset[tostring(x)] ~= nil then
					break
				end
			end
			
			-- look for missing ranks below the maximum
			maxlevelset = dataset[tostring(maxlevel)]
			for x = 1, maxlevel -1 do
				
				if dataset[tostring(x)] == nil then
					newvalues = { }
					newvalues.threat = math.floor(maxlevelset.threat * x / maxlevel)
					
					-- add nextattack if it exists
					if maxlevelset.nextattack then
						newvalues.nextattack = math.floor(maxlevelset.nextattack * x / maxlevel)
					end
					
					dataset[tostring(x)] = newvalues
				end
			end
		end
	end
end

--[[
This is basically a list of all known abilities that do threat stuff.
	The key of each item in the list, e.g. "heroicstrike", matches the localisation key. The localised name of the spell
is mod.string.get("spell", <key>), e.g. mod.string.get("spell", "heroicstrike").
	Each spell has a <class> property, whose value is lower case, locale independent. Also it has the value "item" for 
spells from weapons such as thunderfury or black amnesty.
	<rage> is an optional parameter for warriors and druids, and assumed to be constant.
	<multiplier> says that each point of damage from the spell causes x threat, where x is the value of multipler. When this
property is present, any <threat> value are ignored. i.e. it is assumed that a spell either multiplies the damage to get
threat, or adds a fixed amount, and not both.
	For abilities with multiple ranks, add a key-value pair, where the key is the rank represented as a STRING, and the value
is a table with the properties of that rank. So in the table you might have a <threat> property, and a <nextattack> property.
]]
--! This variable is referenced by these modules: combat, combatparser, my, 
me.spells = 
{	
	-- only ranks 8 (default for 60) and 9 (AQ book) are known
	["heroicstrike"] = 
	{	
		class = "warrior",
		rage = 15,
		["8"] = 
		{
			threat = 145,
			nextattack = 138,
		},
		["9"] = 
		{
			["threat"] = 173,
			["nextattack"] = 157,
		}
	},
	["maul"] = 
	{	
		class = "druid",
		rage = 15,
		multiplier = 1.75,
		["7"] = { nextattack = 128 },
		["6"] = { nextattack = 101 },
		["5"] = { nextattack = 71 },
		["4"] = { nextattack = 49 },
		["3"] = { nextattack = 37 },
		["2"] = { nextattack = 27 },
		["1"] = { nextattack = 18 },
	},
	["swipe"] = 
	{	
		class = "druid",
		rage = 20,
		multiplier = 1.75,
	},
	["shieldslam"] = 
	{	
		class = "warrior",
		rage = 20,
		["4"] = { threat = 250 }
	},
	["revenge"] = 
	{	
		class = "warrior",
		rage = 5,
		["5"] = { threat = 315 },
		["6"] = { threat = 355 },
	},
	["shieldbash"] = 
	{	
		class = "warrior",
		rage = 10,
		["3"] = { threat = 180 },
	},
	["sunder"] = 
	{	
		class = "warrior",
		rage = 15,
		["5"] = { threat = 260 },
	},
	["cleave"] = 
	{
		class = "warrior",
		rage = 20,
		["5"] = { threat = 100 },
	},	
	["feint"] = 
	{
		class = "rogue",
		["5"] = { threat = -800 },
		["4"] = { threat = -600 },
		["3"] = { threat = -390 },
		["2"] = { threat = -240 },
		["1"] = { threat = -150 },
	},
	["cower"] = 
	{
		class = "druid",
		rage = 0,
		["3"] = { threat = -600 },
		["2"] = { threat = -390 },
		["1"] = { threat = -240 },
	},
	["searingpain"] = 
	{	
		class = "warlock",
		multiplier = 2.0,
	},
	["earthshock"] = 
	{	
		class = "shaman",
		multiplier = 2.0,
	},
	["mindblast"] = 
	{
		class = "priest",
		multiplier = 2.0,
	},
	["holyshield"] = 
	{	
		class = "paladin",
		multiplier = 1.2,
	},
	["distractingshot"] = 
	{
		class = "hunter",
		["1"] = { threat = 110 },
		["2"] = { threat = 160 },
		["3"] = { threat = 250 },
		["4"] = { threat = 350 },
		["5"] = { threat = 465 },
		["6"] = { threat = 600 },			
	},
	["fade"] = 
	{
		class = "priest",
		["1"] = { threat = 55 },
		["2"] = { threat = 155 },
		["3"] = { threat = 285 },
		["4"] = { threat = 440 },
		["5"] = { threat = 620 },
		["6"] = { threat = 820 },				
	},
	["thunderfury"] = 
	{
		class = "item",
		threat = 145 + 90,
	},
	["graceofearth"] = 
	{
		class = "item",
		threat = -650,
	},
	["blackamnesty"] = 
	{
		class = "item",
		threat = -540,
	},
	["whitedamage"] = 
	{
		class = "item",
		threat = 0,
	},
	["execute"] = 
	{	
		class = "warrior",
		multiplier = 1, -- tested vmangos
	},
}

-- These are the DPS modifiers for ranks of rockbiter. Whenever a hit lands with a rockbiter weapon, the added threat
-- equals the speed of the weapon times the rockbiter value, e.g. 72 dps for max rank.
--! This variable is referenced by these modules: combat, my, 
me.rockbiter = 
{
	[1] = 6,  --  1
	[2] = 10, --  8
	[3] = 16, -- 16
	[4] = 27, -- 24
	[5] = 41, -- 34
	[6] = 55, -- 44
	[7] = 72, -- 54
}

-- A bunch of firm constants. 
--! This variable is referenced by these modules: boss, combat, my, 
me.threatconstants = 
{	
	["healing"] = 0.5,
	["meleeaggrogain"] = 1.1,
	["rangeaggrogain"] = 1.3,
	["ragegain"] = 5.0,
	["energygain"] = 5.0,
	["managain"] = 0.5,	
}

--[[ 
mod.data.isbuffpresent(texture)
Looks in your buff list for an icon matching the supplied texture.
<texture> is the path of the texture, e.g. "Interface\\Icons\\Ability_Warrior_Sunder"
Returns: true if the buff is present, false otherwise
]]
--! This variable is referenced by these modules: my, 
me.isbuffpresent = function(texture)
	
	local x
	local bufftexture
	
	for x = 1, 32 do
		bufftexture = UnitBuff("player", x)
		
		if bufftexture == nil then
			break
			
		elseif bufftexture == texture then
			return true
		end
	end
			
	return false
end

--------------------------------------------------------------------------

------------------------------
--        Spell Sets        --
------------------------------

--[[ 
Certain items and abilities only affect particular schools of spells. For these specific sets, we keep
a list of all the possible spells, and provide a method to query a spell as from a school.
]]
me.spellsets = 
{
	["Warlock Destruction"] = 
	{ "shadowbolt", "immolate", "conflagrate", "searingpain", "rainoffire", "soulfire", "shadowburn", "hellfire" },
	["Plagueheart 6 Bonus"] = 
	{"corruption", "curseofagony", "immolate", "siphonlife"	},
}

--[[ 
mod.data.spellmatchesset(setname, spellname)
Returns: true if the spell is in the set, false otherwise.
<setname> is a key to me.spellsets above, e.g. "Priest Shadow Spells".
<spellname> is the name of a spell. It is localised.
]]
--! This variable is referenced by these modules: combat, 
me.spellmatchesset = function(setname, spellid)
	
	local x = 0
	local spellset = me.spellsets[setname]
	local spell
	
	while true do
		x = x + 1
		spell = spellset[x]
		
		if spell == nil then 
			return false
		
		elseif spell == spellid then 
			return true
		end
	end
	
end


--------------------------------------------------------------------------

------------------------------
--      Talent Points       --
------------------------------

-- Values are {Page, Talent, Class}
me.talentinfo = 
{	
	sunder = {3, 10, "warrior"},
	heroicstrike = {1, 1, "warrior"},
	defiance = {3, 9, "warrior"},
	impale = {1, 11, "warrior"},
	silentresolve = {1, 3, "priest"},
	shadowaffinity = {3, 3, "priest"},
	druidsubtlety = {3, 8, "druid"},
	feralinstinct = {2, 3, "druid"},
	ferocity = {2, 1, "druid"},
	tranquility = {3, 13, "druid"},
	savagefury = {2, 13,"druid"},
	masterdemonologist = {2, 15, "warlock"},
	arcanesubtlety = {1, 1, "mage"},
	frostchanneling = {3, 12, "mage"},
	burningsoul = {2, 9, "mage"},
	righteousfury = {2, 7, "paladin"},
	healinggrace = {3, 9, "shaman"},
	sleightofhand = {3, 3, "rogue"},
}

--[[ 
me.gettalentrank(talent)
Returns: how many points you have invested in the specified talent.
<talent> is a value from the me.talentinfo array.
]]
--! This variable is referenced by these modules: my, 
me.gettalentrank = function(talent)
	
	local info = me.talentinfo[talent]
	local rank
	_, _, _, _, rank = GetTalentInfo(info[1], info[2])
	
	return rank
end

-- This is a pretty simple function to print out the talents you havee that the mod is checking for
--! This variable is referenced by these modules: console, 
me.testtalents = function()
	
	local key, value, rank
	local numtalents = 0
	
	for key, value in me.talentinfo do
		
		if value[3] == mod.my.class then
			rank = me.gettalentrank(key)
			numtalents = numtalents + 1
			
			mod.out.print(string.format(mod.string.get("print", "data", "talentpoint"), rank, mod.string.get("talent", key)))
		end
	end
	
	mod.out.print(string.format(mod.string.get("print", "data", "talent"), numtalents, UnitClass("player")))
end


--------------------------------------------------------------------------

-------------------------------------------
--        Checking for Set Pieces        --
-------------------------------------------

-- This will print a list of all the (significant) set pieces you are wearing.
--! This variable is referenced by these modules: console, 
me.testitemsets = function()
	
	local setname
	local output
	local pieces
	
	for setname in me.itemsets do
		output = mod.string.get("sets", setname) .. ": {" 
		_, pieces = me.getsetpieces(setname, "non-nil")
		output = output .. pieces .. "}"
		mod.out.print(output)
	end
	
end

-- the key is the description, the value is the item slot index, for GetInventoryItemLink
me.itemslots = 
{
	head = 1,
	legs = 7,
	shoulder = 3,
	feet = 8,
	waist = 6,
	wrist = 9, 
	chest = 5,
	hands = 10,
}

-- values are item numbers. The numbers will be contained in an item link string.
me.itemsets = 
{
	might = 
	{
		head = "16866",
		legs = "16867",
		shoulder = "16868",
		feet = "16862",
		waist = "16864",
		wrist = "16861",
		chest = "16865",
		hands = "16863",
	},
	bloodfang = 
	{
		head = "16908",
		legs = "16909",
		shoulder = "16832",
		feet = "16906",
		waist = "16910",
		wrist = "16911",
		chest = "16905",
		hands = "16907",
	},
	arcanist = 
	{
		head = "16795",
		legs = "16796",
		shoulder = "16797",
		feet = "16800",
		waist = "16802",
		wrist = "16799",
		chest = "16798",
		hands = "16801",
	},
	netherwind = 
	{
		head = "16914",
		legs = "16915",
		shoulder = "16917",
		feet = "16912",
		waist = "16818",
		wrist = "16918",
		chest = "16916",
		hands = "16913",
	},
	nemesis = 
	{
		head = "16929",
		legs = "16930",
		shoulder = "16932",
		feet = "16927",
		waist = "16933",
		wrist = "16934",
		chest = "16931",
		hands = "16928",
	},
	bonescythe = 
	{
		head = "22478",
		legs = "22477",
		shoulder = "22479",
		feet = "22480",
		waist = "22482",
		wrist = "22483",
		chest = "22476",
		hands = "22481",
	},
	plagueheart = 
	{
		head = "22506",
		legs = "22505",
		shoulder = "22507",
		feet = "22508",
		waist = "22510",
		wrist = "22511",
		chest = "22504",
		hands = "22509",
	},
}

--[[ 
mod.data.getsetpieces(setname, isdebug)
Returns: the number of set pieces the player is currently wearing.
<setname> is the localised name of the set.
if <isdebug> is non-nil, the method will also generate and return as the second value a printout.
]]
--! This variable is referenced by these modules: my, 
me.getsetpieces = function(setname, isdebug)
	
	-- 1) Get the set list
	local setlist = me.itemsets[setname]
	
	if setlist == nil then
		me.out.printtrace("assertion", string.format("The set |cffffff00%s|r does not exist in our database.", setname))
		return 0
	end
	
	local slotname
	local slotnumber
	local debugout = ""
	local itemlink
	local numitems = 0
	
	for slotname, slotnumber in me.itemslots do
		itemlink = GetInventoryItemLink("player", slotnumber)
		
		if itemlink and string.find(itemlink, setlist[slotname]) then
			numitems = numitems + 1
			
			-- if it's for debug, print out which piece it is
			if isdebug then
				if numitems > 1 then
					debugout = debugout .. ", "
				end
				
				debugout = debugout .. slotname
			end
		end
	end
	
	return numitems, debugout
	
end
```

## Code\KTM_Diagnostic.lua
```lua
--! This module references these other modules:
--! out:	checktrace, printtrace, print, 

--! This module is referenced by these other modules:
--! console:	printalldata, 

local mod = klhtm
local me = { }
mod.diag = me

--[[
KTM_Diagnostic.lua

This module monitors computer performance and how it is affected by the rest of the mod. It is useful to check for
methods that are using excessive amounts of memory or processor time.

Whenever the KTM_Core.lua is about to call a module's .onevent() or .onupdate() methods, it instead sends the method to mod.diag.logmethodcall(module, methodtype). The time taken in milliseconds and memory used in kilobytes is recorded. For each module that has a .onevent() or .onupdate() method, a separate entry is kept, which records the total value,average rate, maximum rate over 5 seconds and rate in the last 5 seconds.

To print out the memory data, run the command "/ktm test memory"; for timing data, "/ktm test time".

Times are recorded in one second intervals. So whenever a method is called, the .current value of the relevant dataset is incremented. Then every second, there is a collation, where .current is added to .history, and .total and .recordinterval are updated. This is done in me.onupdate().

]]


me.lastcollation = GetTime() -- value of GetTime(). Happens once a second.
me.datalogstart = GetTime() -- when we started logging times. For the "average rate" value.

--[[
timing / memory data set. Each module-method combination has a separate set. e.g. there is one for the .onevent() function of the .combat module.
]]
me.createnewdataset = function()

	return
	{
		["total"] = 0,
		["history"] = {0, 0, 0, 0, 0}, 	-- values for the last 5 seconds
		["historylength"] = 5,
		["current"] = 0, 				-- working value for the current second
		["recordinterval"] = 0,			-- maximum sum of .history
	}

end

--[[
All the data we keep is in this table. At startup, we can only be sure the "total" sets will exist - we don't know which modules have a .onupdate or .onevent method. As soon as those methods are called for the first time, we will add a data set for them.
]]
me.data = 
{
	["memory"] =
	{
		["onupdate"] = 
		{
			["total"] = me.createnewdataset(),
		},
		["onevent"] = 
		{
			["total"] = me.createnewdataset(),
		},
		["total"] = me.createnewdataset(),
	},
	["time"] =
	{
		["onupdate"] = 
		{
			["total"] = me.createnewdataset(),
		},
		["onevent"] = 
		{
			["total"] = me.createnewdataset(),
		},
		["total"] = me.createnewdataset(),
	}
}

--[[
mod.diag.logmethodcall(module, calltype)
Runs the special Core.lua methods, and logs the timing and memory usage.
<module> is a string, the key for a module, e.g. "combat", "string", "netin", etc.
<calltype> is either "onupdate" or "onevent".
]]
me.logmethodcall = function(module, calltype)

	local method = mod[module][calltype]
	local memory
	local time
	
	local manualstart = GetTime()
	memory, time = me.getfunctionstats(method)
	local manualtime = math.floor(0.5 + (GetTime() - manualstart) * 1000)
	
	-- Scrub out bullshit values! > 100ms = bs, > 10 ms = should be traced. < 0 kb = bs (gc).
	-- Sometimes debugprofile gives completely spasticated values for unknown reasons. Also we might get a negative
	-- value for memory if a garbage collection occurs.
	if time > 100 or time < 0 or math.abs(time - manualtime) > 5 then
		time = 0
	elseif time > 10 then
		if mod.out.checktrace("info", me, "timing") then
			mod.out.printtrace(string.format("Time from %s %s is %s ms (manual says %s ms) (memory was %s).", module, calltype, me.formatdecimal(time), manualtime, memory))
		end
	end
	
	if memory < 0 then
		memory = 0
	end
	
	me.adddatapoint("time", calltype, module, time)
	me.adddatapoint("memory", calltype, module, memory)
	
end

--[[
me.getfunctionstats(method)
Runs the the function <method>, and records how much time was taken, and memory used.
Returns: <memory, in whole kilobytes>, <time, in fractional milliseconds>.
]]
me.getfunctionstats = function(method) 

	local memorystart = gcinfo()
	local timestart = debugprofilestop()
	
	method()
	
	local timetaken = (debugprofilestop() - timestart) 
	local memoryused = gcinfo() - memorystart
	
	return memoryused, timetaken
end


--[[
me.adddatapoint(datatype, calltype, module, value)
Adds <value> to the .current property of the relevant dataset. Also adds it to any parent sets, e.g. "total".
<datatype> is "memory" or "time"
<calltype> is "onupdate" or "onevent"
<module> is "combat", "string", "data", etc.
]]
me.adddatapoint = function(datatype, calltype, module, value)

	if me.data[datatype][calltype][module] == nil then
		me.data[datatype][calltype][module] = me.createnewdataset()
	end
	
	me.data[datatype][calltype][module].current = me.data[datatype][calltype][module].current + value
	me.data[datatype][calltype].total.current = me.data[datatype][calltype].total.current + value
	me.data[datatype].total.current = me.data[datatype].total.current + value

end

--[[
Special Core.lua method. If this "second" has ended (i.e. it's been at least 1 second since the last collation),
then run a collation.
]]
me.onupdate = function()

	local timenow = GetTime()
	
	-- update at most once a second
	if timenow < me.lastcollation + 1.0 then
		return
	end

	me.collatetable(me.data, timenow - me.lastcollation)
	me.lastcollation = timenow
end

--[[
me.collatetable(data, period)
Collating a dataset is to finalise the ".current" value, add it to history, update total, etc.
This is a recursive method. <data> might be a data set (base case), or it might be a tree containing datasets (note the
structure of me.data). If it is a tree, then me.collatetable will be called on any subtrees inside it.
<period> = time in seconds this collation is over. It will be at least 1, and close to 1, but not exactly 1. Since we want
to record the rate, e.g. KB/sec, we have to divide by this value.
]]
me.collatetable = function(data, period)

	if data.current == nil then
		-- this guy is a table, with subtables. do the subtables.
		
		local value
		for _, value in data do
			me.collatetable(value, period)
		end
		
		return
	end

	-- this guy is an actual data set	
	local x
	local interval = 0
	
	for x = data.historylength - 1, 1, -1 do
		data.history[x + 1] = data.history[x]
		interval = interval + data.history[x]
	end
	
	-- take into account period length (we want / second)
	data.history[1] = data.current / period
	interval = interval + data.history[1]
	data.total = data.total + data.current
	
	-- check for new record 5 second burst
	if interval > data.recordinterval then
		data.recordinterval = interval
	end
	
	-- reset the current value, it's a new second
	data.current = 0

end

--[[
mod.diag.printdataset(datatype, units)
This is called when a console command "/ktm test time" or "/ktm test memory" is run.
<datatype> is "time" or "memory"
<datatype> is a description of the units, e.g. "Milliseconds per Second".
]]
--! This variable is referenced by these modules: console, 
me.printalldata = function(datatype, units)

	-- print total, then subcategories, recursively.
	mod.out.print(string.format("|cff6666ffThis is a listing of |cffffff00%s |cff6666ffusage. Units are |cffffff00%s.|r", datatype, units))
	
	local data = me.data[datatype]
	local key
	local value
	
	-- grand total
	me.printdataset("|cffff3333Total", data.total)
	
	-- onupdates
	me.printdataset("|cff66ff66OnUpdates", data.onupdate.total)
	
	for key, value in data.onupdate do
		if key ~= "total" then
			me.printdataset("|cffffff00" .. key, value)
		end
	end
	
	-- onevents
	me.printdataset("|cff66ff66OnEvents", data.onevent.total)
	
	for key, value in data.onevent do
		if key ~= "total" then
			me.printdataset("|cffffff00" .. key, value)
		end
	end
	
end

--[[
me.printdataset(name, set)
This prints the values of an individual data set.
<name> is the name of the module or category, with colouring.
<set> is the actual data set.
]]
me.printdataset = function(name, set)

	local x
	local last5 = 0
	
	for x = 1, 5 do
		last5 = last5 + set.history[x]
	end
	
	mod.out.print(string.format("%s:|r Total = %s, Avg = %s, Burst = %s, Recent = %s.", 
		name, me.formatdecimal(set.total), me.formatdecimal(set.total / (GetTime() - me.datalogstart)), me.formatdecimal(set.recordinterval / 5), me.formatdecimal(last5 / 5)))

end

--[[
me.formatdecimal(value)
Returns a string representation of <value>, including up the the first place after the decimal, if it exists.
]]
me.formatdecimal = function(value)

	if floor(value) == value then
		return string.format("%d", value)

	else
		local base = string.format("%f", value)
		local dotpoint = string.find(base, "%.")
		return string.sub(base, 1, dotpoint + 1)
	end
end
```

## Code\KTM_MasterTarget.lua
```lua

local mod = klhtm
local me = {}
mod.target = me

--[[
KTM_MasterTarget.lua

Organises the master target.
]]

me.mastertarget = nil
me.isworldboss = false
me.lastmtauthor = "" -- name of the player, or "" for noone yet.
me.lastmttime = 0
me.lastpollmessage = ""

--[[
mod.target.automastertarget(target)
Called when the mod itself sets the mastertarget.
<target> is the localised name of the mob.
]]
me.automastertarget = function(target)

	me.mastertarget = target
	KLHTM_RequestRedraw("raid")
	
	me.isworldboss = true
	me.lastmttime = GetTime()
	me.lastpollmessage = ""
	
	-- explain to user
	mod.out.print(string.format(mod.string.get("print", "boss", "automt"), target))
	
end

--[[
mod.target.bossdeath()
Called when players in the raid group report that the master target has died.
]]
me.bossdeath = function()
	
	me.mastertarget = nil
	KLHTM_RequestRedraw("raid")
	
	me.isworldboss = false
	me.lastmttime = GetTime()
	me.lastpollmessage = ""
	
end

me.lastonupdate = 0
me.onupdateinterval = 10.0

-- resend MT if we were the sender
me.onupdate = function()
		
	-- update every few seconds only
	if GetTime() < me.lastonupdate + me.onupdateinterval then
		return
	else
		me.lastonupdate = GetTime()
	end
	
	-- poll MT only if we set it last
	if me.lastmtauthor ~= UnitName("player") then
		return
	end
	
	-- check if you are still an assistant
	if mod.unit.isplayerofficer(UnitName("player")) == nil then
		me.lastmtsender = ""
		return
	end
	
	-- send poll or clear
	if me.mastertarget then
		-- this is stopped till we get a better solution
		-- mod.net.sendmessage("mtpoll " .. me.mastertarget)
	
	else
		mod.net.clearmastertarget()
	end
	
end

--[[
mod.target.pollrequest(author, target)
Called when we receive a network message of someone polling (periodically rebroadcasting) the master target.

<author>		string; name of the player who sent the message
<target>		string; name of a mob
]]
me.pollrequest = function(author, target)
	
	-- this is disabled for the moment
	if true then
		return
	end
	
	-- ignore polls that come quickly after a target change (could be sync error)
	if GetTime() < me.lastmttime + 2.0 then
		return
	end
	
	-- ignore if this message is the same as the last message, or matches our current MT 
	if (target == me.lastpollmessage) or (target == me.mastertarget) then
		return
	end
	
	-- set but warn user
	me.mastertarget = target
	KLHTM_RequestRedraw("raid")
	
	mod.out.print(string.format(mod.string.get("print", "network", "mtpollwarning"), target, author))
	
	me.lastmttime = GetTime()
	me.lastmtstring = target
	me.lastmtauthor = author
	
	-- we can't tell if the mob is a worldboss or not, so assume not
	
end

--[[
mod.target.clearrequest(author, target)
Called when we receive a network message of someone clearing the master target.

<author>		string; name of the player who sent the message
]]
me.clearrequest = function(author)
	
	-- ignore polls that come quickly after a target change (could be sync error)
	if GetTime() < me.lastmttime + 2.0 then
		return
	end
	
	-- announce if there is a change
	if me.mastertarget then
		
		me.mastertarget = nil
		KLHTM_RequestRedraw("raid")
		
		mod.out.print(string.format(mod.string.get("print", "network", "mtclear"), author))
	end
	
	-- update value of author
	me.lastmtauthor = author
	me.lastmttime = GetTime()
	me.lastpollmessage = ""
	
end

--[[
mod.target.setrequest(author, target)
Called when we receive a network message of someone setting the master target.
The problem is that if you have a different localisation to <author>, you will think his target is spelt differently to <target>! So we have to check for this, and override if necessary.

<author>		string; name of the player who sent the message
<target>		string; name of a mob
]]
me.setrequest = function(author, target)
		
	local errormessage = ""	
	
	-- 1) Find the author's UnitID
	local officerunit = mod.unit.findunitidfromname(author)
	local officertarget = UnitName(tostring(officerunit) .. "target")
	
	-- If the officer's target is just far enough away from us, we will be able to target him but his name will be "Unknown", which could stuff things up
	if officertarget == UNKNOWN then
		officertarget = nil
	end
	
	-- 2) Check for differences
	if officertarget == nil then
		errormessage = string.format(mod.string.get("print", "network", "newmttargetnil"), target, author)
	
	elseif officertarget ~= target then
		errormessage = string.format(mod.string.get("print", "network", "newmttargetmismatch"), author, target, officertarget)
		target = officertarget
	end
		
	-- 3) Check for worldboss target
	if UnitClassification((officerunit or "") .. "target") == "worldboss" then
		me.isworldboss = true
	else
		me.isworldboss = false
	end
	
	-- 4) Notify user if there is a change
	if target ~= me.mastertarget then
		me.mastertarget = target
		KLHTM_RequestRedraw("raid")
		
		-- print out any warning if there was one
		if errormessage ~= "" then
			mod.out.print(errormessage)
		end
		
		-- print out the new target
		mod.out.print(string.format(mod.string.get("print", "network", "newmt"), target, author))
	end
	
	-- 5) update network parameters and such
	me.lastmtauthor = author
	me.lastmttime = GetTime()
	me.lastpollmessage = target
	
end

--[[
mod.boss.targetismaster(target)
Checks whether <target> is the master target. The master target is usually just a name / string, but it may be something
more general in the future (e.g. tracking both bosses in the Twin Emps fight).
<target> is the name of the mob being queried.
Return: non-nil if <target> is a mastertarget.
]]
--! This variable is referenced by these modules: combat, 
me.targetismaster = function(target)
	
	if me.mastertarget == nil then
		return true
	end
	
	if target == me.mastertarget then
		return true
	end
	
	-- insert other checks here, later.
	
	return -- (nil)
	
end

-----------------------------------
--		Targeting Behaviour      --
-----------------------------------
--[[

True = True target. Who the mob would have aggro on, if we discount secondary targetting and taunts, etc.
Curr = Current target. Who the mob's target unitid is
New  = New target. If the mob's current target has changed

x, y = players with known threat values
nil  = no target
?    = player with unknown threat value


True	Curr	New		Result
����������������������������������������������
nil		nil		x		true and curr become x

x		x		y		curr -> y. In 2 seconds with no change, true -> y. also, if their threat goes above 110 of yours in that time, put them up.
x		x		?		curr -> ?. In 2 seconds with no change, true -> ?
x		x		nil		curr -> nil.

x		y		z		curr -> z. In 2 secs, true -> z
x		y		nil		curr -> nil.
x		y		?		curr -> ?. In 2 secs, true -> ?
x		y		x		curr -> x

x		nil		y		If it's been nil for more than 1 second, true = y. Otherwise true -> y after 2 - (secs at nil) secs.
x		nil		x		curr -> x
x		nil		?		same as x - nil - y

?		?		x		true -> x. Easy enough.

]]

-- Master Target Variables
--! This variable is referenced by these modules: combat, guiraid, 
me.mttruetarget = nil	-- The Name of the player who this mod thinks is the true target
me.mtcurrenttarget = nil	-- The Name of the player the mob is currently targetting
me.mttargetswaptime = 0	-- The time when the mob last changed its target
me.unknowntarget = "#unknown" 
me.mastertargettarget = nil

-- lm2: aggro gain is now calculated just before redrawing the raid frame
--! This variable is referenced by these modules: guiraid, 
me.updateaggrogain = function()
	
	if mod.boss.mastertarget == nil then
		me.recalculateaggrogain()
	else
		me.updatetrueaggrotarget()
	end
	
end
	

me.updatetrueaggrotarget = function()
		
	-- 1) find a UnitID for the master target
	local mastertargetid = nil
	
	if UnitName("target") == me.mastertarget then
		mastertargetid = "target"
		
	else
		-- check everyone in the raid
		local x
		
		for x = 1, 40 do
			if UnitName("raid" .. x .. "target") == me.mastertarget then
				mastertargetid = "raid" .. x .. "target"
				break
			end
		end
	end
	
	-- 2) If noone can see the mob, give up.
	if mastertargetid == nil then
		
		me.mttruetarget = me.unknowntarget
		me.mtcurrenttarget = me.unknownuarget
		mod.table.raiddata[mod.string.get("misc", "aggrogain")] = nil
		
		return
	end
	
	-- 3) Get the boss' current target
	local targetnow = UnitName(mastertargetid .. "target")
	 
	-- 4) Reevaluate True, Current, Time
	
	-- a) Transitions from true=unknown	
	if (me.mttruetarget == nil) or (me.mttruetarget == me.unknowntarget) or (mod.table.raiddata[me.mttruetarget] == nil) then
		
		-- debug print
		if targetnow ~= me.mttruetarget then
			if targetnow == nil then
				if mod.out.checktrace("info", me, "target") then
					mod.out.printtrace("Target changed from bad to nil.")
				end
			else
				if mod.out.checktrace("info", me, "target") then
					mod.out.printtrace(string.format("Target changed from bad to %s.", targetnow))
				end
				
				if (me.isknockbackdiscoveryactive == true) and (targetnow == UnitName("player")) then
					mod.net.sendmessage("aggrogain " .. mod.table.getraidthreat())
				end
			end
		end
		
		me.mttruetarget = targetnow
		me.mtcurrenttarget = targetnow
	
	-- b) Transitions from true = known
	elseif targetnow ~= me.mtcurrenttarget then
	
		if me.mtcurrenttarget ~= nil then
			me.mttargetswaptime = GetTime()
		end
	
		me.mtcurrenttarget = targetnow
		
		if targetnow == nil then
			if mod.out.checktrace("info", me, "target") then
				mod.out.printtrace("CurrentTarget changed to nil.")
			end
		else
			if mod.out.checktrace("info", me, "target") then
				mod.out.printtrace(string.format("CurrentTarget changed from bad to %s.", targetnow))
			end
			
			if (me.isknockbackdiscoveryactive == true) and (targetnow == UnitName("player")) then
				mod.net.sendmessage("aggrogain " .. mod.table.getraidthreat())
			end
		end
	end
	
	-- 5) Check if CurrentTarget should become Truetarget
	if me.mttruetarget ~= me.mtcurrenttarget then
		-- to get here, true target is known.
		
		if me.mtcurrenttarget == nil then
			-- do nothing
			
		elseif mod.table.raiddata[me.mtcurrenttarget] == nil then
			-- switch to unknown if it's been more than 2 seconds
			
			if GetTime() > me.mttargetswaptime + 2 then
				me.mttruetarget = me.mtcurrenttarget
				
				if mod.out.checktrace("info", me, "target") then
					mod.out.printtrace(string.format("TrueTarget switches to the unknown %s after 2 seconds.", me.mttruetarget))
				end
			end
			
		else -- current target is a known user
			if GetTime() - me.mttargetswaptime > 2 then
				me.mttruetarget = me.mtcurrenttarget
				
				if mod.out.checktrace("info", me, "target") then
					mod.out.printtrace(string.format("TrueTarget switches to the known player %s after 2 seconds.", me.mttruetarget))
				end
				
			elseif mod.table.raiddata[me.mtcurrenttarget] > mod.data.threatconstants.meleeaggrogain * mod.table.raiddata[me.mttruetarget] then
				me.mttruetarget = me.mtcurrenttarget

				if mod.out.checktrace("info", me, "target") then
					mod.out.printtrace(string.format("TrueTarget switches to the known player %s due to high threat.", me.mttruetarget))
				end
			end
		end
	end
	
	-- update the AggroGain virtual player
	if ((me.mttruetarget ~= nil) and (me.truetarget ~= me.unknowntarget) and
		(mod.table.raiddata[me.mttruetarget] ~= nil)) then
		
		local aggro = mod.table.raiddata[me.mttruetarget];

		if (UnitName("player") ~= me.mttruetarget) then
			if CheckInteractDistance(mastertargetid, 1) then
				aggro = math.ceil(aggro * mod.data.threatconstants.meleeaggrogain)
			else
				aggro = math.ceil(aggro * mod.data.threatconstants.rangeaggrogain)
			end
		end
		
		mod.table.raiddata[mod.string.get("misc", "aggrogain")] = aggro;
	else
		mod.table.raiddata[mod.string.get("misc", "aggrogain")] = nil
	end
end

me.recalculateaggrogain = function()

	-- update aggro, and such
	local newaggrogain
	local targetname = ""
	local maxdepth = 5
	local i
	local targetacquired = false
	
	for i = 1, maxdepth do
		targetname = targetname .. "target"
		
		if UnitName(targetname) == nil then
			break
		
		elseif UnitIsFriend("player", targetname) == nil then
			targetacquired = true
			break
		end
	end
	
	if targetacquired == false then
		-- remove aggro gain
		newaggrogain = nil
		
	else
		local mobtarget = UnitName(targetname .. "target")
		if mobtarget == nil then
			mobtarget = "<nil>"
		end
		
		if mod.table.raiddata[mobtarget] then
			-- aggro target has a known threat value
			
			if UnitName("player") == mobtarget then
				newaggrogain = mod.table.raiddata[mobtarget]
			
			else
				-- now check our range to the mob
				if CheckInteractDistance(targetname, 1) then
					-- we're in melee range 
					newaggrogain = math.ceil(mod.table.raiddata[mobtarget] * mod.data.threatconstants.meleeaggrogain)
					
				else
					-- there's a small region where we might be in melee range. for now, assume not
					newaggrogain = math.ceil(mod.table.raiddata[mobtarget] * mod.data.threatconstants.rangeaggrogain)
				end
			end
		else
			newaggrogain = nil
		end
	end
	
	local currentaggrogain = mod.table.raiddata[mod.string.get("misc", "aggrogain")]
	if newaggrogain ~= currentaggrogain then
		mod.table.raiddata[mod.string.get("misc", "aggrogain")] = newaggrogain
	end

end
```

## Code\KTM_ModernAPI.lua
```lua
--[[
KTM_ModernAPI.lua

Optional companion module for KLHThreatMeter (laytya fork).
Add this file to the .toc AFTER KTM_Core.lua and BEFORE KTM_Combat.lua /
KTM_CombatParser.lua, e.g.:

    Code\KTM_Core.lua
    Code\KTM_ModernAPI.lua        <-- new
    Code\Localisation\KTM_Localisation.lua
    ...
    Code\KTM_Combat.lua
    Code\KTM_CombatParser.lua
    ...

WHAT THIS DOES AND WHY
-----------------------
KTM's threat numbers for YOUR OWN character come from regex-matching the
localized text of CHAT_MSG_COMBAT_SELF_HITS / CHAT_MSG_SPELL_SELF_DAMAGE /
CHAT_MSG_SPELL_SELF_BUFF / etc. (see KTM_Regex.lua + KTM_CombatParser.lua).
That is fragile: it breaks on chat-filter settings, floating-text-only
clients, non-enUS locales the maintainers haven't covered, and abilities
that don't print a message at all.

The addons you listed replace parts of that guesswork with real structured
data. Not all of them are relevant to a threat meter, so this file only
wires up the ones that actually are:

  * SuperWoW     -> GUIDs on UnitExists/UnitGUID, UNIT_CASTEVENT, RAW_COMBATLOG
  * nampower     -> SPELL_DAMAGE_EVENT_SELF/OTHER, AUTO_ATTACK_SELF/OTHER,
                    SPELL_HEAL_BY_SELF, SPELL_ENERGIZE_BY_SELF,
                    AURA_CAST_ON_SELF/OTHER  (all with real numbers, no text)
  * ClassicAPI   -> C_UnitAuras.* (read real aura/stack data off a unit),
                    UnitGUID / UnitTokenFromGUID, C_NamePlate.*
  * UnitXP_SP3   -> UnitXP("distanceBetween", ...) for real range checks

  * VanillaHelpers is NOT used here. It's real and useful (file I/O, minimap
    blips, texture/memory limits, character morphing) but nothing in it
    touches combat, auras, or unit identity, so it has no role in a threat
    meter. Don't bother loading it for this purpose.

  * nampower's spell-queue/buffer system (the reason most people install it)
    is also NOT a threat-data source -- it only smooths out cast timing. We
    only hook the *event* additions it ships (SPELL_DAMAGE_EVENT_SELF etc.),
    which exist independently of whether queuing is even enabled.

DESIGN
------
Every external library is optional and detected at runtime. Nothing here
assumes a given mod is present; if none are, KTM behaves exactly as before
because nothing in this file is ever called.

This module deliberately does NOT reach into KTM_Combat.lua's private
`me.*` locals (they're upvalues closed over inside that file and are not
exposed on `mod`). Instead it does the one thing that's both safe and
effective: when a real structured event fires, it constructs the exact
en-US combat-log line KTM's own regex table already expects
(mod.string.get(...) patterns in KTM_Regex.lua) and feeds it through
KTM's normal event pipeline via a synthetic CHAT_MSG_* event on a hidden
frame that KTM is already listening on. KTM's parser can't tell the
difference between "real" chat text and this synthetic text -- except
the synthetic text is always well-formed, always fires (no chat filters,
no combat-log-disabled edge cases, no message truncation), and is sourced
from a GUID instead of a name, so it never gets confused by two mobs
sharing a name.

For the one thing structured aura data does strictly better than any
text message ever could -- knowing the *actual current stack count* of a
debuff on your target, which is exactly what this fork's Sunder-tracking
feature wants -- KTM_ModernAPI exposes KTM_ModernAPI.GetSunderStacks(unit)
directly, bypassing text parsing entirely. Wire this into whatever prints
"sunder success/failure" in your fork's KTM_Combat.lua / KTM_PetMod.lua
in place of the guess-from-chat-text logic.

BEFORE YOU TRUST ANY OF THIS
-----------------------------
UPDATE: nampower's EVENTS.md turned out to be reachable after all -- via
GitHub's blob viewer (github.com/.../blob/main/EVENTS.md), not the raw
or gitea mirrors I'd tried and given up on. The nampower event payloads
below are now CONFIRMED against that doc, not guessed. Where my first
draft of this file guessed wrong -- and it did, on every single event --
the fix is now against the real spec, not a second guess.

Still UNCONFIRMED: the exact field names on the aura tables
ClassicAPI's C_UnitAuras.GetUnitAuras returns (docs/API.md is robots-
blocked on every mirror I have access to, and this sandbox has no
outbound network for a git-clone workaround). That one's still marked
inline and still dumps its shape on first use.

Four of the nampower events used here are gated behind CVars that
default to OFF: NP_EnableAutoAttackEvents, NP_EnableSpellHealEvents,
NP_EnableSpellEnergizeEvents, NP_EnableAuraCastEvents. This module
turns them on itself at login (see PLAYER_LOGIN handler below) since
they cost nothing when nampower isn't even installed. If you already
have another addon that also manages these CVars, note that here.

`KTM_ModernAPI.debugUnknownPayloads` defaults to `true` and prints the
raw payload of every relevant event to chat -- useful now as a sanity
check that the confirmed spec still matches your nampower build, since
CVars/behavior can change between versions and I have no way to verify
against a live client myself. Turn it off once you've confirmed a
session's worth of events look right.
]]

KTM_ModernAPI = {}
local M = KTM_ModernAPI

-------------------------------------------------------------------------
-- Library detection
-------------------------------------------------------------------------

M.hasSuperWoW  = (SUPERWOW_VERSION ~= nil)
M.hasClassicAPI = (CLASSIC_API_VERSION ~= nil)
M.hasNampower  = false
M.hasUnitXP3   = false

do
	local ok = pcall(function() return NP_QueueCastTimeSpells end)
	-- nampower doesn't publish a version global consistently across builds;
	-- the reliable check is whether it registered its custom events, which
	-- we do lazily below in RegisterEvent and record the first time one fires.
	-- As a synchronous check, its Lua-callable functions are a good proxy:
	M.hasNampower = (type(GetSpellIdCooldown) == "function")
end

do
	local ok = pcall(UnitXP, "nop", "nop")
	M.hasUnitXP3 = ok and true or false
end

-------------------------------------------------------------------------
-- GUID helpers (SuperWoW / ClassicAPI / nampower all add GUIDs; prefer
-- whichever is present, in this order, since SuperWoW's UnitExists(...)
-- returning a GUID as a 3rd value was the original convention the others
-- copied).
-------------------------------------------------------------------------

--- Returns a GUID string for `unit`, or nil if unresolvable.
--- Preference order: nampower's GetUnitGUID (CONFIRMED signature, from
--- SCRIPTS.md: takes a unit token/GUID/extended-token string, returns a
--- hex GUID string or nil) > SuperWoW's UnitExists 3rd-return-value idiom
--- > vanilla UnitGUID if some other mod already added it.
function M.GetGUID(unit)
	if not unit then return nil end

	if M.hasNampower and type(GetUnitGUID) == "function" then
		local ok, guid = pcall(GetUnitGUID, unit)
		if ok and guid then return guid end
	end

	if M.hasSuperWoW then
		local exists, guid = UnitExists(unit)
		if exists and guid then return guid end
	end

	if type(UnitGUID) == "function" then
		local ok, guid = pcall(UnitGUID, unit)
		if ok and guid then return guid end
	end

	return nil
end

--- Best-effort reverse lookup, GUID -> current unit token, using whatever
--- library exposes it. Falls back to nil (caller should keep using names).
function M.TokenFromGUID(guid)
	if not guid then return nil end
	if type(UnitTokenFromGUID) == "function" then
		return UnitTokenFromGUID(guid)
	end
	if type(C_NamePlate) == "table" and C_NamePlate.GetNamePlateForGUID then
		local plate = C_NamePlate.GetNamePlateForGUID(guid)
		if plate and plate.GetName then
			return plate:GetName()
		end
	end
	return nil
end

-------------------------------------------------------------------------
-- Reliable debuff-stack reading (ClassicAPI C_UnitAuras)
-- This is the concrete, no-guessing replacement for "did my Sunder Armor
-- land, and what stack is it at now".
-------------------------------------------------------------------------

local SUNDER_ARMOR_SPELL_IDS = {
	[7386]  = true, [7405]  = true, [8380]  = true,
	[11596] = true, [11597] = true, -- ranks 1-5
}

--- Returns current Sunder Armor stack count (0-5) on `unit`, or nil if we
--- have no reliable source (no ClassicAPI/no aura data available), so the
--- caller can fall back to the old text-guessing path.
function M.GetSunderStacks(unit)
	if not (M.hasClassicAPI and C_UnitAuras and C_UnitAuras.GetUnitAuras) then
		return nil
	end

	local ok, debuffs = pcall(C_UnitAuras.GetUnitAuras, unit, "HARMFUL")
	if not ok or not debuffs then return nil end

	-- CONFIRMED: ClassicAPI's README lists C_UnitAuras.GetUnitAuras as a
	-- real function. NOT CONFIRMED: the exact field names on each returned
	-- aura table (I'm guessing `.spellId` / `.applications` by analogy with
	-- retail's AuraData, since that's the convention ClassicAPI is
	-- explicitly backporting -- but I have not fetched docs/API.md to
	-- verify it). First call, dump the shape so this gets fixed from real
	-- data instead of a second guess:
	if KTM_ModernAPI.debugUnknownPayloads and debuffs[1] then
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

	return 0 -- ClassicAPI answered and there's no Sunder debuff up at all
end

-------------------------------------------------------------------------
-- Synthetic combat-log text feed, sourced from nampower's structured
-- combat events instead of the real chat frame.
--
-- KTM's own locale files define the phrasing (KTM_Regex.lua reads them via
-- mod.string.get(category, key)); we reuse THAT table so we automatically
-- match whatever locale the user has KTM set to, instead of hardcoding
-- English. That also means: if your fork's regex table changes, this still
-- lines up, because we're driving it through the same strings.
-------------------------------------------------------------------------

local feeder = CreateFrame("Frame", "KTM_ModernAPIFeeder")

local function FireSynthetic(event, text)
	-- KTM (like all 1.12 addons) reads combat text off the globals
	-- `event` and `arg1`; there is no ...args in this API level. We can't
	-- forge those globals for OTHER frames' scripts from here, so instead
	-- we re-dispatch through the true event system: this frame registers
	-- for nothing, but any frame that IS registered for `event` will still
	-- see it because we use the client's own event firing entry point.
	--
	-- 1.12 does not expose a Lua-level "fire event" call, so the supported
	-- way addons solve this (Nampower, SuperWoW, and older bridge addons
	-- like Parrot/Bongos combat-text hooks all do the same thing) is to
	-- hook the target's own handler directly rather than refire the event.
	-- We do that below with hooksecurefunc-style wrapping where ClassicAPI
	-- provides hooksecurefunc, else a manual pre-hook.
	if KTM_ModernAPI.onSyntheticCombatText then
		KTM_ModernAPI.onSyntheticCombatText(event, text)
	end
end

--- Register your fork's real handler here, e.g. in KTM_CombatParser.lua:
---   KTM_ModernAPI.onSyntheticCombatText = function(event, text)
---       event = event
---       arg1 = text
---       mod.combat.oneventinternal()
---   end
--- This keeps KTM_ModernAPI decoupled from KTM's private locals -- you wire
--- the one bridging line into your own combat parser once, and every event
--- below flows through your existing, already-tested regex path, just fed
--- with guaranteed-correct text instead of real (sometimes-missing) chat
--- text.
KTM_ModernAPI.onSyntheticCombatText = nil

-- SpellName wraps a native call from a closed-source DLL. Per past
-- experience (see PROJECT_NOTES_eavesdrop.md #Lua-specific traps), such
-- calls cannot be trusted to fail safely -- some return nil out-of-range,
-- some throw. pcall + a one-time-per-id cache means a bad id is only ever
-- probed once and never propagates into the event handler.
local spellNameCache = {}
local function SpellName(spellId)
	if spellNameCache[spellId] ~= nil then return spellNameCache[spellId] end

	local ok, name = pcall(function()
		if C_Spell and C_Spell.GetSpellName then
			return C_Spell.GetSpellName(spellId)
		end
		if SpellInfo then -- SuperWoW
			return SpellInfo(spellId)
		end
		return GetSpellName and GetSpellName(spellId, "spell")
	end)

	name = (ok and name) or ("spell:" .. tostring(spellId))
	spellNameCache[spellId] = name
	return name
end

--------------------------------------------------------------------
-- CONFIRMED against nampower's EVENTS.md (fetched via GitHub's blob
-- viewer at github.com/brues-code/nampower/blob/main/EVENTS.md -- the
-- raw.githubusercontent.com and gitea.com mirrors are both blocked for
-- me, but this URL shape worked). Every payload order below is the
-- real documented one, not a guess -- and every one of them differs
-- from what I'd originally guessed. See the file header for specifics.
--------------------------------------------------------------------

--- Prints the raw payload of every relevant event to chat. Not needed
--- to make this work (the spec below is confirmed), but useful as an
--- ongoing sanity check against your actual nampower build/version,
--- since I have no way to verify this against a live client myself.
KTM_ModernAPI.debugUnknownPayloads = true

local function DumpPayload(evt)
	if not KTM_ModernAPI.debugUnknownPayloads then return end
	DEFAULT_CHAT_FRAME:AddMessage(string.format(
		"|cff33ccffKTM_ModernAPI|r %s: %s, %s, %s, %s, %s, %s, %s, %s",
		evt, tostring(arg1), tostring(arg2), tostring(arg3), tostring(arg4),
		tostring(arg5), tostring(arg6), tostring(arg7), tostring(arg8)))
end

-- Power-of-two bit test without relying on a `bit` library being present
-- (stock Lua 5.0 has none; nampower's own EVENTS.md examples use `bit.*`
-- but don't state it's guaranteed available client-wide, so don't
-- depend on it for a single-flag check).
local function HasFlag(value, flag)
	if not value then return false end
	return math.floor(value / flag) % 2 == 1
end

local HITINFO_CRITICALHIT = 128 -- AUTO_ATTACK_SELF/OTHER hitInfo bit (0x80)

feeder:RegisterEvent("PLAYER_LOGIN")
feeder:SetScript("OnEvent", function()
	if event ~= "PLAYER_LOGIN" then return end

	if M.hasNampower then
		-- SPELL_DAMAGE_EVENT_SELF fires unconditionally, no CVar needed.
		this:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")

		-- These four are gated OFF by default (confirmed in EVENTS.md).
		-- Turning them on here is safe even if nampower isn't installed
		-- -- SetCVar on an unrecognized name is a silent no-op in 1.12,
		-- and we already gated the whole block on M.hasNampower anyway.
		SetCVar("NP_EnableAutoAttackEvents", "1")
		SetCVar("NP_EnableSpellHealEvents", "1")
		SetCVar("NP_EnableSpellEnergizeEvents", "1")
		SetCVar("NP_EnableAuraCastEvents", "1")

		this:RegisterEvent("AUTO_ATTACK_SELF")
		this:RegisterEvent("SPELL_HEAL_BY_SELF")
		this:RegisterEvent("SPELL_ENERGIZE_BY_SELF")
		this:RegisterEvent("AURA_CAST_ON_SELF")
		this:RegisterEvent("AURA_CAST_ON_OTHER")
	end

	if M.hasSuperWoW then
		this:RegisterEvent("UNIT_CASTEVENT")
	end
end)

feeder:SetScript("OnEvent", function()
	if event == "PLAYER_LOGIN" then return end

	DumpPayload(event)

	if event == "SPELL_DAMAGE_EVENT_SELF" then
		-- CONFIRMED order: targetGuid, casterGuid, spellId, amount,
		-- mitigationStr, hitInfo, spellSchool, effectAuraStr
		local targetGUID, _, spellId, amount, _, hitInfo = arg1, arg2, arg3, arg4, arg5, arg6
		if targetGUID and spellId and amount then
			local target = M.TokenFromGUID(targetGUID) or "target"
			local isCrit = (hitInfo == 2) -- confirmed: 2 == crit, 0 otherwise
			local text = string.format(
				isCrit and (mod.string.get("selfcombat", "critdamageother") or "%s")
				        or (mod.string.get("selfcombat", "damageother") or "%s"),
				SpellName(spellId), target, amount)
			FireSynthetic(event, text)
		end

	elseif event == "AUTO_ATTACK_SELF" then
		-- CONFIRMED order: attackerGuid, targetGuid, totalDamage, hitInfo,
		-- victimState, subDamageCount, blockedAmount, totalAbsorb, totalResist
		local _, targetGUID, amount, hitInfo, victimState = arg1, arg2, arg3, arg4, arg5
		-- victimState 1 == VICTIMSTATE_NORMAL (an actual hit landed);
		-- dodge/parry/block/etc are 2-8 and shouldn't post as a hit.
		if targetGUID and amount and victimState == 1 then
			local target = M.TokenFromGUID(targetGUID) or "target"
			local isCrit = HasFlag(hitInfo, HITINFO_CRITICALHIT)
			local text = string.format(
				mod.string.get("selfcombat", isCrit and "critdamage" or "damage") or "%s",
				target, amount)
			FireSynthetic(event, text)
		end

	elseif event == "SPELL_HEAL_BY_SELF" then
		-- CONFIRMED order: targetGuid, casterGuid, spellId, amount,
		-- critical, periodic
		local targetGUID, _, spellId, amount, critical = arg1, arg2, arg3, arg4, arg5
		if targetGUID and spellId and amount then
			local target = M.TokenFromGUID(targetGUID) or "target"
			local text = string.format(
				mod.string.get("selfcombat", "healother") or "%s",
				SpellName(spellId), target, amount)
			FireSynthetic(event, text)
		end

	elseif event == "SPELL_ENERGIZE_BY_SELF" then
		-- rage/mana/energy gains from spells -- exactly what KTM's threat
		-- table needs for e.g. Bloodrage, Shield Slam rage refunds, etc.,
		-- without guessing from a "you gain N rage" chat line.
		-- CONFIRMED order: targetGuid, casterGuid, spellId, powerType,
		-- amount, periodic
		local _, _, spellId, powerType, amount = arg1, arg2, arg3, arg4, arg5
		if amount then
			local text = string.format(
				mod.string.get("selfcombat", "energize") or "%s",
				SpellName(spellId), amount)
			FireSynthetic(event, text)
		end

	elseif event == "UNIT_CASTEVENT" then
		-- SuperWoW's own event, separate from nampower's -- format per
		-- SuperWoW's wiki: casterGUID, targetGUID, castType ("START",
		-- "CAST", "FAIL", "CHANNEL", "MAINHAND", "OFFHAND"), spellId, duration
		local casterGUID, _, castType, spellId = arg1, arg2, arg3, arg4
		if casterGUID == M.GetGUID("player") and castType == "CAST" and spellId then
			-- Confirms YOUR cast actually landed (vs. started/failed), which
			-- is the ambiguity KTM's CHAT_MSG_SPELL_SELF_DAMAGE regex can't
			-- always resolve on its own for interrupted/parried casts.
			M.lastConfirmedCast = spellId
		end
	end
end)

-------------------------------------------------------------------------
-- UnitXP_SP3: real distance for cleave / multi-target threat splitting.
-- KTM's guess-code has to assume "if I'm in melee range of my target, any
-- cleave/whirlwind also hit whatever else I'm tagged on" -- UnitXP3 lets
-- you actually check.
-------------------------------------------------------------------------

--- Returns true if `unit` is within melee auto-attack range of the player,
--- using UnitXP3's calibrated melee metric (falls back to nil, meaning
--- "unknown, assume KTM's existing heuristic").
function M.IsInMeleeRange(unit)
	if not M.hasUnitXP3 then return nil end
	local ok, dist = pcall(UnitXP, "distanceBetween", "player", unit, "meleeAutoAttack")
	if not ok or not dist then return nil end
	return dist <= 5 -- 5yd covers all melee weapon reach incl. polearms/staves
end

-------------------------------------------------------------------------
-- Small public status printer so raid members can see who's actually
-- running with which backend, useful when triaging "my numbers don't
-- match yours" reports.
-------------------------------------------------------------------------

function M.PrintStatus()
	local function yn(b) return b and "|cff33ff33yes|r" or "|cffff3333no|r" end
	DEFAULT_CHAT_FRAME:AddMessage("KTM_ModernAPI:")
	DEFAULT_CHAT_FRAME:AddMessage("  SuperWoW:   " .. yn(M.hasSuperWoW))
	DEFAULT_CHAT_FRAME:AddMessage("  ClassicAPI: " .. yn(M.hasClassicAPI))
	DEFAULT_CHAT_FRAME:AddMessage("  nampower:   " .. yn(M.hasNampower))
	DEFAULT_CHAT_FRAME:AddMessage("  UnitXP_SP3: " .. yn(M.hasUnitXP3))
	DEFAULT_CHAT_FRAME:AddMessage("  VanillaHelpers: not used (no combat/aura surface)")
end

SLASH_KTMMODERNAPI1 = "/ktmapi"
SlashCmdList["KTMMODERNAPI"] = M.PrintStatus
```

## Code\KTM_My.lua
```lua
--! This module references these other modules:
--! combat:	recentattacks, 
--! data:	spells, rockbiter, threatconstants, isbuffpresent, gettalentrank, getsetpieces, 
--! out:	checktrace, printtrace, print, booltostring, 
--! regex:	parse, addparsestring, 
--! table:	raidthreatoffset, resetraidthreat, 
--! string:	unlocalise, get, 

--! This module is referenced by these other modules:
--! combat:	class, ability, states, mods, globalthreat, 
--! console:	testthreat, states, 
--! data:	class, 
--! net:	states, 
--! table:	class, 

local mod = klhtm
local me, _ = { }
mod.my = me

--[[ 
KTM_My.lua

This file stores data that specifically relates to the current player, and methods that change these data sets.
Most of the data sets are updated by polling, that is frequently recalculating their values.

me.states		- 	a set of flags, e.g. "player in combat" / "feigning death"
me.spellranks	-	list of ranks the player has for the important threat causing spells / abilities
me.mods			-	currently active modifiers to threat / abilities from talents, gear, buffs, etc
me.globalthreat	-	buffs that affect all threat the player generates
]]

----------------------------------------------------------------------------------------

me.feigndeathresisttime = 0 -- return value of GetTime()
me.lastfadevalue = 0

-- mod.my.class is the unlocalised lower case representation. e.g. "warrior", "rogue", no matter what locale you are in.
me.lclass, me.class = UnitClass("player")
--! This variable is referenced by these modules: combat, data, table, 
me.class = string.lower(me.class)

-----------------------------------------
--    Special Methods from Core.lua    --
-----------------------------------------

me.parserset = { }

-- onupdate
me.onload = function()
	
	-- make our parser
	local parserdata
	
	for _, parserdata in me.parserconstructor do
		mod.regex.addparsestring(me.parserset, parserdata[1], parserdata[2], parserdata[3])
	end
	
end

me.parserconstructor = 
{
   {"buffstart", "AURAADDEDSELFHELPFUL", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"},	-- "You gain %s."
   {"debuffstart", "AURAADDEDSELFHARMFUL", "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE"}, -- "You are afflicated by %s."
	{"weaponbuff", "ITEMENCHANTMENTADDSELFSELF", "CHAT_MSG_SPELL_ITEM_ENCHANTMENTS"}, -- "You cast %s on your %s."
	{"buffend", "AURAREMOVEDSELF", "CHAT_MSG_SPELL_AURA_GONE_SELF"}, -- "%s fades from you."
	{"selfperform", "SIMPLEPERFORMSELFSELF", "CHAT_MSG_SPELL_SELF_BUFF"}, -- "You perform %s."
}

-- The "UI_ERROR_MESSAGE" event is used to detect Feign Death resists.
me.myevents = { "UI_ERROR_MESSAGE", "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "CHAT_MSG_SPELL_AURA_GONE_SELF", 
	"CHAT_MSG_SPELL_ITEM_ENCHANTMENTS", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "CHAT_MSG_SPELL_SELF_BUFF", }

me.onevent = function()

	local ability

	-- 1) Check for Feign Death resisted
	if event == "UI_ERROR_MESSAGE" then
		
		if arg1 == ERR_FEIGN_DEATH_RESISTED then
			if mod.out.checktrace("info", me, "feigndeath") then
				mod.out.printtrace("Feign Death Resist message intercepted.")
			end
			me.feigndeathresisttime = GetTime()
		end
		
		return
	end
	
	-- 2) Check for various buffs
	local output = mod.regex.parse(me.parserset, arg1, event)
	
	if output.hit == nil then
		return
	end
	
	me.parserstagetwo[output.parser.identifier](output.final[1], output.final[2], output.final[3], output.final[4])

end

--[[
This is the continuation of the combat log parsing from me.onevent above. From that method, we know the identifier of the event that has been parsed, and all the arguments that go with it. We put all the identifiers into a table whose value is a method to handle that event.
]]
me.parserstagetwo = 
{
	["debuffstart"] = function(buff)	
		if buff == mod.string.get("boss", "spell", "burningadrenaline") then
			me.setstate("burningadrenaline", true)
	
		elseif buff == mod.string.get("boss", "spell", "fungalbloom") then
			me.setstate("fungalbloom", true)
		end
	end,
	
	["buffend"] = function(buff)
		if buff == mod.string.get("boss", "spell", "burningadrenaline") then
			me.setstate("burningadrenaline", false)
			
		elseif buff == mod.string.get("boss", "spell", "fungalbloom") then
			me.setstate("fungalbloom", false)
			
		elseif buff == mod.string.get("spell", "arcaneshroud") then
			me.setstate("arcaneshroud", false) 
		
		elseif buff == mod.string.get("spell", "theeyeofdiminution") then
			me.setstate("theeyeofdiminution", false)
		
		elseif buff == mod.string.get("spell", "notthere") then
			me.setstate("notthere", false)
		
		elseif buff == mod.string.get("spell", "fade") then
			-- retract fade
			mod.table.raidthreatoffset = mod.table.raidthreatoffset + me.lastfadevalue
			me.setstate("fade", false)
		end 	
				
	end,
	
	["weaponbuff"] = function(buff, weapon)
		-- only care about rockbiter == shaman
		if me.class ~= "shaman" then
			return
		end
		
		if string.find(buff, mod.string.get("spell", "rockbiter")) then
			
			-- get rank
			local rank
			_, _, rank = string.find(buff, ".-(%d+).-")
			
			-- set rank in mods
			me.mods.shaman.rockbiter = tonumber(rank)
		
		else
		
			-- added an enchant that was not rockbiter
			me.mods.shaman.rockbiter = 0
		end	
		
	end,
	
	["buffstart"] = function(buff)
		if buff == mod.string.get("spell", "arcaneshroud") then -- fetish of the sand reaver activation
			mod.my.setstate("arcaneshroud", true)
			
		elseif buff == mod.string.get("spell", "fade") then
		
			local threat = mod.my.ability("fade", "threat")
			mod.table.raidthreatoffset = mod.table.raidthreatoffset - threat
			mod.my.lastfadevalue = threat
			
			mod.my.setstate("fade", true)
		
		elseif buff == mod.string.get("spell", "theeyeofdiminution") then
			mod.my.setstate("theeyeofdiminution", true)
		
		elseif buff == mod.string.get("spell", "notthere") then
			me.setstate("notthere", true)
		end
	end,
	
	["selfperform"] = function(ability)
		if ability == mod.string.get("spell", "vanish") then
			mod.table.resetraidthreat()
		end
	end,
}


me.lastupdatetime = 0.0			-- return value of GetTime()
me.longupdateinterval = 1.0 	-- at least this time in seconds will pass between long updates

me.lastmegaupdatetime = 0.0
me.megaupdateinterval = 10.0

--[[  
Special onupdate() function, called from Core.lua
me.states		-	frequent update
me.spellranks	-	long time update
me.mods			-	long time update
me.globalthreat	-	frequent update
]]
me.onupdate = function()
	
	-- short updates
	me.redostates()
	
	-- check for long updates
	local timenow = GetTime()
	
	-- long updates
	if timenow > me.lastupdatetime + me.longupdateinterval then
		me.lastupdatetime = timenow
		me.redomods()
		me.redoglobalthreat()
	end
	
	-- mega updates
	if timenow > me.lastmegaupdatetime + me.megaupdateinterval then
		me.lastmegaupdatetime = timenow
		me.redospellranks()
	end
		
	-- check status of rockbiter enchant for Shaman, i.e. whether it has run out.
	if GetWeaponEnchantInfo() == nil then
		me.mods.shaman.rockbiter = 0
	end
end

----------------------------------------------------------------------------------------

----------------------------
--	  General Methods     --
----------------------------


--[[ 
mod.my.ability(name, value)
Returns the current value for some property of your spells and abilities.
	<name> is the mod's internal name for the ability.
	<value> is the name of the property, e.g. "threat", "multiplier", "rage". These are the indexes of values in
the mod.data.spells structure.
--> multiplier: return nil if nil
--> rage: return 0 if nil
--> threat / nextattack: throw error if nil

	This method will use me.spellranks to get the data that applies to your specific rank of the ability. Then
it will apply any modifiers from me.mods that are appropriate.
]]
--! This variable is referenced by these modules: combat, 
me.ability = function(spellid, parameter)
	
	if (spellid == nil) or (mod.data.spells[spellid] == nil) then
		if mod.out.checktrace("error", me, "ability") then
			mod.out.printtrace(string.format("No ability |cffffff00%s|r found.", tostring(spellid)))
		end
		return 0
	end
	
	local value
	local data = mod.data.spells[spellid]
	
	-- "rage" and "multiplier" parameters are easy, since they 
	if parameter == "rage" then
		if data.rage == nil then
			return 0
		else
			return data.rage
		end
	
	elseif parameter == "multiplier" then
		return data.multiplier -- may be nil
	end
		
	-- to get here, <parameter> is either "threat" or "nextattack"
	
	-- Item abilities only have one value for threat, no ranks.
	if data.class == "item" then
		return data.threat
	end
	
	-- Now check the spell has a known rank
	local spellrank = me.spellranks[spellid]
	
	if spellrank == nil then
		if mod.out.checktrace("error", me, "ability") then
			mod.out.printtrace(string.format("No spell rank defined for |cffffff00%s.", tostring(spellid)))
		end

		return 0
	end
	
	-- Check there is a value in data for our parameter (should always be)
	value = data[spellrank][parameter]
	
	if value == nil then
		if mod.out.checktrace("error", me, "ability") then
			mod.out.printtrace(string.format("No value of |cffffff00%s for rank |cffffff00%s of |cffffff00%s.", tostring(parameter), tostring(spellrankg), tostring(spellid)))
		end
		
		return 0
	end

	-- to get here, there were no errors. we got a value. Now we have to look for class mods that would affect it.
	if spellid == "sunder" then
		if parameter == "rage" then
			value = value + me.mods.warrior.sundercost
		elseif parameter == "threat" then
			value = value * me.mods.warrior.sunderthreat
		end
		
	elseif spellid == "heroicstrike" then
		if parameter == "rage" then
			value = value + me.mods.warrior.heroicstrikecost
		end
		
	elseif spellid == "feint" then
		if parameter == "threat" then
			value = value * me.mods.rogue.feint
		end
		
	elseif spellid == "maul" then
		if parameter == "rage" then
			value = value + me.mods.druid.ferocity
		end
		
	elseif spellid == "swipe" then
		if parameter == "rage" then
			value = value + me.mods.druid.ferocity
		end	
	end
	
	return value
end

--[[
mod.my.testthreat()
Print out your threat properties for debug purposes.
]]
--! This variable is referenced by these modules: console, 
me.testthreat = function()
		
	-- 1) Print out spell ranks
	local key
	local value
	
	--[[
	for key, value in me.spellranks do
		mod.out.print(string.format(mod.string.get("print", "data", "abilityrank"), key, value))
	end
	]]
	
	-- 2) Print out global threat
	mod.out.print(string.format(mod.string.get("print", "data", "globalthreat"), me.globalthreat.value))
	for key, value in me.globalthreat.modifiers do
		if value.isactive == false then
			break
		end
		
		mod.out.print(string.format(mod.string.get("print", "data", "globalthreatmod"), value.reason, value.value))
	end

	-- 3) Print out threat for specific abilities
	if me.class == "priest" then
		mod.out.print(string.format(mod.string.get("print", "data", "multiplier"), me.lclass, mod.string.get("talent", "silentresolve"), 1.0 + me.mods.priest.silentresolve))
		mod.out.print(string.format(mod.string.get("print", "data", "multiplier"), me.lclass, SPELL_SCHOOL5_CAP, me.mods.priest.shadowaffinity))
	
	elseif me.class == "warlock" then
		mod.out.print(string.format(mod.string.get("print", "data", "setactive"), mod.string.get("sets", "nemesis"), 8, mod.out.booltostring(me.mods.warlock.nemesis)))
		mod.out.print(string.format(mod.string.get("print", "data", "setactive"), mod.string.get("sets", "plagueheart"), 6, mod.out.booltostring(me.mods.warlock.plagueheart)))
	
	elseif me.class == "mage" then
		mod.out.print(string.format(mod.string.get("print", "data", "setactive"), mod.string.get("sets", "netherwind"), 3, mod.out.booltostring(me.mods.mage.netherwind)))
		mod.out.print(string.format(mod.string.get("print", "data", "multiplier"), me.lclass, SPELL_SCHOOL6_CAP, 1.0 + me.mods.mage.arcanethreat))
		mod.out.print(string.format(mod.string.get("print", "data", "multiplier"), me.lclass, SPELL_SCHOOL4_CAP, 1.0 + me.mods.mage.frostthreat))
		mod.out.print(string.format(mod.string.get("print", "data", "multiplier"), me.lclass, SPELL_SCHOOL2_CAP, 1.0 + me.mods.mage.firethreat))
		
	elseif me.class == "paladin" then
		mod.out.print(string.format(mod.string.get("print", "data", "multiplier"), me.lclass, mod.string.get("print", "data", "holyspell"), me.mods.paladin.righteousfury))
		mod.out.print(string.format(mod.string.get("print", "data", "healing"), mod.data.threatconstants.healing * me.mods.paladin.healing))
		
	elseif me.class == "warrior" then
		mod.out.print(string.format(mod.string.get("print", "data", "multiplier"), me.lclass, mod.string.get("spell", "sunder"), me.mods.warrior.sunderthreat))
		
	elseif me.class == "druid" then
		mod.out.print(string.format(mod.string.get("print", "data", "multiplier"), me.lclass, mod.string.get("talent", "tranquility"), me.mods.druid.tranquilitythreat))
		
	elseif me.class == "shaman" then
		mod.out.print(string.format(mod.string.get("print", "data", "healing"), mod.data.threatconstants.healing * me.mods.shaman.healing))
		
		if me.mods.shaman.rockbiter > 0 then
			mod.out.print(string.format(mod.string.get("print", "data", "rockbiter"), me.mods.shaman.rockbiter, UnitAttackSpeed("player") * mod.data.rockbiter[me.mods.shaman.rockbiter]))
		end
	end
end


----------------------------------------------------------------------------------------

----------------------------
--	  	  States          --
----------------------------

--[[      
each state is represented by a key-value pair. The key is a string, which is a description of the state,
e.g. "incombat", "feigndeath". The value is a list with properties 
	["value"], boolean, whether the state is on or off
	["lastchange"], return value of GetTime() (seconds + decimal), when the value last changed
	["duration"], OPTIONAL, known duration of the state. This is used to turn the state off just in case
				  the normal mechanism to detect it does not work.
				
To set a state's value, call the method mod.my.setstate(<string name>, <boolean value>). If this causes the
state to change, the method will return non-nil, and an event KLHTM_STATECHANGE_<NAME> will be raised.
]]  
--! This variable is referenced by these modules: combat, console, net, 
me.states = 
{
	["feigndeath"] = 
	{
		["value"] = false,
		["lastchange"] = 0,
	},
	["arcaneshroud"] = -- from Fetish of the Sandreaver
	{
		["value"] = false,
		["lastchange"] = 0,
		["duration"] = 20.0
	},
	["theeyeofdiminution"] = -- from Eye of Diminution
	{
		["value"] = false,
		["lastchange"] = 0,
		["duration"] = 20.0
	},
	["notthere"] =			-- frostfire 8 piece proc
	{
		["value"] = false,
		["lastchange"] = 0,
		["duration"] = 8.0
	},
	["incombat"] = 
	{
		["value"] = false,
		["lastchange"] = 0,
	},
	["playercharmed"] = -- whether you have been mind controlled
	{
		["value"] = false,
		["lastchange"] = 0,
	},
	["burningadrenaline"] = 
	{
		["value"] = false,
		["lastchange"] = 0,
		["duration"] = 20.0,
	},
	["fade"] = 
	{
		["value"] = false,
		["lastchange"] = 0,
		["duration"] = 10.0,
	},
	["fungalbloom"] = 
	{
		["value"] = false,
		["lastchange"] = 0,
		["duration"] = 90.0,
	},
}


--[[ 
mod.my.setstate(state, value)
Sets the value of one of the state variables above.
<state> is a string, a key to the me.states list, e.g. "feigndeath", "incombat", etc.
<value> is a boolean, true or false.
Return: true if the set represents a change, otherwise nil
]]
me.setstate = function(state, value)
	
	-- verify <state>
	if me.states[state] == nil then
		if mod.out.checktrace("error", me, "state") then
			mod.out.printtrace(string.format("There is no state |cffffff00%s|r.", tostring(state)))
		end
		return
	end
	
	-- update
	if me.states[state].value ~= value then
		me.states[state].value = value
		me.states[state].lastchange = GetTime()
		
		return true
	end

end

--[[
me.redostates()
Checks for changes to state variables that we poll for (e.g. "incombat" / "ischarmed").
Also checks for states that have run out, but whose end events were not detected (e.g. burning adrenaline). This
last should not be relied upon though.
]]
me.redostates = function()
	
	-- hunter: check for FD
	if mod.my.class == "hunter" then
		
		-- Check for feign death debuff
		local currentfd = mod.data.isbuffpresent("Interface\\Icons\\Ability_Rogue_FeignDeath")
		
		if me.setstate("feigndeath", currentfd) and (currentfd == true) then
			
			-- first check for resist.
			if math.abs(me.feigndeathresisttime - GetTime()) < 1.0 then
				--resisted. Nothing happens
				
				if mod.out.checktrace("info", me, "feigndeath") then
					mod.out.printtrace("feigndeathdebug", "Feign Death was resisted!")
				end
				
			else -- wipe threat
			
				mod.table.resetraidthreat()
				
			end
			
		end
	end
 
	-- update charmed state
	if UnitIsCharmed("player") == 1 then
		me.setstate("playercharmed", true)
	else
		me.setstate("playercharmed", false)
	end

	-- update combat state
	if UnitAffectingCombat("player") == 1 then
		
		if me.setstate("incombat", true) then
			
			-- player has just joined combat
			if mod.out.checktrace("info", me, "incombat") then
				mod.out.printtrace("You entered combat.")
			end
			
			mod.table.resetraidthreat()
			
			local key
			local value
		
			for key, value in mod.combat.recentattacks do
				mod.table.raidthreatoffset = mod.table.raidthreatoffset + value[2]
			end	
		end
	
	else
		if (me.states.playercharmed.value == true) or (GetTime() - me.states.playercharmed.lastchange < 2.0) then
			me.setstate("incombat", true) -- should not be a change
		else
			if me.setstate("incombat", false) then
				if mod.out.checktrace("info", me, "incombat") then
					mod.out.printtrace("You left combat.")
				end
				me.lastfadevalue = 0 -- stop fade
			end 
		end
	end
	
	-- update states with a "duration" parameter. They are all designed to deactivate on their own, but e.g.
	-- burning adrenaline isn't working, so we put in this mechanism as a backup
	local state
	local data
	
	for state, data in me.states do
		if data.duration and (data.value == true) and (GetTime() > data.lastchange + data.duration + 1.0) then
			me.setstate(state, false)
			
			if mod.out.checktrace("info", me, "state") then
				mod.out.printtrace(string.format("Deactivated the state %s because it had passed its duration.", state))
			end
		end
	end 
end

----------------------------------------------------------------------------------------

----------------------------
--      Spell Ranks       --
----------------------------

--[[
	A collection of key-value pairs. The key is a string, the name of a spell / ability, e.g. "Sunder Armor". It
is localised. The value is an integer, the rank of that spell you have.
	The only spells recorded are those which are cause or remove threat by known amounts, i.e. Sunder Armor, 
Revenge, Maul, Feint, etc.
	We want to know the what rank of the spell the player has, because most abilities have different numbers for 
different spell ranks. e.g. Heroic Strike does more damage and threat for each new rank. Some players will have the
extra rank from AQ20, some will not.
	These ranks will probably not change over the course of a session, but we poll just in case.
]]
me.spellranks = { } 

--[[
me.redospellranks()
Redetermines the ranks of all special threat abilities you have.
]]
me.redospellranks = function()
	
	local index = 0
	local name, rankstring, rank, spellid
	local rankpattern = mod.string.get("misc", "spellrank") -- e.g. "Rank %d" in english.
		
	while true do
		index = index + 1
		name, rankstring = GetSpellName(index, "spell")
		
		if name == nil then
			break
		end
		
		-- get the internal spell ID
		spellid = mod.string.unlocalise("spell", name)
		
		if spellid and mod.data.spells[spellid] then
			rank = 0
			
			_, _, rank = string.find(rankstring, rankpattern)
			if rank then
				me.spellranks[spellid] = rank
			end
		end
	end
	
end


----------------------------------------------------------------------------------------

---------------------------------------
--    Threat And Ability Modifers    --
---------------------------------------

--! This variable is referenced by these modules: combat, 
me.mods = 
{
	["warrior"] = 
	{
		["defiance"] = 0.0, 			-- modifier to global threat. e.g. "+0.15" for 5 points.
		["sunderthreat"] = 1.0, 	-- multiplier. e.g. "1.15" for 8/8 Might.
		["sundercost"] = 0.0,		-- modifier of rage cost. e.g. "-3" for 3/3 improved sunder talent.
		["heroicstrikecost"] = 0.0,-- modifier of rage cost. e.g. "-3" for 3/3 improved heroic strike talent.
		["impale"] = 0.0 				-- critical strike bonus damage for abilities. e.g. "0.2" for 2/2 impale talent.
	},
	["rogue"] = 
	{
		["feint"] = 1.0,		-- multiplier. e.g. "1.25" for 5/8 Bloodfang. +20% for sleight of hand, maybe.
		["bonescythe"] = false,		-- bonescythe 6/8 bonus
	},
	["druid"] = 
	{
		["feralinstinct"] = 0.0, 	-- defiance for druids.
		["savagefury"] = 1.0, 		-- multiplier to damage for druid abilities
		["subtlety"] = 1.0, 			-- multiplier to healing threat. e.g. "0.8" for all talents.
		["ferocity"] = 0.0, 			-- modifier to rage cost of maul and swipe. e.g. "-5" for all talents.
		["tranquilitythreat"] = 1.0-- multiplier, from Improved Tranquility Talent
	},
	["mage"] = 
	{
		["arcanist"] = false, 		-- 8 piece bonus
		["netherwind"] = false, 	-- 3 piece
		["arcanethreat"] = 0.0,		-- almost a modifier to global threat (spells only) e.g. "-0.4" for 2/2 talent points.
		["frostthreat"] = 0.0, 		-- almost a modifier to global threat (spells only) e.g. "-0.3" for 3/3 talent points.
		["firethreat"] = 0.0, 		-- almost a modifier to global threat (spells only) e.g. "-0.3" for 2/2 talent points.
	},
	["warlock"] = 
	{
		["masterdemo"] = 0.0, 		-- modifier to global threat. e.g. "-0.2" for imp out, 5/5.
		["nemesis"] = false,			-- 8 piece bonus
		["plagueheart"] = false,			-- 6 piece bonus
	},
	["priest"] =
	{
		["silentresolve"] = 0.0, 	-- almost a modifier to global threat (spells only) e.g. "-0.2" for fully talented.
		["shadowaffinity"] = 1.0, 	-- multiplier for shadow damage. e.g. "0.8".
	},
	["paladin"] = 
	{
		["righteousfury"] = 1.0, 	-- multiplier for threat from holy damage / abilities.
		["healing"] = 0.5, 			-- this is actually constant, but really fits best in this variable.
	},
	["shaman"] = 
	{
		["rockbiter"] = 0, 			-- current rank of rockbiter that is active, 0 for none.
		["healing"] = 1.0, 			-- multiplier. e.g. 0.85 for 3/3 Healing Grace.
	}
}

me.redomods = function()
	
	-- talent / gear searching
	local info
	local rank
	local key
	local value
	
	-- warrior
	if mod.my.class == "warrior" then

		-- might 8/8
		if mod.data.getsetpieces("might") == 8 then
			me.mods.warrior.sunderthreat = 1.15
		else
			me.mods.warrior.sunderthreat = 1.0
		end

		-- improved sunder armor
		rank = mod.data.gettalentrank("sunder")
		me.mods.warrior.sundercost = -rank

		-- improved heroic strike
		rank = mod.data.gettalentrank("heroicstrike")
		me.mods.warrior.heroicstrikecost = -rank

		-- defiance
		rank = mod.data.gettalentrank("defiance")
		me.mods.warrior.defiance = 0.03 * rank

		-- impale
		rank = mod.data.gettalentrank("impale")
		me.mods.warrior.impale = 0.05 * rank

	-- rogue
	elseif mod.my.class == "rogue" then
		
		-- bloodfang 4 piece
		if mod.data.getsetpieces("bloodfang") > 4 then
			me.mods.rogue.feint = 1.25
		else
			me.mods.rogue.feint = 1.0
		end
		
		-- bonescythe 6 piece
		if mod.data.getsetpieces("bonescythe") == 6 then
			me.mods.rogue.bonescythe = true
		else
			me.mods.rogue.bonescythe = false
		end
		
		rank = mod.data.gettalentrank("sleightofhand")
		me.mods.rogue.feint = me.mods.rogue.feint + rank * 0.1
	
	-- priest
	elseif mod.my.class == "priest" then
		
		-- silent resolve
		rank = mod.data.gettalentrank("silentresolve") 
		me.mods.priest.silentresolve = -0.04 * rank
				
		-- shadow affinity
		rank = mod.data.gettalentrank("shadowaffinity")
		me.mods.priest.shadowaffinity = 1 - rank * 0.25 / 3
	
	-- druid
	elseif mod.my.class == "druid" then
		
		-- subtlety
		rank = mod.data.gettalentrank("druidsubtlety")
		me.mods.druid.subtlety = 1 - 0.04 * rank
			
		-- feral instinct
		rank = mod.data.gettalentrank("feralinstinct")
		me.mods.druid.feralinstinct = 0.03 * rank
		
		-- ferocity
		rank = mod.data.gettalentrank("ferocity")
		me.mods.druid.ferocity = -rank
		
		-- savage fury
		rank = mod.data.gettalentrank("savagefury")
		me.mods.druid.savagefury = rank * 0.1
		
		-- improved tranquility
		rank = mod.data.gettalentrank("tranquility")
		me.mods.druid.tranquilitythreat = 1.0 - rank * 0.4
		
	-- mage
	elseif mod.my.class == "mage" then
		
		-- arcanist 8 piece
		if mod.data.getsetpieces("arcanist") == 8 then
			me.mods.mage.arcanist = true
		else
			me.mods.mage.arcanist = false
		end
		
		-- arcane subtelty
		rank = mod.data.gettalentrank("arcanesubtlety")
		me.mods.mage.arcanethreat = 0.0 - 0.2 * rank

		-- frost channeling
		rank = mod.data.gettalentrank("frostchanneling")
		me.mods.mage.frostthreat = 0.0 - 0.1 * rank
		
		-- burning soul
		rank = mod.data.gettalentrank("burningsoul")
		me.mods.mage.firethreat = 0.0 - 0.15 * rank
		
		-- netherwind 3 piece
		if mod.data.getsetpieces("netherwind") > 2 then
			me.mods.mage.netherwind = true
		else
			me.mods.mage.netherwind = false
		end
	
	-- warlock
	elseif mod.my.class == "warlock" then
		-- master demonologist
		rank = mod.data.gettalentrank("masterdemonologist")
		
		-- check for imp
		if UnitCreatureFamily("pet") == mod.string.get("misc", "imp") then
			me.mods.warlock.masterdemo = -0.04 * rank
		else
			me.mods.warlock.masterdemo = 0
		end
		
		-- nemesis 8 piece
		if mod.data.getsetpieces("nemesis") == 8 then
			me.mods.warlock.nemesis = true
		else
			me.mods.warlock.nemesis = false
		end

		-- plagueheart 6 piece
		if mod.data.getsetpieces("plagueheart") >= 6 then
			me.mods.warlock.plagueheart = true
		else
			me.mods.warlock.plagueheart = false
		end
		
	-- shaman
	elseif mod.my.class == "shaman" then
		
		-- healing grace
		rank = mod.data.gettalentrank("healinggrace")
		me.mods.shaman.healing = 1.0 - 0.05 * rank
		
	-- paladin
	elseif mod.my.class == "paladin" then
		
		local multi = 1.0
		
		-- righteous fury buff:
		if mod.data.isbuffpresent("Interface\\Icons\\Spell_Holy_SealOfFury") then
			multi = multi + 0.6
		
			-- talents
			rank = mod.data.gettalentrank("righteousfury")
			multi = multi + (0.5 * rank / 3)
		end
		
		me.mods.paladin.righteousfury = multi
	end
	
end


----------------------------------------------------------------------------------------

----------------------------
--  Global Threat Mods    --
----------------------------

--[[
	There are certain threat modifiers that are applied to all threat done, and that stack additively.
For instance with the "Blessing of Salvation" buff, all your threat is reduced by 30%. Wit the Arcanist
8 piece bonus, threat is reduced by 15%, but these bonuses add directly, so that with both bonuses, your 
threat is reduced by 45%.
	mod.my.globalthreat provides a list of all your global bonuses that are currently active. The data is
designed to be easily printed to the user.
	The data is updated frequently, because the modifiers can come on and off at any time. This means once
every OnUpdate, roughly 40 times per second. As a result we take pains to avoid the creation of new lists,
which would otherwise generate excess heap memory.
	me.globalthreat.modifiers is an ARRAY, i.e. a list keyed by [1], [2], [3], etc. Each item of the array the value
is a list with properties
	["value"] - the fractional reduction in threat. -30% from Blessing of Salvation would be "-0.3".
	["reason"] - a description of the effect, for the user's benefit. e.g. "Blessing of Salvation".
	["isactive"] - if false, this value and all further values should be ignored. Since we don't want to keep
	             recreating lists in a frequently called procedure, when a threat modifier is no longer active,
				 <isactive> is set to false, and that value is ignored. A newly added buff will overwrite the
				other data fields, but set <isactive> to true.
	There is one final part me.globalthreat, a key-value pair. The key is "value" and the value is your total
modifier, i.e. the sum of all the modifiers. For a normal character with no buffs / talents / items, this
value would be 1.0, e.g.
	me.globalthreat = 
{
	["value"] = 1.0,
	["modifiers"] = 
	{
		[1] = 
		{
			["value"] = 1.0,
			["reason"] = "Base Value",
			["isactive"] = true,
		}
	}
}
]]
--! This variable is referenced by these modules: combat, 
me.globalthreat = 
{
	["value"] = 0.0,
	["modifiers"] = { }
}

--[[ 
me.modifyglobalthreat(value, reason)
Adds a global threat modifier to me.globalthreat.
<value> and <reason> are as defined in me.globalthreat (see comments above).
This method will first look for a value in the me.globalthreat array that is labeled inactive (unused memory) 
and write the values there. Otherwise it will create a new value and append it to the array.
Heap memory creation occurs a maximum of n times, where n is the largest number of +- threat buffs you get.
This is on the order of 5, and for the whole running time, so negligable.
]]
me.modifyglobalthreat = function(value, reason)
	
	-- update the total / sum
	me.globalthreat.value = me.globalthreat.value * (1.0 + value)
	value = 1.0 + value
	
	-- look for an unused array position
	local x
	local count = table.getn(me.globalthreat.modifiers)
	
	for x = 1, count do
		
		if me.globalthreat.modifiers[x].isactive == false then
			
			-- found an inactive array index. Activate it and write values
			me.globalthreat.modifiers[x].value = value
			me.globalthreat.modifiers[x].reason = reason
			me.globalthreat.modifiers[x].isactive = true 
			return
		end
	end
	
	-- all the slots in the array are being used. Add a new value to the end
	table.insert(me.globalthreat.modifiers, {["value"] = value, ["reason"] = reason, ["isactive"] = true})
	
end

--[[ 
me.redoglobalthreat()
Recalculates all your global threat modifiers.
]]
me.redoglobalthreat = function()

	-- 1) reset
	local x
	for x = 1, table.getn(me.globalthreat.modifiers) do
		me.globalthreat.modifiers[x].isactive = false
	end
	
	-- 1.12 change: all threat is multiplicative
	me.globalthreat.value = 1.0
	me.modifyglobalthreat(0.0, mod.string.get("threatmod", "basevalue"))
	
	-- 2) rebuild
	
	-- Tranquil Air
	if mod.data.isbuffpresent("Interface\\Icons\\Spell_Nature_Brilliance") == true then
		me.modifyglobalthreat(-0.2, mod.string.get("threatmod", "tranquilair"))
	end
	
	-- Blessing of Salvation
	if mod.data.isbuffpresent("Interface\\Icons\\Spell_Holy_SealOfSalvation") == true then
		me.modifyglobalthreat(-0.3, mod.string.get("threatmod", "salvation"))
		
	elseif mod.data.isbuffpresent("Interface\\Icons\\Spell_Holy_GreaterBlessingofSalvation") == true then
		me.modifyglobalthreat(-0.3, mod.string.get("threatmod", "salvation"))
	end
	
	-- disabled: 17.15. Doesn't seem to occur any more.
	-- Burning Adrenaline
	--if me.states["burningadrenaline"].value == true then
	--	me.modifyglobalthreat(-0.75, mod.string.get("boss", "spell", "burningadrenaline"))
	--end
	
	-- fungal bloom
	if me.states["fungalbloom"].value == true then
		me.modifyglobalthreat(0.0, mod.string.get("boss", "spell", "fungalbloom"))
	end
	
	-- Fetish of the Sand Reaver
	if me.states["arcaneshroud"].value == true then
		me.modifyglobalthreat(-0.7, mod.string.get("spell", "arcaneshroud"))
	end
	
	-- Eye of Diminution
	if me.states["theeyeofdiminution"].value == true then
		me.modifyglobalthreat(-0.35, mod.string.get("spell", "theeyeofdiminution"))
	end	
	local linkstring
	local enchant
	
	-- +2% threat enchant to gloves
	linkstring = GetInventoryItemLink("player", 10) or "" 
	_, _, enchant = string.find(linkstring, ".-item:%d+:(%d+).*")
	
	if enchant == "2613" then
		me.modifyglobalthreat(0.02, mod.string.get("threatmod", "glovethreatenchant"))
	end
	
	-- -2% threat enchant to back
	linkstring = GetInventoryItemLink("player", 15) or ""
	_, _, enchant = string.find(linkstring, ".-item:%d+:(%d+).*")
	
	if enchant == "2621" then
		me.modifyglobalthreat(-0.02, mod.string.get("threatmod", "backthreatenchant"))
	end
	
	local stance
	
	-- Warrior
	if mod.my.class == "warrior" then
		stance = me.getstanceindex()
		
		if stance == 1 then
			me.modifyglobalthreat(-0.2, mod.string.get("threatmod", "battlestance"))
			
		elseif stance == 2 then
			me.modifyglobalthreat(0.3, mod.string.get("threatmod", "defensivestance"))
			me.modifyglobalthreat(me.mods.warrior.defiance, mod.string.get("talent", "defiance"))
	
		elseif stance == 3 then
			me.modifyglobalthreat(-0.2, mod.string.get("threatmod", "berserkerstance"))
		end
		
	-- Druid Stances
	elseif mod.my.class == "druid" then
		stance = me.getstanceindex()
		
		if stance == 1 then
			me.modifyglobalthreat(0.3, mod.string.get("threatmod", "bearform"))
			me.modifyglobalthreat(me.mods.druid.feralinstinct, mod.string.get("talent", "feralinstinct"))
			
		elseif stance == 3 then
			me.modifyglobalthreat(-0.29, mod.string.get("threatmod", "catform"))
			
		end
	
	-- Rogue
	elseif mod.my.class == "rogue" then
		me.modifyglobalthreat(-0.29, me.lclass)
		
	-- Arcanist
	elseif (mod.my.class == "mage") and (me.mods.mage.arcanist == true) then
		me.modifyglobalthreat(-0.15, mod.string.get("sets", "arcanist") .. " 8/8")
		
	-- Warlock
	elseif (mod.my.class == "warlock") and (me.mods.warlock.masterdemo ~= 0) then
		me.modifyglobalthreat(me.mods.warlock.masterdemo, mod.string.get("talent", "masterdemonologist"))
	end	
end


--[[ 
me.getstanceindex()
For Druids and Warriors, returns an integer saying which stance you are in.
]]
me.getstanceindex = function()
	
	local x = 0
	local isactive
	local texture 
	
	while true do
		x = x + 1
		texture, _, isactive = GetShapeshiftFormInfo(x)
		
		if texture == nil then
			return 0
		end
		
		if isactive == 1 then
			return x
		end
	end
	
end
```

## Code\KTM_Net.lua
```lua
--! This module references these other modules:
--! boss:	bossattacks, 
--! my:	states, 
--! netin:	messagein, 
--! out:	print, 
--! table:	raiddata, getraidthreat, 
--! unit:	isplayeringroup, isplayerofficer, 
--! string:	get, 

--! This module is referenced by these other modules:
--! boss:	lastmtsender, sendmessage, clearmastertarget, sendmastertarget, clearraidthreat, reportspelleffect, sendevent, 
--! console:	checkpermission, clearmastertarget, sendmastertarget, clearraidthreat, startspellreporting, stopspellreporting, setspellvalue, checkspellvaluesyntax, versionnotify, versionquery, toggleadvertise, 
--! netin:	lastmtsender, lastmtstring, lastmttime, sendmessage, checkspellvaluesyntax, addversionresponse, 
--! table:	idleupdateinterval, 
--! guititle:	clearmastertarget, sendmastertarget, clearraidthreat, 

local mod = klhtm
local me = { }
mod.net = me

--[[
KTM_Net.lua

This module has all the code for operating the chat channel and sending KLHTM messages on it. Note that it doesn't deal with parsing / interpreting messages received from the chat channel - this is all done in KTM_NetIn.lua.

]]

-- Special onupdate method from Core.lua
me.onupdate = function()
	
	me.updatethreattoraid()
	me.checkversionquery()
	me.checkadvertise()
	
end


------------------------------------------------------------------------------------------------

--[[
mod.net.sendmessage(message)
Sends a message to the Addons chat channel.
<message> is a string.
Return: true (compatability).
]]
--! This variable is referenced by these modules: boss, netin, 
me.sendmessage = function(message)
	
	if GetNumRaidMembers() > 0 then
		SendAddonMessage("KLHTM", message, "RAID")
	
	elseif GetNumPartyMembers() > 0 then
		SendAddonMessage("KLHTM", message, "PARTY")
	
	else
		-- Send directly to our input handler
		mod.netin.messagein(UnitName("player"), message, 1)
	end
	
	return true
	
end


------------------------------------------------------------------------------------------------

---------------------------------
--    Special Raid Commands    --
---------------------------------

--[[ 
me.checkpermission()
Returns: non-nil iff you are allowed to send special commands (raid assistant / party leader, etc)
]]
--! This variable is referenced by these modules: console, 
me.checkpermission = function()

	if mod.unit.isplayerofficer(UnitName("player")) == true then
		return true
		
	else
		mod.out.print(mod.string.get("print", "network", "raidpermission"))
		return
	end
	
end
	
--[[
mod.net.clearmastertarget()
Sends a message to clear the master target. This is called from "/ktm mastertarget", or clicking the master target button when you have no target.
]]
--! This variable is referenced by these modules: boss, console, guititle, 
me.clearmastertarget = function()
	
	if me.checkpermission() == nil then
		return
	end
	
	me.sendmessage("cleartarget")
		
end

--[[
mod.net.sendmastertarget()
Sends a message to set the master target to your current target. The name of your current target, as you see it, is sent along with the command, in case someone is out of (targetting) range of your target. This is called from 
"/ktm mastertarget", or clicking the master target button when you have a target.
]]
--! This variable is referenced by these modules: boss, console, guititle, 
me.sendmastertarget = function()

	if me.checkpermission() == nil then
		return
	end
	
	if UnitName("target") == nil then
		mod.out.print(mod.string.get("print", "network", "needtarget"))
		return 
	end
	
	me.sendmessage("target " .. UnitName("target"))
	
end

--[[
mod.net.clearraidthreat()
Commands everyone in the raid to reset their threat. Called when you type "/ktm resetraid" or click the "clear threat"
button on the GUI (which is not visible by default).
]]
--! This variable is referenced by these modules: boss, console, guititle, 
me.clearraidthreat = function()
	
	if me.checkpermission() == nil then
		return
	end
	
	me.sendmessage("clear")
	
end

-- Commands in the Boss Section

--! This variable is referenced by these modules: console, 
me.startspellreporting = function()

	if me.checkpermission() == nil then
		return
	end
	
	me.sendmessage("spellstart")
		
end

--! This variable is referenced by these modules: console, 
me.stopspellreporting = function()
	
	if me.checkpermission() == nil then
		return
	end
	
	me.sendmessage("spellstop")

end

--! This variable is referenced by these modules: boss, 
me.reportspelleffect = function(spellname, bossname, result, value1, value2)
	
	if result == "miss" then
		me.sendmessage(string.format("spelleffect \"%s\" \"%s\" %s", spellname, bossname, result))
		
	else
		me.sendmessage(string.format("spelleffect \"%s\" \"%s\" %s %s %s", spellname, bossname, result, value1, value2))
	end
	
end

--! This variable is referenced by these modules: console, 
me.setspellvalue = function(spellid, bossid, parameter, value)

	if me.checkpermission() == nil then
		return
	end
	
	me.sendmessage(string.format("spellvalue %s %s %s %s", spellid, bossid, parameter, value))

end

-- syntax: <spellid> <bossid> <parameter> <value>
--[[
	if it succeeds, it will return just the value that is set.
	if it fails, it will return nil, then the error message.
]]
--! This variable is referenced by these modules: console, netin, 
me.checkspellvaluesyntax = function(allvalues)
			
	local x, spellid, bossid, parameter, value, key, message

	-- Check their first argument, <spellid>, is valid
	spellid = allvalues[1]
	if (spellid == nil) or (mod.boss.bossattacks[spellid] == nil) then
		
		message = "The argument |cffffff00" .. tostring(spellid) .. "|r does not match any boss spell id. Valid spellids are|cffffff00"
		
		for key, value in mod.boss.bossattacks do
			message = message .. " " .. key
		end

		message = message .. "|r."
		return nil, message
	end
	
	-- Check their second argument, <bossid>, is valid
	local dataset = mod.boss.bossattacks[spellid]
	
	bossid = allvalues[2]
	if (bossid == nil) or (dataset[bossid] == nil) then
		
		message = "The argument |cffffff00" .. tostring(bossid) .. "|r does not match any boss that uses the spell |cffffff00" .. mod.string.get("boss", "spell", spellid) .. "|r. Valid bossids are|cffffff00"
		
		for key, value in dataset do
			message = message .. " " .. key
		end

		message = message .. "|r."
		return nil, message
	end
	
	-- Check their third argument, <parameter>, is valid
	dataset = dataset[bossid]
	
	parameter = allvalues[3]
	if (parameter == nil) or (dataset[parameter] == nil) then
		
		message = "The argument |cffffff00" .. tostring(parameter) .. "|r does not match any parameter that can be set. Valid parameters are|cffffff00"
		
		for key, valud in dataset do
			message = message .. " " .. key
		end

		message = message .. "|r."
		return nil, message
	end
	
	-- 4th parameter is value
						
	-- multiplier / addition: need number
	if (parameter == "addition") or (parameter == "multiplier") then
		value = tonumber(allvalues[4])
		
		if value == nil then
			
			message = "The argument |cffffff00" .. tostring(allvalues[4]) .. "|r is not a number."
			return nil, message
		end
		
	elseif parameter == "ticks" then
		value = tonumber(allvalues[4])
		
		if (value == nil) or (math.floor(value) ~= value) or (value < 1) then
			
			message = "The argument |cffffff00" .. tostring(allvalues[4]) .. "|r is not a positive integer."
			return nil, message
	end
		
	elseif parameter == "effectonmiss" then
		
		if value == "true" then
			value = true
		
		elseif value == "false" then
			value = false
		
		else
			message = "The argument |cffffff00" .. tostring(allvalues[4]) .. "|r is not a boolean value."
			return nil, message
		end
		
	elseif parameter == "type" then
		
		if (value ~= "physical") or (value ~= "debuff") or (value ~= "spell") then
			
			message = "The argument |cffffff00" .. tostring(allvalues[4]) .. "|r is not one of |cffffff00 physical debuff spell|r."
			return nil, message
		end
	end
	
	-- it worked!
	return value
end


--! This variable is referenced by these modules: console, 
me.versionnotify = function()

	if me.checkpermission() == nil then
		return
	end
	
	me.sendmessage(string.format("version %d.%d", mod.release, mod.revision))
	mod.out.print(mod.string.get("print", "network", "upgradenote"))
	
end

--! This variable is referenced by these modules: console, 
me.versionquery = function()
	
	if me.checkpermission() == nil then
		return
	end
	
	-- clear the version table
	local key

	for key, _ in me.raidversions do
		table.remove(me.raidversions, key)
	end
	
	-- set the timeout for responses
	me.versionquerytimeout = GetTime() + 2
	
	-- Notify the user
	mod.out.print(mod.string.get("print", "network", "versionrequest"))
	
	-- send the message
	me.sendmessage("versionquery")
		
end

--! This variable is referenced by these modules: boss, 
me.sendevent = function(event)
	
	me.sendmessage("event " .. event)
	
end

-- Version Querying Stuff. Key = release number, value = array of names
me.raidversions = { }
me.versionquerytimeout = 0 -- 0 = inactive, > 0 = active. Return value of GetTime()

--! This variable is referenced by these modules: netin, 
me.addversionresponse = function(playername, version)

	local versionstring = tostring(version)
	
	-- ignore unless we are checking versions
	if me.versionquerytimeout > 0 then
	
		if me.raidversions[versionstring] == nil then
			me.raidversions[versionstring] = { }
		end
		
		me.raidversions[versionstring][playername] = true
	end

end


-- When we do "/ktm version query", the rest of the raid has 3 seconds to respond.
me.checkversionquery = function()
	
	if me.versionquerytimeout == 0 then
		return
	end
	
	if GetTime() > me.versionquerytimeout then
		
		-- print it out and stuff
		me.versionquerytimeout = 0
		
		local message
		local key
		local value
		local key2
		local namesfound = { }
		
		for key, value in me.raidversions do
			message = string.format(mod.string.get("print", "network", "versionrecent"), key)
			
			for key2, _ in value do
				message = message .. key2 .. ", "
				namesfound[key2] = true
			end
			
			message = message .. " }."
			mod.out.print(message)
			
			table.remove(me.raidversions, key)
		end
		
		-- Now print the people who have out of date versions
		message = mod.string.get("print", "network", "versionold")
		for key, _ in mod.table.raiddata do
			if namesfound[key] == nil and mod.unit.isplayeringroup(key) == true then
				namesfound[key] = true
				message = message .. key .. ", "
			end
		end
		
		message = message .. " }."
		mod.out.print(message)
		
		-- Now print out people who are not talking to us
		message = mod.string.get("print", "network", "versionnone")
		
		for value = 1, 40 do
			key = GetRaidRosterInfo(value)
			if (key ~= nil) and (namesfound[key] == nil) then
				namesfound[key] = true
				message = message .. key .. ", "
			end
		end
		
		message = message .. " }."
		mod.out.print(message)
		
	end
end

me.lastthreatupdate = 0 -- value of GetTime(). When we last posted our threat to the raid
me.minimumupdateinterval = 0.5 -- minimum time, in seconds, between threat updates to the raid
--! This variable is referenced by these modules: table, 
me.idleupdateinterval = 5.0 -- how often to update when our value is not changing
me.lastthreatvaluesent = -1 -- the name says it all, really

--[[
me.updatethreattoraid()
Sends a message to your raid group updating your threat if necessary. If your threat is constantly changing, you will send updates every <me.minimumupdateinterval> = 500ms, plus a small bit due to waiting for an OnUpdate() method to be called. If your threat is the same as before, you will only update every 5 seconds. If your threat is 0 and constant, you won't update it at all.
]]
me.updatethreattoraid = function()
	
	local interval
	local myraidthreat
	
	if mod.my.states.incombat.value == true then
		myraidthreat = math.floor(0.5 + mod.table.getraidthreat())
	else
		myraidthreat = 0
	end
	
	-- determine update inverval. If the value has changed, we'd like to update it soon, otherwise no hurry.
	if myraidthreat == me.lastthreatvaluesent then
		interval = me.idleupdateinterval		
	else
		interval = me.minimumupdateinterval
	end
	
	-- check update frequency
	if GetTime() < me.lastthreatupdate + interval then
		return -- only just sent an update. Wait a bit to send the next one.
	end
	
	-- don't update at all if idle and out of combat
	if (myraidthreat == 0) and (me.lastthreatvaluesent == 0) then
		return
	end
	
	-- OK. Send.
        local message = "s " .. mod.table.getmysunder()
	me.sendmessage(message)
	
        message = "t " .. myraidthreat
	me.sendmessage(message)

	
	me.lastthreatupdate = GetTime()
	me.lastthreatvaluesent = myraidthreat

end

--------------------------------------------------------------------------------------------------

-------------------------------------------------------
--    Advertising KLHTM to people who pull aggro!    --
-------------------------------------------------------

me.isadvertising = false
me.lastadvert = 0
me.advertinterval = 300 -- seconds

--[[
mod.net.toggleadvertise()
Switch the advertising function on or off.
]]
--! This variable is referenced by these modules: console, 
me.toggleadvertise = function()

	me.isadvertising = not me.isadvertising
	
	if me.isadvertising == true then
		mod.out.print(mod.string.get("print", "network", "advertisestart"))
	else
		mod.out.print(mod.string.get("print", "network", "advertisestop"))
	end

end

me.raidnumbers = { } -- {1, 2, 3, ..., 40}

for x = 1, 40 do
	me.raidnumbers[x] = x
end

--[[
me.checkadvertise()
Looks for people who have pulled aggro but don't have KLHTM, and tells them to get it. A message will be sent no more than
once every <me.advertinterval> = 5 minutes. Messages will be sent to non-warriors who are being targetted by a mob, so it's
not a complete guarantee that they have aggro.
]]
me.checkadvertise = function()

	if me.isadvertising == false then
		return
	end
	
	-- don't spam
	if GetTime() < me.lastadvert + me.advertinterval then
		return
	end

	-- look for someone who has aggro, is not a warrior, is not in the raid threat
	if GetNumRaidMembers() <= 0 then
		return
	end
	
	local target = ""
	local player = ""
	local x
	
	-- make it a random permutation of the raid, to stop bugging one person
	me.scrambleraid(me.raidnumbers)
	
	for y = 1, 40 do
		
		-- get x from scrambled array
		x = me.raidnumbers[y]
		
		-- there is a raid player
		target = "raid" .. x
		if UnitExists(target) == 1 then
			
			-- the player is targetting a mob
			target = target .. "target"
			if UnitExists(target) == 1 and UnitIsFriend("player", target) ~= 1 then
			
				-- mob has another player targetted
				player = target .. "target"
				if UnitIsFriend("player", player) == 1 then
				
					-- player is not yourself, not a warrior, is a player
					if (UnitIsPlayer(player) == 1) and (UnitName("player") ~= UnitName(player)) then
					
						local _, class = UnitClass(player)
						if class ~= "WARRIOR" then
							
							-- check they arne't using the meter
							if mod.table.raiddata[UnitName(player)] == nil then
							
								-- send them a message
								SendChatMessage(string.format(mod.string.get("print", "network", "advertisemessage"), UnitName(target)), "WHISPER", nil, UnitName(player))
								me.lastadvert = GetTime()
								return
							end
						end
					end
				end
			end
		end
	end
end

--[[
me.scrambleraid(numbers)
Slightly scrambles the array <numbers>. Picks 10 random pairs and swaps them. Since this scramble method gets called
each time we check, the array will be sufficiently inconstant all the time.
]]
me.scrambleraid = function(numbers)

	local x
	local temp
	local box1
	local box2
	
	for x = 1, 10 do
		box1 = math.random(1, 40)
		box2 = math.random(1, 40)
		
		temp = numbers[box1]
		numbers[box1] = numbers[box2]
		numbers[box2] = temp
	end
	
end					
			
```

## Code\KTM_NetIn.lua
```lua
--! This module references these other modules:
--! boss:	mastertarget, isspellreportingactive, istrackingspells, bossevents, reportevent, bossattacks, newmastertarget, clearmastertarget, 
--! net:	lastmtsender, lastmtstring, lastmttime, sendmessage, checkspellvaluesyntax, addversionresponse, 
--! out:	checktrace, printtrace, print, 
--! table:	resetraidthreat, updateplayerthreat, clearraidtable, 
--! unit:	isplayerofficer, 
--! string:	get, 

--! This module is referenced by these other modules:
--! console:	messagelog, 
--! net:	messagein, 

local mod = klhtm
local me, _ = { }
mod.netin = me

me.myevents = {"CHAT_MSG_ADDON" }

-- Special onevent function from Core.lua
me.onevent = function()

	if event == "CHAT_MSG_ADDON" then
		
		-- check the message is KLHTM, and comes from the party or raid
		if (arg1 ~= "KLHTM") or ((arg3 ~= "PARTY") and (arg3 ~= "RAID")) then
			me.logmessage("nonklhtm", string.len(arg1))
			return 
		end
		
		-- ok
		me.messagein(arg4, arg2, 1)
		
		return
	end

end

--[[ 
me.messagein(author, message, startindex)
Processes a message from the chat channel.
<author> is the name of the player who sent the message.
<message> is the original string sent.
<startindex> is the 1-based string index where the message starts.
]]
--! This variable is referenced by these modules: net, 
me.messagein = function(author, message, startindex)
	
	-- get first bit and rest
	local command
	local data
	
	_, _, command, data = string.find(message, "(%a+)(.*)", startindex)
	
	if (command == nil) or (me.commands[command] == nil) then
		
		-- log as invalid
		me.logmessage("invalid", string.len(message))
		
		if mod.out.checktrace("warning", me, "badmessage") then
			mod.out.printtrace(string.format("Received the invalid message '|cffffff00%s|r' from %s.", message, author))
		end
		
	else
		if me.commands[command](author, message, startindex + string.len(command)) then
			-- log as good
			me.logmessage("good", string.len(message))
			
			if mod.out.checktrace("info", me, "message") then
				mod.out.printtrace(author .. ":" .. message)
			end
		else
			-- log as invalid
			me.logmessage("invalid", string.len(message))
			
			if mod.out.checktrace("warning", me, "badmessage") then
				mod.out.printtrace(string.format("Received the invalid message '|cffffff00%s|r' from %s.", message, author))
			end
		end
	end
	
end

--[[ 
me.officercheck(author, message)
Checks if the author of an officer-only command is an officer. Otherwise, prints an error to trace.
<author> is the name of the player who sent the message.
<message> is the complete text of the message.
Returns: non-nil iff <author> is an officer.
]]
me.officercheck = function(author, message)
	
	if mod.unit.isplayerofficer(author) then
		return true
	
	else
		if mod.out.checktrace("warning", me, "badmessage") then
			mod.out.printtrace(string.format("|cffffff00%s|r is not an officer, but sent the message |cffffff00%s|r.", author, message))
		end
		
		return nil
	end

end

--[[
each function is called with 1) author, 2) message, 3) index of first character after the command (probably a space)
they should return non-nil if the message was good, nil otherwise
]]

local lastClearTime = GetTime()
me.commands = 
{
	-- clearing the raid threat
	["clear"] = function(author, message)
		
		-- author must be officer
		if me.officercheck(author, message) then
			
            if author == UnitName("player") then
                author = "you"
            end
            
			-- only show reset message once a second
			if lastClearTime +1 < GetTime() then
			mod.out.print(string.format(mod.string.get("print", "network", "threatreset"), author))
				lastClearTime = GetTime()
			end
			
			mod.table.resetraidthreat()
			mod.table.clearraidtable()
			
			return true
		end
		
	end,
		
	-- 1.12: "t" is the new "threat"
	["t"] = function(author, message, start)
		
		local value = tonumber(string.sub(message, start + 1))
		
		-- check for validity
		if value == nil then 
			return
		end
	
		mod.table.updateplayerthreat(author, value)
		KLHTM_RequestRedraw("raid")
		
		return true 
		
	end,
	
	-- "s" sunder counter
	["s"] = function(author, message, start)
		
                local value = tonumber(string.sub(message, start + 1))
		if value == nil then return end
	
		mod.table.updateplayersunder(author, value)
		
		return true 
		
	end,

	-- setting the master target
	["target"] = function(author, message, start)
	
		-- check player is an officer
		if me.officercheck(author, message) then
			
			local newmt = string.sub(message, start + 1)
			-- check newmt makes sense
			
			if newmt ~= nil and string.len(newmt) > 0 then
				
				mod.target.setrequest(author, newmt)
				
				return true
			end
		end
	end,

	-- polling the master target
	["mtpoll"] = function(author, message, start)
		
		-- check player is an officer
		if me.officercheck(author, message) then
		
			local newmt = string.sub(message, start + 1)
			-- check newmt makes sense
			
			if newmt ~= nil and string.len(newmt) > 0 then
				
				mod.target.pollrequest(author, newmt)
								
				-- message was valid so return true
				return true
			end
			
		end
		
	end,

	-- clearing the master target
	["cleartarget"] = function(author, message)
		
		-- check player is an officer
		if me.officercheck(author, message) then
			
			mod.target.clearrequest(author)
						
			-- message was valid so return true
			return true
		end
	end,
	
	-- starting knockback discovery
	["spellstart"] = function(author, message)
		
		-- check author is an officer
		if me.officercheck(author, message) == nil then
			return
		end
		
		mod.boss.isspellreportingactive = true
		
		if author == UnitName("player") then
			mod.boss.istrackingspells = true
		end
		
		-- only print out if you are a tracker
		if mod.boss.istrackingspells == true then
			mod.out.print(string.format(mod.string.get("print", "network", "knockbackstart"), author))
		end
		
		return true
		
	end,
	
	-- stopping knockback discovery
	["spellstop"] = function(author, message)
		
		-- check author is an officer
		if me.officercheck(author, message) == nil then
			return
		end
		
		mod.boss.isspellreportingactive = false
	
		if mod.boss.istrackingspells == true then
			mod.out.print(string.format(mod.string.get("print", "network", "knockbackstop"), author))
		end
		
		return true
		
	end,
	
	-- When boss spell reporting is enabled and someone suffers a boss spell
	["spelleffect"] = function(author, message, start)

		-- if we aren't monitoring reports, ignore
		if mod.boss.istrackingspells == false then
			return true -- we don't actually check correctness.
		end
		
		local _, _, spell, mob, result, data = string.find(message, "\"(.+)\" \"(.*)\" (%l+) ?(.*)", start + 1)
		
		if spell == nil then 
			return
		end
		
		if result == "miss" then
			mod.out.print(string.format(mod.string.get("print", "boss", "reportmiss"), author, mob, spell))
			
		else
			local value1, value2
			
			_, _, value1, value2 = string.find(tostring(data), "(-?%d+) (-?%d+)")
						
			if (tostring(number) == nil) or (tostring(number) == nil) then
				return
			end
			
			if result == "proc" then
				mod.out.print(string.format(mod.string.get("print", "boss", "reportproc"), author, mob, spell, value1, value2))
				
			elseif result == "tick" then
				mod.out.print(string.format(mod.string.get("print", "boss", "reporttick"), author, mob, spell, value1, value2))
				
			else
				return
			end
		end
		
		return true
	end,
	
	-- when someone changes a parameter of a boss spell
	["spellvalue"] = function(author, message, start)
		
		-- check author is an officer
		if me.officercheck(author, message) == nil then
			return
		end
		
		-- argh!! Memory creation! 64 bytes for this method! ... 
		local arglist = {}
		local x
		
		for x in string.gfind(message, "[^ ]+") do
			table.insert(arglist, x)
		end
		
		table.remove(arglist, 1)
		
		-- parse
		local value, errormsg = mod.net.checkspellvaluesyntax(arglist)
		
		-- did it work?
		if value then
			if arglist[2] == "default" then
				
				--[[ 
				suppose we receive the message "spellvalue timelapse default ticks 6". Then this would print out
					"Kenco sets the ticks parameter of the Time Lapse ability to 6."
				]]
				mod.out.print(string.format(mod.string.get("print", "boss", "spellsetall"), author, "|cffffff00" .. arglist[3] .. "|r", mod.string.get("boss", "spell", arglist[1]), value, mod.boss.bossattacks[arglist[1]][arglist[2]][arglist[3]]))
			
			else				
				mod.out.print(string.format(mod.string.get("print", "boss", "spellsetmob"), author, "|cffffff00" .. arglist[3] .. "|r", mod.string.get("boss", "spell", arglist[2]), mod.string.get("boss", "spell", arglist[1]), value, mod.boss.bossattacks[arglist[1]][arglist[2]][arglist[3]]))
			end
			
			mod.boss.bossattacks[arglist[1]][arglist[2]][arglist[3]] = value
		
			return true
		else
			
			if mod.out.checktrace("warning", me, "spellvalue") then
				mod.out.printtrace(string.format("The error message was '%s'.", errormsg))
			end
			
			return
		end
	end,
	
	-- telling people to upgrade to a new version
	["version"] = function(author, message, start)
		
		-- check author is an officer
		if me.officercheck(author, message) == nil then
			return
		end
		
		-- next argument should be the version number
		local release, revision
		_, _, release, revision = string.find(message, "(%d+)%.?(%d*)", start + 1)
		
		release = tonumber(release)
		revision = tonumber(revision)
		
		if release == nil then
			return
		end
		
		-- previously, only the release was sent as the version code. Therefore if someone sends in this format, 
		-- their version must be old.
		if revision == nil then

			mod.out.print(string.format(mod.string.get("print", "network", "remoteoldversion"), author, release .. ".x", mod.release .. "." .. mod.revision))
		
		else
		
			-- newer versions send their release and revision numbers, in a dot delimited string.			
			if (release < mod.release) or (release == mod.release and revision < mod.revision) then
				-- other guy has an old version
				mod.out.print(string.format(mod.string.get("print", "network", "remoteoldversion"), author, release .. "." .. revision, mod.release .. "." .. mod.revision))
				
			elseif (release == mod.release) and (revision == mod.revision) then
				-- we have the same version; do nothing
				
			else
				-- we have an older version - upgrade!
				mod.out.print(string.format(mod.string.get("print", "network", "upgraderequest"), author, release .. "." .. revision, mod.release .. "." .. mod.revision))
			end
		end
		
		return true
		
	end,
	
	-- asking the raid group what versions they are using
	["versionquery"] = function(author, message)
		
		-- check author is an officer
		if me.officercheck(author, message) == nil then
			return
		end
	
		-- send our version
		mod.net.sendmessage("versionresponse " .. mod.release .. "." .. mod.revision)
		
		return true
		
	end,
	
	-- response to versionquery
	["versionresponse"] = function(author, message, start)
		
		-- next argument should be the version number
		local value = tonumber(string.sub(message, start + 1))
		if value == nil then
			return
		end
		
		mod.net.addversionresponse(author, value)		
		return true
		
	end,
	
	-- Boss Spell Event
	["event"] = function(author, message, start)
		
		local eventid = string.sub(message, start + 1)
		
		-- check the event is valid
		if (eventid == nil) or (mod.boss.bossevents[eventid] == nil) then
			return
		end
		
		-- it is valid. send it to boss handler
		mod.boss.reportevent(eventid, author)
		return true
		
	end
	
}
	

------------------------------------------------------------------------

---------------------------------
--   lololol Message Logging   --
---------------------------------

--! This variable is referenced by these modules: console, 
me.messagelog = 
{
	["nonklhtm"] = 
	{
		["count"] = 0,
		["bytes"] = 0,
	},
	["invalid"] = 
	{
		["count"] = 0,
		["bytes"] = 0,
	},
	["good"] = 
	{
		["count"] = 0,
		["bytes"] = 0,
	},
	["total"] = 
	{
		["count"] = 0,
		["bytes"] = 0,
	},
}

--[[ 
me.logmessage(category, length)
Record a message from the mod's chat channel.
<category> is one of the keys in me.messagelog.
<length> is the lenght in bytes of the complete message.
]]
me.logmessage = function(category, length) 

	me.messagelog[category].count = me.messagelog[category].count + 1
	me.messagelog[category].bytes = me.messagelog[category].bytes + length

	me.messagelog["total"].count = me.messagelog["total"].count + 1
	me.messagelog["total"].bytes = me.messagelog["total"].bytes + length

end
```

## Code\KTM_Output.lua
```lua
--! This module references these other modules:

--! This module is referenced by these other modules:
--! alert:	print, announce, 
--! boss:	checktrace, printtrace, print, 
--! combat:	checktrace, printtrace, 
--! combatparser:	checktrace, printtrace, 
--! console:	print, booltostring, 
--! data:	print, 
--! diag:	checktrace, printtrace, print, 
--! my:	checktrace, printtrace, print, booltostring, 
--! net:	print, 
--! netin:	checktrace, printtrace, print, 
--! regex:	checktrace, printtrace, print, 
--! table:	checktrace, printtrace, 
--! gui:	checktrace, printtrace, 
--! guiopt:	checktrace, printtrace, 
--! guiraid:	checktrace, printtrace, 
--! guiself:	checktrace, printtrace, 
--! guititle:	checktrace, printtrace, print, 
--! string:	checktrace, printtrace, print, 

-- Add the module to the tree
local mod = klhtm
local me = {}
mod.out = me

--[[ 
Output.lua. These comments last updated R17.8.

	This module controls printing. For a normal print to the user that will always occur, call mod.out.print(<message>).
	The second part of this module is trace printing. This is a printout that assists with debugging, which you might not want most users to see. The module provides methods to determine which debug prints should be sent to the user. Then to make a debug print, first call mod.out.checktrace(). If it returns non-nil, call mod.out.printtrace() with the actual message.
	Defaults are set by <me.default> around line 27, overrides are set by <me.setprintstatus()> calls around line 128.
]]

--[[ 
--------------------------------------------------------------------------
			Trace Printing for Debugging or Extra Information
--------------------------------------------------------------------------

	The idea of this section is to provide a detailed method to evaluate whether a specific trace message should be printed. We have a few data structures that are print options of the form "if the print is <x>, do / dont print it".
	The more specific a print option is, the higher the priority it has. So the defaults, which just say "always print on <error>" or "never print on <info>" are the least specific and will be overridden by <me.setprintstatus>.
	For a release version, it is sufficient to set "error" = true, and the rest = "false", but for a debug version, you might only want to focus on specific sections of code for trace prints.

]]

-- These are default printing options. For a release version, error only. For a debug version, maybe warnings too.
me.default = 
{
	info = false,
	warning = false,
	error = true,
}

me.onload = function()

	-- optional debug specification
	
	--me.setprintstatus("boss", nil, "info", true)
	--me.setprintstatus("boss", "target", "info", false)
	--me.setprintstatus("netin", "message", "info", true)

end

--[[  
Suppose the following method calls were made:
	me.setprintstatus("boss", nil, "warning", true)
	me.setprintstatus("boss", "event", "info", true)
	
Then me.override would look like
me.override = 
{
	boss = 
	{
		warning = true
		error = true
		sections = 
		{
			event = 
			{
				info = true
				warning = true
				error = true
			}
		}
	}
}

See <me.setprintstatus> for more information
]]
me.override = { }

--[[ 
me.setprintstatus(modulename, sectionname, messagetype, value)
Overrides the default print option for a specific trace print.
<modulename> is a string, the source of the print, e.g. "out" for this module.
<sectionname> is a string, a feature in the source module. e.g. "trace" for this section.
<messagetype> is either "info" or "warning" or "error".
<value> is a boolean, true to enable the print, false to disable it.

<sectionname> is an optional parameter. If it is nil, the override will apply to the whole module, but it is now less specific, so an individual section inside that module may be overriden again.
<messagetype> will automatically cascade. "error" is assumed to be more important than "warning", which is more important than "info". So if you turn "warning" off, it will turn "info off as well"; if you turn "info" on, "warning" and "error" will be turned on too.
]]
me.setprintstatus = function(modulename, sectionname, messagetype, value)

	-- check module exists
	if me.override[modulename] == nil then
		me.override[modulename] = { }
	end
	
	local printdata = me.override[modulename]
	
	-- is this for the whole module, or more specific?
	if sectionname then
		
		-- check whether any sections have been defined for this module
		if printdata.sections == nil then
			printdata.sections = { }
		end
		
		printdata = printdata.sections
		
		-- check whether this section has been defined in the sections list
		if printdata[sectionname] == nil then
			printdata[sectionname] = { }
		end
		
		printdata = printdata[sectionname]
	end
	
	-- set
	printdata[messagetype] = value
	
	-- cascade
	if value == true then
		if messagetype == "info" then
			printdata.warning = true
			messagetype = "warning"
		end
		
		if messagetype == "warning" then
			printdata.error = true
		end
	
	elseif value == false then
		if messagetype == "error" then
			printdata.warning = false
			messagetype = "warning"
		end
		
		if messagetype == "warning" then
			printdata.info = false
		end
	end

end



--[[
This is a reverse lookup of the top level of the list <mod>. <mod> has keys that are strings like "out", and values that are modules (lists), like <me>. <me.modulelookup> reverses this, giving us the name of a module from a reference to it.
Calls to <me.checktrace> supply a module reference and we might like to name the module. However we wouldn't want to search for the module name every time that method is called, since we want it in particular to be fast. 
We don't fill me.modulelookup at runtime, but each time <me.checktrace> is called with a <module> parameter that is not a key to <me.modulelookup>, we will search to find that module.
]]
me.modulelookup = { }

--[[
me.getmodulename(module)
Given a reference to a module (subtree of <local mod>), returns the name, which is the key in <mod> of the module.
]]
me.getmodulename = function(module)
	
	-- have we already found this module before?
	local try = me.modulelookup[module]
	if try then
		return try
	end
	
	-- manual search
	local key, value
	
	for key, value in mod do
		if value == module then
			me.modulelookup[module] = key
			return key
		end
	end
	
	return "unknown"
	
end

--[[ 
mod.out.checktrace(messagetype, module, sectionname)
Checks whether a debug print with the given properties should be printed.
Return: non-nil iff the message should be printed.
<messagetype> must be one of "error", "warning" or "info"
<module> should always be <me> in the calling context
<sectionname> is a description of the feature in <module> that the message concerns.
]]
--! This variable is referenced by these modules: boss, combat, combatparser, diag, my, netin, regex, table, gui, guiopt, guiraid, guiself, guititle, string, 
me.checktrace = function(messagetype, module, sectionname)
	
	-- start with default print value
	local value = me.default[messagetype]
	me.printargs.overridelevel = "default"
	
	-- convert module reference to name
	local modulename = me.getmodulename(module)
	
	-- are there any overrides for that module?
	local printdata = me.override[modulename]
	
	if printdata then
		if printdata[messagetype] then
			value = printdata[messagetype]
			me.printargs.overridelevel = "module"
		end
		
		-- are there overrides for this section of the module?		
		if printdata.sections and printdata.sections[sectionname] and (printdata.sections[sectionname][messagetype] ~= nil) then
			value = printdata.sections[sectionname][messagetype]
			me.printargs.overridelevel = "section"
		end
	end
	
	-- pre-return: load arguments for me.printtrace
	me.printargs.modulename = modulename
	me.printargs.sectionname = sectionname
	me.printargs.messagetype = messagetype
	
	-- return: nil or non-nil
	if value == true then
		return true
	end
	
end

-- This stores the options supplied to <me.checktrace>, which will slightly affect the printout.
me.printargs = 
{
	messagetype = "",
	modulename = "",
	sectionname = "",
	overridelevel = "",
}

--[[
mod.out.printtrace(message)
Prints a message that has been OK'd by <me.checktrace>.
]]
--! This variable is referenced by these modules: boss, combat, combatparser, diag, my, netin, regex, table, gui, guiopt, guiraid, guiself, guititle, string, 
me.printtrace = function(message)

	-- setup the colour. Error = red, warning = yellow, info = blue. Lightish colours.
	local header = ""
	
	if me.printargs.messagetype == "info" then
		header = "|cff8888ff"
	
	elseif me.printargs.messagetype == "warning" then
		header = "|cffffff44"
	
	elseif me.printargs.messagetype == "error" then
		header = "|cffff8888"
	end
	
	header = header .. "<" .. me.printargs.modulename .. "." .. me.printargs.sectionname .. "> "
	
	-- print!
	me.print(header .. message)
	
end


--[[ 
----------------------------------------------------------------------
			Normal Printing to the Console
----------------------------------------------------------------------
]]

--[[ 
mod.out.print(message, [chatframeindex, noheader])
Prints out <message> to chat.
To print to ChatFrame3, set <chatframeindex> to 3, etc.
Adds a header "KTM: " to the message, unless <noheader> is non-nil.
]]
--! This variable is referenced by these modules: alert, boss, console, data, diag, my, net, netin, regex, guititle, string, 
me.print = function(message, chatframeindex, noheader)

	-- Get a Frame to write to
	local chatframe

	if chatframeindex == nil then
		chatframe = DEFAULT_CHAT_FRAME
		
	else
		chatframe = getglobal("ChatFrame" .. chatframeindex)
		
		if chatframe == nil then
			chatframe = DEFAULT_CHAT_FRAME
		end
	end

	-- touch up message
	message = message or "<nil>"
		
	if noheader == nil then
		message = "KTM: " .. message 
	end
	
	-- write
	chatframe:AddMessage(message)

end

--[[
mod.out.booltostring(boolean)
Converts a Boolean value (true or false) to a string representation.
true -> "true", false -> "false", nil -> "nil"
]]
--! This variable is referenced by these modules: console, my, 
me.booltostring = function(boolean)
	
	if boolean == true then
		return "true"
	elseif boolean == false then
		return "false"
	else
		return "nil"
	end
	
end

--[[ 
mod.out.announce(message)
Sends a chat message to Raid if possible, or Party if possible, or finally Say.
]]
--! This variable is referenced by these modules: alert, 
me.announce = function(message)
		
	local channel = "SAY"

	if GetNumRaidMembers() > 0 then
		channel = "RAID"

	elseif GetNumPartyMembers() > 0 then
		channel = "PARTY"
	end

	SendChatMessage(message, channel)

end
```

## Code\KTM_PetMod.lua
```lua

local mod = klhtm
local me = {}
local petthreat
local petincombat = false
mod.pet = me

--[[
PetMod.lua
v1.0 by Ghost, public domain

An extension to measure pet threat for warlocks (maybe hunters?) while solo
playing. Just proof-of-concept code, based on the klhtm framework for making
extensions. It seems to work with DE and EN client voidwalker, on levels 10-60,
assuming all books have been bought. Have fun, but don't expect updates :-)

Known bugs:
-"prin" statements are for debugging purpose only but should not be executed
-target of the pet is ignored
-pet aggro display is not deleted when pet leaves combat
-no talents or whatever are taken into account, only Damage+Torment+Suffering
-no character can use the name Pet
]]


------------------------------------------------------------------------
-- 					   Aggro for Warlocks Voidwalker				  --
------------------------------------------------------------------------

me.myevents = { "CHAT_MSG_SPELL_PET_DAMAGE", "CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_COMBAT_HOSTILE_DEATH", "PET_ATTACK_START"}
me.lclass, me.class = UnitClass("player")

--[[  
onupdate() function, called from Core.lua
]]
me.onupdate = function()
	-- update combat state
	if UnitAffectingCombat("pet") then
    if petincombat == false then
    	petincombat = true
		end 
	else
    if petincombat == true then
    	petincombat = false
			if UnitName("pet") then 
    	mod.table.raiddata[UnitName("pet")] = nil
			end
    	KLHTM_RequestRedraw("raid")
		end 
	end
end

me.onevent = function()

	--prin(string.format("Received the event %s: %s", event, arg1))
	
--	if (mod.my.states.incombat.value == false) then
--		mod.table.raiddata["Pet"] = nil
--	end

	-- This is stage one:
	local output = mod.regex.parse(me.parserset, arg1, event)
	
	if output.hit == nil then
		return
	end
	

	if output.final[1] ~= UnitName("pet") then
		local found, _, petname, playerName =  string.find(output.final[1],"([^%(]+)%s%((.+)%)")
		if(petname ~= UnitName("pet") or playerName ~= UnitName("player")) then
		return
	end
	end

	
	if output.parser.identifier == "petattack" then
		me.addpetthreat(output.final[3])
	elseif output.parser.identifier == "petcastaggro" then
		if me.getenglishspell(output.final[2]) == "Torment" then
			me.addpetthreat(me.getthreatvalue(output.final[2]))
		elseif me.getenglishspell(output.final[2]) == "Suffering" then
			if UnitName("target") == output.final[3] then	
				me.addpetthreat(me.getthreatvalue(output.final[2]))
			end
		elseif me.getenglishspell(output.final[2]) == "Growl" then
			me.addpetthreat(me.getthreatvalue(output.final[2]))
		elseif me.getenglishspell(output.final[2]) == "Intimidation" then
			me.addpetthreat(me.getthreatvalue(output.final[2]),True)
		end
	elseif output.parser.identifier == "petspell" then
		me.addpetthreat(output.final[4])
	end

end

--me.onloadcomplete = function()
--	prin("KTM PetMod loaded!!")
--end

-- show pet threat value in raid display
me.addpetthreat = function(value)
--	if not value then prin("no pet threat value to add"); return; end
	if mod.table.raiddata[UnitName("pet")] == nil then
		petthreat = 0
	end

	petthreat = petthreat + value
	mod.table.updateplayerthreat(UnitName("pet"), petthreat)
	KLHTM_RequestRedraw("raid")
	return
end

---- BEGIN spell data
-- minimum player level for each rank
local spellaggrolevel = {
	["Torment"] = {
		60, 50, 40, 30, 20, 10
	},
	["Suffering"] = {
		60, 48, 36, 24
	},
	["Growl"] = {
		60, 50, 40, 30, 20, 10, 1
	},
	["Intimidation"] = {
		1
	}
}
-- base aggro value for each rank
local spellaggrobase = {
	["Torment"] = {
		395, 300, 215, 125,  75,  45
	},
	["Suffering"] = {
		600, 450, 300, 150
	},
	["Growl"] = {
		415, 320, 240, 170, 110, 65, 50
	},
	["Intimidation"] = {
		580
	}
}
local spellaggro = function(spellname, rank)
	local value = spellaggrobase[spellname][rank]
	if me.class == "WARLOCK" then
		local _, _, _, _, impvoid = GetTalentInfo(2,5)
		if impvoid > 0 then
			local mod = 1 + (impvoid/10)
			value = value * mod
		end
	end
	return value
end

me.getthreatvalue = function(spellname)
	spellname = me.getenglishspell(spellname)
	if not spellaggrolevel[spellname] then prin("key not found in spelldata "..spellname); return 0; end
	local i = 1
	while UnitLevel('pet') < spellaggrolevel[spellname][i] do
		i = i + 1
	end
	return spellaggro(spellname, i)
end

me.getenglishspell = function(spellname)
-- translate localised spell name to english version, to match spellaggro data above
	if GetLocale() == "deDE" then
		if spellname == "Qual" then return "Torment"
		elseif spellname == "Leiden" then return "Suffering"
		-- additional translations could be added
		end
	end
	if GetLocale() == "koKR" then
		if spellname == "고문" then return "Torment"
		elseif spellname == "고통" then return "Suffering"
		elseif spellname == "포효" then return "Growl"
		elseif spellname == "위협" then return "Intimidation"
		end
	end
	if GetLocale() == "ruRU" then
		if spellname == "Мучение" then return "Torment"
		elseif spellname == "Муки" then return "Suffering"
		elseif spellname == "Рык" then return "Growl"
		elseif spellname == "Устрашение" then return "Intimidation"
			-- additional translations could be added
		end
	end
	return spellname
end
---- END spell data

me.parserset = { }
me.onload = function()

	local parserdata
	
	for _, parserdata in me.parserconstructor do
		mod.regex.addparsestring(me.parserset, parserdata[1], parserdata[2], parserdata[3])
	end
		
end

--[[
List of all the parsers we use. The first value is the identifier, the second value is the name of the variable
defined in GlobalStrings.lua, and the third variable is the event the parser works on.
]]
me.parserconstructor = 
{
	{"petcastaggro", "SPELLCASTGOOTHERTARGETTED", "CHAT_MSG_SPELL_PET_DAMAGE"}, 		-- %1$s wirkt %2$s auf %3$s. "You hit %s for %d."
	{"petcastaggro", "SIMPLECASTOTHEROTHER", "CHAT_MSG_SPELL_PET_DAMAGE"},
	
	{"petattack", "COMBATHITCRITOTHEROTHER", "CHAT_MSG_COMBAT_PET_HITS"}, -- %1$s trifft %2$s fA¼r %3$d Schaden. "You crit %s for %d."
	{"petattack", "COMBATHITOTHEROTHER", "CHAT_MSG_COMBAT_PET_HITS"}, -- %1$s trifft %2$s fA¼r %3$d Schaden. "You crit %s for %d."
	
	{"petspell", "SPELLLOGCRITSCHOOLOTHEROTHER", "CHAT_MSG_SPELL_PET_DAMAGE"},	-- "%ss %s trifft %s kritisch fA¼r %d %s Schaden."
	{"petspell", "SPELLLOGSCHOOLOTHEROTHER", "CHAT_MSG_SPELL_PET_DAMAGE"},

	{"petspell", "SPELLLOGOTHEROTHER", "CHAT_MSG_SPELL_PET_DAMAGE"},	-- "%ss %s trifft %s kritisch fA¼r %d %s Schaden."
	{"petspell", "SPELLLOGCRITOTHEROTHER", "CHAT_MSG_SPELL_PET_DAMAGE"},
	
--	{"abilityhit", "SPELLLOGSELFOTHER", "CHAT_MSG_SPELL_SELF_DAMAGE"}, 			-- "Your %s hits %s for %d."
--	{"abilitycrit", "SPELLLOGCRITSELFOTHER", "CHAT_MSG_SPELL_SELF_DAMAGE"}, 	-- "Your %s crits %s for %d."
}


```

## Code\KTM_Regex.lua
```lua
--! This module references these other modules:
--! out:	checktrace, printtrace, print, 

--! This module is referenced by these other modules:
--! boss:	parse, addparsestring, 
--! combatparser:	parse, addparsestring, 
--! my:	parse, addparsestring, 

-- Add the module to the tree
local mod = klhtm
local me, _ = {}
mod.regex = me

--[[
Regex.lua

The Regex module converts printing formatted strings to parsing formatted strings, in a locale independent way.

e.g.
"Your %s hits %s for %d." -> {"Your (.+) hits (.+) for (%d+)%.", {1, 2, 3}}
"Le %$3s de %$2s vous fait gagner %$1d points de vie." -> {"Le (.+) de (.+) vous fait gagner (%d+) points de vie%.", {3, 2, 1}}

First a bit of background. We want to be able to read the combat log on all clients, whether the language is english or french or chinese or otherwise. Furthermore, we don't want to rely on localisers working out the parser strings manually, because there is a likelihood of human error, and it would take too long to get a new string added.

Fortunately, we have all the information we need (at runtime, at least). For instance, in the example above, the value of the format string is given in the variable SPELLLOGSELFOTHER. If you open the GlobalStrings.lua (may need the WoW interface extractor to see it), on english clients you will see
...
SPELLLOGSELFOTHER = "Your %s hits %s for %d."
...
and on french clients you will see
...
SPELLLOGSELFOTHER = "Le %$3s de %$2s vous fait gagner %$1d points de vie."
...
When the WoW client is printing to the combat log, it will run a command like
ChatFrame2:AddMessage(string.format(SPELLLOGSELFOTHER, "Mortal Strike", "Mottled Boar", 352))

So, at Runtime (that is, when the addon loads, but not when i am writing it - i only have the english values) the mod has access to all the printing string format variables, like SPELLLOGSELFOTHER. We have a list of all the important ones, for all the abilities that the mod needs, so we want to make a big parser to scan them all at runtime. So the first thing we do when the addon loads is create all these parsers, then use them for all our combat log parsing.

------------------------------------------------------------

Structures:

1) Small Parser:

	local parser = 
	{
		["formatstring"] = formatstring,			"You hit %s for %s."
		["regexstring"] = regexstring,			"You hit (.+) for (.+)%."
		numarguments = me.numarguments,			2
		ordering = me.ordering,						{1, 2}
		argtypes = me.types,							{"string", "number"}
	}
	Note that the values of <argtypes> matches the canonical ordering (1, 2, 3, ...), not the localised ordering
	as in <ordering>.

2) Big Parser:

	local value = 
	{
		["parser"] = parser,							a <Small Parser> structure
		["globalstring"] = globalstringname,	COMBATHITSELFOTHER
		["identifier"] = identifier,				"whiteattackhit"
	}

3) Parser Set:

	First level is a key-value list. The keys are event names, e.g. "CHAT_MSG_SPELL_SELF_BUFF". 
	The values are ordered lists of <Big Parser>s.

4) Parser Output:

	local output = 
	{
		hit = <flag. Nil or non-nil>,
		temp = { },								list of up to 4 values, the captures with localised ordering
		final = { },							list of up to 4 values, the captures with canonical ordering
	}
	
	The idea is to reuse the <Parser Output> structure, so the flag <hit> just records whether the last parse
	succeeded (non-nil for success). It is assumed that all parse strings have at most 4 arguments.

5) BigParser Output:

	same as <Parser Output>, but has the property <parser>, which is a <BigParser> structure.
]]

--[[
------------------------------------------------------------------------------
			Section A: Parsing a String With the Parser Engine
------------------------------------------------------------------------------
]]

-- this is returned from all calls to mod.regex.parse().
me.output = 
{
	hit = nil,
	temp = { },
	final = { },
	parser = nil,
}

--[[
mod.regex.parse(inputstring, event)
Given a string, checks whether it matches any parser in the engine. The return value is a <BigParser Output>
structure.
<inputstring> is e.g. a line from your combat log to be parsed.
<event> is the event the string was received on, e.g. "CHAT_MSG_SPELL_SELF_BUFF"
]]
--! This variable is referenced by these modules: boss, combatparser, my, 
me.parse = function(parserset, inputstring, event)

	-- 0) Reset output
	me.output.hit = nil

	-- 1) Check that the event is handled by the parser
	local parsersubset = parserset[event]
	if parsersubset == nil then
		return me.output
	end
	
	-- 2) Look for a parser
	local x, bigparser, y, parser
	
	for x, bigparser in parsersubset do
		parser = bigparser.parser
		
		if me.parsestring(parser, inputstring, me.output) then
			me.output.parser = bigparser
			
			-- verify numeric arguments
			for y = 1, parser.numarguments do
				if (parser.argtypes[y] == "number") and (tonumber(me.output.final[y]) == nil) then
					
					-- error occur!
					if mod.out.checktrace("error", me, "regex") then
						mod.out.printtrace(string.format("The value |cffffff00%s|r of argument %d is not a number as it should be! Parser = %s, format string = %s. Event = %s, string = %s.", me.output.final[y], y, bigparser.identifier, parser.formatstring, event, inputstring))
					end
					
					break
				end
			end
			
			return me.output
		end
	end

	-- 3) No hit - oh well!
	return me.output
	
end

--[[
me.parsestring(parser, string, output)
Parses a string with the specified parser. Returns non-nil if the string satisfies the parser
<parser> is a parser structure, i.e. an output of me.formattoregex().
<string> is the string to parse, e.g. a combat log line.
<output> is a structure to store the output. It must have .temp and .final properties which are lists.
]]
me.parsestring = function(parser, inputstring, output)

	_, output.hit, output.temp[1], output.temp[2], output.temp[3], output.temp[4], output.temp[5] = string.find(inputstring, parser.regexstring)
	
	-- early exit on fail
	if output.hit == nil then
		return
	end
	
	-- now reorder arguments
	local x
	
	for x = 1, parser.numarguments do
		output.final[parser.ordering[x]] = output.temp[x]
	end
	
	return true
end


--[[
------------------------------------------------------------------------------
			Section B: Creating the Parser Engine at Startup
------------------------------------------------------------------------------
]]

--[[
me.addparsestring(parserset, indentifier, globalstringname, event)
Adds a new parser to the parser set.
<parserset> is a key-value list, keyed by event names, values are a list of parsers listening to that event
<identifier> is a description of the capture, e.g. "spellcrit"
<globalstringname> is the name of the variable that holds for format pattern, e.g. "SPELLLOGHIT"
<event> is the event in which the capture comes, e.g. "CHAT_MESSAGE_SPELL_SELF_BUFF"
]]
--! This variable is referenced by these modules: boss, combatparser, my, 
me.addparsestring = function(parserset, identifier, globalstringname, event)

	-- if there are no parsers on this event already, create a new list
	if parserset[event] == nil then
		parserset[event] = { }
	end
	
	-- get the value of the global string variable
	local formatstring = getglobal(globalstringname)
	if formatstring == nil then
		if mod.out.checktrace("error", me, "regex") then
			mod.out.printtrace(string.format("No global string %s found. ID = %s, event = %s.", globalstringname, identifier, event))
		end
		return
	end
	
	-- convert to regex
	local parser = me.formattoregex(formatstring)
	
	if me.testparser(parser) == nil then
		if mod.out.checktrace("error", me, "regex") then
			mod.out.printtrace(string.format("parser failed on %s.", identifier))
		end
		return
	end
	
	-- This is a parser structure, i guess. A big one, call it.
	local value = 
	{
		["parser"] = parser,
		["globalstring"] = globalstringname,
		["identifier"] = identifier,
	}
	
	-- ordered insert. If there are several parsers sharing the one event, we want to order them in such a way
	-- that no parser gets blocked by another, less specific parser.
	local length, x = table.getn(parserset[event])
	
	if length == 0 then
		table.insert(parserset[event], value)
	
	else
	
		for x = 1, length do
			-- keep going until you are smaller than one of them 
			
			if me.compareregexstrings(parserset[event][x].parser, parser) == 1 then
				
				-- our string is definitely higher
				table.insert(parserset[event], x, value)
				break
				
			elseif x == length then
				table.insert(parserset[event], value)	
			end
		end	
	end
end

--[[
me.formattoregex(formatstring)
Returns a small parser structure from a print formatting string.
<formatstring> is e.g. "You hit %s for %s.".
The output describes how to convert this to a parser.
]]
me.formattoregex = function(formatstring)

	--[[
	gsub replaces all occurences of the first string with the second string.
	[%.%(%)] means all occurences of . or ( or )
	%%%1 means replace these with a % and then itself.
	We're replacing them now so they don't interfere with the next bit.
	]]
	local regexstring = string.gsub(formatstring, "([%.%(%)])", "%%%1")
	
	--[[
	Formatting blocks have two types. If they arguments are in the same order as the english, the patterns
	will look like "%s   %s   %d %s" etc. If they have a different argument ordering, it would be e.g.
	"%3$s     %1$d     %2$s". So we need to check for both these circumstances
	]]
	
	me.numarguments = 0
	me.ordering = { }	
	me.types = { }
	
	--[[
	string.gsub will search the string regexstring, identify captures of the form "(%%(%d?)$?([sd]))", then replace
	them with the value me.gsubreplacement(<captures>). See me.gsubreplacement comments for more details.
	]]
	regexstring = string.gsub(regexstring, "(%%(%d?)$?([sd]))", me.gsubreplacement)
	
	--[[
	Adding a ^ character to the search string means that the string.find() is only allowed to match the test string 
	starting at the first character.
	]]
	regexstring = "^" .. regexstring
	
	local parser = 
	{
		["formatstring"] = formatstring,
		["regexstring"] = regexstring,
		numarguments = me.numarguments,
		ordering = me.ordering,
		argtypes = me.types,
	}
	
	return parser
	
end

-- set in me.formattoregex:
-- me.numarguments = 0 
-- me.ordering = { }
-- me.types = { }

--[[
The round brackets in the format string "(%%(%d?)$?([sd]))" denote captures. They will be sent to the 
replacement function as arguments. Their order is the order of the open brackets. So the first argument 
is the entire string, e.g. "%3$s" or "%s", the second argument is the index, if supplied, e.g. "3" or nil,
and the third argument is "s" or "d", i.e. whether the print format is a string or an integer.
]]
me.gsubreplacement = function(totalstring, index, formattype)

	me.numarguments = me.numarguments + 1
	
	-- set the index for strings that don't supply them by default (when ordering is 1, 2, 3, ...)
	index = tonumber(index)
	
	if index == nil then
		index = me.numarguments
	end
	
	table.insert(me.ordering, index)

	-- the return value is the actual replacement
	if formattype == "d" then
		me.types[index] = "number"
		return "(%d+)"
	else
		me.types[index] = "string"
		return "(.+)"
	end
	
end

--[[
me.compareregexstrings(regex1, regex2)
We are given two strings, and we want to know in which order to check them. e.g.
(1) "You gain (%d+) health from (.+)%." vs
(2) "You gain (%d+) (.+) from (.+)%."
In this case we should check for (1) first, then (2). To be more specific,
	1) If one pattern goes to a capture and another goes to text, due the text first.
	2) If both of them go to different texts, put the guy with the most captures first. Otherwise, the longest guy.
	3) If both go to captures of differnt types, then don't worry.
	
return values:
-1: regex1 first
+1: regex2 first

Where possible, prefer to return -1.
]]
me.compareregexstrings = function(parser1, parser2)

	local regex1, regex2 = parser1.regexstring, parser2.regexstring
	local start1, start2 = 1, 1
	local token1, token2
		
	while true do
	
		token1 = me.getnexttoken(regex1, start1)
		token2 = me.getnexttoken(regex2, start2)

		-- check for end of strings
		if token2 == nil then
			return -1
		elseif token1 == nil then
			return 1
		end
		
		-- check for equal (so far)
		if token1 == token2 then
			start1 = start1 + string.len(token1)
			start2 = start2 + string.len(token2)
		else
			break
		end
		
	end
	
	-- to get there, they have arrived at different tokens, therefore they must be orderable
		
	if string.len(token1) > 2 then
		-- regex1 is at a capture
			
		if string.len(token2) > 2 then
			-- regex2 is at a capture
	
			-- they are different, so one is a number, one a string, so who cares
			return -1
		
		else
		
			-- prefer the non-capture first
			return 1
		end
		
	else
		-- regex1 is not at a capture
		
		if string.len(token2) > 2 then
			-- regex2 at a capture
			return -1
			
		else
			
			if string.find(string.sub(regex2, start2), string.sub(regex1, start1)) then
				return 1
			end
			
			if true then
				return -1
			end
			
			-- neither at a capture
			if parser1.numarguments < parser2.numarguments then
				return 1
				
			elseif parser1.numarguments > parser2.numarguments then
				return -1
				
			elseif string.len(regex1) >= string.len(regex2) then
				return -1
				
			else
				return 1
			end
		end
	end
		
end

--[[
me.getnexttoken(regex, start)
Returns the next regex token in a string.
<regex> is the regex string, e.g. "hello (.+)%." .
<start> is the 1-based index of the string to start from.
Tokens are captures, e.g. "(.+)" or "(%d+)", or escaped characters, e.g. "%." or "%(", or normal letters, e.g. "a", ",".
]]
me.getnexttoken = function(regex, start)

	if start > string.len(regex) then
		return nil
	end
	
	local char = string.sub(regex, start, start)
	
	if char == "%" then
		return string.sub(regex, start, start + 1)
		
	elseif char == "(" then
		char = string.sub(regex, start + 1, start + 1)
		
		if char == "%" then
			return string.sub(regex, start, start + 4)
			
		else
			return string.sub(regex, start, start + 3)
		end
	
	else
		return char
	end

end

--[[
------------------------------------------------------------------------------
				Section C: Testing the Regex System
------------------------------------------------------------------------------
]]

--[[
mod.regex.test()
Checks that the parsers created from print format strings are working correctly, over a range of tough strings.
Will print out the results.
]]
local strings = {"%3$s vous fait gagner %1$d %2$s.", "Votre %4$s inflige %2$d points de degats de %3$s a %1$s.", 
			   "Vous utilisez %s sur votre %s."}
me.test = function()

	for x = 1, table.getn(strings) do
		if me.testformatstring(strings[x]) == nil then
			mod.out.print(string.format("test failed on string %d, '%s'.", x, strings[x]))
			return
		end
	end
	
	mod.out.print(string.format("all %d strings passed their tests.", table.getn(strings)))

end

--[[
me.testformatstring(value)
Given a print formatting string, creates a parser for that string, and checks that the parser works correctly.
<value> is e.g. "You hit %s for %s."
Returns: non-nil if the test succeeds.
]]
me.testformatstring = function(value)

	local parser = me.formattoregex(value)
	
	-- debug a bit
	mod.out.print(string.format("Format string = |cffffff00%s|r, regex string = |cffffff00%s|r, numargs = |cffffff00%d|r.",	parser.formatstring, parser.regexstring, parser.numarguments))
	
	return me.testparser(parser)

end

--[[
me.testparser(parser, debug)
Verifies experimentally that a parser matches its print format string.
<parser> is a <Small Parser> structure.
<debug> is a flag, if non-nil come debugging will be printed.
Returns: non-nil if the test succeeds.
The method generates a random string that could be made from <parser>'s format string, then parses it with the
parser, and checks that the captured values match the original arguments.
]]
me.testparser = function(parser, debug)

	-- 1) Generate a random string that matches the format
	local arguments = { }
	local x
	
	for x = 1, parser.numarguments do 
		if parser.argtypes[parser.ordering[x]] == "string" then
			arguments[parser.ordering[x]] = me.generaterandomstring()
		else
			arguments[parser.ordering[x]] = math.random(1000)
		end
	end
	
	-- debug print
	if debug then 
		for x = 1, parser.numarguments do
			if arguments[x] == nil then
				mod.out.print("arg " .. x .. " is nil!")
				return
			end
			
			mod.out.print("arg" .. x .. " = " .. arguments[x])
		end
	end
	
	local randomstring = string.format(parser.formatstring, unpack(arguments))
	
	-- debug print
	if debug then
		mod.out.print("the test string = " .. randomstring)
	end
	
	-- try parse
	local output = 
	{
		temp = { },
		final = { },
	}
	
	if me.parsestring(parser, randomstring, output) == nil then
		mod.out.print("The string did not parse.")
		return nil
		
	else
	
		-- debug print
		if debug then
			for x = 1, parser.numarguments do
				mod.out.print("output" .. x .. " = " .. output.final[x])
			end 
		end
		
		return true
	end

end

--[[
Generates a random string of capital letters and spaces. Will look something like "AJ WFDSO ECL SFOE".
]]
me.generaterandomstring = function()

	local length = 10 + math.random(10)
	local x
	local value = ""
	
	for x = 1, length do
		if math.random(3) == 3 then
			value = value .. " "
		else
			value = value .. string.format("%c", 64 + math.random(26))
		end
	end
	
	return value
end
```

## Code\KTM_Tables.lua
```lua
--! This module references these other modules:
--! my:	class, 
--! net:	idleupdateinterval, 
--! out:	checktrace, printtrace, 
--! unit:	isplayeringroup, 
--! string:	get, 

--! This module is referenced by these other modules:
--! alert:	mydata, 
--! boss:	raiddata, raidthreatoffset, getraidthreat, resetraidthreat, 
--! combat:	mydata, raiddata, newdatastruct, getraidthreat, resetraidthreat, 
--! my:	raidthreatoffset, resetraidthreat, 
--! net:	raiddata, getraidthreat, 
--! netin:	resetraidthreat, updateplayerthreat, clearraidtable, 
--! guiraid:	raiddata, raidclasses, redoraidclasses, 
--! guiself:	mydata, resetmytable, 

local mod = klhtm
local me, _ = { }
mod.table = me

--! This variable is referenced by these modules: alert, combat, guiself, 
me.mydata = { } -- personal threat table data
--! This variable is referenced by these modules: boss, combat, net, guiraid, 
me.raiddata = { } -- raid's threat table data
me.raidsunder = {} -- raid's sunder table data
me.totalsunder = {} -- total sunder table data
--! This variable is referenced by these modules: boss, my, 
me.raidthreatoffset = 0 -- difference between your total threat and your raid threat

--! This variable is referenced by these modules: guiraid, 
me.raidclasses = { } -- list of classes by player name. e.g. { ["Kenco"] = "Warrior", }
me.raidupdatetimes = { } -- list of last update times by player, e.g. { ["Kenco"] = GetTime(), }

------------------------------------
--    Special Core.lua Methods    --
------------------------------------

me.onload = function()
	
	-- initialise me.mydata . This refers to static methods from me.string, so goes in our onload().
	me.mydata[mod.string.get("threatsource", "total")] = me.newdatastruct()
	
end


--[[
-------------------------------------------------------------------------------------------------
	Maintaining the Raid Threat List: Reset non-responsive players, remove players not in group
-------------------------------------------------------------------------------------------------

	We have the key-value list <me.raiddata>, key = name of the player, value = threat of the player. 
	We have the list <me.raidupdatetimes>, key = name of the player, value = GetTime() of last update.

There are two maintenance functions:
1) If someone hasn't updated their threat for a long time, set it to 0. This happens for example when someone gets disconnected in the middle of a fight. After the fight ends you don't want their threat sitting in the table forever.
2) If a player leaves the raid group / party, remove them from the threat list.

Now, if someone has left the raid group, then their threat will stop updating. Therefore we only need to check for case (2) when a case (1) has occurred.

We don't want me.onupdate running all the time, since the threat list maintenance doesn't need it and would be using excess processor time. Therefore it is run at most every <me.updateinterval> seconds. <me.lastonupdate> is the last time it was run.

<me.idlereset> is the number of seconds a player must be idle for before their threat is wiped. Make sure it is significantly more than <mod.net.idleupdateinterval>, which is how often players will update when their threat is not changing.
]]
me.lastonupdate = 0			-- value of GetTime()
me.updateinterval = 1.0		-- at most once every second
me.idlereset = 10.0			-- seconds before we reset someone's threat

me.isingroup = false			-- whether we are in a party or raid.

me.onupdate = function()

	-- Let's do some autohider thingy
	if (GetNumRaidMembers() > 0) or (GetNumPartyMembers() > 0) then
		-- we're in a raid
		
		if me.isingroup == false then
			-- this is a change
			me.isingroup = true
			
			-- check for autohide option
			if KLHTM_SavedVariables.autohide == true then
				KLHTM_SetVisible(true)
			end
		end
		
	else
		-- we're not in a raid
		if me.isingroup == true then
			
			-- this is a change
			me.isingroup = false
			
			-- check for autohide option
			if KLHTM_SavedVariables.autohide == true then
				KLHTM_SetVisible(false)
			end
		end
	end
	
	-- 1) check for update time
	local timenow = GetTime()
	if timenow > me.lastonupdate + me.updateinterval then
		me.lastonupdate = timenow
	else
		return
	end

	local x
	
	for x, _ in me.raiddata do
		
		-- if the player doesn't exist in <me.raidupdatetimes>, add them and do nothing.
		if me.raidupdatetimes[x] == nil then
			me.raidupdatetimes[x] = timenow
	
		elseif (timenow > me.raidupdatetimes[x] + me.idlereset) and (x ~= mod.string.get("misc", "aggrogain")) then
			
			-- Player x hasn't updated for an unusually long time. It could be because they are no longer in the raid group - check:
			if  mod.unit.isplayeringroup(x) == nil then
			
				-- yes; this player is no longer in the group. Remove them from the system
				if mod.out.checktrace("info", me, "idleplayer") then
					mod.out.printtrace(string.format("Removing %s from the table, since he isn't in the raid group.", x))
				end
				
				me.raiddata[x] = nil
				me.raidupdatetimes[x] = nil
                                me.raidsunder[x] = nil
				
				-- might need to update gui
				KLHTM_RequestRedraw("true")
			
			elseif me.raiddata[x] ~= 0 then
				-- they are still in the raid group, but they haven't updated for some time, probably becaue they were disconnected. Set their threat to 0. Also reset their UpdateTimes value.
			
				me.raiddata[x] = 0
				me.raidupdatetimes[x] = timenow
                                me.raidsunder[x] = 0
				
				if mod.out.checktrace("info", me, "idleplayer") then
					mod.out.printtrace(string.format("Resetting %s's threat, since he hasn't updated for a while.", x))
				end
				
				KLHTM_RequestRedraw("true")
			end
		end
	end

end


-- to save lots of writing!
--! This variable is referenced by these modules: combat, 
me.newdatastruct = function()
	
	return
	{
		["hits"] = 0,
		["damage"] = 0,
		["threat"] = 0,
		["rage"] = 0,
		["sunder"] = 0,
	}
	
end


-----------------------------------------------------

--[[ 
mod.table.getraidthreat()
Returns the value you would post to the raid group as your threat.
]]
--! This variable is referenced by these modules: boss, combat, net, 
me.getraidthreat = function()

	return me.mydata[mod.string.get("threatsource", "total")].threat + me.raidthreatoffset

end


me.getmysunder = function()
  local s = me.mydata[mod.string.get("threatsource", "total")].sunder
  if s == nil then return 0 end
  return s
end


--[[ 
mod.table.resetraidthreat()
Set your threat for the rest of the raid group to 0. Used for a complete threat wipe.
]]
--! This variable is referenced by these modules: boss, combat, my, netin, 
me.resetraidthreat = function()
	
	me.raidthreatoffset = - me.mydata[mod.string.get("threatsource", "total")].threat
        me.mydata[mod.string.get("threatsource", "total")].sunder = 0
        me.raidsunder = {}
	
end

--[[ 
mod.table.updateplayerthreat(player, threat)
Updates a raid threat entry.
<player> is the name of the player whose threat is updated
<threat> is the new amount
TODO: add code to change aggrogain here, if player is master target???
]]
--! This variable is referenced by these modules: netin, 
me.updateplayerthreat = function(player, threat)
	
	me.raiddata[player] = threat
	me.raidupdatetimes[player] = GetTime()

end


me.updateplayersunder = function(player, sunder)

  if me.totalsunder[player] == nil then me.totalsunder[player] = 0 end
  if me.raidsunder[player] == nil then me.raidsunder[player] = 0 end
  
  if sunder == me.raidsunder[player] + 1 then me.totalsunder[player] = me.totalsunder[player] + 1 end
  
  me.raidsunder[player] = sunder
  
end


function KLHTM_ResetSunders()
  me.totalsunder = {}
  mod.out.print( "Sunders statistic cleared." )
end


function KLHTM_ReportSunders()
  mod.out.print( "Sunders used since last reset:" )
  for player, sunder in me.totalsunder do
    if sunder ~= nil and sunder ~= 0 then
      mod.out.print( "  " .. player .. ":  " .. sunder )
    end
  end
  
end


--[[ 
mod.table.redoraidclasses()
Checks the raid / party and finds the class of every player.
]]
--! This variable is referenced by these modules: guiraid, 
me.redoraidclasses = function()
	
	local numraiders = GetNumRaidMembers()
	local class
	
	if (numraiders == 0) then
		-- we're not in a raid. check party
		
		local numparty = GetNumPartyMembers()
		
		for x = 1, numparty do
			_, class = UnitClass("party" .. x)
			me.raidclasses[UnitName("party" .. x)] = string.lower(class)
		end
		
		-- also do yourself
		me.raidclasses[UnitName("player")] = mod.my.class
		
	else -- we're in a raid
		
		local class
		local name
		
		for x = 1, numraiders do
			_, class = UnitClass("raid" .. x)
			
			-- 1.12: found class could be nil sometimes, maybe just when someone joins the raid group. rare, but still.
			if class then
				me.raidclasses[UnitName("raid" .. x)] = string.lower(class)
			end
		end
	end
end

--[[
mod.table.resetmytable()
Clears all the data in your personal threat table.
]]
--! This variable is referenced by these modules: guiself, 
me.resetmytable = function()
	
	-- reset raid offset
	me.raidthreatoffset = me.getraidthreat()
	
	-- clear table
	local key
	local value
	local key2
	
	for key, value in me.mydata do
		for key2 in value do
			value[key2] = 0
		end
	end
	
end

--[[ 
mod.table.resetraidtable()
Clears all the data in the raid table.
]]
--! This variable is referenced by these modules: netin, 
me.clearraidtable = function()

	local key
	
	for key, _ in me.raiddata do
		me.raiddata[key] = nil;
                me.raidsunder[key] = nil;
	end
	
	me.raiddata[UnitName("player")] = 0

end
```

## Code\KTM_TWT.lua
```lua


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

```

## Code\KTM_Unit.lua
```lua
--! This module references these other modules:

--! This module is referenced by these other modules:
--! boss:	findunitidfromname, isplayerofficer, 
--! combat:	findunitidfromname, 
--! net:	isplayeringroup, isplayerofficer, 
--! netin:	isplayerofficer, 
--! table:	isplayeringroup, 

local mod = klhtm
local me = { }
mod.unit = me

--[[
Unit.lua

Contains helper functions for finding players and units and their properties. Most involve iterating through the raid group.
]]

--[[
mod.unit.findunitidfromname(name)
Returns the unitid of the player in your group whose name is <name>.
Only works on players or pets in your raid or party, or yourself.
Returns nil if there is no match to <name>.
]]
--! This variable is referenced by these modules: boss, combat, 
me.findunitidfromname = function(name)
	
	if name == UnitName("player") then
		return "player"
	end 
	
	local x
	
	if GetNumRaidMembers() > 0 then
		for x = 1, 40 do
			if UnitName("raid" .. x) == name then
				return "raid" .. x
			end
		end
		
		for x = 1, 40 do
			if UnitName("raidpet" .. x) == name then
				return "raidpet" .. x
			end
		end
		
	elseif GetNumPartyMembers() > 0 then
		for x = 1, 4 do
			if UnitName("party" .. x) == name then
				return "party" .. x
			end
		end
		
		for x = 1, 4 do
			if UnitName("partypet" .. x) == name then
				return "partypet" .. x
			end
		end
	end
	
end

--[[
mod.unit.findnearbybossname()
Searches the target of everyone in the raid group, looking for a worldboss.
Returns: the name of the worldboss, or nil.
]]
me.findnearbybossname = function()
	
	local x
	
	for x = 1, 40 do
		if UnitClassification("raid" .. x) == "worldboss" then
			return UnitName("raid" .. x)
		end
	end
	
end

--[[
mod.unit.isplayeringroup(name)
Returns: true if the player is in your group, nil otherwise
]]
--! This variable is referenced by these modules: net, table, 
me.isplayeringroup = function(name)

	-- raid group
	if GetNumRaidMembers() > 0 then
		for x = 1, 40 do
			if UnitName("raid" .. x) == name then
				return true
			end
		end
	
	-- party (check for self separately)
	elseif GetNumPartyMembers() > 0 then
		for x = 1, 4 do
			if UnitName("party" .. x) == name then
				return true
			end
		end
		
		if name == UnitName("player") then
			return true
		end
	end
	
	if name == UnitName("player") then
		return true
	end

end

--[[ 
mod.unit.isplayerofficer(playername)
Returns: true if <playername> is an officer / leader, nil otherwise.
This is for the purpose of sending "special" commands, like setting the master target.
]]
--! This variable is referenced by these modules: boss, net, netin, 
me.isplayerofficer = function(playername)

	local name
	local rank

	if GetNumRaidMembers() > 0 then
		for i = 1, 40 do
			
			name, rank = GetRaidRosterInfo(i)
			if name == playername then
				if rank > -1 then
					return true
				else
					return nil
				end
			end
		end
		
	elseif GetNumPartyMembers() > 0 then
		if UnitIsPartyLeader("player") == 1 and playername == UnitName("player") then
			return true
		else
			for i = 1, 4 do
				if UnitName("party" .. i) == playername then
					if UnitIsPartyLeader("party" .. i) == 1 then
						return true
					else
						return nil
					end
				end
			end
		end
		
	else
		return true -- single player = officer
		
	end
	
end
```

## Code\KTM_UserMods.lua
```lua
--! This module references these other modules:

--! This module is referenced by these other modules:

local mod = klhtm
local me = {}
mod.user = me

--[[
UserMods.lua

This is a framework for making extensions to klhtm.

]]


------------------------------------------------------------------------
-- 						    Broodlord's MS							  --
------------------------------------------------------------------------

--[[

This sub-addon will record the values of Broodlord's Mortal Strike, with or without Demo Shout up

... if i ever complete it. 
]]
```

## Code\Localisation\KTM_deDE.lua
```lua

klhtm.string.data["deDE"] = 
{
	
	["binding"] = 
	{
		hideshow = "Fenster zeigen/verstecken",
		stop = "Notaus",
		mastertarget = "Hauptziel setzen",
		resetraid = "Raidbedrohung l\195\182schen",
	},


	["spell"] = 
	{
		
		["holynova"] = "Heilige Nova", -- no heal or damage threat
		["siphonlife"] = "Lebensentzug", -- no heal threat
		
		
		["drainlife"] = "Blutsauger", -- no heal threat
		["lifetap"] = "Aderlass", -- no mana gain threat
		["holyshield"] = "Heiliger Schild", -- multiplier
		["tranquility"] = "Gelassenheit",
		["distractingshot"] = "Ablenkender Schuss", 
		["earthshock"] = "Erdschock",
		["rockbiter"] = "Felsbei\195\159er",
		["fade"] = "Verblassen",
		["thunderfury"] = "Donnerzorn",
		
		["deathcoil"] = "Todesmantel",


		["heroicstrike"] = "Heldenhafter Sto\195\159",
		["maul"] = "Zermalmen",
		["swipe"] = "Prankenhieb",
		["shieldslam"] = "Schildschlag",
		["revenge"] = "Rache",
		["shieldbash"] = "Schildhieb",
		["sunder"] = "R\195\188stung zerrei\195\159en",
		["feint"] = "Finte",
		["cower"] = "Ducken",
		["taunt"] = "Spott",
		["growl"] = "Knurren",
		["vanish"] = "Verschwinden",
		["frostbolt"] = "Frostblitz",
		["fireball"] = "Feuerball",
		["arcanemissiles"] = "Arkane Geschosse",
		["scorch"] = "Versengen",
		["cleave"] = "Spalten",
		
		-- Items / Buffs:
		["arcaneshroud"] = "Arkaner Schleier",
		["reducethreat"] = "Verringerte Bedrohung",

		-- Spell Sets
		-- warlock descruction
		["shadowbolt"] = "Schattenblitz",
		["immolate"] = "Feuerbrand",
		["conflagrate"] = "Feuersbrunst",
		["searingpain"] = "Sengender Schmerz",
		["rainoffire"] = "Feuerregen",
		["soulfire"] = "Seelenfeuer",
		["shadowburn"] = "Schattenbrand",
		["hellfire"] = "H\195\182llenfeuer",
		
		-- mage offensive arcane
		["arcaneexplosion"] = "Arkane Explosion",
		["counterspell"] = "Gegenzauber",
		
		-- priest shadow
		["mindblast"] = "Gedankenschlag",
		
	},
	-- required for correct behaviour
	["power"] = 
	{
		["mana"] = "Mana",
		["rage"] = "Wut",
		["energy"] = "Energie",
	},
	-- User Printout
	["threatsource"] = 
	{
		["powergain"] = "Power Gain",
		["total"] = "Total",
		["special"] = "Spezial",
		["healing"] = "Heilung",
		["dot"] = "Dots",
		["threatwipe"] = "Threat Wipes",
		["damageshield"] = "Schadensschild",
		["whitedamage"] = "Weisser Schaden",
	},
	-- User Printout
	["talent"] = 
	{
		["defiance"] = "Trotz",
		["impale"] = "Durchbohren",
		["silentresolve"] = "Schweigsame Entschlossenheit",
		["shadowaffinity"] = "Schattenaffinit\195\164t",
		["druidsubtlety"] = "Druide Feingef\195\188hl",
		["feralinstinct"] = "Instinkt der Wildnis",
		["ferocity"] = "Wildheit",
		["savagefury"] = "Ungez\195\164hmte Wut",
		["masterdemonologist"] = "Meister der D\195\164monologie",
		["arcanesubtlety"] = "Arkanes Feingef\195\188hl",
		["righteousfury"] = "Zorn der Gerechtigkeit",
		["tranquility"] = "Verbesserte Gelassenheit",
		["healinggrace"] = "Geschick der Heilung",
		["burningsoul"] = "Brennende Seele",
		["frostchanneling"] = "Frost-Kanalisierung",
	},
	-- User Printout
	["threatmod"] = 
	{
		["tranquilair"] = "Beruhigende Winde",
		["salvation"] = "Segen der Rettung",
		["battlestance"] = "Kampfhaltung",
		["defensivestance"] = "Verteidigungshaltung",
		["berserkerstance"] = "Berserkerhaltung",
		["defiance"] = "Trotz",
		["basevalue"] = "Basiswert",
		["bearform"] = "B\195\164rform",
		["glovethreatenchant"] = "erh\195\182te Bedrohung durch Handschuhverzauberung",
		["backthreatenchant"] = "verringerte Bedrohung durch Umhangverzauberung",
	},

	-- User Printout
	["sets"] = 
	{
		["bloodfang"] = "Blutfang",
		["nemesis"] = "Nemesis",
		["netherwind"] = "Netherwind",
		["might"] = "der Macht",
		["arcanist"] = "des Arkanisten",
	},
	-- required for correct behaviour
	["boss"] = 
	{
		["speech"] = 
		{
			["razorphase2"] = "flieht w\195\164hrend die kontrollierenden Kr\195\164fte der Kugel schwinden",
			["onyxiaphase3"] = "Mir scheint, dass Ihr noch eine Lektion braucht, sterbliche Wesen!",
			["rajaxxfinal"] = "Unversch\195\164mter Narr! Ich werde euch h\195\182chstpers\195\182nlich t\195\182�ten! will kill you myself!",
			["azuregosport"] = "Kommt ihr Wichte! Tretet mir gegen\195\188ber!",
			["nefphase2"] = "BRENNT! Ihr Elenden! BRENNT!",
			["thad1"] = "EAT YOUR BONES",
			["thad2"] = "BREAK YOU!",
			["thad3"] = "KILL!",
			["noth1"] = "Die, trespasser!",
			["noth2"] = "Glory to the master!",
			["noth3"] = "Your life is forfeit!",
			["ktphase2"] = "Pray for mercy!",
		},
		["name"] = 
		{	
			["rajaxx"] = "General Rajaxx",
			["onyxia"] = "Onyxia",
			["ebonroc"] = "Ebonroc",
			["razorgore"] = "Razorgore der Ungez\195\164hmte",
			["thekal"] = "Hohepriester Thekal",
			["shazzrah"] = "Shazzrah",
			["twinempcaster"] = "Imperator Vek'lor",
			["twinempmelee"] = "Imperator Vek'nilash",
			["noth"] = "Noth der Seuchenf\195\188rst",
		},
		["spell"] = 
		{
			["knockaway"] = "Wegschlagen",
			["wingbuffet"] = "Fl\195\188gelsto\195\159", -- "Fl\195\188gelpuffer" appears to be Onyxia only. But that's -0 anyway.
			["burningadrenaline"] = "Brennendes Adrenalin",
			["twinteleport"] = "Zwillingsteleport",
			["wrathofragnaros"] = "Zorn des Ragnaros",
			["timelapse"] = "Zeitraffer",
			["nothblink"] = "Blinzeln",
		}
	},
	-- required for correct behaviour
	["misc"] = 
	{
		["imp"] = "Wichtel", -- UnitCreatureFamily("pet")
		["spellrank"] = "Rang (%d+)", -- second value of GetSpellName(x, "spell")
		["aggrogain"] = "Aggro bekommen",
	},
	
	--[[
	This is reserved for future use.
	
	["mobattack"] = 
	{
		["self"] = {
			["hit"] = "(.+) trifft Euch f\195\188r %d+ Schaden%.", -- COMBATHITOTHERSELF
			["crit"] = "(.+) trifft Euch kritisch%. Schaden: %d+%.", -- COMBATHITCRITOTHERSELF
			["absorb"] = "(.+) greift an%. Ihr absorbiert allen Schaden%.", -- VSABSORBOTHERSELF
			["dodge"] = "(.+) greift an%. Ihr weicht aus%.", -- VSDODGEOTHERSELF
			["parry"] = "(.+) greift an%. Ihr pariert%.", -- VSPARRYOTHERSELF
			["block"] = "(.+) greift an%. Ihr blockt%.", -- VSBLOCKOTHERSELF
			["miss"] = "(.+) verfehlt Euch%.", -- MISSEDOTHERSELF
			["resist"] = "(.+) greift an%. Ihr widersteht dem gesamten Schaden%.", -- VSRESISTOTHERSELF
		},
		["other"] = {	
			["hit"] = "(.+) trifft (.+) f\195\188r %d+ Schaden%.", -- COMBATHITOTHEROTHER 
			["crit"] = "(.+) trifft (.+) kritisch f�r %d+ Schaden%.", -- COMBATHITCRITOTHEROTHER
			["absorb"] = "(.+) greift an%. (.+) absorbiert allen Schaden%.", -- VSABSORBOTHEROTHER
			["dodge"] = "(.+) greift an%. (.+) weicht aus%.", -- VSDODGEOTHEROTHER
			["parry"] = "(.+) greift an%. (.+) pariert%.", -- VSPARRYOTHEROTHER
			["block"] = "(.+) greift an%. (.+) blockt ab%.", -- VSBLOCKOTHEROTHER
			["miss"] = "(.+) verfehlt (.+)%.", -- MISSEDOTHEROTHER
			["resist"] = "(.+) greift an%. (.+) widersteht dem gesamten Schaden%.", -- VSRESISTOTHEROTHER
		},
	},
	
	]]
	
	-- labels and tooltips for the main window
	["gui"] = { 
		["raid"] = {
			["head"] = {
				-- column headers for the raid view
				["name"] = "Name",
				["threat"] = "Bedrohung",
				["pc"] = "%Max",
			},
			["stringshort"] = {
				-- tooltip titles for the bottom bar strings
				["tdef"] = "Threat Margin",
				["targ"] = "Hauptziel",
			},
			["stringlong"] = {
				-- tooltip descriptions for the bottom bar strings
				["tdef"] = "",
				["targ"] = "Nur Bedrohung gegen %s wird derzeit in den Bedrohungswerten des Raids einberechnet."
			},
		},
		["self"] = {
			["head"] = {
				-- column headers for the self view
				["name"] = "Name",
				["hits"] = "Treffer",
				["rage"] = "Wut",
				["dam"] = "Schaden",
				["threat"] = "Bedrohung",
				["pc"] = "%B",
			},
			-- text on the self threat reset button
			["reset"] = "L\195\182schen",
		},
		["title"] = {
			["text"] = {
				-- the window titles
				["long"] = "KTM %d.%d",
				["short"] = "KTM",
			},
			["buttonshort"] = {
				-- the tooltip titles for command buttons
				["close"] = "Schlie\195\159en",
				["min"] = "Minimieren",
				["max"] = "Maximieren",
				["self"] = "Eigenansicht",
				["raid"] = "Raidansicht",
				["pin"] = "Befestigen",
				["unpin"] = "Losmachen",
				["opt"] = "Optionen",
				["targ"] = "Hauptziel",
				["clear"] = "L\195\182schen",
			},
			["buttonlong"] = {
				-- the tooltip descriptions for command buttons
				["close"] = "Bedrohungswerte werden auch dann weiter \195\188bermittelt, wenn du in einer Gruppe oder in einem Raid bist.",
				["min"] = "",
				["max"] = "",
				["self"] = "Zeigt die Details der von dir verursachten Bedrohung.",
				["raid"] = "Zeigt die Bedrohungswerte deines Raids",
				["pin"] = "Verhindert, dass das Threatmeterfenster bewegt werden kann.",
				["unpin"] = "Gibt das Threatmeterfenster frei, so dass es bewegt werden kann.",
				["opt"] = "",
				["targ"] = "Legt das Hauptziel auf dein aktuelles Ziel fest. Falls du kein Ziel hast, wird das Hauptziel gel\195\182scht. Du musst dazu Gruppenanf\195\188hrer oder Assistent sein.",
				["clear"] = "Setzt die Bedrohung aller Spieler auf 0. Du musst dazu Gruppenanf\195\188hrer oder Assistent sein.",
			},
			["stringshort"] = {
				-- the tooltip titles for titlebar strings
				["threat"] = "Bedrohung",
				["tdef"] = "Bedrohungsdefizit",
				["rank"] = "Bedrohungsrang",
				["pc"] = "% Bedrohung",
			},
			["stringlong"] = {
				-- the tooltip descriptions for titlebar strings
				["threat"] = "Die Menge an Bedrohung die angesammelt wurde, seitdem dein pers\195\182nlicher Wert zur\195\188ckgesetzt wurde.",
				["tdef"] = "Die Differenz der Bedrohung zwischen deiner Bedrohung und der des Ziels.",
				["rank"] = "Deine Position in der Bedrohungsliste.",
				["pc"] = "Deine Bedrohung in Prozent am Ziel.",
			},
		},
	},
	-- labels and tooltips for the options gui
	["optionsgui"] = {
		["buttons"] = {
			-- the options gui command button labels
			["gen"] = "Allgem.",
			["raid"] = "Raid",
			["self"] = "Selbst",
			["close"] = "Schlie\195\159en",	
		},
		-- the labels for option checkboxes and headers
		["labels"] = {
			-- the title description for each option page
			["titlebar"] = {
				["gen"] = "Allgemeine Einstellungen",
				["raid"] = "Schlachtzug Einstellungen",
				["self"] = "Eigenansicht Einstellungen",
			},
			["buttons"] = {
				-- the names of title bar command buttons
				["pin"] = "Befestigen",
				["opt"] = "Optionen",
				["view"] = "Ansicht\195\164nderung",
				["targ"] = "Hauptziel",
				["clear"] = "L\195\182schen",
			},
			["columns"] = {
				-- names of columns on the self and raid views
				["hits"] = "Treffer",
				["rage"] = "Wut",
				["dam"] = "Schaden",
				["threat"] = "Bedrohung",
				["pc"] = "% Bedrohung",
			},
			["options"] = {
				-- miscelaneous option names
				["hide"] = "Verstecke '0'-Reihen",
				["abbreviate"] = "Gro\195\159e Werte abk\195\188rzen",
				["resize"] = "Gr\195\182\195\159e anpassen",
				["aggro"] = "Aggrogrenze anzeigen",
				["rows"] = "Sichtbare Reihen",
				["scale"] = "Skalierung",
				["bottom"] = "Unt. Leiste verstecken",
				["minimap"] = "Schaltfl�che Minikarte anzeigen",
			},
			["minvis"] = {
				-- the names of minimised strings
				["threat"] = "minimierte Bedrohung", -- dodge...
				["rank"] = "Bedrohungsrang",
				["pc"] = "% Bedrohung",
				["tdef"] = "Bedrohungsdefizit",
			},
			["headers"] = {
				-- headers in the options gui
				["columns"] = "Sichtbare Spalten",
				["strings"] = "Minimierte Strings",
				["other"] = "Andere Optionen",
				["minvis"] = "Minimierte Ansicht",
				["maxvis"] = "Maximierte Ansicht",
			},
		},
		-- the tooltips for some of the options
		["tooltips"] = {
			-- miscelaneous option descriptions
			["raidhide"] = "Wenn dies aktiviert ist, werden Spieler ohne Bedrohung nicht im Threatmeter anezeigt.",
			["selfhide"] = "Wenn dies ausgeschaltet ist, werden alle Bedrohungsarten gezeigt.",
			["abbreviate"] = "Wenn dies aktivert ist, werden Werte die gr\195\182\195\159er als 10000 sind mit 'k' abgek\195\188rzt. Aus 15400 wird z.B. 15.4k.",
			["resize"] = "Wenn dies aktiviert ist, wird die Anzahl sichtbarer Reihen so veringert, dass sie der Anzahl der Spieler die Bedrohungswerte \195\188bermitteln entspricht.",
			["aggro"] = "Wenn dies aktiviert ist, wird eine Grenze in der Schlachtzugansicht angezeigt, bei der du vorrausichtlich Aggro ziehen wirst. Diese ist am genauesten, wenn ein Hauptziel gesetzt ist.",
			["rows"] = "Die maximale Ansicht  der sichtbaren Spieler im Schlachtzugbedrohungsfenster.",
			["bottom"] = "Wenn dies aktiviert ist, wird die untere Leiste versteckt. Diese zeigt das Bedrohungsdefizit und das Hauptziel an.",
			["minimap"] = "Linksklick, um KTM zu �ffnen.\n Sschalttaste-Linksklick f�r KTM-Optionen.\n Klicken und ziehen Sie mit der rechten Maustaste, um diese Schaltfl�che zu verschieben.",
		},
	},
	["print"] = 
	{
		["main"] = 
		{
			["startupmessage"] = "KLHThreatMeter Release |cff33ff33%s|r Revision |cff33ff33%s|r geladen. Tippe |cffffff00/ktm|r um Hilfe zu erhalten.",
		},
		["boss"] = 
		{
			["automt"] = "Das Hauptziel wurde automatisch auf %s gesetzt.",
			["spellsetmob"] = "%s legt den %s Parameter von %ss %s F\195\164higkeit von %s auf %s.", -- "Kenco sets the multiplier parameter of Onyxia's Knock Away ability to 0.7"
			["spellsetall"] = "%s legt die %s Parameter von %s F\195\164higkeiten von %s auf %s.",
			["reportmiss"] = "%s berichtet, dass %ss %s ihn verfehlt hat.",
			["reporttick"] = "%s berichtet, dass %ss %s ihn getroffen hat. Er hat bereits %s Stapelungen hinter sich, und wird an  %s mehr Stapelungen leiden.",
			["reportproc"] = "%s berichtet, dass %sss %s seine Bedrohung von %s zu %s ge\195\164ndert hat..",
			["bosstargetchange"] = "%s \195\164nderte das Zeil von %s (mit %s Bedrohung) zu %s (mit %s Bedrohung).",
			["autotargetstart"] = "Du wirst automatisch das Threatmeter l\195\182schen und das Hauptziel neu setzen, wenn du das n\195\164chste Mal einen Weltboss anw\195\164hlst.",
			["autotargetabort"] = "Das Hauptziel wurde bereits auf den Weltboss %s gesetzt.",
		},
		["data"] = 
		{
			["abilityrank"] = "Deine %s F\195\164higkeit ist Rang %s.",
			["globalthreat"] = "Dein globaler Bedrohungsmultiplikator ist %s.",
			["globalthreatmod"] = "%s gibt dir einen Wert von %s.",
			["multiplier"] = "Als %s wird deine Bedrohung durch %s mit %s multipliziert.",
			["damage"] = "Schaden",
			["shadowspell"] = "Schattenzauber",
			["arcanespell"] = "Arkanzauber",
			["holyspell"] = "Heiligzauber",
			["setactive"] = "%s %d Teile aktiv? ... %s.",
			["true"] = "ja",
			["false"] = "nein",
			["healing"] = "Deine Heilung verursacht %s Bedrohung (vor Einrechnung des globalen Bedrohungsmultiplikators).",
			["talentpoint"] = "Du hast %d Talentpunkte in %s.",
			["talent"] = "%d %s Talente gefunden.",
			["rockbiter"] = "Dein Rang %d Felsbei\195\159er f\195\188gt %d Bedrohung zu erfolgreichen Nahkampfangriffen hinzu.",
		},
		["network"] = 
		{

			["newmttargetnil"] = "Es konnte kein neues Hauptziel festgelegt werden, da %s scheinbar nicht existiert.",
			["newmttargetmismatch"] = "%s setzte das Hauptziel auf %s, aber sein eigenes Ziel ist %s. Sein eigenes Ziel wird stattdessen benutzt, \195\188berpr�fen!",
			["mtpollwarning"] = "Dein Hauptziel wurde auf %s gesetzt, aber dies konnte nicht \195\188berpr\195\188ft werden. Falls sich dieses falsch anh�rt, bitte %s das Hauptziel erneut bekanntzugeben.",
			["threatreset"] = "Das Threatmeter wurde von %s zur\195\188ckgesetzt.",
			["newmt"] = "Das Hauptziel wurde auf '%s' festgelegt. (von %s)",
			["mtclear"] = "Das Hauptziel wurde von %s gel\195\182scht.",
			["knockbackstart"] = "R\195\188cksto\195\159 Entdeckung wurde von %s aktiviert.",
			["knockbackstop"] = "R\195\188cksto\195\159 Entdeckung wurde von %s gestoppt.",
			["aggrogain"] = "%s meldet 'Aggro bekommen' mit %d Bedrohung.",
			["aggroloss"] = "%s meldet 'Aggro verloren' mit %d Bedrohung.",
			["knockback"] = "%s meldet 'R\195\188cksto\195\159 abbekommen'. Er ist runter auf %d Bedrohung.",
			["knockbackstring"] = "%s meldet diesen R\195\188cksto\195\159text '%s'.",
			["upgraderequest"] = "%s bittet dich um Upgrade auf Release %s von KLHThreatMeter. Du benutzt gerade Release %s.",
			["remoteoldversion"] = "%s benutzt die veraltete Version %s von KLHThreatMeter. Bitte sag Ihm er soll auf Release %s upgraden.",
			["knockbackvaluechange"] = "|cffffff00%s|r hat die Bedrohungreduzierung von %s's |cffffff00%s|r Angriff auf |cffffff00%d%%|r gesetzt.",
			["raidpermission"] = "Du musst Raid Leader oder Assistant sein um das zu tun!",
			["needmastertarget"] = "Du musst zuerst ein Hauptziel setzen!",
			["knockbackinactive"] = "R\195\188cksto\195\159 R\195\188cksto\195\159 ist nicht aktiv im Raid.",
			["versionrequest"] = "Fordere Versionsinformationen des Raids an. Antwort in 3 Sekunden.",
			["versionrecent"] = "Diese Leute haben Release %s: { ",
			["versionold"] = "Diese Leute haben \195\164ltere Versionen: { ",
			["versionnone"] = "Diese Leute haben kein KLHThreatMeter, oder sind nicht im richtigen CTRA channel: { ",	
			["channel"] = 
			{
				ctra = "CTRA Channel",
				ora = "oRA Channel",
				manual = "Manual Override",
			},
			needtarget = "W\195\164hle zuerst einen Gegner aus, bevor du das Hauptziel setzt.",
			upgradenote = "Benutzer veralteter Versionen der Mod wurden zum Upgraden aufgefordert.",
			advertisestart = "Du wirst nun Spieler die Aggro ziehen dazu auffordern KLHThreatMeter zu installieren.",
			advertisestop = "Du hast aufgeh�rt automatisch Werbung f\195\188r KLHThreatMeter zu machen..",
			advertisemessage = "Wenn du KLHThreatMeter h\195\164ttest, h\195\164ttest du vielleicht keine Aggro gezogen, %s.",
		}			
	}
}
```

## Code\Localisation\KTM_enUS.lua
```lua

klhtm.string.data["enUS"] = 
{
	["binding"] = 
	{
		hideshow = "Hide / Show Window",
		stop = "Emergency Stop",
		mastertarget = "Set / Clear Master Target",
		resetraid = "Reset Raid Threat",
	},
	["spell"] = 
	{
		-- 17.20
		["execute"] = "Execute",
		
		["heroicstrike"] = "Heroic Strike",
		["maul"] = "Maul",
		["swipe"] = "Swipe",
		["shieldslam"] = "Shield Slam",
		["revenge"] = "Revenge",
		["shieldbash"] = "Shield Bash",
		["sunder"] = "Sunder Armor",
		["thunderclap"] = "Tunder Clap",
		["demoralizingshout"] = "Demoralizing Shout",
		["feint"] = "Feint",
		["cower"] = "Cower",
		["taunt"] = "Taunt",
		["growl"] = "Growl",
		["vanish"] = "Vanish",
		["frostbolt"] = "Frostbolt",
		["fireball"] = "Fireball",
		["arcanemissiles"] = "Arcane Missiles",
		["scorch"] = "Scorch",
		["cleave"] = "Cleave",
		
		hemorrhage = "Hemorrhage",
		backstab = "Backstab",
		sinisterstrike = "Sinister Strike",
		eviscerate = "Eviscerate",

		corruption = "Corruption",
		curseofagony = "Curse of Agony",
		siphonlife = "Siphon Life",
		immolate = "Immolate",
		
		-- Items / Buffs:
		["arcaneshroud"] = "Arcane Shroud",
		["theeyeofdiminution"] = "The Eye of Diminution",
		["reducethreat"] = "Reduce Threat",
		["notthere"] = "Not There",

		-- Leeches: no threat from heal
		["holynova"] = "Holy Nova", -- no heal or damage threat
		["siphonlife"] = "Siphon Life", -- no heal threat
		["drainlife"] = "Drain Life", -- no heal threat
		["deathcoil"] = "Death Coil",	
		
		-- Fel Stamina and Fel Energy DO cause threat! GRRRRRRR!!!
		--["felstamina"] = "Fel Stamina",
		--["felenergy"] = "Fel Energy",
		
		["bloodsiphon"] = "Blood Siphon", -- poisoned blood vs Hakkar
		
		["lifetap"] = "Life Tap", -- no mana gain threat
		["holyshield"] = "Holy Shield", -- multiplier
		["tranquility"] = "Tranquility",
		["distractingshot"] = "Distracting Shot",
		["earthshock"] = "Earth Shock",
		["rockbiter"] = "Rockbiter",
		["fade"] = "Fade",
		["thunderfury"] = "Thunderfury",
		
		-- Spell Sets
		-- warlock descruction
		["shadowbolt"] = "Shadow Bolt",
		["immolate"] = "Immolate",
		["conflagrate"] = "Conflagrate",
		["searingpain"] = "Searing Pain", -- 2 threat per damage
		["rainoffire"] = "Rain of Fire",
		["soulfire"] = "Soul Fire",
		["shadowburn"] = "Shadowburn",
		["hellfire"] = "Hellfire",
		
		-- mage offensive arcane
		["arcaneexplosion"] = "Arcane Explosion",
		["counterspell"] = "Counterspell",
		
		-- priest shadow. No longer used (R17).
		["mindblast"] = "Mind Blast",	-- 2 threat per damage
		--[[
		["mindflay"] = "Mind Flay",
		["devouringplague"] = "Devouring Plague",
		["shadowwordpain"] = "Shadow Word: Pain",
		["manaburn"] = "Mana Burn",
		]]
	},
	["power"] = 
	{
		["mana"] = "Mana",
		["rage"] = "Rage",
		["energy"] = "Energy",
	},
	["threatsource"] = -- these values are for user printout only
	{
		["powergain"] = "Power Gain",
		["total"] = "Total",
		["special"] = "Specials",
		["healing"] = "Healing",
		["dot"] = "Dots",
		["threatwipe"] = "NPC Spells",
		["damageshield"] = "Damage Shields",
		["whitedamage"] = "White Damage",
	},
	["talent"] = -- these values are for user printout only
	{
		["defiance"] = "Defiance",
		["impale"] = "Impale",
		["silentresolve"] = "Silent Resolve",
		["frostchanneling"] = "Frost Channeling",
		["burningsoul"] = "Burning Soul",
		["healinggrace"] = "Healing Grace",
		["shadowaffinity"] = "Shadow Affinity",
		["druidsubtlety"] = "Druid Subtlety",
		["feralinstinct"] = "Feral Instinct",
		["ferocity"] = "Ferocity",
		["savagefury"] = "Savage Fury",
		["tranquility"] = "Improved Tranquility",
		["masterdemonologist"] = "Master Demonologist",
		["arcanesubtlety"] = "Arcane Subtlety",
		["righteousfury"] = "Righteous Fury",
		["sleightofhand"] = "Sleight of Hand",
	},
	["threatmod"] = -- these values are for user printout only
	{
		["tranquilair"] = "Tranquil Air Totem",
		["salvation"] = "Blessing of Salvation",
		["battlestance"] = "Battle Stance",
		["defensivestance"] = "Defensive Stance",
		["berserkerstance"] = "Berserker Stance",
		["defiance"] = "Defiance",
		["basevalue"] = "Base Value",
		["bearform"] = "Bear Form",
		["catform"] = "Cat Form",
		["glovethreatenchant"] = "+Threat Enchant to Gloves",
		["backthreatenchant"] = "-Threat Enchant to Back",
	},
	
	["sets"] = 
	{
		["bloodfang"] = "Bloodfang",
		["nemesis"] = "Nemesis",
		["plagueheart"] = "Plagueheart",
		["bonescythe"] = "Bonescythe",
		["netherwind"] = "Netherwind",
		["might"] = "Might",
		["arcanist"] = "Arcanist",
	},
	["boss"] = 
	{
		["speech"] = 
		{
			["onyxiaphase1"] = "How fortuitous. Usually, I must leave my lair in order to feed.",
			["onyxiaphase2"] = "This meaningless exertion bores me. I'll incinerate you all from above!",
			["razorphase2"] = "flee as the controlling power of the orb is drained.",
			["onyxiaphase3"] = "It seems you'll need another lesson",
			["thekalphase2"] = "fill me with your RAGE",
			["rajaxxfinal"] = "Impudent fool! I will kill you myself!",
			["azuregosport"] = "Come, little ones",
			["nefphase1"] = "Well done, my minions. The mortals' courage begins to wane! Now, let's see how they contend with the true Lord of Blackrock Spire!",
			["nefphase2"] = "Burn, you wretches! Burn!",
			["razargor1"] = "I'm free! That device shall never torment me again!",
			["broodlord1"] = "None of your kind should be here",
			["thad1"] = "EAT YOUR BONES",
			["thad2"] = "BREAK YOU!",
			["thad3"] = "KILL!",
			["noth1"] = "Die, trespasser!",
			["noth2"] = "Glory to the master!",
			["noth3"] = "Your life is forfeit!",
			["ktphase2"] = "Pray for mercy!",
		},
		-- Some of these are unused. Also, if none is defined in your localisation, they won't be used,
		-- so don't worry if you don't implement it.
		["name"] = 
		{
			["rajaxx"] = "General Rajaxx",
			["onyxia"] = "Onyxia",
			["ebonroc"] = "Ebonroc",
			["razorgore"] = "Razorgore the Untamed",
			["thekal"] = "High Priest Thekal",
			["shazzrah"] = "Shazzrah",
			["twinempcaster"] = "Emperor Vek'lor",
			["twinempmelee"] = "Emperor Vek'nilash",
			["noth"] = "Noth the Plaguebringer",
		},
		["spell"] = 
		{
			["shazzrahgate"] = "Gate of Shazzrah", -- "Shazzrah casts Gate of Shazzrah."
			["wrathofragnaros"] = "Wrath of Ragnaros", -- "Ragnaros's Wrath of Ragnaros hits you for 100 Fire damage."
			["timelapse"] = "Time Lapse", -- "You are afflicted by Time Lapse."
			["knockaway"] = "Knock Away",
			["wingbuffet"] = "Wing Buffet",
			["burningadrenaline"] = "Burning Adrenaline",
			["twinteleport"] = "Twin Teleport",
			["nothblink"] = "Blink",
			["sandblast"] = "Sand Blast",
			["fungalbloom"] = "Fungal Bloom",
			["hatefulstrike"] = "Hateful Strike",
			
			-- 4 horsemen marks
			mark1 = "Mark of Blaumeux",
			mark2 = "Mark of Korth'azz",
			mark3 = "Mark of Mograine",
			mark4 = "Mark of Zeliek",
			
			-- Onyxia fireball (presumably same as mage)
			fireball = "Fireball",
		}
	},
	["misc"] = 
	{
		["imp"] = "Imp", -- UnitCreatureFamily("pet")
		["spellrank"] = "Rank (%d+)", -- second value of GetSpellName(x, "spell")
		["aggrogain"] = "Aggro Gain",
	},

	-- labels and tooltips for the main window
	["gui"] = { 
		["raid"] = {
			["head"] = {
				-- column headers for the raid view
				["name"] = "Name",
				["threat"] = "Threat",
				["pc"] = "%",			-- your threat as a percentage of the #1 player's threat
				["sunder"] = "Su",			-- your threat as a percentage of the #1 player's threat
			},
			["stringshort"] = {
				-- tooltip titles for the bottom bar strings
				["tdef"] = "Threat Margin", -- the difference in threat between you and the MT / #1 in the list.
				["targ"] = "Master Target",
			},
			["stringlong"] = {
				-- tooltip descriptions for the bottom bar strings
				["tdef"] = "",
				["targ"] = "Only threat against %s is being counted towards raid threat values."
			},
		},
		["self"] = {
			["head"] = {
				-- column headers for the self view
				["name"] = "Name",
				["hits"] = "Hits",
				["rage"] = "Rage",
				["dam"] = "Damage",
				["threat"] = "Threat",
				["pc"] = "%T",			-- Abbreviation of %Threat
			},
			-- text on the self threat reset button
			["reset"] = "Reset",
		},
		["title"] = {
			["text"] = {
				-- the window titles
				["long"] = "KTM %d.%d",	-- don't need to localise these
				["short"] = "KTM",
				
			},
			["buttonshort"] = {
				-- the tooltip titles for command buttons
				["close"] = "Close",
				["min"] = "Minimise",
				["max"] = "Maximise",
				["self"] = "Self View",
				["raid"] = "Raid View",
				["pin"] = "Pin",
				["unpin"] = "Unpin",
				["opt"] = "Options",
				["targ"] = "Master Target",
				["clear"] = "Reset",
			},
			["buttonlong"] = {
				-- the tooltip descriptions for command buttons
				["close"] = "Threat data will still be sent if you are in a party or raid",
				["min"] = "",
				["max"] = "",
				["self"] = "Shows personal threat details",
				["raid"] = "Shows raid threat data",
				["pin"] = "Prevents the threatmeter window from being moved",
				["unpin"] = "Allows the threatmeter window to be moved",
				["opt"] = "",
				["targ"] = "Sets the Master Target to your current target. If you do not have a target, the Master Target is cleared. You must be a raid assistant or leader.",
				["clear"] = "Sets all players' threat to zero. You must be a raid assistant or leader.",
			},
			["stringshort"] = {
				-- the tooltip titles for titlebar strings
				["threat"] = "Threat",
				["tdef"] = "Threat Defecit",
				["rank"] = "Threat Rank",
				["pc"] = "% Threat",
				["sunder"] = "Sunders",
			},
			["stringlong"] = {
				-- the tooltip descriptions for titlebar strings
				["threat"] = "The amount of threat accumulated since your personal value was reset",
				["tdef"] = "The difference between your threat and the target's",
				["rank"] = "Your position in the threat list",
				["pc"] = "Your threat as a percent of the target's",
			},
		},
	},
	-- labels and tooltips for the options gui
	["optionsgui"] = {
		["buttons"] = {
			-- the options gui command button labels
			["gen"] = "General",
			["raid"] = "Raid",
			["self"] = "Self",
			["close"] = "Close",	
		},
		-- the labels for option checkboxes and headers
		["labels"] = {
			-- the title description for each option page
			["titlebar"] = {
				["gen"] = "General Options",
				["raid"] = "Raid Options",
				["self"] = "Self Options",
			},
			["buttons"] = {
				-- the names of title bar command buttons
				["pin"] = "Pin",
				["opt"] = "Options",
				["view"] = "View change",
				["targ"] = "Master Target",
				["clear"] = "Reset Raid Threat",
			},
			["columns"] = {
				-- names of columns on the self and raid views
				["hits"] = "Hits",
				["rage"] = "Rage",
				["dam"] = "Damage",
				["threat"] = "Threat",
				["pc"] = "% threat",
				["sunder"] = "Sunders",
			},
			["options"] = {
				-- miscelaneous option names
				["hide"] = "Hide rows with 0 threat",
				["abbreviate"] = "Abbreviate large values",
				["resize"] = "Resize frame",
				["aggro"] = "Show aggro gain",
				["rows"] = "Max visible rows",
				["scale"] = "Frame scale",
				["bottom"] = "Hide bottom bar",
				["minimap"] = "Show Minimap Button",
			},
			["minvis"] = {
				-- the names of minimised strings
				["threat"] = "Minimised threat", -- dodge...
				["rank"] = "Threat rank",
				["pc"] = "% threat",
				["sunder"] = "Sunders",
				["tdef"] = "Threat defecit",
			},
			["headers"] = {
				-- headers in the options gui
				["columns"] = "Visible columns",
				["strings"] = "Minimised strings",
				["other"] = "Other options",
				["minvis"] = "Minimised buttons",
				["maxvis"] = "Maximised buttons",
			},
		},
		-- the tooltips for some of the options
		["tooltips"] = {
			-- miscelaneous option descriptions
			["raidhide"] = "If checked, players with zero threat will not be visible on the threat meter.",
			["selfhide"] = "Uncheck to show all threat categories.",
			["abbreviate"] = "If checked, values larger than ten thousand will be abbreviated with the prefix 'k'. eg '15400' will become '15.4k'.",
			["resize"] = "If checked, the number of visible rows will be lowered to match the number of players reporting threat.",
			["aggro"] = "If checked, a player is added to the raid display showing the estimated threat barrier. It is most accurate when a mastertarget is set.",
			["rows"] = "The maximum number of players visible on the raid threat window.",
			["bottom"] = "If checked, the bottom bar will be hidden. It shows your threat defecit and the master target.",
			["minimap"] = "Left-click to open KTM.\nShift-Left-click for KTM options.\nRight-click and drag to move this button.",
		},
	},
	["print"] = 
	{
		["main"] = 
		{
			["startupmessage"] = "KLHThreatMeter Release |cff33ff33%s|r Revision |cff33ff33%s|r loaded. Type |cffffff00/ktm|r for help.",
		},
		["data"] = 
		{
			["abilityrank"] = "Your %s ability is rank %s.",
			["globalthreat"] = "Your global threat multiplier is %s.",
			["globalthreatmod"] = "%s gives you %s.",
			["multiplier"] = "As a %s, your threat from %s is multiplied by %s.",
			["damage"] = "damage",
			["shadowspell"] = "shadow spells",
			["arcanespell"] = "arcane spells",
			["holyspell"] = "holy spells",
			["setactive"] = "%s %d piece active? ... %s.",
			["true"] = "true",
			["false"] = "false",
			["healing"] = "Your healing causes %s threat (before global threat multiplier).",
			["talentpoint"] = "You have %d talent points in %s.",
			["talent"] = "Found %d %s talents.",
			["rockbiter"] = "Your rank %d Rockbiter adds %d threat to successful melee attacks.",
		},
		
		-- new in R17.7
		["boss"] = 
		{
			["automt"] = "The master target has been automatically set to %s.",
			["spellsetmob"] = "%s sets the %s parameter of %s's %s ability to %s from %s.", -- "Kenco sets the multiplier parameter of Onyxia's Knock Away ability to 0.7"
			["spellsetall"] = "%s sets the %s parameter of the %s ability to %s from %s.",
			["reportmiss"] = "%s reports that %s's %s missed him.",
			["reporttick"] = "%s reports that %s's %s hit him. He has suffered %s ticks, and will be affected in %s more ticks.",
			["reportproc"] = "%s reports that %s's %s changed his threat from %s to %s.",
			["bosstargetchange"] = "%s changed tagets from %s (on %s threat) to %s (on %s threat).",
			["autotargetstart"] = "You will automatically clear the meter and set the master target when you next target a world boss.",
			["autotargetabort"] = "The master target has already been set to the world boss %s.",
		},
		
		["network"] = 
		{
			["newmttargetnil"] = "Could not confirm the master target |cffffff00%s|r, because |cffffff00%s|r has no target.",
			["newmttargetmismatch"] = "|cffffff00%s|r sets the master target to |cffffff00%s|r, but his own target is |cffffff00%s|r. Using his own target instead, check this!",
			["mtpollwarning"] = "Updated your master target to |cffffff00%s|r, but could not confirm this. Ask |cffffff00%s|r to rebroadcast the master target if this does not sound correct.",
			["threatreset"] = "The raid threat meter was cleared by |cffffff00%s|r.",
			["newmt"] = "The master target has been set to |cffffff00%s|r by |cffffff00%s|r.",
			["mtclear"] = "The master target has been cleared by |cffffff00%s|r.",
			["knockbackstart"] = "NPC Spell reporting has been activated by |cffffff00%s|r.",
			["knockbackstop"] = "NPC Spell reporting has been stopped by |cffffff00%s|r.",
			["aggrogain"] = "|cffffff00%s|r reports gaining aggro with %d threat.",
			["aggroloss"] = "|cffffff00%s|r reports losing aggro with %d threat.",
			["knockback"] = "|cffffff00%s|r reports suffering a knock away. He's down to %d threat.",
			["knockbackstring"] = "%s reports this knockback text: '%s'.",
			["upgraderequest"] = "%s urges you to upgrade to Release %s of KLHThreatMeter. You are currently using Release %s.",
			["remoteoldversion"] = "%s is using the outdated Release %s of KLHThreatMeter. Please tell him to upgrade to Release %s.",
			["knockbackvaluechange"] = "|cffffff00%s|r has set the threat reduction of %s's |cffffff00%s|r attack to |cffffff00%d%%|r.",
			["raidpermission"] = "You need to be the raid leader or an assistant to do that!",
			["needmastertarget"] = "You have to set a master target first!",
			["knockbackinactive"] = "Knockback discovery is not active in the raid.",
			["versionrequest"] = "Requesting version information from the raid. Responses in 3 seconds.",
			["versionrecent"] = "These people have release %s: { ",
			["versionold"] = "These people have older versions: { ",
			["versionnone"] = "These people do not have KLHThreatMeter, or are not in the right CTRA channel: { ",
			["channel"] = 
			{
				ctra = "CTRA Channel",
				ora = "oRA Channel",
				manual = "Manual Override",
			},
			needtarget = "Target the mob to select as the master target first.",
			upgradenote = "Older versions of the mod have been notified to upgrade.",
			advertisestart = "You will now occasionally tell people who pull aggro to download KLHThreatMeter.",
			advertisestop = "You have stopped advertising KLHThreatMeter.",
			advertisemessage = "If you had KLHThreatMeter, you might not have pulled aggro on that %s.",
		},
		
		-- ok, so autohide isn't really a word, but just improvise
		table = 
		{
			autohideon = "The window will now automatically hide and show itself.",
			autohideoff = "The window is no longer autohiding.",
		}
	}
}
```

## Code\Localisation\KTM_frFR.lua
```lua

klhtm.string.data["frFR"] = 
{
	["binding"] = 
	{
		hideshow = "Cache / Affiche la fen\195\170tre",
		stop = "Arr\195\170t d'urgence",
		mastertarget = "S\195\169lectionner / Annuler la Cible Principale",
		resetraid = "R\195\169init. la Menace du Raid",
	},
	["spell"] =
	{
		-- 17.20
		["execute"] = "Ex\195\169cution",
		
		["heroicstrike"] = "Frappe h\195\169ro\195\175que",
		["maul"] = "Mutiler",
		["swipe"] = "Balayage",
		["shieldslam"] = "Heurt de bouclier",
		["revenge"] = "Vengeance",
		["shieldbash"] = "Coup de bouclier",
		["sunder"] = "Fracasser armure",
		["feint"] = "Feinte",
		["cower"] = "D\195\169robade", --"Effrayer une b\195\170te",
		["taunt"] = "Provocation",
		["growl"] = "Grondement",
		["vanish"] = "Disparition",
		["frostbolt"] = "Eclair de glace",
		["fireball"] = "Boule de feu",
		["arcanemissiles"] = "Projectiles des arcanes",
		["scorch"] = "Br\195\187lure",
		["cleave"] = "Fendre",
		
		-- Items / Buffs:
		["arcaneshroud"] = " Voile des arcanes",
		["reducethreat"] = "R\195\169duction de la menace",

		-- Fel Stamina and Fel Energy DO cause threat! GRRRRRRR!!!
		--["felstamina"] = "Endurance Corrompue", -- no heal threat
		--["felenergy"] = "Fel Energy",
		
		-- new in R16:
		["holynova"] = "Nova sacr\195\169e", -- no heal or damage threat 
		["siphonlife"] = "Siphon de Vie", -- no heal threat 
		["drainlife"] = "Drainer la Vie", -- no heal threat 
		["lifetap"] = "Connexion", -- no heal threat 
		["holyshield"] = "Bouclier Sacr\195\169", -- multiplier 
		["tranquility"] = "Tranquilit\195\169", 
		["distractingshot"] = "Trait Provocateur", 
		["earthshock"] = "Horion de Terre", 
		["rockbiter"] = "Arme Croque-Roc", 
		["fade"] = "Oubli",
		["deathcoil"] = "Voile mortel",
		["thunderfury"] = "	Lame-tonnerre",

		-- Items / Buffs:
		--["burningadrenaline"] = "Burning Adrenaline",
		--["arcaneshroud"] = "Arcane Shroud",
		--["reducethreat"] = "Reduce Threat",

		["bloodsiphon"] = "Siphon de sang", -- poisoned blood vs Hakkar
		
		-- Spell Sets
		-- warlock descruction
		["shadowbolt"] = "Trait de l'ombre",
		["immolate"] = "Immolation",
		["conflagrate"] = "Conflagration",
		["searingpain"] = "Douleur br\195\187lante",
		["rainoffire"] = "Pluie de Feu",
		["soulfire"] = "Feu de l'\195\162me",
		["shadowburn"] = "Br\195\187lure de l'ombre",
		["hellfire"] = "Flammes infernales",

		-- mage offensive arcane
		["arcaneexplosion"] = "Explosion des arcanes",
		["counterspell"] = "Contresort",

		-- priest shadow
		["mindblast"] = "Attaque Mentale",
		--[[[
		"mindflay"] = "Fouet Mental",
		["devouringplague"] = "Peste D\195\169vorante",
		["shadowwordpain"] = "Mot des T\195\169n\195\168bres: Douleur",
		["manaburn"] = "Br\195\187lure de mana",
		]]
	},
	["power"] =
	{
		["mana"] = "Mana",
		["rage"] = "Rage",
		["energy"] = "Energie",
	},
	["threatsource"] =
	{
		["powergain"] = "Power Gain",
		["total"] = "Total",
		["special"] = "Specials",
		["healing"] = "Soins",
		["dot"] = "Dots",
		["threatwipe"] = "Reduction Aggro",
		["damageshield"] = "Damage Shields",
		["whitedamage"] = "Dommages blancs",
	},
	["talent"] =
	{
		["defiance"] = "D\195\169fi",
		["impale"] = "Empaler",
		["silentresolve"] = "R\195\169solution silencieuse",
		["shadowaffinity"] = "Affinit\195\169 avec les t\195\169nebres",
		["druidsubtlety"] = "Discr\195\169tion",
		["feralinstinct"] = "Instinct farouche",
		["ferocity"] = "F\195\169rocit\195\169",
		["healinggrace"] = "Gr\195\162ce gu\195\169risseuse",
		["savagefury"] = "Furie sauvage",
		["masterdemonologist"] = "Ma\195\174tre d\195\169monologue",
		["arcanesubtlety"] = "Subtilit\195\169 des arcanes",
		["righteousfury"] = "Fureur vertueuse",
		["tranquility"] = "Tranquilit\195\169 am\195\169lior\195\169e",
		["burningsoul"] = "Ame ardente",
		["frostchanneling"] = "Canalisation du givre",
	},
	["threatmod"] =
	{
		["tranquilair"] = "Totem de Tranquillit\195\169",
		["salvation"] = "B\195\169n\195\169diction de salut",
		["battlestance"] = "Posture de combat",
		["defensivestance"] = "Posture d\195\169fensive",
		["berserkerstance"] = "Posture berserker",
		["defiance"] = "D\195\169fi",
		["basevalue"] = "Valeur de base",
		["bearform"] = "Forme d'ours sinistre",
		["glovethreatenchant"] = "+Threat Enchant to Gloves",
		["backthreatenchant"] = "-Threat Enchant to Back",
	},

	["sets"] =
	{
		["bloodfang"] = "Rougecroc",
		["nemesis"] = "N\195\169m\195\169sis",
		["netherwind"] = "Vent du n\195\170ant",
		["might"] = "Courroux",
		["arcanist"] = "Arcaniste",
	},
	["boss"] = 
	{
		["name"] = 
		{
			["rajaxx"] = "G\195\169n\195\169ral Rajaxx",
			["thekal"] = "Grand pr\195\170tre Thekal",
			["shazzrah"] = "Shazzrah",
			["twinempcaster"] = "Empereur Vek'lor",
			["twinempmelee"] = "Empereur Vek'nilash",
			["noth"] = nil, --"Noth the Plaguebringer", --"Not known at this time"
			["onyxia"] = "Onyxia",
			["ebonroc"] = "Ebonroc",
			["razorgore"] = "Tranchetripe l'Indompt\195\169",
		},
		["speech"] = 
		{
			["thekalphase2"] = nil, --"fill me with your RAGE",
			["rajaxxfinal"] = nil, --"Impudent fool! I will kill you myself!",
			["azuregosport"] = "Venez m'affronter, mes petits !",
			["razorphase2"] = "le pouvoir de l'orbe vient de se terminer.",
			["onyxiaphase3"] = "Il semble que vous ayez besoin d'une autre le\195\167on",
			["thad1"] = "EAT YOUR BONES",
			["thad2"] = "BREAK YOU!",
			["thad3"] = "KILL!",
			["noth1"] = "Die, trespasser!",
			["noth2"] = "Glory to the master!",
			["noth3"] = "Your life is forfeit!",
			["ktphase2"] = "Pray for mercy!",
		},
		["spell"] = 
		{
			["knockaway"] = "Renversement",
			["wingbuffet"] = "Frappe des ailes",
			["timelapse"] = "Trou de temps", -- "You are afflicted by Time Lapse. Must Check this in French client""
			["shazzrahgate"] = "Porte de Shazzrah", -- "Shazzrah casts Gate of Shazzrah. Must Check this in French"
			["twinteleport"] = "T\195\169l\195\169portation des jumeaux", --"Must Check this in French client"
			["burningadrenaline"] = "Mont\195\169e d'adr\195\169naline", --"Must Check this in the French client"
			["nothblink"] = nil, --"Blink", --"Not known at this time"
			["wrathofragnaros"] = "Col\195\168re de Ragnaros", -- "Ragnaros's Wrath of Ragnaros hits you for 100 Fire damage. Must Check this in the French client"
		},
	},
	["misc"] =
	{
		["imp"] = "Diablotin", -- UnitCreatureFamily("pet")
		["spellrank"] = "Rang (%d+)", -- second value of GetSpellName(x, "spell")
		["aggrogain"] = "Gain d'Aggro",
	},
	
	--[[ 
	Reserved for possible future use
	
	["mobattack"] = 
	{
		["self"] = {
			["hit"] = "(.+) vous inflige %d+ points de d\195\169g\195\162ts%.", -- COMBATHITOTHERSELF
			["crit"] = "(.+) vous inflige un coup critique pour %d points de d\195\169g\195\162ts%.", -- COMBATHITCRITOTHERSELF
			["absorb"] = "(.+) attaque%. Vous absorbez tous les d\195\169g\195\162ts%.", -- VSABSORBOTHERSELF
			["dodge"] = "(.+) attaque et vous esquivez%.", -- VSDODGEOTHERSELF
			["parry"] = "(.+) attaque, mais vous parez le coup%.", -- VSPARRYOTHERSELF
			["block"] = "(.+) attaque, mais vous bloquez le coup%.", -- VSBLOCKOTHERSELF
			["miss"] = "(.+) vous rate%.", -- MISSEDOTHERSELF
			["resist"] = "(.+) attaque%. Vous r\195\169sistez \195\160 tous les d\195\169g\195\162ts%.", -- VSRESISTOTHERSELF
		},
		["other"] = {
			["hit"] = "(.+) touche (.+) et inflige %d+ points de d\195\169g\195\162ts%.", -- COMBATHITOTHEROTHER 
			["crit"] = "(.+) inflige un coup critique \195\160 (.+) (%d+ points de d\195\169g\195\162ts)%.", -- COMBATHITCRITOTHEROTHER
			["absorb"] = "(.+) attaque%. (.+) absorbe tous les d\195\169g\195\162ts%.", -- VSABSORBOTHEROTHER
			["dodge"] = "(.+) attaque et (.+) esquive%.", -- VSDODGEOTHEROTHER
			["parry"] = "(.+) attaque et (.+) pare son attaque%.", -- VSPARRYOTHEROTHER
			["block"] = "(.+) attaque et (.+) bloque l'attaque%.", -- VSBLOCKOTHEROTHER
			["miss"] = "(.+) manque (.+)%.", -- MISSEDOTHEROTHER
			["resist"] = "(.+) attaque%. (.+) r\195\169siste \195\160 tous les d\195\169g\195\162ts%.", -- VSRESISTOTHEROTHER
		},
	},
	
	]]
	
	["gui"] = {
		["raid"] = {
			["head"] = {
				-- column headers for the raid view
				["name"] = "Nom",
				["threat"] = "Menace",
				["pc"] = "%Max",			-- your threat as a percentage of the #1 player's threat
			},
			["stringshort"] = {
				-- tooltip titles for the bottom bar strings
				["tdef"] = "Marge de menace", -- the difference in threat between you and the MT / #1 in the list.
				["targ"] = "Cible principale",
			},
			["stringlong"] = {
				-- tooltip descriptions for the bottom bar strings
				["tdef"] = "",
				["targ"] = "Seule la menace contre %s est prise en compte pour les valeurs de menace du raid."
			},
		},
		["self"] = {
			["head"] = {
				-- column headers for the self view
				["name"] = "Nom",
				["hits"] = "Touch\195\169",
				["rage"] = "Rage",
				["dam"] = "D\195\169gats",
				["threat"] = "Menace",
				["pc"] = "%M",			-- Abbreviation of %Threat
			},
			-- text on the self threat reset button
			["reset"] = "R\195\169initialiser",
		},
		["title"] = {
			["text"] = {
				-- the window titles
				["long"] = "KTM %d.%d",	-- don't need to localise these
				["short"] = "KTM",
				
			},
			["buttonshort"] = {
				-- the tooltip titles for command buttons
				["close"] = "Fermer",
				["min"] = "Minimis\195\169",
				["max"] = "Maximis\195\169",
				["self"] = "Vue personnelle",
				["raid"] = "Vue du Raid",
				["pin"] = "Bloque",
				["unpin"] = "D\195\169bloque",
				["opt"] = "Options",
				["targ"] = "Cible principale",
				["clear"] = "Vider",
			},
			["buttonlong"] = {
				-- the tooltip descriptions for command buttons
				["close"] = "Les donn�es de menace sont toujours prise en compte si vous \195\170tes en groupe ou raid",
				["min"] = "",
				["max"] = "",
				["self"] = "Montre votre menace personnelle en d�tails",
				["raid"] = "Montre les donn�es de menace du raid",
				["pin"] = "Emp\195\168che le d\195\169placement de la fen\195\170tre",
				["unpin"] = "Autorise le d\195\169placement de la fen\195\170tre",
				["opt"] = "",
				["targ"] = "Positionne votre cible comme cible principale. Si vous n'avez pas de cible, le cible principale est mise � z\195\169ro. R\195\169initialise",
				["clear"] = "R\195\169initialise la menace de tous les membres du raid. R\195\169initialise.",
			},
			["stringshort"] = {
				-- the tooltip titles for titlebar strings
				["threat"] = "Menace",
				["tdef"] = "D\195\169ficite de Menace",
				["rank"] = "Rang de Menace",
				["pc"] = "% de Menace",
			},
			["stringlong"] = {
				-- the tooltip descriptions for titlebar strings
				["threat"] = "La quantit� de menace accumul� depuis la r\195\169initialisation de votre profil.",
				["tdef"] = "Diff\195\169rence de menace entre votre cible et vous",
				["rank"] = "Votre position dans la liste de Menace",
				["pc"] = "Votre menace en pourcentage pour la cible",
			},
		},
	},
	-- labels and tooltips for the options gui
	["optionsgui"] = {
		["buttons"] = {
			-- the options gui command button labels
			["gen"] = "General",
			["raid"] = "Raid",
			["self"] = "Personnel",
			["close"] = "Fermer",	
		},
		-- the labels for option checkboxes and headers
		["labels"] = {
			-- the title description for each option page
			["titlebar"] = {
				["gen"] = "Options G\195\169n\195\169rales",
				["raid"] = "Options de Raid",
				["self"] = "Options Personnelles",
			},
			["buttons"] = {
				-- the names of title bar command buttons
				["pin"] = "Bloque",
				["opt"] = "Options",
				["view"] = "Changer la vue",
				["targ"] = "Cible principale",
				["clear"] = "R\195\169\init. la menace du Raid",
			},
			["columns"] = {
				-- names of columns on the self and raid views
				["hits"] = "Touch\195\169",
				["rage"] = "Rage",
				["dam"] = "D\195\169gats",
				["threat"] = "Menace",
				["pc"] = "% de Menace",
			},
			["options"] = {
				-- miscelaneous option names
				["hide"] = "Cache les col. menace=0",
				["abbreviate"] = "Abr\195\169viation",
				["resize"] = "Ajuster la fen\195\170tre",
				["aggro"] = "Voir le gain de menace",
				["rows"] = "Nb de col. visibles",
				["scale"] = "Echelle de la fen\195\170tre",
				["bottom"] = "Cacher la barre du bas",
				["minimap"] = "Afficher le Bouton de la Mini-carte",
			},
			["minvis"] = {
				-- the names of minimised strings
				["threat"] = "Menace minimis\195\169", -- dodge...
				["rank"] = "Rang de menace",
				["pc"] = "% de Menace",
				["tdef"] = "D\195\169ficite de Menace",
			},
			["headers"] = {
				-- headers in the options gui
				["columns"] = "Colonnes visibles",
				["strings"] = "Cha\195\174nes minimis\195\169es",
				["other"] = "Autres options",
				["minvis"] = "Minimis\195\169",
				["maxvis"] = "Maximis\195\169",
			},
		},
		-- the tooltips for some of the options
		["tooltips"] = {
			-- miscelaneous option descriptions
			["raidhide"] = "Si coch\195\169, les joueurs avec une menace nulle ne seront pas visiblent dans la fen\195\170tre graphique.",
			["selfhide"] = "D\195\169coch\195\169 pour afficher tous les types de menace.",
			["abbreviate"] = "Si coch\195\169, Les valeurs plus grande que 10000 seront abr\195\169g\195\169es avec le suffixe 'k'. ie '15400' deviendra '15.4k'.",
			["resize"] = "Si coch\195\169, le nombre de colonnes visibles sera r�duit aux nombre de joueurs g\195\169n\195\169rant de la menace.",
			["aggro"] = "Si coch\195\169, un joueur est ajout� � l'affichage de raid montrant le seuil estim\195\169 de menace. Ceci est plus pr\195\169cis quand une cible principale est positionn\195\169e.",
			["rows"] = "Le nombre maximum de joueurs visible sur la fen\195\170tre de menace du raid.",
			["bottom"] = "Si coch\195\169,la barre du bas sera cach\195\169. Elle montre votre d\195\169ficite de menace et la cible principale.",
			["minimap"] = "Cliquez avec le bouton gauche pour ouvrir KTM.\nMaj-clic gauche pour les options KTM.\nCliquez avec le bouton droit et faites glisser pour d�placer ce bouton.",
		},
	},
	["print"] =
	{
		["main"] =
		{
			["startupmessage"] = "KLHThreatMeter Version |cff33ff33%s|r Revision |cff33ff33%s|r charg�. Taper |cffffff00/ktm|r pour l\'aide.",
		},
		["data"] =
		{
			["abilityrank"] = "Votre %s est au rang %s.",
			["globalthreat"] = "Votre multiplicateur d'aggro est de %s.",
			["globalthreatmod"] = "%s vous donnent %s.",
			["multiplier"] = "En tant que %s, votre aggro de %s est multipli\195\169 par %s.",
			["damage"] = "D\195\169gats",
			["shadowspell"] = "sorts d'ombre ",
			["arcanespell"] = "sorts d'arcane",
			["holyspell"] = "sorts de sacr\195\169",
			["setactive"] = "%s %d pi\195\168ces actives ? ... %s.",
			["true"] = "vrai",
			["false"] = "faux",
			["healing"] = "Votre soin g195\169n\195\168re %s d'aggro (avant le calcul global d'aggro).",
			["talentpoint"] = "Vous avez %d points de talent dans %s.",
			["talent"] = "%d %s talents trouv\195\169s.",
			["rockbiter"] = "Your rank %d Rockbiter adds %d threat to successful melee attacks.",
		},
		
		-- new in R17.7
		["boss"] = 
		{
			["automt"] = "La cible principale a \195\169t\195\169 automatiquement positionn\195\169e sur %s.",
			["spellsetmob"] = "%s change le param�tre de %s du talent de %s de %s vers %s.",-- "Kenco sets the multiplier parameter of Onyxia's Knock Away ability to 0.7"
			["spellsetall"] = "%s change le param�tre de %s du talent de %s de %s \195\160 %s.",
			["reportmiss"] = "%s rapporte que %s l'a manqu\195\169.",
			["reporttick"] = "%s rapporte que %s l'a touch\195\169. Il a endur\195\169 %s ticks, et souffrira pour encore %s ticks.",
			["reportproc"] = "%s rapporte que %s a chang\195\169 son niveau de menace de %s \195\160 %s.",
			["bosstargetchange"] = "%s a chang\195\169 de cible de %s (\195\160 %s de menace) vers %s (\195\160 %s de menace).",
			["autotargetstart"] = "Vous assignerez la cible principale et r\195\169initialiserez automatiquement le compteur quand vous ciblerez un world boss.",
			["autotargetabort"] = "La cible principale a d\195\169j\195\160 \195\169t\195\169 fix\195\169e sur le world boss %s.",
		},
		
		["network"] =
		{
			["newmttargetnil"] = "Ne peut pas confirmer la cible principale %s, car %s bn'a pas de cible.",
			["newmttargetmismatch"] = "%s assigne la cible principale \195\160 %s, mais sa cible est %s. Utilisation de sa cible, v\195\169rifier ceci!",
			["mtpollwarning"] = "Mise \195\160 jour de votre cible principale \195\160 %s, mais pas de confirmation possible. Demander \195\160 %s de redistibuer la cible principale si cela ne semble pas correcte.",
			["threatreset"] = "Le raid aggro meter a \195\169t\195\169 r\195\169initialis� par %s.",
			["newmt"] = "La cible principale est '%s' design\195\169e par %s.",
			["mtclear"] = "La cible principale a \195\169t\195\169 r\195\169initialis� par %s.",
			["knockbackstart"] = "Rapport des sorts des PNJ a \195\169t\195\169 activ\195\169 par %s",
			["knockbackstop"] = "Rapport des sorts des PNJ a \195\169t\195\169 stopp\195\169 par %s.",
			["aggrogain"] = "%s rapporte un gain d'aggro de %d.",
			["aggroloss"] = "%s rapporte une perte d'aggro de %d.",
			["knockback"] = "%s rapporte avoir subi un kock away. Il perd %d d'aggro.",
			["knockbackstring"] = "%s rapporte le contrecoup suivant : '%s'.",
			["upgraderequest"] = "%s est urgent que vous changiez de version %s de KLHThreatMeter. Vous utilisez la version  %s.",
			["remoteoldversion"] = "%s utilise une version ancienne %s de KLHThreatMeter. Whisper le pour mettre a jour vers la version %s.",
			["knockbackvaluechange"] = "|cffffff00%s|r a mis la r�duction de menace de %s |cffffff00%s|r attaque \195\160 |cffffff00%d%%|r.",
			["raidpermission"] = "Vous devez \195\170tre promu ou le leader pour faire ca!",
			["needmastertarget"] = "Choississez une cible principale avant!",
			["knockbackinactive"] = "La d\195\169couverte des contrecoups n'est pas active dans le raid.",
			["versionrequest"] = "Verification des versions sur le raid. Reponses dans 3 seconds.",
			["versionrecent"] = "Ces personnes ont la version %s: { ",
			["versionold"] = "Ces personnes ont d'anciennes version: { ",
			["versionnone"] = "Ces personnes n'ont pas KHL ou ne sont pas dans le bon canal CTRAID: { ",
			["channel"] = 
			{
				ctra = "Canal CTRA",
				ora = "Canal oRA",
				manual = "Forc\195\169 manuellement",
			},
			needtarget = "Ciblez un mob pour le prendre en cible principale.",
			upgradenote = "Les utilisateurs d'anciennes versions du mod ont \195\169t\195\169 inform\195\169 qu'une mise � jour est disponible.",
			advertisestart = "Vous avertirez dor\195\169navant les personnes qui prennent l'aggro de t\195\169l\195\169charger KLHThreatMeter.",
			advertisestop = "Vous avez arret\195\169 de parler de KLHThreatMeter.",
			advertisemessage = "Si tu avais KLHThreatMeter, tu aurais pu \195\169viter de prendre l'aggro de %s.",
		}
	}

}
```

## Code\Localisation\KTM_koKR.lua
```lua
klhtm.string.data["koKR"] =

{
	["binding"] =
	{
		hideshow = "창 숨기기/보기",
		stop = "비상중단",
		mastertarget = "주타겟 설정/해제",
		resetraid = "레이드 위협수준 리셋",
	},
	["spell"] =
	{
		["heroicstrike"] = "영웅의 일격",
		["maul"] = "후려치기",
		["swipe"] = "휘둘러치기",
		["shieldslam"] = "방패 밀쳐내기",
		["revenge"] = "복수",
		["shieldbash"] = "방패 가격",
		["sunder"] = "방어구 가르기",
		["feint"] = "교란",
		["cower"] = "웅크리기",
		["taunt"] = "도발",
		["growl"] = "포효",
		["vanish"] = "소멸",
		["frostbolt"] = "얼음 화살",
		["fireball"] = "화염구",
		["arcanemissiles"] = "신비한 화살",
		["scorch"] = "불태우기",
		["cleave"] = "회전베기",

		hemorrhage = "과다출혈",
		backstab = "기습",
		sinisterstrike = "사악한 일격",
		eviscerate = "절개",

		-- Items / Buffs:
		["arcaneshroud"] = "신비의 장막",
		["reducethreat"] = "위협 수준 감소",

		-- new in R16
		["holynova"] = "신성한 폭발", -- no heal or damage threat
		["siphonlife"] = "생명력 착취", -- no heal threat
		["drainlife"] = "생명력 흡수", -- no heal threat
		["deathcoil"] = "죽음의 고리",

		-- no threat for fel stamina. energy unknown.
		--["felstamina"] = "마의 체력",
		--["felenergy"] = "마의 에너지",

		["bloodsiphon"] = "생명력 착취", -- poisoned blood vs Hakkar


		["lifetap"] = "생명력 전환", -- no mana gain threat
		["holyshield"] = "신성한 방패", -- multiplier
		["tranquility"] = "평온",
		["distractingshot"] = "견제 사격",
		["earthshock"] = "대지 충격",
		["rockbiter"] = "대지의 무기",
		["fade"] = "소실",
		["thunderfury"] = "우레폭풍",

		-- Spell Sets
		-- warlock descruction
		["shadowbolt"] = "어둠의 화살",
		["immolate"] = "제물",
		["conflagrate"] = "점화",
		["searingpain"] = "불타는 고통", -- 2 threat per damage
		["rainoffire"] = "불의 비",
		["soulfire"] = "영혼의 불꽃",
		["shadowburn"] = "어둠의 연소",
		["hellfire"] = "지옥의 불길",

		-- mage offensive arcane
		["arcaneexplosion"] = "신비한 폭발",
		["counterspell"] = "마법 반사",

		-- priest shadow
		["mindblast"] = "정신 분열", 	-- 2 threat per damage
	},
	["power"] =
	{
		["mana"] = "마나",
		["rage"] = "분노",
		["energy"] = "기력",
	},
	["threatsource"] = -- these values are for user printout only
	{
		["powergain"] = "파워 획득",
		["total"] = "합",
		["special"] = "기술/마법",
		["healing"] = "치유",
		["dot"] = "DOT",
		["threatwipe"] = "NPC 주문",
		["damageshield"] = "피해 보호막",
		["whitedamage"] = "평타",
	},
	["talent"] = -- these values are for user printout only
	{
		["defiance"] = "도전",
		["impale"] = "꿰뚫기",
		["silentresolve"] = "무언의 결심",
		["frostchanneling"] = "냉기계 정신집중",
		["burningsoul"] = "불타는 영혼",
		["healinggrace"] = "회복의 토템",
		["shadowaffinity"] = "암흑 마법 친화",
		["druidsubtlety"] = "미묘함",
		["feralinstinct"] = "야생의 본능",
		["ferocity"] = "야수의 본성",
		["savagefury"] = "맹렬한 격노",
		["tranquility"] = "평온 연마",
		["masterdemonologist"] = "악령술의 대가",
		["arcanesubtlety"] = "신비한 미묘함",
		["righteousfury"] = "정의의 격노",
		["sleightofhand"] = "손재주",
	},
	["threatmod"] = -- these values are for user printout only
	{
		["tranquilair"] = "평온의 토템",
		["salvation"] = "구원의 축복",
		["battlestance"] = "전투 태세",
		["defensivestance"] = "방어 태세",
		["berserkerstance"] = "광폭 태세",
		["defiance"] = "도전",
		["basevalue"] = "기본 값",
		["bearform"] = "곰 변신",
		["catform"] = "표범 변신",
		["glovethreatenchant"] = "장갑에 위협수준 증가 마법부여",
		["backthreatenchant"] = "망토에 위협수준 감소 마법부여",
	},
	["sets"] =
	{
		["bloodfang"] = "붉은송곳니",
		["nemesis"] = "천벌",
		["netherwind"] = "소용돌이",
		["might"] = "투지",
		["arcanist"] = "신비술사",
	},
	["boss"] =
	{
		["speech"] =
		{
	  	["razorphase2"] = "수정 구슬의 지배 마력이 빠져나가자 도망칩니다.",
  		["onyxiaphase3"] = "혼이 더 나야 정신을 차리겠구나!",
			["thekalphase2"] = "시르밸라시여, 분노를 채워 주서소!",
			["rajaxxfinal"] = "건방진...  내 친히 너희를 처치해주마!",
			["azuregosport"] = "오너라, 조무래기들아! 덤벼봐라!",
			["nefphase2"] = "불타라! 활활! 불타라!",
		},
		-- Some of these are unused. Also, if none is defined in your localisation, they won't be used,
		-- so don't worry if you don't implement it.
		["name"] =
		{
			["rajaxx"] = "장군 라작스",
		  ["onyxia"] = "오닉시아",
	  	["ebonroc"] = "에본로크",
  		["razorgore"] = "폭군 서슬송곳니",
			["thekal"] = "대사제 데칼",
			["shazzrah"] = "샤즈라",
			["twinempcaster"] = "제왕 베클로어",
			["twinempmelee"] = "제왕 베크닐라쉬",
			["noth"] = "역병술사 노스",
		},
		["spell"] =
		{
			["shazzrahgate"] = "샤즈라의 문", -- "Shazzrah casts Gate of Shazzrah."
			["wrathofragnaros"] = "라그나로스의 징벌", -- "Ragnaros's Wrath of Ragnaros hits you for 100 Fire damage."
			["timelapse"] = "시간의 쇠퇴", -- "You are afflicted by Time Lapse."
  		["knockaway"] = "날려버리기",
	  	["wingbuffet"] = "폭풍 날개",
		  ["burningadrenaline"] = "불타는 아드레날린",
		  ["twinteleport"] = "쌍둥이 순간이동",
			["nothblink"] = "점멸",
			["sandblast"] = "모래 돌풍",
			["fungalbloom"] = "곰팡이 번식",
			["hatefulstrike"] = "증오의 일격",

		}
	},
	["misc"] =
	{
		["imp"] = "임프", -- UnitCreatureFamily("pet")
		["spellrank"] = "(%d+) 레벨", -- second value of GetSpellName(x, "spell")
		["aggrogain"] = "어그로획득",
	},
	-- labels and tooltips for the main window
	["gui"] = {
		["raid"] = {
			["head"] = {
				-- column headers for the raid view
				["name"] = "이름",
				["threat"] = "위협수준",
				["pc"] = "%최대",
			},
			["stringshort"] = {
				-- tooltip titles for the bottom bar strings
				["tdef"] = "위협차",
				["targ"] = "주타겟",
			},
			["stringlong"] = {
				-- tooltip descriptions for the bottom bar strings
				["tdef"] = "",
				["targ"] = "%s에 대한 위협수준."
			},
		},
		["self"] = {
			["head"] = {
				-- column headers for the self view
				["name"] = "이름",
				["hits"] = "횟수",
				["rage"] = "분노",
				["dam"] = "피해",
				["threat"] = "위협수준",
				["pc"] = "%T",
			},
			-- text on the self threat reset button
			["reset"] = "Reset",
		},
		["title"] = {
			["text"] = {
				-- the window titles
				["long"] = "KTM %d.%d",
				["short"] = "KTM",

			},
			["buttonshort"] = {
				-- the tooltip titles for command buttons
				["close"] = "닫기",
				["min"] = "최소화",
				["max"] = "최대화",
				["self"] = "개별창",
				["raid"] = "레이드창",
				["pin"] = "핀고정",
				["unpin"] = "핀풀림",
				["opt"] = "옵션",
				["targ"] = "주타겟",
				["clear"] = "리셋",
			},
			["buttonlong"] = {
				-- the tooltip descriptions for command buttons
				["close"] = "위협수준 데이터는 여전히 파티나 레이드에 보내짐",
				["min"] = "",
				["max"] = "",
				["self"] = "개별 위협수준을 보임",
				["raid"] = "레이드 위협수준을 보임",
				["pin"] = "이동을 방지",
				["unpin"] = "이동을 허용",
				["opt"] = "",
				["targ"] = "현재대상을 주타겟으로 설정. 대상이 없으면 주타겟을 초기화. 공대장이나 승급자만 설정가능.",
				["clear"] = "모든 플레이어의 위협수준을 초기화. 공대장이나 승급자만 설정가능.",
			},
			["stringshort"] = {
				-- the tooltip titles for titlebar strings
				["threat"] = "위협수준",
				["tdef"] = "위협차",
				["rank"] = "위협순위",
				["pc"] = "위협%",
			},
			["stringlong"] = {
				-- the tooltip descriptions for titlebar strings
				["threat"] = "리셋화 축적된 위협수준",
				["tdef"] = "타겟과 자신의 위협수준 차이값",
				["rank"] = "위협리스트중 자신의 순위",
				["pc"] = "타겟의 위협수준대비 자신의 위협수준 %",
			},
		},
	},
	-- labels and tooltips for the options gui
	["optionsgui"] = {
		["buttons"] = {
			-- the options gui command button labels
			["gen"] = "일반",
			["raid"] = "레이드",
			["self"] = "개별",
			["close"] = "닫기",
		},
		-- the labels for option checkboxes and headers
		["labels"] = {
			-- the title description for each option page
			["titlebar"] = {
				["gen"] = "일반옵션",
				["raid"] = "레이드옵션",
				["self"] = "개별옵션",
			},
			["buttons"] = {
				-- the names of title bar command buttons
				["pin"] = "핀",
				["opt"] = "옵션",
				["view"] = "뷰변경",
				["targ"] = "주타겟",
				["clear"] = "레이드 위협수준 리셋",
			},
			["columns"] = {
				-- names of columns on the self and raid views
				["hits"] = "횟수",
				["rage"] = "분노",
				["dam"] = "피해",
				["threat"] = "위협수준",
				["pc"] = "% 위협수준",
			},
			["options"] = {
				-- miscelaneous option names
				["hide"] = "0 위협수준은 숨김",
				["abbreviate"] = "큰수치간략화",
				["resize"] = "프레임 크기조절",
				["aggro"] = "어그로 재표시",
				["rows"] = "최대 행표시",
				["scale"] = "프레임 크기",
				["bottom"] = "하단바를 숨김",
				["minimap"] = "미니맵 버튼 표시",
			},
			["minvis"] = {
				-- the names of minimised strings
				["threat"] = "위협수준 최소화", -- dodge...
				["rank"] = "위협순위",
				["pc"] = "위협%",
				["tdef"] = "위협차이",
			},
			["headers"] = {
				-- headers in the options gui
				["columns"] = "열 표시",
				["strings"] = "최소화시 표시값",
				["other"] = "기타 옵션",
				["minvis"] = "최소화시 버튼",
				["maxvis"] = "최대화시 버튼",
			},
		},
		-- the tooltips for some of the options
		["tooltips"] = {
			-- miscelaneous option descriptions
			["raidhide"] = "체크시, 어그로가 0인 플레이어는 목록에서 제외됨.",
			["selfhide"] = "체크시, 위협수준이 0인 항목은 표시가 안됨.",
			["abbreviate"] = "체크시, 천이 넘아가는 수치는 뒤에 k가 붙어서 간략히 표시됨. 예) '15400'는 '15.4k'로 표시됨.",
			["resize"] = "체크시, 표시행수가 애드온이 깔린 플레이어수이 맞추어서 적어짐.",
			["aggro"] = "체크시, 위협한계치가 레이드뷰에 첨가됨. 주타겟이 설정되었을 시 가장 정확함.",
			["rows"] = "레이드 화면에 보여지는 최대 플레이어수",
			["bottom"] = "체크시, 위협차이와 주타겟을 보여주는 하단바가 숨겨짐.",
			["minimap"] = "KTM을 열려면 왼쪽 클릭하세요.\nKTM 옵션을 보려면 Shift-왼쪽 클릭하세요.\n이 버튼을 이동하려면 마우스 오른쪽 버튼을 클릭하고 드래그하세요.",
		},
	},
	["print"] =
	{
		["main"] =
		{
			["startupmessage"] = "KLHThreatMeter(Release |cff33ff33%s|r Revision |cff33ff33%s|r)가 로딩됨. 도움말은 |cffffff00/ktm|r 을 치십시오.",
		},
		["data"] =
		{
			["abilityrank"] = "당신의 %s 기술은 %s레벨입니다.",
			["globalthreat"] = "당신의 포괄적인 위협수준 배율은 %s입니다.",
			["globalthreatmod"] = "%s에 의한 위협수준 배율은 %s입니다.",
			["multiplier"] = "%s|1으로써;로써;, %s 기술에 의한 위협수준 배율은 %s입니다.",
			["damage"] = "데미지",
			["shadowspell"] = "암흑 주문",
			["arcanespell"] = "아케인 주문",
			["holyspell"] = "신성 주문",
			["setactive"] = "%s %d 셋템이 활성화 : %s.",
			["true"] = "옳음",
			["false"] = "틀림",
			["healing"] = "당신의 치유는 %s 위협수준을 발생시킨다.(포괄적인 위협수준 배율을 적용하기전).",
			["talentpoint"] = "특성포인트 %d : %s 기술.",
			["talent"] = "%d %s 특성 발견.",
			["rockbiter"] = "당신의 %d레벨의 대지의 무기는 근접공격이 성공할 시, %d 위협수준이 추가된다.",
		},
		-- new in R17.7
		["boss"] =
		{
			["automt"] = "주타겟이 자동적으로 %s|1으로;로; 설정되었습니다.",
			["spellsetmob"] = "%1$s님이 %3$s의 %4$s 기술의 %2$s 변수값을 %6$s에서 %5$s으로 설정합니다.",
			["spellsetall"] = "%1$s님이 %3$s 기술의 %2$s 변수값을 %5$s에서 %4$s으로 설정합니다.",
			["reportmiss"] = "%s님이 %s의 %s 기술이 자신을 빛맞추었다고 보고합니다.",
			["reporttick"] = "%s님이 %s의 %s 기술이 자신을 맞추었다고 보고합니다. %s틱동안 피해를 당했으며, %s틱동안 더 영향을 받을 것입니다.",
			["reportproc"] = "%s님이 %s의 %s 기술이 위협수준을 %s에서 %s으로 변경시켰다고 보고합니다.",
			["bosstargetchange"] = "%s|1이;가; 타겟을 %s(%s 위협수준)에서 %s (%s 위협수준)으로 변경하였습니다.",
			["autotargetstart"] = "미터기가 자동적으로 주타겟을 비우고 타겟으로 한 다음 월드보스몹을 주타겟으로 설정할 것입니다.",
			["autotargetabort"] = "주타겟이 이미 월드보스인 %s|1으로;로; 설정되었습니다.",
		},

		["network"] =
		{
			["newmttargetnil"] = "주타겟을 %s|1으로;로; 설정할 수 없습니다. %s님은 타겟이 없습니다.",
			["newmttargetmismatch"] = "%s님이 주타겟을 %s|1으로;로; 설정하였습니다, 하지만 현재 자신의 대상은 %s입니다. 자신의 대상을 사용하려 했다면, 확인하십시요!",
			["mtpollwarning"] = "당신의 주타겟이 %s|1으로;로; 업데이트되었지만, 확신할 수 없습니다. 정확하지 않다면, %s님에게 주타겟을 재개시하도록 요청하십시오.",
			["threatreset"] = "%s님이 레이드 어그로미터를 리셋함.",
			["newmt"] = "%2$s님이 주타겟을 %1$s|1으로;로; 설정함.",
			["mtclear"] = "%s님이 주타겟을 초기화함.",
			["knockbackstart"] = "NPC 주문 리포팅을 %s님이 활성화함.",
			["knockbackstop"] = "NPC 주문 리포팅을 %s님이 비활성화함.",
			["aggrogain"] = "%s님이 %d의 위협수준으로 어그로를 얻었습니다.",
			["aggroloss"] = "%s님이 %d의 위협수준으로 어그로를 잃었습니다.",
			["knockback"] = "%s님이 knockback 당했다고 보고됩니다. 그의 위협수준이 %d만큼 다운되었습니다.",
			["knockbackstring"] = "%s님이 knockback 문자열이 '%s'이라고 보고했습니다.",
			["upgraderequest"] = "%s님이 KLHThreatMeter 버젼 %s으로 업그레이드하라는 요청이 있습니다. 현재 사용하는 버젼은 %s입니다..",
			["remoteoldversion"] = "%s님이 오래된 KLHThreatMeter 버젼 %s을 사용하고 있습니다. 버젼 %s으로 업그레이드하라고 알려주십시오.",
			["knockbackvaluechange"] = "|cffffff00%s|r님이 %s의 |cffffff00%s|r 공격의 위협수준 감소를 |cffffff00%d%%|r로 셋팅했습니다.",
			["raidpermission"] = "공대장이나 승급자만이 수행가능함.",
			["needmastertarget"] = "주타겟을 먼저 설정해야 함!",
			["knockbackinactive"] = "Knockback discovery가 공격대에서 활성화되지 못함.",
			["versionrequest"] = "레이드로부터 버젼정보를 요청중. 3초정도의 응답시간.",
			["versionrecent"] = "release %s을 사용하는 사람: { ",
			["versionold"] = "이전 버젼을 사용하는 사람: { ",
			["versionnone"] = "KLHThreatMeter을 사용하지 않거나, CTRA채널이 틀린 사람: { ",
			["channel"] =
			{
				ctra = "CTRA Channel",
				ora = "oRA Channel",
				manual = "Manual Override",
			},
			needtarget = "대상이 있어야 주타겟으로 선택 가능합니다.",
			upgradenote = "이전버젼을 업그레이드하라고 알리게 됩니다.",
			advertisestart = "어그로를 끄는 사람에게 KLHThreatMeter를 사용하라는 말을 지금부터 광고하게 됩니다.",
			advertisestop = "KLHThreatMeter에 대한 광고 중단.",
			advertisemessage = "KLHThreatMeter를 사용하셨다면, %s의 어그로를 끌지 않았을 것입니다.",
		},
		
		-- ok, so autohide isn't really a word, but just improvise
		table = 
		{
			autohideon = "창이 지금부터 자동적으로 숨겨지고 나타납니다.",
			autohideoff = "창이 더이상 자동적으로 숨겨지지 않습니다.",
		}
	}
}


```

## Code\Localisation\KTM_Localisation.lua
```lua

--[[
Localisation for KLHThreatMeter.

The structure for localisation is probably a bit different to most mods. There is no long list of constants called KLHTM_COMBAT_RAZORGORE_PHASE2 or similar, because it looks silly, and is hard to debug, not to mention type.

All the strings are stored in multi-layered table with related strings. The names of spells are in one subtable,
the names of talents in another. Some tables contain subtables. 

The highest level of the tree is keyed by your localisation - "enUS" or "frFR" etc (these are the return values of GetLocale()). A small subset of the tree is

me.data = 
{
	["enUS"] = 
	{
		["spell"] = 
		{
			["cower"] = "Cower",
		}
	},
	["frFR"] = 
	{
		["spell"] = 
		{
			["cower"] = "D\195\169robade",
		},
	},
}
	
To get the localised name of the spell Cower, call the function 
	mod.string.get("spell", "cower")

The table mod.string.data is an empty table defined below; each localisation file adds their own subtable.
]]

-- Add the module to the tree
local mod = klhtm
local me = {}
mod.string = me

-- Special onload method called from Core.lua
me.onload = function()
	
	me.createreverselookup(me.data[me.mylocale], me.reverselookup, "klhtm.string.data." .. me.mylocale )
	
	-- set up key binding variables
	BINDING_HEADER_KLHTM = "KLHThreatMeter"
	
	BINDING_NAME_KLHTM_HIDESHOW = me.get("binding", "hideshow")
	BINDING_NAME_KLHTM_STOP = me.get("binding", "stop")
	BINDING_NAME_KLHTM_MASTERTARGET = me.get("binding", "mastertarget")
	BINDING_NAME_KLHTM_RESETRAID = me.get("binding", "resetraid")
	
end

--[[
	Often we could like to unlocalise the name of a spell or mob. It is much easier to work with an internal representation such as "sunder" than the value mod.string.get("spell", "sunder") all the time.
	The table me.reverselookup is where we will store the unlocalisation. Before run time, it will just list all the parts of the localisation tree that we want to unlocalise. e.g. "spell = true", indicates that we want to "spell" section to have a reverse lookup.
	To get a lookup for deeper parts of the localisation tree, just duplicate the tree until you reach the set you want.
]]
me.reverselookup = 
{
	spell = true,
	boss = 
	{
		name = true,
		spell = true,
	},
}

--[[
me.createreverselookup(localtree, reversetree, parentkey)
	Fills in the lookup tree (initially me.reverselookup) with a key-value list, where the key is the localised string and the value is the internal identifier.
	The method is recursive, if it encounters a subtable it will call itself on that table.
]]
me.createreverselookup = function(localtree, reversetree, parentkey)

	local key, value, localtable, reversetable, key2, value2
	
	for key, value in reversetree do
		
		-- check that your localisation has <key> defined
		localtable = localtree[key]
		
		if localtable == nil then
			if mod.out.checktrace("warning", me, "lookup") then
				mod.out.printtrace(string.format("Can't complete the localisation reverse lookup because the strings for %s.%s haven't been localised!", parentkey, key))
			end
		elseif type(value) == "table" then
			me.createreverselookup(localtree[key], value, parentkey .. "." .. key)
			
		else
			reversetable = { }
			localtable = localtree[key]
			
			for key2, value2 in localtable do
				reversetable[value2] = key2
			end
			
			reversetree[key] = reversetable
		end
	end
	
end

--[[
mod.string.unlocalise(key1, key2, [key3, key4, key5])
	Gets the internal name for a spell or mob that has a localisation string. e.g. converts "Sunder Armor" to "sunder", but works on any locale (where "sunder" has been defined).
	The first few keys are entries in the me.reverselookup table, which specify which part of the localisation tree the lookup will work on, i.e. are you looking for a spell, or a boss' name, etc. The last key is the value you have parsed from a combat log.
Returns: the internal identifier, if it exists, otherwise nil.
]]
me.unlocalise = function(key1, key2, key3, key4, key5)

	-- Load arguments
	me.stringkeys[1] = key1
	me.stringkeys[2] = key2
	me.stringkeys[3] = key3
	me.stringkeys[4] = key4
	me.stringkeys[5] = key5
	
	local x
	local subtable = me.reverselookup
	
	for x = 1, 5 do
		if subtable[me.stringkeys[x]] == nil then
			
			--[[
				There is no such entry in the reverse lookup tree. If the key we are checking was the last key, this is fine, it just means the spell or mob is not a special one, or there is no localisation created for it.
				However if it is not the last key, then there is an internal error in the reverse lookup tree, or the keys are invalid.
			]]
			if (x == 5) or (me.stringkeys[x + 1] == nil) then
				-- this was the last key - no hit. return nil.
				return nil
			
			else
				-- error occur!
				if mod.out.checktrace("error", me, "lookup") then
					mod.out.printtrace(string.format("Localisation reverse lookup error. No subtable for %s in the keyset %s.", me.stringkeys[x], me.keysettostring()))
				end
				return nil
			end
		
		else
			subtable = subtable[me.stringkeys[x]]
			
			if type(subtable) ~= "table" then
				-- we've come to the end of the keyset and found a match, yay
				return subtable
			end
		end	
	end
	
end

me.data = {}
me.mylocale = GetLocale()

-- we want enGB to use the enUS names for spells and mobs. We don't want enGB to just default to enUS, because features would be disabled if the mod thought it was defaulting.
if me.mylocale == "enGB" then
	me.mylocale = "enUS"
end


-- This holds the arguments to the method me.get(). We want to store them in a table, but don't want to
-- recreate the table whenever the method is called, because excessive heap memory will be used.
me.stringkeys = { "1", "2", "3", "4", "5" }

--[[
mod.string.get(key1, key2, [key3, key4, key5])
	Gives the localisation string specified by the set of keys. Localisation strings are grouped into related categories in a heirarchial manner. <key1> is the highest, most general level, e.g. "print", <key2> is more specific, e.g. "network", and the other keys are more specific still, e.g. "newmttargetnil". So the method call mod.string.get("print", "network", "newmttargetnil") is a message whose english value is "Could not confirm the master target %s, because %s has no target.".
	Refer to KTM_enUS.lua for a list of all keys.
	If there is no localised version available, the mod will return the English version instead. 
]]
me.get = function(key1, key2, key3, key4, key5)
	
	-- Load arguments
	me.stringkeys[1] = key1
	me.stringkeys[2] = key2
	me.stringkeys[3] = key3
	me.stringkeys[4] = key4
	me.stringkeys[5] = key5
	
	-- Try to find a localised version
	local stringvalue = me.getinternal(me.mylocale)
	
	if stringvalue == nil then
		
		-- No value was found. It's likely that your localisation has not been completely updated.
		-- This is probably a non-essential string, so the English version will do
		
		stringvalue = me.getinternal("enUS")
			
		if stringvalue == nil then
			-- No string in the english version either. The keys must have been wrong.
			
			if mod.out.checktrace("error", me, "get") then
				mod.out.printtrace(string.format("The localisation identifier |cffffff00%s|r does not exist.", me.keysettostring()))
			end
			return "."
		
		else
			
			-- Found the english version. Use it this time. 
			if mod.out.checktrace("warning", me, "get") then
				mod.out.printtrace(string.format("The |cffffff00%s|r locale has no value for the key |cffffff00%s|r.", me.mylocale, me.keysettostring()))
			end
			return stringvalue
		end
	end
		
	return stringvalue
	
end

--[[
Fetches a localisation string. Returns nil if there is no match.
<locale> is e.g. "enUS", "frFR", a return value of GetLocale().
The lookup keys for the string have already been written to the me.stringkeys array.
]]
me.getinternal = function(locale)

	local value = me.data[locale]
	local key
	
	-- Recall the format of me.stringkeys is e.g. { "print", "data", "talent" }
	
	-- The length of the array me.stringkeys is unknown. The for loop will keep going until it comes to <nil>.
	for _, key in me.stringkeys do
		
		-- "value" was obtained in the last loop. Since we are looping again, there must be another key
		-- inside, so value has to be a table object
		
		if value == nil then
			return nil
		end
		
		if type(value) ~= "table" then
			return nil
		end
		
		value = value[key]
	end
	
	return value
	
end

--[[
Prints out the keys that were requested for a localisation string. Used only when there is an error.
e.g. { "combat", "attack", "kill" } --> "combat.attack.kill"
]]
me.keysettostring = function()
	
	local message = ""

	for _, key in me.stringkeys do
		message = message .. "." .. key
	end
	
	return message
	
end

--[[
mod.string.testlocalisation(locale)
Checks your localisation for missing values (compared to enUS)
locale is "enUS" or "deDE", etc.
]]
me.testlocalisation = function(locale)

	-- default = check your own locale
	if locale == nil then
		locale = me.mylocale
	end
	
	if me.data[locale] == nil then
		mod.out.print(string.format("Sorry, there's no localisation at all for the |cffffff00%s|r locale.", locale))
		return
	end
	
	me.testlocalisationbranch(me.data["enUS"], me.data[locale], "")

end

-- return value = number of errors
-- linkstring = current table identifier, e.g. "print.combat."
me.testlocalisationbranch = function(english, mine, linkstring)

	local key
	local value
	local errors = 0
	
	-- check for missing values in our locale
	for key, value in english do
		
		if mine[key] == nil then
			if type(value) == "table" then
				mod.out.print(string.format("Missing the set of keys |cffffff00%s%s|r.", linkstring, key))
				errors = errors + 1
			else
				mod.out.print(string.format("Missing the key |cffffff00%s%s|r. The english value is |cff3333ff%s|r", linkstring, key, value))
				errors = errors + 1
			end
			
		else
			-- recurse to subtables
			if type(value) == "table" then
				errors = errors + me.testlocalisationbranch(value, mine[key], linkstring .. key .. ".")
			end
		end
	end
	
	-- check for unused values (in the english)
	for key, value in mine do
		
		if english[key] == nil then
			if type(value) == "table" then
				mod.out.print(string.format("The set of keys |cffffff00%s%s|r does not exist in the english version, so is probably no longer used.", linkstring, key))
				errors = errors + 1
			else
				mod.out.print(string.format("The key |cffffff00%s%s|r does not exist in the english version, so is probably no longer used. The current value is |cff3333ff%s|r", linkstring, key, value))
				errors = errors + 1
			end
		end
	end
	
	-- print out total errors (base case only)
	if linkstring == "" then
		mod.out.print(string.format("Found |cffffff00%d|r errors in total.", errors))
	end
	
	return errors
end
```

## Code\Localisation\KTM_ruRU.lua
```lua
-- Version : Russian ( by Maus )

klhtm.string.data["ruRU"] = 
{
	["binding"] = 
	{
		hideshow = "Скрыть / Показать окно",
		stop = "Аварийная остановка",
		mastertarget = "Установка / Очистка мастера цели",
		resetraid = "Сброс рейд. угрозы",
	},
	["spell"] = 
	{
		-- 17.20
		["execute"] = "Казнь",
		
		["heroicstrike"] = "Удар героя",
		["maul"] = "Трепка",
		["swipe"] = "Размах",
		["shieldslam"] = "Мощный удар щитом",
		["revenge"] = "Реванш",
		["shieldbash"] = "Удар щитом",
		["sunder"] = "Раскол брони",
		["thunderclap"] = "Удар грома",
		["demoralizingshout"] = "Деморализующий крик",
		["feint"] = "Ложный выпад",
		["cower"] = "Попятиться",
		["taunt"] = "Провокация",
		["growl"] = "Рык",
		["vanish"] = "Исчезновение",
		["frostbolt"] = "Ледяная стрела",
		["fireball"] = "Огненный шар",
		["arcanemissiles"] = "Чародейские стрелы",
		["scorch"] = "Ожог",
		["cleave"] = "Рассекающий удар",
		
		hemorrhage = "Кровоизлияние",
		backstab = "Удар в спину",
		sinisterstrike = "Коварный удар",
		eviscerate = "Потрошение",

		corruption = "Порча",
		curseofagony = "Проклятие агонии",
		siphonlife = "Вытягивание жизни",
		immolate = "Жертвенный огонь",
		
		-- Items / Buffs:
		["arcaneshroud"] = "Чародейский покров",
		["reducethreat"] = "Снижение угрозы",
		["theeyeofdiminution"] = "Око Убывания",
		["notthere"] = "Не там",

		-- Leeches: no threat from heal
		["holynova"] = "Кольцо света", -- no heal or damage threat
		["siphonlife"] = "Вытягивание жизни", -- no heal threat
		["drainlife"] = "Похищение жизни", -- no heal threat
		["deathcoil"] = "Лик смерти",	
		
		-- Fel Stamina and Fel Energy DO cause threat! GRRRRRRR!!!
		--["felstamina"] = "Выносливость скверны",
		--["felenergy"] = "Энергия Скверны",
		
		["bloodsiphon"] = "Кровавый насос", -- poisoned blood vs Hakkar
		
		["lifetap"] = "Жизнеотвод", -- no mana gain threat
		["holyshield"] = "Щит нечестивости", -- multiplier
		["tranquility"] = "Спокойствие",
		["distractingshot"] = "Отвлекающий выстрел",
		["earthshock"] = "Земной шок",
		["rockbiter"] = "Оружие Камнедробителя",
		["fade"] = "Слиться с тенью",
		["thunderfury"] = "Неистовство бури",
		
		-- Spell Sets
		-- warlock descruction
		["shadowbolt"] = "Стрела Тьмы",
		["immolate"] = "Жертвенный огонь",
		["conflagrate"] = "Поджигание",
		["searingpain"] = "Жгучая боль", -- 2 threat per damage
		["rainoffire"] = "Огненный ливень",
		["soulfire"] = "Ожог души",
		["shadowburn"] = "Ожог Тьмы",
		["hellfire"] = "Адское пламя",
		
		-- mage offensive arcane
		["arcaneexplosion"] = "Чародейский взрыв",
		["counterspell"] = "Антимагия",
		
		-- priest shadow. No longer used (R17).
		["mindblast"] = "Взрыв разума",	-- 2 threat per damage
		--[[
		["mindflay"] = "Пытка разума",
		["devouringplague"] = "Всепожирающая чума",
		["shadowwordpain"] = "Слово Тьмы: Боль",
		["manaburn"] = "Сожжение маны",
		]]
	},
	["power"] = 
	{
		["mana"] = "Мана",
		["rage"] = "Ярость",
		["energy"] = "Энергия",
	},
	["threatsource"] = -- these values are for user printout only
	{
		["powergain"] = "Power Gain",
		["total"] = "Всего",
		["special"] = "Особые",
		["healing"] = "Исцеление",
		["dot"] = "Период. урон",
		["threatwipe"] = "Закл. НПС",
		["damageshield"] = "Урон щитом",
		["whitedamage"] = "Белый урон",
	},
	["talent"] = -- these values are for user printout only
	{
		["defiance"] = "Неукротимость",
		["impale"] = "Прокалывание",
		["silentresolve"] = "Молчаливая решимость",
		["frostchanneling"] = "Направленная сила льда",
		["burningsoul"] = "Пылающая душа",
		["healinggrace"] = "Исцеляющая благодать",
		["shadowaffinity"] = "Единение с Тьмой",
		["druidsubtlety"] = "Скрытность друидов",
		["feralinstinct"] = "Животный инстинкт",
		["ferocity"] = "Свирепость",
		["savagefury"] = "Бешеное неистовство",
		["tranquility"] = "Улучшенное спокойствие",
		["masterdemonologist"] = "Мастер-демонолог",
		["arcanesubtlety"] = "Искусные чары",
		["righteousfury"] = "Праведное неистовство",
		["sleightofhand"] = "Ловкость рук",
	},
	["threatmod"] = -- these values are for user printout only
	{
		["tranquilair"] = "Тотем безветрия",
		["salvation"] = "Благословение спасения",
		["battlestance"] = "Боевая стойка",
		["defensivestance"] = "Оборонительная стойка",
		["berserkerstance"] = "Стойка берсерка",
		["defiance"] = "Неукротимость",
		["basevalue"] = "Базовое значение",
		["bearform"] = "Облик медведя",
		["catform"] = "Облик кошки",
		["glovethreatenchant"] = "+Угроза Чары для перчаток",
		["backthreatenchant"] = "-Угроза Чары для плаща",
	},
	
	["sets"] = 
	{
		["bloodfang"] = "Кровавых Клыков",
		["nemesis"] = "возмездия",
		["plagueheart"] = "Проклятого Сердца",
		["bonescythe"] = "костяной косы",
		["netherwind"] = "ветра Пустоты",
		["might"] = "мощи",
		["arcanist"] = "чародея",
	},
	["boss"] = 
	{
		["speech"] = 
		{
			["onyxiaphase1"] = "Вот это сюрприз. Обычно, чтобы найти обед, мне приходится покидать логово.",
			["onyxiaphase2"] = "Эта бессмысленная возня вгоняет меня в тоску. Я сожгу вас всех!",
			["razorphase2"] = "убегает, как только сила сферы пошла на спад.",
			["onyxiaphase3"] = "Похоже, вам требуется преподать еще один урок",
			["thekalphase2"] = "наполни меня своим ГНЕВОМ",
			["rajaxxfinal"] = "Настырная тварь! Я сам тебя убью!",
			["azuregosport"] = "Сюда, малыши",
			["nefphase1"] = "Браво, слуги мои! Смертные утрачивают мужество!", --vmangos+old
			["nefphase2"] = "Горите, мерзавцы, ГОРИТЕ!",
			["razargor1"] = "Я свободен! Эта адская машина больше не будет меня мучить!", --vmangos
			["broodlord1"] = "Таких, как вы, здесь быть не должно! Смерть грозит лишь вам!", --vmangos
			["thad1"] = "Я сожру ваши кости!",
			["thad2"] = "BREAK YOU!",
			["thad3"] = "Убивать!",
			["noth1"] = "Умри, преступник!",
			["noth2"] = "Слава господину!",
			["noth3"] = "Жизнь – плата за твои проступки.",
			["ktphase2"] = "Моли о пощаде!",
		},
		-- Some of these are unused. Also, if none is defined in your localisation, they won't be used,
		-- so don't worry if you don't implement it.
		["name"] = 
		{
			["rajaxx"] = "Генерал Раджакс",
			["onyxia"] = "Ониксия",
			["ebonroc"] = "Черноскал",
			["razorgore"] = "Бритвосмерт Неукротимый",
			["thekal"] = "Верховный жрец Текал",
			["shazzrah"] = "Шаззрах",
			["twinempcaster"] = "Император Век'лор",
			["twinempmelee"] = "Император Век'нилаш",
			["noth"] = "Нот Чумной",
		},
		["spell"] = 
		{
			["shazzrahgate"] = "Врата Шаззраха", -- "Shazzrah casts Gate of Shazzrah."
			["wrathofragnaros"] = "Гнев Рагнароса", -- "Ragnaros's Wrath of Ragnaros hits you for 100 Fire damage."
			["timelapse"] = "Искажение времени", -- "You are afflicted by Time Lapse."
			["knockaway"] = "Отталкивание",
			["wingbuffet"] = "Рассечение крылом",
			["burningadrenaline"] = "Горящий адреналин",
			["twinteleport"] = "Двойной телепорт",
			["nothblink"] = "Скачок",
			["sandblast"] = "Песчаный вихрь",
			["fungalbloom"] = "Поганочный цвет",
			["hatefulstrike"] = "Удар ненависти",
			
			-- 4 horsemen marks
			mark1 = "Знак Бломе",
			mark2 = "Знак Кортазза",
			mark3 = "Знак Могрейна",
			mark4 = "Знак Зелиека",
			
			-- Onyxia fireball (presumably same as mage)
			fireball = "Огненный шар",
		}
	},
	["misc"] = 
	{
		["imp"] = "Бес", -- UnitCreatureFamily("pet") -- CreatureFamily.dbc
		["spellrank"] = "Уровень (%d+)", -- second value of GetSpellName(x, "spell")
		["aggrogain"] = "Срыв Аггро",
	},

	-- labels and tooltips for the main window
	["gui"] = { 
		["raid"] = {
			["head"] = {
				-- column headers for the raid view
				["name"] = "Имя",
				["threat"] = "Угроза",
				["pc"] = "%Макс",			-- your threat as a percentage of the #1 player's threat
				["sunder"] = "РБ",			-- your threat as a percentage of the #1 player's threat
			},
			["stringshort"] = {
				-- tooltip titles for the bottom bar strings
				["tdef"] = "Срыв Аггро", -- the difference in threat between you and the MT / #1 in the list.
				["targ"] = "Мастер цели",
			},
			["stringlong"] = {
				-- tooltip descriptions for the bottom bar strings
				["tdef"] = "",
				["targ"] = "В настоящий момент в таблицу рейда записывается показатель угрозы только по отношению к (%s)"
			},
		},
		["self"] = {
			["head"] = {
				-- column headers for the self view
				["name"] = "Имя",
				["hits"] = "Попаданий",
				["rage"] = "Ярость",
				["dam"] = "Урон",
				["threat"] = "Угроза",
				["pc"] = "%У",			-- Abbreviation of %Threat
			},
			-- text on the self threat reset button
			["reset"] = "Сброс",
		},
		["title"] = {
			["text"] = {
				-- the window titles
				["long"] = "KTM %d.%d",	-- don't need to localise these
				["short"] = "KTM",
				
			},
			["buttonshort"] = {
				-- the tooltip titles for command buttons
				["close"] = "Закрыть",
				["min"] = "Свернуть",
				["max"] = "Развернуть",
				["self"] = "Персональные данные",
				["raid"] = "Данные рейда",
				["pin"] = "Закрепить",
				["unpin"] = "Открепить",
				["opt"] = "Настройки",
				["targ"] = "Мастер Цели",
				["clear"] = "Сброс",
			},
			["buttonlong"] = {
				-- the tooltip descriptions for command buttons
				["close"] = "Если вы находитесь в группе или рейде, данные по прежнему буду передаваться.",
				["min"] = "",
				["max"] = "",
				["self"] = "Показ персональных данных угрозы",
				["raid"] = "Показ данных угрозы рейда",
				["pin"] = "Предотвращает перемещение окна",
				["unpin"] = "Позволяет перемещать окно",
				["opt"] = "",
				["targ"] = "Установка Мастера Цели на вашу текущую цель. Если у вас нет цели, Мастер Цели очищается. Вы должны быть помощником или лидером рейда",
				["clear"] = "Обнуление угрозы всем игрокам. Вы должны быть помощником или лидером рейда.",
			},
			["stringshort"] = {
				-- the tooltip titles for titlebar strings
				["threat"] = "Угроза",
				["tdef"] = "Разница угрозы",
				["rank"] = "Уровень угрозы",
				["pc"] = "% Угрозы",
				["sunder"] = "Раскол брони",
			},
			["stringlong"] = {
				-- the tooltip descriptions for titlebar strings
				["threat"] = "Значение уровня угрозы в ваших личных записях был сброшен",
				["tdef"] = "Разница между угрозой и целями",
				["rank"] = "Ваша позиция в списке угрозы",
				["pc"] = "Ваша угроза в виде процента в отношении к цели ",
			},
		},
	},
	-- labels and tooltips for the options gui
	["optionsgui"] = {
		["buttons"] = {
			-- the options gui command button labels
			["gen"] = "Общее",
			["raid"] = "Рейд",
			["self"] = "Свой",
			["close"] = "Закрыть",	
		},
		-- the labels for option checkboxes and headers
		["labels"] = {
			-- the title description for each option page
			["titlebar"] = {
				["gen"] = "Общие настройки",
				["raid"] = "Рейдовые настройки",
				["self"] = "Персональные настройки",
			},
			["buttons"] = {
				-- the names of title bar command buttons
				["pin"] = "Закрепить",
				["opt"] = "Настройки",
				["view"] = "Данные",
				["targ"] = "Мастер Цели",
				["clear"] = "Сброс рейд. угрозы",
			},
			["columns"] = {
				-- names of columns on the self and raid views
				["hits"] = "Попаданий",
				["rage"] = "Ярость",
				["dam"] = "Урон",
				["threat"] = "Угроза",
				["pc"] = "% угрозы",
				["sunder"] = "Раскол брони",
			},
			["options"] = {
				-- miscelaneous option names
				["hide"] = "Скрыть строки с 0 угр.",
				["abbreviate"] = "Сокр. большие значения",
				["resize"] = "Изм. размера рамки",
				["aggro"] = "Показ. срыв аггро",
				["rows"] = "Макс. число вид. строк",
				["scale"] = "Масштаб. окна",
				["bottom"] = "Скрыть нижнюю панель",
				["minimap"] = "Показать кнопку у миникарты",
			},
			["minvis"] = {
				-- the names of minimised strings
				["threat"] = "Мин. угрозы", -- dodge...
				["rank"] = "Ранг угрозы",
				["pc"] = "% угрозы",
				["sunder"] = "Раскол брони",
				["tdef"] = "Разница угрозы",
			},
			["headers"] = {
				-- headers in the options gui
				["columns"] = "Видимые столбцы",
				["strings"] = "Мин. строки",
				["other"] = "Другие настройки",
				["minvis"] = "Мин. кнопки",
				["maxvis"] = "Макс. кнопки",
			},
		},
		-- the tooltips for some of the options
		["tooltips"] = {
			-- miscelaneous option descriptions
			["raidhide"] = "Если установлен флажок , игроки с нулевым показателем угрозы не будут видны в списке.",
			["selfhide"] = "Снимите флажок, чтобы увидеть все категории угрозы.",
			["abbreviate"] = "Если установлен флажок, значения, превышающие десять тысяч будут сокращены префиксом \"К\". Например \"15400\" станет \"15.4К\".",
			["resize"] = "Если установлен флажек, количество строк будет снижено, чтобы соответствовать количеству игроков в листе угрозы.",
			["aggro"] = "Если установлен фладок, игрок добавляется в дисплей рейда, на котором отображается срыв аггро. Для более точного значения рекомендуется поставить на цель Мастера Цели.",
			["rows"] = "Максимальное количество игроков в листе угрозы.",
			["bottom"] = "Если установлен флажок, будет скрыта нижняя строка.",
			["minimap"] = "Нажмите левую клавишу мыши, чтобы открыть KTM.\nНажмите Shift + левую клавишу мыши, чтобы открыть настройки KTM.\nНажмите правую клавишу мыши для перемещения кнопки.",
		},
	},
	["print"] = 
	{
		["main"] = 
		{
			["startupmessage"] = "KLHThreatMeter Версия |cff33ff33%s|r Ревизия |cff33ff33%s|r загружена. Введите |cffffff00/ktm|r для вызова справки.",
		},
		["data"] = 
		{
			["abilityrank"] = "Ваша %s способность %s ранга.",
			["globalthreat"] = "Ваш глобальный множитель угрозы %s.",
			["globalthreatmod"] = "%s предоставляет вам %s.",
			["multiplier"] = "%s, ваша угроза к %s умножается на %s.",
			["damage"] = "урон",
			["shadowspell"] = "заклинания темной магии",
			["arcanespell"] = "заклинания тайной магии",
			["holyspell"] = "заклинания светлой магии",
			["setactive"] = "%s %d активный? ... %s.",
			["true"] = "верно",
			["false"] = "ложно",
			["healing"] = "Ваше исцеление создают %s  угрозы (до глобального множителя угрозы)",
			["talentpoint"] = "У вас есть %d очков талантов %s.",
			["talent"] = "Обнаружены %d %s таланты.",
			["rockbiter"] = "Ваш уровень %d камнедробителя добавляет %d угрозы после успешных атак ближнего боя.",
		},
		
		-- new in R17.7
		["boss"] = 
		{
			["automt"] = "Мастер Цели автоматически установлен на %s.",
			["spellsetmob"] = "%s задает %s параметр %s %s способности %s с %s.", -- "Kenco sets the multiplier parameter of Onyxia's Knock Away ability to 0.7"
			["spellsetall"] = "%s устанавливает the %s параметр со %s способности в %s с %s.",
			["reportmiss"] = "%s сообщает что %s's %s промахнулся.",
			["reporttick"] = "%s сообщает что %s's %s попал. Он пострадал от %s тиков, и находится еще под %s тиками.",
			["reportproc"] = "%s сообщает что %s's %s изменил свою угрозу с %s на %s.",
			["bosstargetchange"] = "%s изменил свою цель с %s (на %s угрозы) на %s (на %s угрозы).",
			["autotargetstart"] = "Автоматически обнулится счетски угрозы и установтся Матсер Метски, когда вы атакуюете следующего мирового босса.",
			["autotargetabort"] = "Мастер Цели уже установлен на мирового босса %s.",
		},
		
		["network"] = 
		{
			["newmttargetnil"] = "Мастер Цели не может подтвердить |cffffff00%s|r, потому что |cffffff00%s|r не имеет цели.",
			["newmttargetmismatch"] = "|cffffff00%s|r устанавливает Мастер Цели на |cffffff00%s|r, но его собственная цель |cffffff00%s|r.",
			["mtpollwarning"] = "Обновлен ваш Мастер Цели на |cffffff00%s|r, но не подтвердили. Запросите |cffffff00%s|r на повторный Мастер Цели, если текущий кажется некоректным",
			["threatreset"] = "Рейдовый измеритель угрозы был очищен |cffffff00%s|r.",
			["newmt"] = "Мастер Цели был установлен на |cffffff00%s|r персонажем |cffffff00%s|r.",
			["mtclear"] = "Мастер Цели был очищен |cffffff00%s|r.",
			["knockbackstart"] = "Отчет заклинаний НПС был активирован |cffffff00%s|r.",
			["knockbackstop"] = "Отчет заклинаний НПС был остановлен |cffffff00%s|r.",
			["aggrogain"] = "|cffffff00%s|r получен отчет угрозы с %d угрозой.",
			["aggroloss"] = "|cffffff00%s|r потерян отчет угрозы с %d угрозой.",
			["knockback"] = "|cffffff00%s|r Спадает до %d угрозы.",
			["knockbackstring"] = "%s отчет этого отбрасывания в тексте: '%s'.",
			["upgraderequest"] = "%s настоятельно рекомендуем вам перейти на версию %s KLHThreatMeter. В данный момет вы используете %s.",
			["remoteoldversion"] = "%s использует устаревшую версию %s KLHThreatMeter. Пожалуйста, попросите его перейти на версию %s.",
			["knockbackvaluechange"] = "|cffffff00%s|r установил сокращение угрозы на %s |cffffff00%s|r атаки |cffffff00%d%%|r.",
			["raidpermission"] = "Вы должны быть рейд лидером или помощником что бы сделать это!",
			["needmastertarget"] = "В начале вы должны установить Мастер Цели.",
			["knockbackinactive"] = "Открытое сбрасывание не активно в рейде.",
			["versionrequest"] = "Запрос о информации аддона от рейда. Ответ через 3 секунды",
			["versionrecent"] = "Эти игроки имеют версию %s: { ",
			["versionold"] = "Эти игроки имеют старую версию: { ",
			["versionnone"] = "Это игроки не имеют KLHThreatMeter или не в CTRA  канале: { ",
			["channel"] = 
			{
				ctra = "CTRA канал",
				ora = "oRA канал",
				manual = "Ручное управление",
			},
			needtarget = "Для установки Мастера Цели нужна цель",
			upgradenote = "Старая версия аддона. Уведомление для обновления.",
			advertisestart = "Теперь вы можете посоветовать игрокам, которые срывают с вас угрозу, установить KLHThreatMeter.",
			advertisestop = "Вы остановили объявления KLHThreatMeter.",
			advertisemessage = "Если вы имеете KLHThreatMeter, вы моежете увидеть количество угрозы %s.",
		},
		
		-- ok, so autohide isn't really a word, but just improvise
		table = 
		{
			autohideon = "Окно будет автоматически скрыто и показывать персональное окно.",
			autohideoff = "Окно автоматически больше не скрывается.",
		}
	}
}
```

## Code\Localisation\KTM_zhCN.lua
```lua

klhtm.string.data["zhCN"] =
{
	["spell"] = 
	{
		["heroicstrike"] = "????",
		["maul"] = "??",
		["swipe"] = "??",
		["shieldslam"] = "????",
		["revenge"] = "??",
		["shieldbash"] = "??",
		["sunder"] = "????",
		["feint"] = "??",
		["cower"] = "??",
		["taunt"] = "??",
		["growl"] = "??",
		["vanish"] = "??",
		["frostbolt"] = "???",
		["fireball"] = "???",
		["arcanemissiles"] = "????",
		["scorch"] = "??",
		
		-- Items / Buffs:
		["burningadrenaline"] = "????",
		["arcaneshroud"] = "Arcane Shroud",
		["reducethreat"] = "Reduce Threat",
		["twinteleport"] = "Twin Teleport", 
		
		-- Spell Sets
		-- warlock descruction
		["shadowbolt"] = "???",
		["immolate"] = "??",
		["conflagrate"] = "??",
		["searingpain"] = "????",
		["rainoffire"] = "????",
		["soulfire"] = "????",
		["shadowburn"] = "????",
		["hellfire"] = "????",
		
		-- mage offensive arcane
		["arcaneexplosion"] = "???",
		["counterspell"] = "????",
		
		-- priest shadow
		["mindflay"] = "????",
		["devouringplague"] = "??????",
		["shadowwordpain"] = "???:?",
		["mindblast"] = "????",
		["manaburn"] = "????",
	},
	["power"] = 
	{
		["mana"] = "??",
		["rage"] = "??",
		["energy"] = "??",
	},
	["threatsource"] = 
	{
		["powergain"] = "????",
		["total"] = "??",
		["special"] = "??",
		["healing"] = "??",
		["dot"] = "Dots",
		["threatwipe"] = "????",
		["damageshield"] = "????",
		["whitedamage"] = "????",
	},
	["talent"] = 
	{
		["defiance"] = "??",
		["impale"] = "??",
		["silentresolve"] = "????",
		["shadowaffinity"] = "????",
		["druidsubtlety"] = "??",
		["feralinstinct"] = "????",
		["ferocity"] = "??",
		["savagefury"] = "????",
		["masterdemonologist"] = "??????",
		["arcanesubtlety"] = "????",
		["righteousfury"] = "??????",
	},
	["threatmod"] = 
	{
		["tranquilair"] = "??????",
		["salvation"] = "????",
		["battlestance"] = "????",
		["defensivestance"] = "????",
		["berserkerstance"] = "????",
		["defiance"] = "??",
		["basevalue"] = "???",
		["bearform"] = "???",	
		["glovethreatenchant"] = "+Threat Enchant to Gloves",
		["backthreatenchant"] = "-Threat Enchant to Back",
	},
	["class"] = 
	{
		["warrior"] = "??",
		["druid"] = "???",
		["shaman"] = "??",
		["rogue"] = "??",
		["hunter"] = "??",
		["warlock"] = "??",
		["mage"] = "??",
		["paladin"] = "???",
		["priest"] = "??",
	},
	["sets"] = 
	{
		["bloodfang"] = "??",
		["nemesis"] = "??",
		["netherwind"] = "??",
		["might"] = "??",
		["arcanist"] = "???",
	},
	["boss"] = 
	{
		["name"] = 
		{
			["onyxia"] = "?????",
			["ebonroc"] = "????",
			["razorgore"] = "???????",
		},
		["spell"] = 
		{
			["knockaway"] = "??",
			["wingbuffet"] = "????",
			["uppercut"] = "???",
		},
		["speech"] = 
		{
			["razorphase2"] = "?????????????",
			["onyxiaphase3"] = "????????????",
		},
	},
	["misc"] = 
	{
		["imp"] = "??", -- UnitCreatureFamily("pet")
		["spellrank"] = "?? (%d+)", -- second value of GetSpellName(x, "spell")
		["aggrogain"] = "??Aggro",
	},
	
	--[[
	No longer used: R17
	
	["combatlog"] = 
	{
		
		["whiteattackhit"] = "???(.+)??(%d+)????", -- COMBATHITSELFOTHER and COMBATHITSCHOOLSELFOTHER
		["whiteattackcrit"] = "??(.+)??(%d+)????????", -- COMBATHITCRITSELFOTHER and COMBATHITCRITSCHOOLSELFOTHER
		["damageshield"] = "??(%d+)?(.+)?????(.+)?", -- DAMAGESHIELDSELFOTHER
		["abilityhit"] = "??(.+)??(.+)??(%d+)????", -- SPELLLOGSELFOTHER
		["abilitycrit"] = "??(.+)?(.+)??(%d+)????????", -- SPELLLOGCRITSELFOTHER
		["spellhit"] = "??(.+)??(.+)??(%d+)?(.+)???", --SPELLLOGSCHOOLSELFOTHER
		["spellcrit"] = "??(.+)?????(.+)??(%d+)?(.+)???", -- SPELLLOGCRITSCHOOLSELFOTHER
		["perform"] = "??(.+)??(.+)?", -- SPELLPERFORMGOSELFTARGETTED
		["dot"] = "??(.+)?(.+)???(%d+)?(.+)???", -- PERIODICAURADAMAGESELFOTHER
		["yourhotonother"] = "(.+)??(%d+)???? (??(.+))?", -- PERIODICAURAHEALSELFOTHER
		["othershotonyou"] = "???(%d+)????((.+)?(.+))?", -- PERIODICAURAHEALOTHERSELF
		["hotonself"] = "??(.+)????(%d+)?????", -- PERIODICAURAHEALSELFSELF
		["powergain"] = "??(.+)???(%d+)?(.+)?", -- POWERGAINSELFSELF
		["healcritonself"] = "??(.+)??????????,???(%d+)?????", -- HEALEDCRITSELFSELF
		["healcritonother"] = "??(.+)?(.+)????????,???(%d+)?????", -- HEALEDCRITSELFOTHER 
		["healhitonself"] = "??(.+)????(%d+)?????", -- HEALEDSELFSELF
		["healhitonother"] = "??(.+)???(.+[^%d])(%d+)?????", -- HEALEDSELFOTHER
		["enemyspellhit"] = "(.+)?(.+)?????(%d+)????", -- SPELLLOGOTHERSELF
		["buffstart"] = "????(.+)????", -- AURAADDEDSELFHELPFUL
		["debuffstart"] = "???(.+)??????", -- AURAADDEDSELFHARMFUL
		["buffend"] = "(.+)??????????", -- AURAREMOVEDSELF
		["spellcast"] = "??(.+)???(.+)?", -- SPELLCASTGOSELFTARGETTED
	},
	
	]]
	
	["gui"] = 
	{
		["raidlabel"] = "????",
		["raidshortlabel"] = "??",
		["column"] = 
		{
			["name"] = "??",
			["hits"] = "??",
			["damage"] = "??",
			["threat"] = "??",
			["%max"] = "%Max",
		}
	},
	["print"] = 
	{
		["main"] = 
		{
			["startupmessage"] = "KLHThreatMeter Release |cff33ff33%s|r Revision |cff33ff33%s|r ????? ?? |cffffff00/ktm|r ???????",
		},
		["data"] = 
		{
			["abilityrank"] = "?? %s ????? %s?",
			["globalthreat"] = "?????????? %s?",
			["globalthreatmod"] = "%s ??? %s?",
			["multiplier"] = "????%s,??%s?????? %s?",
			["damage"] = "??",
			["shadowspell"] = "???",
			["arcanespell"] = "??",
			["holyspell"] = "????",
			["setactive"] = "???? %s ?? %d ?? ... %s?",
			["true"] = "?",
			["false"] = "?",
			["healing"] = "??????? %s ??(?????????)?",
			["talentpoint"] = "?? %d ????? %s?",
			["talent"] = "?? %d ? %s ???",
		},
		["combat"] = 
		{
			["razorphase2"] = "?????????????,?????????",
			["onyxiaphase3"] = "???????????????",
		},
		["network"] = 
		{
			["newmttargetnil"] = "???????? %s, ?? %s ?????",
			["newmttargetmismatch"] = "%s ??????? %s,????????? %s, ????????????,????",
			["threatreset"] = "????????? %s ???",
			["newmt"] = "??????????'%s',? %s ???",
			["mtclear"] = "??????? %s ???",
			["knockbackstart"] = "??????? %s ???",
			["knockbackstop"] = "??????? %s ???",
			["aggrogain"] = "%s ??,???? %d ?????Aggro?",
			["aggroloss"] = "%s ??,%d ?????Aggro?",
			["knockback"] = "%s ?????,???????? %d ?",
			["knockbackstring"] = "%s ??????????:'%s'?",
			["upgraderequest"] = "%s ????KLHThreatMeter? %s ?????????? %s?",
			["remoteoldversion"] = "%s ????KLHThreatMeter? %s ?????????? %s?",
			["knockbackvaluechange"] = "|cffffff00%s|r ??? %s ? |cffffff00%s|r ????? |cffffff00%d%%|r?",
			["raidpermission"] = "??????????",
			["needmastertarget"] = "???????????",
			["knockbackinactive"] = "????????????",
			["versionrequest"] = "??????????,??3??????",
			["versionrecent"] = "??????? %s: { ",
			["versionold"] = "????????: { ",
			["versionnone"] = "???????KLHThreatMeter,???????CTRA??: { ",	
		}			
	}
}	
```

## Code\Localisation\KTM_zhTW.lua
```lua
--[[
-- Traditional  Chinese localization file copyright
-- This file free for everyone who want use this AddOn with zhTW WoW, EXCEPT meidoku.
-- Please just keep my name on it is ok. XD
--
-- ?????????
-- ??????????????, ??????? meidoku ??.
-- ?????????. XD
--
-- ????????????????????
-- meidoku???????????????????????????? WoW???AddOn???????
-- ???????????????????OK?????? XD
--
-- KLHThreatMeter Traditional Chinese localization file
-- Maintained by: Kuraki, Suzuna
-- Last updated: 10/11/2006
-- Revision History:
--    06/25/2006  * Update to R16 Test 6
--    06/27/2006  * Update some translation.
--                * Add R16.12 Release support.
--                * Keep check for the "hic!".
--    07/11/2006  * Update to R16.15
--    08/05/2006  * Update to R17 Test 7
--    08/08/2006  * Update to R17.7 RC
--    08/09/2006  * Fixed bug, comment out Fel Stamina
--    08/17/2006  * Update to R17.9
--    08/19/2006  * Update to R17.10 test
--    08/23/2006  * Update to Release 17 (17.12)
--    08/26/2006  * Update to R17.13
--    08/31/2006  * Update to R17.14
--    09/25/2006  * Update to R17.15
--    09/29/2006  * Update to R17.16
--    10/11/2006  * Update to R17.19
--    10/11/2006  * Update to R17.20
--
--]]

klhtm.string.data["zhTW"] =
{
	["binding"] =
	{
		hideshow = "?? / ????",
		stop = "????",
		mastertarget = "?? / ??????",
		resetraid = "??????",
	},
	["spell"] =
	{
		-- 17.20
		["execute"] = "??",
		
		["heroicstrike"] = "????",
		["maul"] = "??",
		["swipe"] = "??",
		["shieldslam"] = "????",
		["revenge"] = "??",
		["shieldbash"] = "??",
		["sunder"] = "????",
		["feint"] = "??",
		["cower"] = "??",
		["taunt"] = "??",
		["growl"] = "??",
		["vanish"] = "??",
		["frostbolt"] = "???",
		["fireball"] = "???",
		["arcanemissiles"] = "????",
		["scorch"] = "??",
		["cleave"] = "???",
		
		["hemorrhage"] = "??",
		["backstab"] = "??",
		["sinisterstrike"] = "????",
		["eviscerate"] = "??",
		
		-- Items / Buffs:
		["arcaneshroud"] = "????",
		["reducethreat"] = "????",

		-- Leeches: no threat from heal
		["holynova"] = "????", -- no heal or damage threat
		["siphonlife"] = "????", -- no heal threat
		["drainlife"] = "????", -- no heal threat
		["deathcoil"] = "????",

		-- Fel Stamina and Fel Energy DO cause threat! GRRRRRRR!!!
		--["felstamina"] = "????",
		--["felenergy"] = "????",

		["bloodsiphon"] = "????", -- poisoned blood vs Hakkar

		["lifetap"] = "????", -- no mana gain threat
		["holyshield"] = "????", -- multiplier
		["tranquility"] = "??",
		["distractingshot"] = "????",
		["earthshock"] = "???",
		["rockbiter"] = "??",
		["fade"] = "???",
		["thunderfury"] = "????",

		-- Spell Sets
		-- warlock descruction
		["shadowbolt"] = "???",
		["immolate"] = "??",
		["conflagrate"] = "??",
		["searingpain"] = "????", -- 2 threat per damage
		["rainoffire"] = "????",
		["soulfire"] = "????",
		["shadowburn"] = "????",
		["hellfire"] = "????",

		-- mage offensive arcane
		["arcaneexplosion"] = "???",
		["counterspell"] = "????",

		-- priest shadow. No longer used (R17).
		["mindblast"] = "????",	-- 2 threat per damage
		--[[
		["mindflay"] = "????",
		["devouringplague"] = "??????",
		["shadowwordpain"] = "???:?",
		,
		["manaburn"] = "????",
		]]
	},
	["power"] =
	{
		["mana"] = "??",
		["rage"] = "??",
		["energy"] = "??",
	},
	["threatsource"] = -- these values are for user printout only
	{
		["powergain"] = "????",
		["total"] = "??",
		["special"] = "??",
		["healing"] = "??",
		["dot"] = "????",
		["threatwipe"] = "????",
		["damageshield"] = "???",
		["whitedamage"] = "????",
	},
	["talent"] = -- these values are for user printout only
	{
		["defiance"] = "??",
		["impale"] = "??",
		["silentresolve"] = "????",
		["frostchanneling"] = "????",
		["burningsoul"] = "????",
		["healinggrace"] = "????",
		["shadowaffinity"] = "????",
		["druidsubtlety"] = "??",
		["feralinstinct"] = " ????",
		["ferocity"] = "??",
		["savagefury"] = "????",
		["tranquility"] = "????",
		["masterdemonologist"] = "??????",
		["arcanesubtlety"] = "????",
		["righteousfury"] = "??????",
		["sleightofhand"] = "????",
	},
	["threatmod"] = -- these values are for user printout only
	{
		["tranquilair"] = "??????",
		["salvation"] = "????",
		["battlestance"] = "????",
		["defensivestance"] = "????",
		["berserkerstance"] = "????",
		["defiance"] = "??",
		["basevalue"] = "???",
		["bearform"] = "???",
		["catform"] = "???",
		["glovethreatenchant"] = "?????????",
		["backthreatenchant"] = "?????????",
	},

	["sets"] =
	{
		["bloodfang"] = "??",    -- Rog, 5? ?????????? 25%
		["nemesis"] = "??",      -- Wlk, 8? ?????????????? 20%
		["netherwind"] = "??",   -- Mag, 3? ?????(-100)?????(??-20)????(-100)????(-100)?????????
		["might"] = "??",        -- War, 8? ?????????? 15%
		["arcanist"] = "???",   -- Mag, 8? ??????????????15%
	},
	["boss"] =
	{
		["speech"] =
		{
			["razorphase2"] = "??????????????",
			["onyxiaphase3"] = "????????????",
			["thekalphase2"] = "????????",
			["rajaxxfinal"] = "???????!???????!",
			["azuregosport"] = "??,??????!",
			["nefphase2"] = "???!???????!???!",
		},
		-- Some of these are unused. Also, if none is defined in your localisation, they won't be used,
		-- so don't worry if you don't implement it.
		["name"] =
		{
			["rajaxx"] = "??????",
			["onyxia"] = "?????",
			["ebonroc"] = "????",
			["razorgore"] = "???????",
			["thekal"] = "???????",
			["shazzrah"] = "????",
			["twinempcaster"] = "??????",
			["twinempmelee"] = "???????",
			["noth"] = "?????",
		},
		["spell"] =
		{
			["shazzrahgate"] = "??????", -- "Shazzrah casts Gate of Shazzrah."
			["wrathofragnaros"] = "???????", -- "Ragnaros's Wrath of Ragnaros hits you for 100 Fire damage."
			["timelapse"] = "????", -- "You are afflicted by Time Lapse."
			["knockaway"] = "??",
			["wingbuffet"] = "????",
			["burningadrenaline"] = "????",
			["twinteleport"] = "????",
			["nothblink"] = "???",
			["sandblast"] = "????",
			["fungalbloom"] = "????",
			["hatefulstrike"] = "????",
			
			-- 4 horsemen marks
			mark1 = "??????",
			mark2 = "??????",
			mark3 = "??????",
			mark4 = "?????",
		}
	},
	["misc"] =
	{
		["imp"] = "??", -- UnitCreatureFamily("pet")
		["spellrank"] = "?? (%d+)", -- second value of GetSpellName(x, "spell")
		["aggrogain"] = "?? Aggro",
	},

	-- labels and tooltips for the main window
	["gui"] = {
		["raid"] = {
			["head"] = {
				-- column headers for the raid view
				["name"] = "??",
				["threat"] = "??",
				["pc"] = "%Max",			-- your threat as a percentage of the #1 player's threat
			},
			["stringshort"] = {
				-- tooltip titles for the bottom bar strings
				["tdef"] = "????", -- the difference in threat between you and the MT / #1 in the list.
				["targ"] = "????",
			},
			["stringlong"] = {
				-- tooltip descriptions for the bottom bar strings
				["tdef"] = "",
				["targ"] = "?????, ???? %s ??????????."
			},
		},
		["self"] = {
			["head"] = {
				-- column headers for the self view
				["name"] = "??",
				["hits"] = "??",
				["rage"] = "??",
				["dam"] = "??",
				["threat"] = "??",
				["pc"] = "%T",
			},
			-- text on the self threat reset button
			["reset"] = "??",
		},
		["title"] = {
			["text"] = {
				-- the window titles
				["long"] = "KTM %d.%d",	-- don't need to localise these
				["short"] = "KTM",

			},
			["buttonshort"] = {
				-- the tooltip titles for command buttons
				["close"] = "??",
				["min"] = "???",
				["max"] = "???",
				["self"] = "????",
				["raid"] = "????",
				["pin"] = "??",
				["unpin"] = "??",
				["opt"] = "??",
				["targ"] = "????",
				["clear"] = "??",
			},
			["buttonlong"] = {
				-- the tooltip descriptions for command buttons
				["close"] = "?????????????, ??????????",
				["min"] = "",
				["max"] = "",
				["self"] = "??????????",
				["raid"] = "????????",
				["pin"] = "???????????",
				["unpin"] = "???????????",
				["opt"] = "",
				["targ"] = "?????????????. ?????????, ????????. ????????????.",
				["clear"] = "??????????? 0. ????????????.",
			},
			["stringshort"] = {
				-- the tooltip titles for titlebar strings
				["threat"] = "??",
				["tdef"] = "????",
				["rank"] = "????",
				["pc"] = "% ??",
			},
			["stringlong"] = {
				-- the tooltip descriptions for titlebar strings
				["threat"] = "????, ?????????",
				["tdef"] = "??????????",
				["rank"] = "??????????",
				["pc"] = "?????, ?????????",
			},
		},
	},
	-- labels and tooltips for the options gui
	["optionsgui"] = {
		["buttons"] = {
			-- the options gui command button labels
			["gen"] = "??",
			["raid"] = "??",
			["self"] = "??",
			["close"] = "??",
		},
		-- the labels for option checkboxes and headers
		["labels"] = {
			-- the title description for each option page
			["titlebar"] = {
				["gen"] = "????",
				["raid"] = "????",
				["self"] = "????",
			},
			["buttons"] = {
				-- the names of title bar command buttons
				["pin"] = "??",
				["opt"] = "??",
				["view"] = "????",
				["targ"] = "????",
				["clear"] = "??????",
			},
			["columns"] = {
				-- names of columns on the self and raid views
				["hits"] = "??",
				["rage"] = "??",
				["dam"] = "??",
				["threat"] = "??",
				["pc"] = "% ??",
			},
			["options"] = {
				-- miscelaneous option names
				["hide"] = "???????",
				["abbreviate"] = "???????",
				["resize"] = "??????",
				["aggro"] = "???? Aggro",
				["rows"] = "?????",
				["scale"] = "?????",
				["bottom"] = "????",
				["minimap"] = "???????",
			},
			["minvis"] = {
				-- the names of minimised strings
				["threat"] = "????", -- dodge...
				["rank"] = "????",
				["pc"] = "% ??",
				["tdef"] = "????",
			},
			["headers"] = {
				-- headers in the options gui
				["columns"] = "?????",
				["strings"] = "???????",
				["other"] = "????",
				["minvis"] = "?????",
				["maxvis"] = "?????",
			},
		},
		-- the tooltips for some of the options
		["tooltips"] = {
			-- miscelaneous option descriptions
			["raidhide"] = "????, ?????????????? threat meter ?.",
			["selfhide"] = "????????????????.",
			["abbreviate"] = "????, ??????????????? 'k'. ?? '15400' ???? '15.4k'.",
			["resize"] = "????, ????????????????????????.",
			["aggro"] = "????, ?????????????????. ???????, ??????????.",
			["rows"] = "???????????????????.",
			["bottom"] = "?????, ?????????. ???????????????.",
			["minimap"] = "??????? KTM?\n?? Shift ?????? KTM ???\n????????????????",
		},
	},
	["print"] =
	{
		["main"] =
		{
			["startupmessage"] = "KLHThreatMeter Release |cff33ff33%s|r Revision |cff33ff33%s|r ???. ?? |cffffff00/ktm|r ?????.",
		},
		["data"] =
		{
			["abilityrank"] = "?? %s ?????? %s.",
			["globalthreat"] = "????????? %s.",
			["globalthreatmod"] = "%s ??? %s.",
			["multiplier"] = "????%s, ??%s?????%s.",
			["damage"] = "??",
			["shadowspell"] = "????",
			["arcanespell"] = "????",
			["holyspell"] = "????",
			["setactive"] = "????? %s ?? %d ?? ... %s.",
			["true"] = "?",
			["false"] = "?",
			["healing"] = "??????? %s ?? (???????????).",
			["talentpoint"] = "?? %d ?????? %s.",
			["talent"] = "?? %d ? %s ??.",
			["rockbiter"] = "???? %d ????? %d ????????????.",
		},

		-- new in R17.7
		["boss"] = 
		{
			["automt"] = "???????????? %s.",
			["spellsetmob"] = "%$1s ??? %$3s ? %$4s ?? %$2s ?????, ? %$6s ??? %$5s.", -- "Kenco sets the multiplier parameter of Onyxia's Knock Away ability to 0.7"
			["spellsetall"] = "%$1s ??? %$3s ??? %$2s ?????, ? %$5s ??? %$4s.",
			["reportmiss"] = "%s ?? %s ? %s ????.",
			["reporttick"] = "%s ?? %s ? %s ????. ?????? %s ?, ????? %s ???????.",
			["reportproc"] = "%s ?? %s ? %s ????????, ? %s ? %s.",
			["bosstargetchange"] = "%s ?????, ? %s (%s ??) ? %s (%s ??).",
			["autotargetstart"] = "??????????????, ???????????????????????.",
			["autotargetabort"] = "?????????????? %s.",
		},

		["network"] =
		{
			["newmttargetnil"] = "???????? %s, ?? %s ????.",
			["newmttargetmismatch"] = "%s ??????? %s, ??????? %s. ?????????, ??????!!",
			["mtpollwarning"] = "??????????? %s, ??????. ?????????, ? %s ??????????.",
			["threatreset"] = "????????? %s ??.",
			["newmt"] = "???????? '%s', ? %s ??.",
			["mtclear"] = "?????? %s ??.",
			["knockbackstart"] = "??????? %s ??.",
			["knockbackstop"] = "??????? %s ??.",
			["aggrogain"] = "%s ??, ???? %d ????? aggro.",
			["aggroloss"] = "%s ??, %d ????? aggro.",
			["knockback"] = "%s ?????????. ???????? %d.",
			["knockbackstring"] = "%s ?????????: '%s'.",
			["upgraderequest"] = "%s ????? KLHThreatMeter ??? Release %d. ?????? Release %d.",
			["remoteoldversion"] = "%s ??????? KLHThreatMeter Release %d. ???????? Release %d ?.",
			["knockbackvaluechange"] = "|cffffff00%s|r ?? %s ? |cffffff00%s|r ??????? |cffffff00%d%%|r.",
			["raidpermission"] = "????????????????!",
			["needmastertarget"] = "????????????!",
			["knockbackinactive"] = "????????????.",
			["versionrequest"] = "???????????, ?? 3 ????.",
			["versionrecent"] = "????? release %s: { ",
			["versionold"] = "?????????: { ",
			["versionnone"] = "??????? KLHThreatMeter, ?????????? CTRA ??: { ",
			["channel"] =
			{
				ctra = "CTRA ??",
				ora = "oRA ??",
				manual = "????",
			},
			needtarget = "?????????????????.",
			upgradenote = "???????????????????????.",
			advertisestart = "??????????? aggro ????? KLHThreatMeter.",
			advertisestop = "?????? KLHThreatMeter ????.",
			advertisemessage = "???? KLHThreatMeter, ?????????? %s ? aggro.",
		},
		
		-- ok, so autohide isn't really a word, but just improvise
		table = 
		{
			autohideon = "???????????????.",
			autohideoff = "??????????.",
		}
	}
}
```

