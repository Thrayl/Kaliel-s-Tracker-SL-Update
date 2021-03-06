--- Kaliel's Tracker
--- Copyright (c) 2012-2020, Marouan Sabbagh <mar.sabbagh@gmail.com>
--- All Rights Reserved.
---
--- This file is part of addon Kaliel's Tracker.

local addonName, KT = ...
local M = KT:NewModule(addonName.."_Filters")
KT.Filters = M

local _DBG = function(...) if _DBG then _DBG("KT", ...) end end

-- Lua API
local ipairs = ipairs
local pairs = pairs
local strfind = string.find

-- WoW API
local _G = _G

local db, dbChar
local mediaPath = "Interface\\AddOns\\"..addonName.."\\Media\\"

local KTF = KT.frame
local OTF = ObjectiveTrackerFrame
local OTFHeader = OTF.HeaderMenu

local continents = KT.GetMapContinents()
local achievCategory = GetCategoryList()
local instanceQuestDifficulty = {
	[DifficultyUtil.ID.DungeonNormal] = { Enum.QuestTag.Dungeon },
	[DifficultyUtil.ID.DungeonHeroic] = { Enum.QuestTag.Dungeon, Enum.QuestTag.Heroic },
	[DifficultyUtil.ID.Raid10Normal] = { Enum.QuestTag.Raid, Enum.QuestTag.Raid10 },
	[DifficultyUtil.ID.Raid25Normal] = { Enum.QuestTag.Raid, Enum.QuestTag.Raid25 },
	[DifficultyUtil.ID.Raid10Heroic] = { Enum.QuestTag.Raid, Enum.QuestTag.Raid10 },
	[DifficultyUtil.ID.Raid25Heroic] = { Enum.QuestTag.Raid, Enum.QuestTag.Raid25 },
	[DifficultyUtil.ID.RaidLFR] = { Enum.QuestTag.Raid },
	[DifficultyUtil.ID.DungeonChallenge] = { Enum.QuestTag.Dungeon },
	[DifficultyUtil.ID.Raid40] = { Enum.QuestTag.Raid },
	[DifficultyUtil.ID.PrimaryRaidNormal] = { Enum.QuestTag.Raid },
	[DifficultyUtil.ID.PrimaryRaidHeroic] = { Enum.QuestTag.Raid },
	[DifficultyUtil.ID.PrimaryRaidMythic] = { Enum.QuestTag.Raid },
	[DifficultyUtil.ID.PrimaryRaidLFR] = { Enum.QuestTag.Raid },
}
local factionColor = { ["Horde"] = "ff0000", ["Alliance"] = "007fff" }

local eventFrame

--------------
-- Internal --
--------------

