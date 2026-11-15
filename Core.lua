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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	local ok, err = pcall(function()
		if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
			if not GearQuest or not GearQuest.Compare or not GearQuest.Data then
				AHU.Print("GearQuestForever was not found or didn't load first. Upgrade scoring needs it.")
			end
		elseif event == "AUCTION_HOUSE_SHOW" then
			AHU.UI:OnAuctionHouseShown()
		elseif event == "AUCTION_HOUSE_CLOSED" then
			AHU.UI:OnAuctionHouseClosed()
		end
	end)
	if not ok then
		AHU.Print("Error handling " .. event .. ": " .. tostring(err))
	end
end)

SLASH_AHUPGRADECHECK1 = "/ahup"
SlashCmdList["AHUPGRADECHECK"] = function()
	AHU.UI:Toggle()
end
