------------------------------------------------------------------------
-- WHISPER DKP
------------------------------------------------------------------------
-- This file contains methods related to WhisperDKP functionality. 
------------------------------------------------------------------------

-- A reference to the original chat frame event hook (the one that we will replace)
-- Used to disguise our whisper messages
local WebDKP_ChatFrame_OnEvent_Original = nil; 

-- ================================
-- Places a hook on incoming whispers to the chat message box. 
-- We can use this to disguise our whisper messages
-- ================================
function WebDKP_Register_WhisperHook()
	--hooksecurefunc("ChatFrame_OnEvent",WebDKP_ChatFrame_OnEvent_Hook);
  if ( ChatFrame_OnEvent ~= WebDKP_ChatFrame_OnEvent_Hook ) then
        -- hook the chatframe onevent to allow us to hide the queue requrests if we want
        WebDKP_ChatFrame_OnEvent_Original = ChatFrame_OnEvent;
        ChatFrame_OnEvent = WebDKP_ChatFrame_OnEvent_Hook;
    end
end


-- ================================
-- Event handler for regular chat whisper messages
-- Responds to the players whisper with a whisper telling
-- them their current dkp. 
-- ================================
function WebDKP_WhisperDKP_Event()
	local tableid = WebDKP_GetTableid();
	local name = arg2;
	local trigger = arg1;
	if ( WebDKP_IsWebDKPWhisper(name, trigger) ) then
		-- its a valid whisper for us. Now to determine what type of whisper
		if(string.find(string.lower(trigger), "#dkp")==1 ) then		-- THEY WANT THEIR DKP
			-- look up this player in our dkp table and see if we can find their information
			
			if ( WebDKP_DkpTable[name] == nil ) then
				-- not in our system, send them message
				WebDKP_SendWhisper(name,"Du hast keine DKP Historie."); 
			else
				-- they are here, get them their dkp
				local dkp = WebDKP_DkpTable[name]["dkp_"..tableid];
				if( dkp == nil ) then
					WebDKP_DkpTable[name]["dkp_"..tableid] = 0;
				end 
				local tier = floor((dkp-1)/WebDKP_TierInterval);
				if(dkp == 0 ) then
					tier = 0;
				end
				WebDKP_SendWhisper(name,"Du hast "..dkp.." DKP.");
				--WebDKP_SendWhisper(name,"Tier - "..tier); 
			end	
		elseif(string.find(string.lower(trigger), "#listealle")==1 ) then -- THEY WANT _ALL_ THE DKP OF EVERYONE
			local filter = WebDKP_GetWhisperFiltersFromMessage(trigger);
			WebDKP_SendWhisper(name,"DKP - Name(Klasse)");
			WebDKP_SendWhisper(name,"========================");
			WebDKP_WhisperSortedList(name,false,filter);
		elseif(string.find(string.lower(trigger), "#liste")==1 ) then  -- THEY WANT THE DKP OF PEOPLE IN THE CURRENT GROUP
			local filter = WebDKP_GetWhisperFiltersFromMessage(trigger);
			WebDKP_SendWhisper(name,"DKP - Name (Klasse)");
			WebDKP_SendWhisper(name,"========================");
			WebDKP_WhisperSortedList(name,true,filter);
		elseif(trigger == "#hilfe" ) then		-- THEY WANT HELP / LIST OF COMMANDS
			WebDKP_SendWhisper(name,"Mögliche Befehle:"); 
			WebDKP_SendWhisper(name,"#dkp - Gibt deine aktuellen DKP aus.");
			WebDKP_SendWhisper(name,"#liste - Gibt die DKP der aktuellen Gruppe aus.");
			WebDKP_SendWhisper(name,"#listealle - Liste aller im DKP-System geführten Spieler.");
			WebDKP_SendWhisper(name,"#hilfe - Diese Hilfe"); 
			WebDKP_SendWhisper(name,"Du kannst die Listen filtern indem du die Klasse anhängst."); 
			WebDKP_SendWhisper(name,"Beispiel: '#liste Jäger' Gibt nur alle Jäger aus."); 
			WebDKP_SendWhisper(name,"Beispiel: '#liste Jäger Schurke' Gibt alle Jäger und Schurken aus."); 
		end
	end
end

-- ================================
-- Our special event hook that picks up on all whispers 
-- Before they are displayed on the screen or trigger the 
-- regular whisper. Here we can hide any whispers that our
-- ours. 
-- ================================
function WebDKP_ChatFrame_OnEvent_Hook()
    if ( arg1 and arg2 ) then
        -- whisper too me
        if ( event == "CHAT_MSG_WHISPER" ) then
            if ( WebDKP_IsWebDKPWhisper( arg2, arg1 ) ) then
                -- don't display whispercast whisper
                return
            end
        end
        -- whisper I am sending
        if ( event == "CHAT_MSG_WHISPER_INFORM" ) then
            if ( string.find(arg1,"^WebDKP: " ) ) then
                -- hide whispers that I am sending
                return
            end
        end
    end
    WebDKP_ChatFrame_OnEvent_Original(event, arg1, name);