local function SetHooks()
	local bck_ObjectiveTracker_OnEvent = OTF:GetScript("OnEvent")
	OTF:SetScript("OnEvent", function(self, event, ...)
		if event == "QUEST_ACCEPTED" then
			local questID = ...
			if not C_QuestLog.IsQuestBounty(questID) and not C_QuestLog.IsQuestTask(questID) and db.filterAuto[1] then
				return
			end
		end
		bck_ObjectiveTracker_OnEvent(self, event, ...)
	end)

	-- Quests
	local bck_QuestObjectiveTracker_UntrackQuest = QuestObjectiveTracker_UntrackQuest
	QuestObjectiveTracker_UntrackQuest = function(dropDownButton, questID)
		if not db.filterAuto[1] then
			bck_QuestObjectiveTracker_UntrackQuest(dropDownButton, questID)
		end
	end

	local bck_QuestMapQuestOptions_TrackQuest = QuestMapQuestOptions_TrackQuest
	QuestMapQuestOptions_TrackQuest = function(questID)
		if not db.filterAuto[1] then
			bck_QuestMapQuestOptions_TrackQuest(questID)
		end
	end

	-- Achievements
	local bck_AchievementObjectiveTracker_UntrackAchievement = AchievementObjectiveTracker_UntrackAchievement
	AchievementObjectiveTracker_UntrackAchievement = function(dropDownButton, achievementID)
		if not db.filterAuto[2] then
			bck_AchievementObjectiveTracker_UntrackAchievement(dropDownButton, achievementID)
		end
	end

	-- Quest Log
	hooksecurefunc("QuestMapFrame_UpdateQuestDetailsButtons", function()
		if db.filterAuto[1] then
			QuestMapFrame.DetailsFrame.TrackButton:Disable()
			QuestLogPopupDetailFrame.TrackButton:Disable()
		else
			QuestMapFrame.DetailsFrame.TrackButton:Enable()
			QuestLogPopupDetailFrame.TrackButton:Enable()
		end
	end)

	-- POI
	local bck_QuestPOIButton_OnClick = QuestPOIButton_OnClick
	QuestPOIButton_OnClick = function(self)
		if not QuestUtils_IsQuestWatched(C_QuestLog.GetLogIndexForQuestID(self.questID)) and db.filterAuto[1] then
			SetSuperTrackedQuestID(self.questID)
			if self.pingWorldMap then
				WorldMapPing_StartPingQuest(self.questID)
			end
			return
		end
		bck_QuestPOIButton_OnClick(self)
	end
end

local function SetHooks_AchievementUI()
	local bck_AchievementButton_ToggleTracking = AchievementButton_ToggleTracking
	AchievementButton_ToggleTracking = function(id)
		if not db.filterAuto[2] then
			return bck_AchievementButton_ToggleTracking(id)
		end
	end

	hooksecurefunc("AchievementButton_DisplayAchievement", function(button, category, achievement, selectionID, renderOffScreen)
		if not button.completed then
			if db.filterAuto[2] then
				button.tracked:Disable()
			else
				button.tracked:Enable()
			end
		end
	end)
end

local function GetActiveWorldEvents()
	local eventsText = ""
	local date = C_DateAndTime.GetCurrentCalendarTime()
	C_Calendar.SetAbsMonth(date.month, date.year)
	local numEvents = C_Calendar.GetNumDayEvents(0, date.monthDay)
	for i=1, numEvents do
		local event = C_Calendar.GetDayEvent(0, date.monthDay, i)
		if event.calendarType == "HOLIDAY" then
			local gameHour, gameMinute = GetGameTime()
			if event.sequenceType == "START" then
				if gameHour >= event.startTime.hour and gameMinute >= event.startTime.minute then
					eventsText = eventsText..event.title.." "
				end
			elseif event.sequenceType == "END" then
				if gameHour <= event.endTime.hour and gameMinute <= event.endTime.minute then
					eventsText = eventsText..event.title.." "
				end
			else
				eventsText = eventsText..event.title.." "
			end
		end
	end
	return eventsText
end

local function IsInstanceQuest(questID)
	local _, _, difficulty, _ = GetInstanceInfo()
	local difficultyTags = instanceQuestDifficulty[difficulty]
	if difficultyTags then
		local tagID, tagName = C_QuestLog.GetQuestTagInfo(questID)
		for _, tag in ipairs(difficultyTags) do
			_DBG(difficulty.." ... "..tag, true)
			if tag == tagID then
				return true
			end
		end
	end
	return false
end

