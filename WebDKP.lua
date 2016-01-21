------------------------------------------------------------------------
-- WEB DKP
------------------------------------------------------------------------
-- An addon to help manage the dkp for a guild. The addon provides a 
-- list of the dkp of all players as well as an interface to add / deduct dkp 
-- points. 
-- The addon generates a log file which can then be uploaded to a companion 
-- website at www.webdkp.com
--
--
-- HOW THIS ADDON IS ORGANIZED:
-- The addon is grouped into a series of files which hold code for certain
-- functions. 
-- 
-- WebDKP			Code to handle start / shutdown / registering events
--					and GUI event handlers. This is the main entry point
--					of the addon and directs events to the functionality
--					in the other files
--
-- GroupFunctions	Methods the handle scanning the current group, updating
--					the dkp table to be show based on filters, sorting, 
--					and updating the gui with the current table
--
-- Announcements	Code handling announcements as they are echoed to the screen
--
-- WhisperDKP		Implementation of the Whisper DKP feature. 
--
-- Utility			Utility and helper methods. For example, methods
--					to find out a users guild or print something to the 
--					screen. 

-- AutoFill			Methods related to autofilling in item names when drops
--					Occur		
------------------------------------------------------------------------

---------------------------------------------------
-- MEMBER VARIABLES
---------------------------------------------------
-- Sets the range of dkp that defines tiers.
-- Example, 50 would be:
-- 0-50 = teir 0
-- 51-100 = teir 1, etc
WebDKP_TierInterval = 50;   