end

-- ================================
-- Returns true if the passed whisper is a whisper directed
-- towards web dkp
-- ================================
function WebDKP_IsWebDKPWhisper(name, trigger)
	-- if it has webdkp in it, its an outgoing message. ignore it

	if ( string.find(string.lower(trigger), "WebDKP:" ) ) then
		return false;
	end
	if ( string.find(string.lower(trigger), "#dkp" )==1 or
		 string.find(string.lower(trigger), "#hilfe")==1 or
		 string.find(string.lower(trigger), "#liste")==1
		) then
        return true
    end
    
    return false
end




-- ================================
-- Helper method for the whisper features. 
-- Sends the player a list of dkp for people either in the current
-- group or in the guild
-- ================================
function WebDKP_WhisperSortedList(toPlayer, limitToGroup, classFilter)
	local tableid = WebDKP_GetTableid();	
	if(classFilter == nil) then
		classFilter = {};
	end
	-- increment through the dkp table and move data over
	local tableToWhisper={}; 
	for k, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" ) then
			local playerName = k; 
			local playerClass = v["class"];
			local playerDkp = v["dkp_"..tableid];
			if ( playerDkp ~= nil ) then
				local playerTier = floor((playerDkp-1)/WebDKP_TierInterval);
				if( playerDkp == 0 ) then
					playerTier = 0;
				end
				-- if it should be displayed (passes filter) add it to the table
				if (WebDKP_PassesWhisperFilter(playerName, playerClass, playerDkp, playerTier,limitToGroup,classFilter)) then
					tinsert(tableToWhisper,{playerName,playerClass,playerDkp,playerTier});
				end
			end
		end
	end
	-- we now have our table to whisper
	-- sort it
	table.sort(
		tableToWhisper,
		function(a1, a2)
			if ( a1 and a2 ) then
				if(a1[3] == a2[3]) then
					return a1[1] >= a2[1];
				else
					return a1[3] <= a2[3];
				end
			end
		end
	);
	
	-- display it
	for k, v in pairs(tableToWhisper) do
		if ( type(v) == "table" ) then
			if( v[1] ~= nil and v[2] ~= nil and v[3] ~= nil) then
				--WebDKP_SendWhisper(toPlayer,v[3].." - Tier "..v[4].." "..v[1].." ( "..v[2].." ) ");
				-- Klassenbezeichnungen werden ins deutsche übersetzt
				if v[2] == "Druid" then v[2] = "Druide" end
				if v[2] == "Hunter" then v[2] = "Jäger" end
				if v[2] == "Mage" then v[2] = "Magier" end
				if v[2] == "Rogue" then v[2] = "Schurke" end
				if v[2] == "Shaman" then v[2] = "Schamane" end
				if v[2] == "Paladin" then v[2] = "Paladin" end
				if v[2] == "Priest" then v[2] = "Priester" end
				if v[2] == "Warrior" then v[2] = "Krieger" end
				if v[2] == "Warlock" then v[2] = "Hexenmeister" end
				WebDKP_SendWhisper(toPlayer,v[3].." - "..v[1].." ("..v[2]..")");
			end
		end
	end
end

-- ================================
-- Checks to see if a given entry passes a set of whisper filters
-- ================================
function WebDKP_PassesWhisperFilter(name, class, dkp, tier, limitToGroup, filter)
	-- check the limit to group
	if( limitToGroup ) then
		if( not WebDKP_PlayerInGroup(name) ) then
			return false;
		end
	end
	-- now check the filters
	if ( filter["showall"] ) then
		return true;
	else
		-- return true if the class entry is not equal to nil, meaning it should be displayed
		if( class == nil) then
			return false;
		end
		return (not ( filter[string.lower(class)] == nil ) ); 
	end
	
	
end

-- ================================
-- Scans a whisper message to determine what filters are being used. 
-- Returns a filter object that can be passed to WebDKP_WhisperSortedList
-- ================================
function WebDKP_GetWhisperFiltersFromMessage(message)
	local filter = {}; 
	filter["druid"] = string.find(string.lower(message), "druide");
	filter["hunter"] = string.find(string.lower(message), "jäger");
	filter["mage"]= string.find(string.lower(message), "magier");
	filter["rogue"] = string.find(string.lower(message), "schurke");
	filter["shaman"] = string.find(string.lower(message), "schamane");
	filter["paladin"] = string.find(string.lower(message), "paladin");
	filter["priest"] = string.find(string.lower(message), "priester");
	filter["warrior"] = string.find(string.lower(message), "krieger");
	filter["warlock"] = string.find(string.lower(message), "hexenmeister");
	
	-- If no filters were passed, everything should be nill. In that case
	-- just display everyone
	if( filter["druid"] == nil and filter["hunter"] == nil and filter["mage"] == nil and
		filter["rogue"] == nil and filter["shaman"] == nil and filter["paladin"] == nil  and
		filter["priest"] == nil and filter["warrior"] == nil  and filter["warlock"] == nil  ) then
		filter["showall"] = true;
	else
		filter["showall"] = false;
	end
	return filter;
end