local function Filter_Quests(self, spec, idx)
	if not spec then return end
	local numEntries, _ = C_QuestLog.GetNumQuestLogEntries()

	KT.stopUpdate = true
	--KTF.Buttons.reanchor = (KTF.Buttons.num > 0)
	if C_QuestLog.GetNumQuestWatches() > 0 then
		for i=1, numEntries do
			local qinfo = C_QuestLog.GetInfo(i)
			if not qinfo.isHeader and not qinfo.isTask and (not qinfo.isBounty or C_QuestLog.IsComplete(qinfo.questID)) then
				C_QuestLog.RemoveQuestWatch(i)
			end
		end
	end

	if spec == "all" then
		for i=numEntries, 1, -1 do
			local qinfo = C_QuestLog.GetInfo(i)
			if not qinfo.isHidden and not qinfo.isHeader and not qinfo.isTask and (not qinfo.isBounty or C_QuestLog.IsComplete(qinfo.questID)) then
				C_QuestLog.AddQuestWatch(i, 1)
			end
		end
	elseif spec == "group" then
		for i=idx, 1, -1 do
			local qinfo = C_QuestLog.GetInfo(i)
			if not qinfo.isHidden and not qinfo.isHeader and not qinfo.isTask and (not qinfo.isBounty or C_QuestLog.IsComplete(qinfo.questID)) then
				C_QuestLog.AddQuestWatch(i, 1)
			else
				break
			end
		end
		MSA_CloseDropDownMenus()
	elseif spec == "zone" then
		local mapID = KT.GetCurrentMapAreaID()
		local zoneName = GetRealZoneText() or ""
		local isInZone = false
		if (C_Map.GetMapGroupID(mapID) and not KT.inInstance) or
				mapID == 1165 then	-- BfA - Dazar'alor
			local mapInfo = C_Map.GetMapInfo(mapID)
			OpenQuestLog(mapInfo.parentMapID)
		end
		for i=1, numEntries do
			local qinfo = C_QuestLog.GetInfo(i)
			if not qinfo.isHidden then
				if qinfo.isHeader then
					isInZone = (qinfo.title == zoneName)
				else
					if not qinfo.isTask and (not qinfo.isBounty or C_QuestLog.IsComplete(qinfo.questID)) and (qinfo.isOnMap or isInZone) then
						if KT.inInstance then
							if IsInstanceQuest(questID) then
								C_QuestLog.AddQuestWatch(i, 1)
							end
						else
							C_QuestLog.AddQuestWatch(i, 1)
						end
					end
				end
			end
		end
		HideUIPanel(WorldMapFrame)
	elseif spec == "daily" then
		for i=numEntries, 1, -1 do
			local qinfo = C_QuestLog.GetInfo(i)
			if not qinfo.isHidden and not qinfo.isHeader and not qinfo.isTask and (not qinfo.isBounty or C_QuestLog.IsComplete(qinfo.questID)) and qinfo.frequency >= 2 then
				C_QuestLog.AddQuestWatch(i, 1)
			end
		end
	elseif spec == "instance" then
		for i=numEntries, 1, -1 do
			local qinfo = C_QuestLog.GetInfo(i)
			if not qinfo.isHidden and not qinfo.isHeader and not qinfo.isTask and (not qinfo.isBounty or C_QuestLog.IsComplete(qinfo.questID)) then
				local tagID, _ = C_QuestLog.GetQuestTagInfo(qinfo.questID)
				if not tagID then
					tagID = {}
				end
				if tagID.tagID == Enum.QuestTag.Dungeon or
					tagID.tagID == Enum.QuestTag.Heroic or
					tagID.tagID == Enum.QuestTag.Raid or
					tagID.tagID == Enum.QuestTag.Raid10 or
					tagID.tagID == Enum.QuestTag.Raid25 then
					C_QuestLog.AddQuestWatch(i, 1)
				end
			end
		end
	elseif spec == "complete" then
		for i=numEntries, 1, -1 do
			local qinfo = C_QuestLog.GetInfo(i)
			if not qinfo.isHidden and not qinfo.isHeader and not qinfo.isTask and (not qinfo.isBounty or C_QuestLog.IsComplete(qinfo.questID)) and C_QuestLog.IsComplete(qinfo.questID) then
				C_QuestLog.AddQuestWatch(i, 1)
			end
		end
	end
	KT.stopUpdate = false

	C_QuestLog.SortQuestWatches()
	ObjectiveTracker_Update(OBJECTIVE_TRACKER_UPDATE_MODULE_QUEST)
	QuestSuperTracking_ChooseClosestQuest()