-- Specify what filters are turned on and off. 1 = on, 0 = off
-- (Don't mess around with)
WebDKP_Filters = {
	["Druid"] = 1,
	["Hunter"] = 1,
	["Mage"] = 1,
	["Rogue"] = 1,
	["Shaman"] = 1,
	["Paladin"] = 1,
	["Priest"] = 1,
	["Warrior"] = 1,
	["Warlock"] = 1,
	["Group"] = 1
}

-- The dkp table itself (This is loaded from the saved variables file)
-- Its structure is:
-- ["playerName"] = {
--		["dkp"] = 100,
--		["class"] = "ClassName",
--		["Selected"] = true/ false if they are selected in the guid
-- }
WebDKP_DkpTable = {};

-- Holds the list of users tables on the site. This is used for those guilds
-- who have multiple dkp tables for 1 guild. 
-- When there are multiple table names in this list a drop down will appear 
-- in the addon so a user can select which table they want to award dkp to
-- Its structure is: 
-- ["tableName"] = { 
--		["id"] = 1 (this is the tableid of the table on the webdkp site)
-- }
WebDKP_Tables = {};
selectedTableid = 1;


-- The dkp table that will be shown. This is filled programmatically
-- based on running through the big dkp table applying the selected filters
WebDKP_DkpTableToShow = {}; 

-- Keeps track of the current players in the group. This is filled programmatically
-- and is filled with Raid data if the player is in a raid, or party data if the
-- player is in a party. It is used to apply the 'Group' filter
WebDKP_PlayersInGroup = {};

-- Keeps track of the sorting options. 
-- Curr = current columen being sorted
-- Way = asc or desc order. 0 = desc. 1 = asc
WebDKP_LogSort = {
	["curr"] = 3,
	["way"] = 1 -- Desc
};

-- Additional user options
WebDKP_Options = {
	["AutofillEnabled"] = 0,		-- auto fill data. 0 = disabled. 1 = enabled. 
	["AutofillThreshold"] = 2,		-- What level of items should be picked up by auto fill. -1 = Gray, 4 = Orange
	["AutoAwardEnabled"] = 0,		-- Whether dkp awards should be recorded automatically if all data can be auto filled (user is still prompted)
	["SelectedTableId"] = 1,		-- The last table that was being looked at
	--["MiniMapButtonAngle"] = 1,
	["MiniMapButtonPositionX"] = -67.84618063153107,
	["MiniMapButtonPositionY"] = -43.39881708444011,
}

-- User options that are syncronized with the website
WebDKP_WebOptions = {			
	["ZeroSumEnabled"] = 0,			-- Whether or not to use ZeroSum DKP settings
}

---------------------------------------------------
-- INITILIZATION
---------------------------------------------------
-- ================================
-- On load setup the slash event to will toggle the gui
-- and register for some events
-- ================================
function WebDKP_OnLoad()
	SlashCmdList["WEBDKP"] = WebDKP_ToggleGUI;
	SLASH_WEBDKP1 = "/webdkp";
		
	-- Register for party / raid changes so we know to update the list of players in group
	this:RegisterEvent("PARTY_MEMBERS_CHANGED"); 
	this:RegisterEvent("RAID_ROSTER_UPDATE"); 
	this:RegisterEvent("CHAT_MSG_WHISPER"); 
	this:RegisterEvent("ITEM_TEXT_READY");
	this:RegisterEvent("ADDON_LOADED");
	this:RegisterEvent("CHAT_MSG_LOOT");
	this:RegisterEvent("CHAT_MSG_PARTY");
	this:RegisterEvent("CHAT_MSG_RAID");
	this:RegisterEvent("CHAT_MSG_RAID_LEADER");
	this:RegisterEvent("CHAT_MSG_RAID_WARNING");
	this:RegisterEvent("ADDON_ACTION_FORBIDDEN");
	
	WebDKP_OnEnable();
	
end

-- ================================
-- Called when the addon is enabled. 
-- Takes care of basic startup tasks: hide certain forms, 
-- get the people currently in the group, register for events, 
-- etc. 
-- ================================
function WebDKP_OnEnable()
	WebDKP_Frame:Hide();
	getglobal("WebDKP_FiltersFrame"):Show();
	getglobal("WebDKP_AwardDKP_Frame"):Hide();
	getglobal("WebDKP_AwardItem_Frame"):Hide();
	getglobal("WebDKP_Options_Frame"):Hide();
	
	WebDKP_UpdatePlayersInGroup();
	WebDKP_UpdateTableToShow();
	
	-- place a hook on the chat frame so we can filter out our whispers
	WebDKP_Register_WhisperHook();
	
	-- place a hook on item shift+clicks so we can get item details
	--hooksecurefunc("SetItemRef",WebDKP_ItemChatClick);
end

-- ================================
-- Invoked when we recieve one of the requested events. 
-- Directs that event to the appropriate part of the addon
-- ================================
function WebDKP_OnEvent()
	if(event=="CHAT_MSG_WHISPER") then
		WebDKP_CHAT_MSG_WHISPER();
	elseif(event=="CHAT_MSG_PARTY") then
		WebDKP_CHAT_MSG_PARTY()
	elseif(event=="CHAT_MSG_RAID") then
		WebDKP_CHAT_MSG_RAID()
	elseif(event=="CHAT_MSG_RAID_LEADER") then
		WebDKP_CHAT_MSG_RAID_LEADER()
	elseif(event=="CHAT_MSG_RAID_WARNING") then
		WebDKP_CHAT_MSG_RAID_WARNING()
	elseif(event=="PARTY_MEMBERS_CHANGED") then
		WebDKP_PARTY_MEMBERS_CHANGED();
	elseif(event=="RAID_ROSTER_UPDATE") then
		WebDKP_RAID_ROSTER_UPDATE();
	elseif(event=="ADDON_LOADED") then
		WebDKP_ADDON_LOADED();
	elseif(event=="CHAT_MSG_LOOT") then
		WebDKP_Loot_Taken();
	elseif(event=="ADDON_ACTION_FORBIDDEN") then
		WebDKP_Print(arg1.."  "..arg2);
	end
end

-- ================================
-- Invoked when addon finishes loading data from the saved variables file. 
-- Should parse the players options and update the gui.
-- ================================
function WebDKP_ADDON_LOADED()
	if( WebDKP_DkpTable == nil) then
		WebDKP_DkpTable = {};
	end
	
	--load up the last loot table that was being viewed
	WebDKP_Frame.selectedTableid = WebDKP_Options["SelectedTableId"];
	--WebDKP_Options_Autofill_DropDown_Init();
	
	-- load the options from saved variables and update the settings on the 
	if ( WebDKP_Options["AutofillEnabled"] == 1 ) then
		WebDKP_Options_FrameToggleAutofill:SetChecked(1);
		WebDKP_Options_FrameAutofillDropDown:Show();
		WebDKP_Options_FrameToggleAutoAward:Show();
	else
		WebDKP_Options_FrameToggleAutofill:SetChecked(0);
		WebDKP_Options_FrameAutofillDropDown:Hide();
		WebDKP_Options_FrameToggleAutoAward:Hide();
	end 
	
	WebDKP_Options_FrameToggleAutoAward:SetChecked(WebDKP_Options["AutoAwardEnabled"]);
	WebDKP_Options_FrameToggleZeroSum:SetChecked(WebDKP_WebOptions["ZeroSumEnabled"]);
	
	
	WebDKP_UpdateTableToShow(); --update who is in the table
	WebDKP_UpdateTable();       --update the gui
	
	-- set the mini map position
	--WebDKP_MinimapButton_SetPositionAngle(WebDKP_Options["MiniMapButtonAngle"]);
	WebDKP_MinimapButton_SetPosition(WebDKP_Options["MiniMapButtonPositionX"], WebDKP_Options["MiniMapButtonPositionY"])
end





-- ================================
-- Called on shutdown. Does nothing
-- ================================
function WebDKP_OnDisable()
    
end


---------------------------------------------------
-- EVENT HANDLERS (Party changed / gui toggled / etc.)
---------------------------------------------------

-- ================================
-- Called by slash command. Toggles gui. 
-- ================================
function WebDKP_ToggleGUI()
	-- self:Print("Should toggle gui now...")
	-- WebDKP_Refresh()
	if ( WebDKP_Frame:IsShown() ) then
		WebDKP_Frame:Hide();
	else
		WebDKP_Frame:Show();	
		WebDKP_Tables_DropDown_OnLoad();
		WebDKP_Options_Autofill_DropDown_OnLoad();
		WebDKP_Options_Autofill_DropDown_Init();
	end
	
	-- WebDKP_Bid_ToggleUI();
	
end

-- ================================
-- Handles the master loot list being opened 
-- ================================
function WebDKP_OPEN_MASTER_LOOT_LIST()
    
end

-- ================================
-- Called when the party / raid configuration changes. 
-- Causes the list of current group memebers to be refreshed
-- so that filters will be ok
-- ================================
function WebDKP_PARTY_MEMBERS_CHANGED()
	-- self:Print("Party / Raid change");
	WebDKP_UpdatePlayersInGroup();
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
end
function WebDKP_RAID_ROSTER_UPDATE()
	-- self:Print("Party / Raid change");
	WebDKP_UpdatePlayersInGroup();
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
end

-- ================================
-- Handles an incoming whisper. Directs it to the modules
-- who are interested in it. 
-- ================================
function WebDKP_CHAT_MSG_WHISPER()
	WebDKP_WhisperDKP_Event();
	--WebDKP_Bid_Event();
end

-- ================================
-- Event handler for party chat messages.
-- ================================
function WebDKP_CHAT_MSG_PARTY()
	--WebDKP_Bid_Event();
end

-- ================================
-- Event handler for raid chat messages.
-- ================================
function WebDKP_CHAT_MSG_RAID()
	WebDKP_Bid_Event();
end

-- ================================
-- Event handler for raid leader chat messages.
-- ================================
function WebDKP_CHAT_MSG_RAID_LEADER()
	WebDKP_Bid_Event();
end

-- ================================
-- Event handler for raid warning chat messages.
-- ================================
function WebDKP_CHAT_MSG_RAID_WARNING()
	--WebDKP_Bid_Event();
end

---------------------------------------------------
-- GUI EVENT HANDLERS
-- (Handle events raised by the gui and direct
--  events to the other parts of the addon)
---------------------------------------------------
-- ================================
-- Called by the refresh button. Refreshes the people displayed 
-- in your party. 
-- ================================
function WebDKP_Refresh()
	WebDKP_UpdatePlayersInGroup();
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
end

-- ================================
-- Called when a player clicks on different tabs. 
-- Causes certain frames to be hidden and the appropriate
-- frame to be displayed
-- ================================
function WebDKP_Tab_OnClick()
	if ( this:GetID() == 1 ) then
		getglobal("WebDKP_FiltersFrame"):Show();
		getglobal("WebDKP_AwardDKP_Frame"):Hide();
		getglobal("WebDKP_AwardItem_Frame"):Hide();
		getglobal("WebDKP_Options_Frame"):Hide();
	elseif ( this:GetID() == 2 ) then
		getglobal("WebDKP_FiltersFrame"):Hide();
		getglobal("WebDKP_AwardDKP_Frame"):Show();
		getglobal("WebDKP_AwardItem_Frame"):Hide();
		getglobal("WebDKP_Options_Frame"):Hide();
	elseif (this:GetID() == 3 ) then
		getglobal("WebDKP_FiltersFrame"):Hide();
		getglobal("WebDKP_AwardDKP_Frame"):Hide();
		getglobal("WebDKP_AwardItem_Frame"):Show();
		getglobal("WebDKP_Options_Frame"):Hide();
	elseif (this:GetID() == 4 ) then
		getglobal("WebDKP_FiltersFrame"):Hide();
		getglobal("WebDKP_AwardDKP_Frame"):Hide();
		getglobal("WebDKP_AwardItem_Frame"):Hide();
		getglobal("WebDKP_Options_Frame"):Show();
	end 
	PlaySound("igCharacterInfoTab");
end

-- ================================
-- Called when a player clicks on a column header on the table
-- Changes the sorting options / asc&desc. 
-- Causes the table display to be refreshed afterwards
-- to player instantly sees changes
-- ================================
function WebDPK2_SortBy(id)
	if ( WebDKP_LogSort["curr"] == id ) then
		WebDKP_LogSort["way"] = abs(WebDKP_LogSort["way"]-1);
	else
		WebDKP_LogSort["curr"] = id;
		if( id == 1) then
			WebDKP_LogSort["way"] = 0;
		elseif ( id == 2 ) then
			WebDKP_LogSort["way"] = 0;
		elseif ( id == 3 ) then
			WebDKP_LogSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		else
			WebDKP_LogSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		end
		
	end
	-- update table so we can see sorting changes
	WebDKP_UpdateTable();
end

-- ================================
-- Called when the user clicks on a filter checkbox. 
-- Changes the filter setting and updates table
-- ================================
function WebDKP_ToggleFilter(filterName)
	WebDKP_Filters[filterName] = abs(WebDKP_Filters[filterName]-1);
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
end

-- ================================
-- Called when user clicks on 'check all'
-- Sets all filters to on and updates table display
-- ================================
function WebDKP_CheckAllFilters()
	WebDKP_SetFilterState("Druid",1);
	WebDKP_SetFilterState("Hunter",1);
	WebDKP_SetFilterState("Mage",1);
	WebDKP_SetFilterState("Rogue",1);
	WebDKP_SetFilterState("Shaman",1);
	WebDKP_SetFilterState("Paladin",1);
	WebDKP_SetFilterState("Priest",1);
	WebDKP_SetFilterState("Warrior",1);
	WebDKP_SetFilterState("Warlock",1);
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
end

-- ================================
-- Called when user clicks on 'uncheck all'
-- Sets all filters to off and updates table display
-- ================================
function WebDKP_UncheckAllFilters()
	WebDKP_SetFilterState("Druid",0);
	WebDKP_SetFilterState("Hunter",0);
	WebDKP_SetFilterState("Mage",0);
	WebDKP_SetFilterState("Rogue",0);
	WebDKP_SetFilterState("Shaman",0);
	WebDKP_SetFilterState("Paladin",0);
	WebDKP_SetFilterState("Priest",0);
	WebDKP_SetFilterState("Warrior",0);
	WebDKP_SetFilterState("Warlock",0);
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
end

-- ================================
-- Small helper method for filters - updates
-- checkbox state and updates filter setting in data structure
-- ================================
function WebDKP_SetFilterState(filter,newState)
	local checkBox = getglobal("WebDKP_FiltersFrameClass"..filter);
	checkBox:SetChecked(newState);
	WebDKP_Filters[filter] = newState;
end

-- ================================
-- Called when mouse goes over a dkp line entry. 
-- If that player is not selected causes that row
-- to become 'highlighted'
-- ================================
function WebDKP_HandleMouseOver()
	local playerName = getglobal(this:GetName().."Name"):GetText();
	if( not WebDKP_DkpTable[playerName]["Selected"] ) then
		getglobal(this:GetName() .. "Background"):SetVertexColor(0.2, 0.2, 0.7, 0.5);
	end
end

-- ================================
-- Called when a mouse leaes a dkp line entry. 
-- If that player is not selected, causes that row
-- to return to normal (none highlighted)
-- ================================
function WebDKP_HandleMouseLeave()
	local playerName = getglobal(this:GetName().."Name"):GetText();
	if( not WebDKP_DkpTable[playerName]["Selected"] ) then
		getglobal(this:GetName() .. "Background"):SetVertexColor(0, 0, 0, 0);
	end
end

-- ================================
-- Called when the user clicks on a player entry. Causes 
-- that entry to either become selected or normal
-- and updates the dkp table with the change
-- ================================
function WebDKP_SelectPlayerToggle()
	local playerName = getglobal(this:GetName().."Name"):GetText();
	if( WebDKP_DkpTable[playerName]["Selected"] ) then
		WebDKP_DkpTable[playerName]["Selected"] = false;
		getglobal(this:GetName() .. "Background"):SetVertexColor(0.2, 0.2, 0.7, 0.5);
	else
		WebDKP_DkpTable[playerName]["Selected"] = true;
		getglobal(this:GetName() .. "Background"):SetVertexColor(0.1, 0.1, 0.9, 0.8);
	end
end

-- ================================
-- Selects all players in the dkp table and updates 
-- table display
-- ================================
function WebDKP_SelectAll()
	local tableid = WebDKP_GetTableid();
	for k, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" ) then
			local playerName = k; 
			local playerClass = v["class"];
			local playerDkp = v["dkp"..tableid];
			if ( playerDkp == nil ) then 
				v["dkp"..tableid] = 0;
				playerDkp = 0;
			end
			local playerTier = floor((playerDkp-1)/WebDKP_TierInterval);
			if (WebDKP_ShouldDisplay(playerName, playerClass, playerDkp, playerTier)) then
				WebDKP_DkpTable[playerName]["Selected"] = true;
			else
				WebDKP_DkpTable[playerName]["Selected"] = false;
			end
		end
	end
	WebDKP_UpdateTable();
end

-- ================================
-- Deselect all players and update table display
-- ================================
function WebDKP_UnselectAll()
	for k, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" ) then
			local playerName = k; 
			WebDKP_DkpTable[playerName]["Selected"] = false;
		end
	end
	WebDKP_UpdateTable();
end

-- ================================
-- Invoked when the gui loads up the drop down list of 
-- available dkp tables. 
-- ================================
function WebDKP_Tables_DropDown_OnLoad()
	UIDropDownMenu_Initialize(WebDKP_Tables_DropDown, WebDKP_Tables_DropDown_Init);
	
	local numTables = WebDKP_GetTableSize(WebDKP_Tables)
	if ( WebDKP_Tables == nil or numTables==0 or numTables==1) then
		WebDKP_Tables_DropDown:Hide();
	else
		WebDKP_Tables_DropDown:Show();
	end
end
-- ================================
-- Invoked when the drop down list of available tables
-- needs to be redrawn. Populates it with data 
-- from the tables data structure and sets up an 
-- event handler
-- ================================
function WebDKP_Tables_DropDown_Init()
	if( WebDKP_Frame.selectedTableid == nil ) then
		WebDKP_Frame.selectedTableid = 1;
	end
	local info;
	local selected = "";
	if ( WebDKP_Tables ~= nil and next(WebDKP_Tables)~=nil ) then
		for key, entry in pairs(WebDKP_Tables) do
			if ( type(entry) == "table" ) then
				info = { };
				info.text = key;
				info.value = entry["id"]; 
				info.func = WebDKP_Tables_DropDown_OnClick;
				if ( entry["id"] == WebDKP_Frame.selectedTableid ) then
					info.checked = ( entry["id"] == WebDKP_Frame.selectedTableid );
					selected = info.text;
				end
				UIDropDownMenu_AddButton(info);
			end
		end
	end
	UIDropDownMenu_SetSelectedName(WebDKP_Tables_DropDown, selected );
	UIDropDownMenu_SetWidth(200, WebDKP_Tables_DropDown);
end

-- ================================
-- Called when the user switches between
-- a different dkp table.
-- ================================
function WebDKP_Tables_DropDown_OnClick()
	WebDKP_Frame.selectedTableid = this.value;
	WebDKP_Options["SelectedTableId"] = this.value; 
	WebDKP_Tables_DropDown_Init();
	WebDKP_UpdateTableToShow(); --update who is in the table
	WebDKP_UpdateTable();       --update the gui
end


-- ================================
-- Toggles zero sum support
-- ================================
function WebDKP_ToggleZeroSum()
	-- is enabled, disable it
	if ( WebDKP_WebOptions["ZeroSumEnabled"] == 1 ) then
		WebDKP_WebOptions["ZeroSumEnabled"] = 0;
	-- is disabled, enable it
	else
		WebDKP_WebOptions["ZeroSumEnabled"] = 1;
	end
end


-- ================================
-- MiniMap Scrolling code. 
-- Credit goes to Outfitter and WoWWiki for the know how 
-- of how to pull this off. 
-- ================================

-- ================================
-- Called when the user presses the mouse button down on the
-- mini map button. Remembers that position in case they
-- attempt to start dragging
-- ================================
function WebDKP_MinimapButton_MouseDown()
	-- Remember where the cursor was in case the user drags
	
	local	vCursorX, vCursorY = GetCursorPosition();
	
	vCursorX = vCursorX / this:GetEffectiveScale();
	vCursorY = vCursorY / this:GetEffectiveScale();
	
	WebDKP_MinimapButton.CursorStartX = vCursorX;
	WebDKP_MinimapButton.CursorStartY = vCursorY;
	
	local	vCenterX, vCenterY = WebDKP_MinimapButton:GetCenter();
	local	vMinimapCenterX, vMinimapCenterY = Minimap:GetCenter();
	
	WebDKP_MinimapButton.CenterStartX = vCenterX - vMinimapCenterX;
	WebDKP_MinimapButton.CenterStartY = vCenterY - vMinimapCenterY;
end

-- ================================
-- Called when the user starts to drag. Shows a frame that is registered
-- to recieve on update signals, we can then have its event handler
-- check to see the current mouse position and update the mini map button
-- correctly
-- ================================
function WebDKP_MinimapButton_DragStart()
	WebDKP_MinimapButton.IsDragging = true;
	WebDKP_UpdateFrame:Show();
end

-- ================================
-- Users stops dragging. Ends the timer
-- ================================
function WebDKP_MinimapButton_DragEnd()
	WebDKP_MinimapButton.IsDragging = false;
	WebDKP_UpdateFrame:Hide();
end

-- ================================
-- Updates the position of the mini map button. Should be called
-- via the on update method of the update frame
-- ================================
function WebDKP_MinimapButton_UpdateDragPosition()
	-- Remember where the cursor was in case the user drags
	local	vCursorX, vCursorY = GetCursorPosition();
	
	vCursorX = vCursorX / this:GetEffectiveScale();
	vCursorY = vCursorY / this:GetEffectiveScale();
	
	local	vCursorDeltaX = vCursorX - WebDKP_MinimapButton.CursorStartX;
	local	vCursorDeltaY = vCursorY - WebDKP_MinimapButton.CursorStartY;
	
	--
	
	local	vCenterX = WebDKP_MinimapButton.CenterStartX + vCursorDeltaX;
	local	vCenterY = WebDKP_MinimapButton.CenterStartY + vCursorDeltaY;
	
	-- Calculate the angle
	
	--local	vAngle = math.atan2(vCenterX, vCenterY);
	
	-- Set the new position
	
	--WebDKP_MinimapButton_SetPositionAngle(vAngle);
	WebDKP_MinimapButton_SetPosition(vCenterX, vCenterY)
end

-- ================================
-- Helper method. Helps restrict a given angle from occuring within a restricted angle
-- range. Returns where the angle should be pushed to - before or after the resitricted
-- range. Used to block the minimap button from appear behind the default ui buttons
-- ================================
function WebDKP_RestrictAngle(pAngle, pRestrictStart, pRestrictEnd)
	if ( pAngle == nil ) then
		return pRestrictStart;
	end
	if ( pRestrictStart == nil or pRestrictStart == nil) then
		return pAngle;
	end

	if pAngle <= pRestrictStart
	or pAngle >= pRestrictEnd then
		return pAngle;
	end
	
	local	vDistance = (pAngle - pRestrictStart) / (pRestrictEnd - pRestrictStart);
	
	if vDistance > 0.5 then
		return pRestrictEnd;
	else
		return pRestrictStart;
	end
end


-- ================================
-- Sets the free position of the mini map button.
-- ================================
function WebDKP_MinimapButton_SetPosition(positionX, positionY)
	WebDKP_MinimapButton:SetPoint("CENTER", "Minimap", "CENTER", positionX, positionY);
	WebDKP_Options["MiniMapButtonPositionX"] = positionX;
	WebDKP_Options["MiniMapButtonPositionY"] = positionY;
end

-- ================================
-- Sets the position of the mini map button based on the passed angle. 
-- Restricts the button from appear over any of the default ui buttons. 
-- ================================
--function WebDKP_MinimapButton_SetPositionAngle(pAngle)
	--local	vAngle = pAngle;
	
	-- Restrict the angle from going over the date/time icon or the zoom in/out icons
	
	--local	vRestrictedStartAngle = nil;
	--local	vRestrictedEndAngle = nil;
	
	--if GameTimeFrame:IsVisible() then
		--if MinimapZoomIn:IsVisible()
		--or MinimapZoomOut:IsVisible() then
			--vAngle = WebDKP_RestrictAngle(vAngle, 0.4302272732931596, 2.930420793963121);
		--else
			--vAngle = WebDKP_RestrictAngle(vAngle, 0.4302272732931596, 1.720531504573905);
		--end
		
	--elseif MinimapZoomIn:IsVisible()
	--or MinimapZoomOut:IsVisible() then
		--vAngle = WebDKP_RestrictAngle(vAngle, 1.720531504573905, 2.930420793963121);
	--end
	
	-- Restrict it from the tracking icon area
	
	--vAngle = WebDKP_RestrictAngle(vAngle, -1.290357134304173, -0.4918423429923585);
	
	--
	
	--local	vRadius = 80;
	
	--vCenterX = math.sin(vAngle) * vRadius;
	--vCenterY = math.cos(vAngle) * vRadius;
	
	--WebDKP_MinimapButton:SetPoint("CENTER", "Minimap", "CENTER", vCenterX - 1, vCenterY - 1);
	
	--WebDKP_Options["MiniMapButtonAngle"] = vAngle;
	--gOutfitter_Settings.Options.MinimapButtonAngle = vAngle;
--end

-- ================================
-- Event handler for the update frame. Updates the minimap button
-- if it is currently being dragged. 
-- ================================
function WebDKP_OnUpdate(elapsed)
	if WebDKP_MinimapButton.IsDragging then
		WebDKP_MinimapButton_UpdateDragPosition();
	end
end


-- ================================
-- Initializes the minimap drop down
-- ================================
function WebDKP_MinimapDropDown_OnLoad()
	UIDropDownMenu_SetAnchor(-2, -20, this, "TOPRIGHT", this:GetName(), "TOPLEFT");
	UIDropDownMenu_Initialize(this, WebDKP_MinimapDropDown_Initialize);
end

-- ================================
-- Adds buttons to the minimap drop down
-- ================================
function WebDKP_MinimapDropDown_Initialize()
	WebDKP_Add_MinimapDropDownItem("DKP Tabelle",WebDKP_ToggleGUI);
	WebDKP_Add_MinimapDropDownItem("Gebote",WebDKP_Bid_ToggleUI);
	--WebDKP_Add_MinimapDropDownItem("Help",WebDKP_ToggleGUI);
end

-- ================================
-- Helper method that adds individual entries into the minimap drop down
-- menu.
-- ================================
function WebDKP_Add_MinimapDropDownItem(text, eventHandler)
	local info = { };
	info.text = text;
	info.value = text; 
	info.owner = this;
	info.func = eventHandler; -- WebDKP_Tables_DropDown_OnClick;
	UIDropDownMenu_AddButton(info);
end


-- ================================
-- Helper method. Called whenever a player clicks on shift click
-- ================================
function WebDKP_ItemChatClick(link, text, button)
	
	-- do a search for 'player'. If it can be found... this is a player link, not an item link. It can be ignored
	local idx = strfind(text, "player");
	
	if( idx == nil ) then
		-- check to see if the bidding frame wants to do anything with the information
		WebDKP_Bid_ItemChatClick(link, text, button);
		
		-- put the item text into the award editbox as long as the table frame is visible
		if ( IsShiftKeyDown()) then
			local _,itemName,_ = WebDKP_GetItemInfo(link); 
			WebDKP_AwardItem_FrameItemName:SetText(itemName);
		end
	end
end
