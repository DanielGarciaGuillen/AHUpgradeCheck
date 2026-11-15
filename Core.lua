local ADDON_NAME = ...

AHUpgradeCheck = AHUpgradeCheck or {}
local AHU = AHUpgradeCheck

-- GearQuestForever's own slot names (GQ.Data.SLOT_TO_INVENTORY / MERGED_SLOT_INVENTORY),
-- reused here so scores stay comparable between equipped gear and AH candidates.
AHU.SLOTS = {
	"Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands",
	"Waist", "Legs", "Feet", "Finger", "Trinket", "MainHand", "SecondaryHand", "Ranged",
}

-- itemEquipLoc (from GetItemInfo) -> GearQuestForever slot name.
AHU.EQUIP_LOC_TO_SLOT = {
	INVTYPE_HEAD = "Head",
	INVTYPE_NECK = "Neck",
	INVTYPE_SHOULDER = "Shoulder",
	INVTYPE_CLOAK = "Back",
	INVTYPE_CHEST = "Chest",
	INVTYPE_ROBE = "Chest",
	INVTYPE_WRIST = "Wrist",
	INVTYPE_HAND = "Hands",
	INVTYPE_WAIST = "Waist",
	INVTYPE_LEGS = "Legs",
	INVTYPE_FEET = "Feet",
	INVTYPE_FINGER = "Finger",
	INVTYPE_TRINKET = "Trinket",
	INVTYPE_WEAPON = "MainHand",
	INVTYPE_WEAPONMAINHAND = "MainHand",
	INVTYPE_2HWEAPON = "MainHand",
	INVTYPE_WEAPONOFFHAND = "SecondaryHand",
	INVTYPE_HOLDABLE = "SecondaryHand",
	INVTYPE_SHIELD = "SecondaryHand",
	INVTYPE_RANGED = "Ranged",
	INVTYPE_RANGEDRIGHT = "Ranged",
	INVTYPE_THROWN = "Ranged",
	INVTYPE_RELIC = "Ranged",
}

function AHU.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AHUpgradeCheck|r: " .. msg)
end

-- Tracked from the AUCTION_HOUSE_SHOW/CLOSED events themselves rather than
-- checking a guessed Blizzard frame global (e.g. AuctionFrame) - that global's
-- name/existence isn't reliable across client forks, but these events are.
AHU.auctionHouseOpen = false

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	local ok, err = pcall(function()
		if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
			local hasGearQuest = GearQuest and GearQuest.Compare and GearQuest.Data
			AHU.Debug:Log("ADDON_LOADED - GearQuest present: %s", tostring(hasGearQuest))
			if not hasGearQuest then
				AHU.Print("GearQuestForever was not found or didn't load first. Upgrade scoring needs it.")
			end
		elseif event == "AUCTION_HOUSE_SHOW" then
			AHU.Debug:Log("AUCTION_HOUSE_SHOW")
			AHU.Debug:DumpGlobals()
			AHU.auctionHouseOpen = true
			AHU.UI:OnAuctionHouseShown()
		elseif event == "AUCTION_HOUSE_CLOSED" then
			AHU.Debug:Log("AUCTION_HOUSE_CLOSED")
			AHU.auctionHouseOpen = false
			AHU.UI:OnAuctionHouseClosed()
		end
	end)
	if not ok then
		AHU.Debug:Log("ERROR in %s handler: %s", event, tostring(err))
		AHU.Print("Error handling " .. event .. ": " .. tostring(err))
	end
end)

SLASH_AHUPGRADECHECK1 = "/ahup"
SlashCmdList["AHUPGRADECHECK"] = function(msg)
	local cmd = strtrim((msg or ""):lower())
	if cmd == "debug" or cmd == "log" then
		AHU.Debug:ShowExport()
	elseif cmd == "cleardebug" or cmd == "clearlog" then
		AHU.Debug:Clear()
	else
		AHU.UI:Toggle()
	end
end