end

local function Filter_Achievements(self, spec)
	if not spec then return end
	local trackedAchievements = { GetTrackedAchievements() }

	KT.stopUpdate = true
	if GetNumTrackedAchievements() > 0 then
		for i=1, #trackedAchievements do
			RemoveTrackedAchievement(trackedAchievements[i])
		end
	end

	if spec == "zone" then
		local continentName = KT.GetCurrentMapContinent().name
		local zoneName = GetRealZoneText() or ""
		local categoryName = continentName
		if KT.GetCurrentMapContinent().mapID == 619 then
			categoryName = EXPANSION_NAME6	-- Legion
		elseif KT.GetCurrentMapContinent().mapID == 875 or
				KT.GetCurrentMapContinent().mapID == 876 or
				KT.GetCurrentMapContinent().mapID == 1355 then
			categoryName = EXPANSION_NAME7	-- Battle for Azeroth
		end
		local instance = KT.inInstance and 168 or nil
		_DBG(zoneName.." ... "..KT.GetCurrentMapAreaID(), true)

		-- Dungeons & Raids
		local instanceDifficulty
		if instance and db.filterAchievCat[instance] then
			local _, type, difficulty, difficultyName = GetInstanceInfo()
			local _, _, sufix = strfind(difficultyName, "^.* %((.*)%)$")
			instanceDifficulty = difficultyName
			if sufix then
				instanceDifficulty = sufix
			end
			_DBG(type.." ... "..difficulty.." ... "..difficultyName, true)
		end

		-- World Events
		local events = ""
		if db.filterAchievCat[155] then
			events = GetActiveWorldEvents()
		end

		for i=1, #achievCategory do
			local category = achievCategory[i]
			local name, parentID, _ = GetCategoryInfo(category)

			if db.filterAchievCat[parentID] then
				if (parentID == 92) or										-- Character
						(parentID == 96 and name == categoryName) or		-- Quests
						(parentID == 97 and name == categoryName) or		-- Exploration
						(parentID == 95 and strfind(zoneName, name)) or		-- Player vs. Player
						(category == instance or parentID == instance) or	-- Dungeons & Raids
						(parentID == 169) or								-- Professions
						(parentID == 201) or								-- Reputation
						(parentID == 155 and strfind(events, name)) or		-- World Events
						(category == 15117 or parentID == 15117) or			-- Pet Battles
						(category == 15246 or parentID == 15246) or			-- Collections
						(parentID == 15301) then							-- Expansion Features
					local aNumItems, _ = GetCategoryNumAchievements(category)
					for i=1, aNumItems do
						local track = false
						local aId, aName, _, aCompleted, _, _, _, aDescription = GetAchievementInfo(category, i)
						if aId and not aCompleted then
							--_DBG(aId.." ... "..aName, true)
							if parentID == 95 or
									(not instance and (category == 15117 or parentID == 15117) and strfind(aName.." - "..aDescription, continentName)) then
								track = true
							elseif strfind(aName.." - "..aDescription, zoneName) then
								if category == instance or parentID == instance then
									if instanceDifficulty == "Normal" then
										if not strfind(aName.." - "..aDescription, "[Heroic|Mythic]") then
											track = true
										end
									else
										if strfind(aName.." - "..aDescription, instanceDifficulty) or
												(strfind(aName.." - "..aDescription, "difficulty or higher")) then	-- TODO: other languages
											track = true
										end
									end
								else
									track = true
								end
							elseif strfind(aDescription, " capita") then	-- capital city (TODO: de, ru strings)
								local cNumItems = GetAchievementNumCriteria(aId)
								for i=1, cNumItems do
									local cDescription, _, cCompleted = GetAchievementCriteriaInfo(aId, i)
									if not cCompleted and strfind(cDescription, zoneName) then
										track = true
										break
									end
								end
							end
							if track then
								AddTrackedAchievement(aId)
							end
						end
						if GetNumTrackedAchievements() == MAX_TRACKED_ACHIEVEMENTS then
							break
						end
					end
				end
			end
			if GetNumTrackedAchievements() == MAX_TRACKED_ACHIEVEMENTS then
				break
			end
			if parentID == -1 then
				--_DBG(category.." ... "..name, true)
			end
		end
	elseif spec == "wevent" then
		local events = GetActiveWorldEvents()
		local eventName = ""

		for i=1, #achievCategory do
			local category = achievCategory[i]
			local name, parentID, _ = GetCategoryInfo(category)

			if parentID == 155 and strfind(events, name) then	-- World Events
				eventName = eventName..(eventName ~= "" and ", " or "")..name
				local aNumItems, _ = GetCategoryNumAchievements(category)
				for i=1, aNumItems do
					local aId, aName, _, aCompleted, _, _, _, aDescription = GetAchievementInfo(category, i)
					if aId and not aCompleted then
						AddTrackedAchievement(aId)
					end
					if GetNumTrackedAchievements() == MAX_TRACKED_ACHIEVEMENTS then
						break
					end
				end
			end
			if GetNumTrackedAchievements() == MAX_TRACKED_ACHIEVEMENTS then
				break
			end
			if parentID == -1 then
				--_DBG(category.." ... "..name, true)
			end
		end

		if db.messageAchievement then
			local numTracked = GetNumTrackedAchievements()
			if numTracked == 0 then
				KT:SetMessage("There is currently no World Event.", 1, 1, 0)
			elseif numTracked > 0 then
				KT:SetMessage("World Event - "..eventName, 1, 1, 0)
			end
		end
	end
	KT.stopUpdate = false

	if AchievementFrame then
		AchievementFrameAchievements_ForceUpdate()
	end
	ObjectiveTracker_Update(OBJECTIVE_TRACKER_UPDATE_MODULE_ACHIEVEMENT)
end

local DropDown_Initialize	-- function

local function DropDown_Toggle(level, button)
	local dropDown = KT.DropDown
	if dropDown.activeFrame ~= KTF.FilterButton then
		MSA_CloseDropDownMenus()
	end
	dropDown.activeFrame = KTF.FilterButton
	dropDown.initialize = DropDown_Initialize
	MSA_ToggleDropDownMenu(level or 1, button and MSA_DROPDOWNMENU_MENU_VALUE or nil, dropDown, KTF.FilterButton, -15, -1, nil, button or nil, MSA_DROPDOWNMENU_SHOW_TIME)
	if button then
		_G["MSA_DropDownList"..MSA_DROPDOWNMENU_MENU_LEVEL].showTimer = nil
	end
end

local function Filter_AutoTrack(self, id, spec)
	db.filterAuto[id] = (db.filterAuto[id] ~= spec) and spec or nil
	if db.filterAuto[id] then
		if id == 1 then
			Filter_Quests(self, spec)
		elseif id == 2 then
			Filter_Achievements(self, spec)
		end
		KTF.FilterButton:GetNormalTexture():SetVertexColor(0, 1, 0)
	else
		if id == 1 then
			QuestMapFrame_UpdateQuestDetailsButtons()
		elseif id == 2 and AchievementFrame then
			AchievementFrameAchievements_ForceUpdate()
		end
		if not (db.filterAuto[1] or db.filterAuto[2]) then
			KTF.FilterButton:GetNormalTexture():SetVertexColor(KT.hdrBtnColor.r, KT.hdrBtnColor.g, KT.hdrBtnColor.b)
		end
	end
	DropDown_Toggle()
end

local function Filter_AchievCat_CheckAll(self, state)
	for id, _ in pairs(db.filterAchievCat) do
		db.filterAchievCat[id] = state
	end
	if db.filterAuto[2] then
		Filter_Achievements(_, db.filterAuto[2])
		MSA_CloseDropDownMenus()
	else
		local listFrame = _G["MSA_DropDownList"..MSA_DROPDOWNMENU_MENU_LEVEL]
		DropDown_Toggle(MSA_DROPDOWNMENU_MENU_LEVEL, _G["MSA_DropDownList"..listFrame.parentLevel.."Button"..listFrame.parentID])
	end
end

local function GetInlineFactionIcon()
	local coords = QUEST_TAG_TCOORDS[strupper(KT.playerFaction)]
	return CreateTextureMarkup(QUEST_ICONS_FILE, QUEST_ICONS_FILE_WIDTH, QUEST_ICONS_FILE_HEIGHT, 22, 22
		, coords[1]
		, coords[2] - 0.02 -- Offset to stop bleeding from next image
		, coords[3]
		, coords[4])
end

function DropDown_Initialize(self, level)
	local numEntries, numQuests = C_QuestLog.GetNumQuestLogEntries()
	local info = MSA_DropDownMenu_CreateInfo()
	info.isNotRadio = true

	if level == 1 then
		info.notCheckable = true

		-- Quests
		info.text = TRACKER_HEADER_QUESTS
		info.isTitle = true
		MSA_DropDownMenu_AddButton(info)

		info.isTitle = false
		info.disabled = (db.filterAuto[1])
		info.func = Filter_Quests

		info.text = "All  ("..numQuests..")"
		info.hasArrow = not (db.filterAuto[1])
		info.value = 1
		info.arg1 = "all"
		MSA_DropDownMenu_AddButton(info)

		info.hasArrow = false

		info.text = "Zone"
		info.arg1 = "zone"
		MSA_DropDownMenu_AddButton(info)

		info.text = "Daily"
		info.arg1 = "daily"
		MSA_DropDownMenu_AddButton(info)

		info.text = "Instance"
		info.arg1 = "instance"
		MSA_DropDownMenu_AddButton(info)

		info.text = "Complete"
		info.arg1 = "complete"
		MSA_DropDownMenu_AddButton(info)

		info.text = "Untrack All"
		info.disabled = (db.filterAuto[1] or C_QuestLog.GetNumQuestWatches() == 0)
		info.arg1 = ""
		MSA_DropDownMenu_AddButton(info)

		info.text = "|cff00ff00Auto|r Zone"
		info.notCheckable = false
		info.disabled = false
		info.arg1 = 1
		info.arg2 = "zone"
		info.checked = (db.filterAuto[info.arg1] == info.arg2)
		info.func = Filter_AutoTrack
		MSA_DropDownMenu_AddButton(info)

		MSA_DropDownMenu_AddSeparator(info)

		-- Achievements
		info.text = TRACKER_HEADER_ACHIEVEMENTS
		info.isTitle = true
		MSA_DropDownMenu_AddButton(info)

		info.isTitle = false
		info.disabled = false

		info.text = "Categories"
		info.keepShownOnClick = true
		info.hasArrow = true
		info.value = 2
		info.func = nil
		MSA_DropDownMenu_AddButton(info)

		info.keepShownOnClick = false
		info.hasArrow = false
		info.disabled = (db.filterAuto[2])
		info.func = Filter_Achievements

		info.text = "Zone"
		info.arg1 = "zone"
		MSA_DropDownMenu_AddButton(info)

		info.text = "World Event"
		info.arg1 = "wevent"
		MSA_DropDownMenu_AddButton(info)

		info.text = "Untrack All"
		info.disabled = (db.filterAuto[2] or GetNumTrackedAchievements() == 0)
		info.arg1 = ""
		MSA_DropDownMenu_AddButton(info)

		info.text = "|cff00ff00Auto|r Zone"
		info.notCheckable = false
		info.disabled = false
		info.arg1 = 2
		info.arg2 = "zone"
		info.checked = (db.filterAuto[info.arg1] == info.arg2)
		info.func = Filter_AutoTrack
		MSA_DropDownMenu_AddButton(info)

		-- Addon - PetTracker
		if KT.AddonPetTracker.isLoaded then
			MSA_DropDownMenu_AddSeparator(info)

			info.text = PETS
			info.isTitle = true
			MSA_DropDownMenu_AddButton(info)

			info.isTitle = false
			info.disabled = false
			info.notCheckable = false

			info.text = KT.AddonPetTracker.Texts.TrackPets
			info.checked = (PetTracker.sets.trackPets)
			info.func = function()
				PetTracker.Tracker:Toggle()
				if dbChar.collapsed and PetTracker.sets.trackPets then
					ObjectiveTracker_MinimizeButton_OnClick()
				end
			end
			MSA_DropDownMenu_AddButton(info)

			info.text = KT.AddonPetTracker.Texts.CapturedPets
			info.checked = (PetTracker.sets.capturedPets)
			info.func = function()
				PetTracker.Tracker:ToggleCaptured()
			end
			MSA_DropDownMenu_AddButton(info)
		end
	elseif level == 2 then
		info.notCheckable = true

		if MSA_DROPDOWNMENU_MENU_VALUE == 1 then
			info.arg1 = "group"
			info.func = Filter_Quests
			if numEntries > 0 then
			for i=1, numEntries do
				local headerTitle, headerOnMap, headerShown
				local warCampaignID = C_CampaignInfo.GetAvailableCampaigns()
				local warCampaignID = warCampaignID[1]
				if warCampaignID then
					local warCampaignInfo = C_CampaignInfo.GetCampaignInfo(warCampaignID)
					headerTitle = "|cff"..factionColor[KT.playerFaction]..warCampaignInfo.name..GetInlineFactionIcon()
				end
				end
				for i=1, numEntries do
					local qinfo = C_QuestLog.GetInfo(i)
					if qinfo.isHeader then
						if headerShown and i > 1 then
							info.arg2 = i - 1
							MSA_DropDownMenu_AddButton(info, level)
						end
						headerTitle = qinfo.title
						headerOnMap = qinfo.isOnMap
						headerShown = false
					elseif not qinfo.isTask and (not qinfo.isBounty or C_QuestLog.IsComplete(qinfo.questID)) and not qinfo.isHidden then
						if not headerShown then
							info.text = (headerOnMap and "|cff00ff00" or "")..headerTitle
							headerShown = true
						end
					end
				end
				if headerShown then
					info.arg2 = numEntries
					MSA_DropDownMenu_AddButton(info, level)
				end
			end
		elseif MSA_DROPDOWNMENU_MENU_VALUE == 2 then
			info.func = Filter_AchievCat_CheckAll

			info.text = "Check All"
			info.arg1 = true
			MSA_DropDownMenu_AddButton(info, level)

			info.text = "Uncheck All"
			info.arg1 = false
			MSA_DropDownMenu_AddButton(info, level)

			info.keepShownOnClick = true
			info.notCheckable = false

			for i=1, #achievCategory do
				local id = achievCategory[i]
				local name, parentID, _ = GetCategoryInfo(id)
				if parentID == -1 and id ~= 15234 and id ~= 81 then		-- Skip "Legacy" and "Feats of Strength"
					info.text = name
					info.checked = (db.filterAchievCat[id])
					info.arg1 = id
					info.func = function(_, arg)
						db.filterAchievCat[arg] = not db.filterAchievCat[arg]
						if db.filterAuto[2] then
							Filter_Achievements(_, db.filterAuto[2])
							MSA_CloseDropDownMenus()
						end
					end
					MSA_DropDownMenu_AddButton(info, level)
				end
			end
		end
	end
end

local function SetFrames()
	-- Event frame
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
			_DBG("Event - "..event.." - "..(arg1 or ""), true)
			if event == "ADDON_LOADED" and arg1 == "Blizzard_AchievementUI" then
				SetHooks_AchievementUI()
				self:UnregisterEvent(event)
			elseif event == "QUEST_ACCEPTED" then
				local questID = arg1
				if not C_QuestLog.IsQuestTask(questID) and (not C_QuestLog.IsQuestBounty(questID) or C_QuestLog.C_QuestLog.IsComplete(questID)) and db.filterAuto[1] then
					self:RegisterEvent("QUEST_POI_UPDATE")
				end
			elseif event == "QUEST_POI_UPDATE" then
				KT.questStateStopUpdate = true
				Filter_Quests(_, "zone")
				KT.questStateStopUpdate = false
				self:UnregisterEvent(event)
			elseif event == "ZONE_CHANGED_NEW_AREA" then
				if db.filterAuto[1] == "zone" then
					Filter_Quests(_, "zone")
				end
				if db.filterAuto[2] == "zone" then
					Filter_Achievements(_, "zone")
				end
			end
		end)
	end
	eventFrame:RegisterEvent("ADDON_LOADED")
	eventFrame:RegisterEvent("QUEST_ACCEPTED")
	eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

	-- Filter button
	local button = CreateFrame("Button", addonName.."FilterButton", KTF)
	button:SetSize(16, 16)
	button:SetPoint("TOPRIGHT", KTF.MinimizeButton, "TOPLEFT", -4, 0)
	button:SetFrameLevel(KTF:GetFrameLevel() + 10)
	button:SetNormalTexture(mediaPath.."UI-KT-HeaderButtons")
	button:GetNormalTexture():SetTexCoord(0.5, 1, 0.5, 0.75)

	button:RegisterForClicks("AnyDown")
	button:SetScript("OnClick", function(self, btn)
		DropDown_Toggle()
	end)
	button:SetScript("OnEnter", function(self)
		self:GetNormalTexture():SetVertexColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Filter", 1, 1, 1)
		GameTooltip:AddLine(db.filterAuto[1] and "- "..db.filterAuto[1].." Quests", 0, 1, 0)
		GameTooltip:AddLine(db.filterAuto[2] and "- "..db.filterAuto[2].." Achievements", 0, 1, 0)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		if db.filterAuto[1] or db.filterAuto[2] then
			self:GetNormalTexture():SetVertexColor(0, 1, 0)
		else
			self:GetNormalTexture():SetVertexColor(KT.hdrBtnColor.r, KT.hdrBtnColor.g, KT.hdrBtnColor.b)
		end
		GameTooltip:Hide()
	end)
	KTF.FilterButton = button

	OTFHeader.Title:SetWidth(OTFHeader.Title:GetWidth() - 20)

	-- Move other buttons
	if db.hdrOtherButtons then
		local point, _, relativePoint, xOfs, yOfs = KTF.AchievementsButton:GetPoint()
		KTF.AchievementsButton:SetPoint(point, KTF.FilterButton, relativePoint, xOfs, yOfs)
	end
end

--------------
-- External --
--------------

function M:OnInitialize()
	_DBG("|cffffff00Init|r - "..self:GetName(), true)
	db = KT.db.profile
	dbChar = KT.db.char

    local defaults = KT:MergeTables({
        profile = {
            filterAuto = {
				nil,	-- [1] Quests
				nil,	-- [2] Achievements
			},
			filterAchievCat = {
				[92] = true,	-- Character
				[96] = true,	-- Quests
				[97] = true,	-- Exploration
				[95] = true,	-- Player vs. Player
				[168] = true,	-- Dungeons & Raids
				[169] = true,	-- Professions
				[201] = true,	-- Reputation
				[155] = true,	-- World Events
				[15117] = true,	-- Pet Battles
				[15246] = true,	-- Collections
				[15301] = true,	-- Expansion Features
			},
			filterWQTimeLeft = nil,
        }
    }, KT.db.defaults)
	KT.db:RegisterDefaults(defaults)
end

function M:OnEnable()
	_DBG("|cff00ff00Enable|r - "..self:GetName(), true)
	SetHooks()
	SetFrames()
end
