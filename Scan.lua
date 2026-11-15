local AHU = AHUpgradeCheck

AHU.Scan = AHU.Scan or {}
local Scan = AHU.Scan

local MAX_PAGES = 200
local MAX_RESCORE_ATTEMPTS = 3

local eventFrame = CreateFrame("Frame")
Scan.eventFrame = eventFrame

-- Baseline = the weaker of the two equipped items for Finger/Trinket (mirrors
-- GQ.Compare:GetEquippedItemLevel's own "compare against the weaker slot" rule),
-- otherwise just the one equipped item's score.
-- Scoring can fail for a slot/class/spec GearQuestForever's data isn't
-- complete for yet (e.g. a class whose module isn't fully built out) - treat
-- that as "no score" rather than letting it take down the whole scan.
local function SafeScore(itemLink, slotName)
	local ok, score = pcall(GearQuest.Compare.ScoreItemLinkStats, GearQuest.Compare, itemLink, slotName)
	if not ok then
		return 0
	end
	return score or 0
end

function Scan:ComputeBaselines()
	self.baselines = {}
	for _, slotName in ipairs(AHU.SLOTS) do
		local invSlots = GearQuest.Data:GetInventorySlots(slotName)
		local bestScore
		for _, invSlot in ipairs(invSlots) do
			local link = GetInventoryItemLink("player", invSlot)
			local score = link and SafeScore(link, slotName) or 0
			if not bestScore or score < bestScore then
				bestScore = score
			end
		end
		self.baselines[slotName] = bestScore or 0
	end
end

function Scan:Start()
	if self.active then
		return
	end
	if not GearQuest or not GearQuest.Compare or not GearQuest.Data then
		AHU.Print("GearQuestForever is required but not loaded.")
		return
	end
	if not AHU.auctionHouseOpen then
		AHU.Print("Open the Auction House first.")
		return
	end

	self.active = true
	self.page = 0
	self.results = {}
	self.pending = {}
	self.rescoreAttempts = {}
	self:ComputeBaselines()

	eventFrame:RegisterEvent("AUCTION_ITEMS_UPDATE")
	eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	eventFrame:SetScript("OnEvent", function(_, event, arg1)
		Scan:OnEvent(event, arg1)
	end)

	AHU.UI:SetStatus("Scanning page 1...")
	QueryAuctionItems("", nil, nil, nil, nil, nil, self.page, false, nil)
end

function Scan:OnEvent(event, arg1)
	local ok, err = pcall(function()
		if event == "AUCTION_ITEMS_UPDATE" then
			self:ProcessPage()
		elseif event == "GET_ITEM_INFO_RECEIVED" then
			self:RetryPending(arg1)
		end
	end)
	if not ok then
		AHU.Print("Error handling " .. event .. ": " .. tostring(err))
	end
end

function Scan:ProcessPage()
	if not self.active then
		return
	end

	local numItems, totalAuctions = GetNumAuctionItems("list")
	for i = 1, numItems do
		local _, _, _, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemId =
			GetAuctionItemInfo("list", i)
		if itemId and buyoutPrice and buyoutPrice > 0 then
			local itemLink = GetAuctionItemLink("list", i)
			if itemLink then
				self:ConsiderItem(itemId, itemLink, buyoutPrice)
			end
		end
	end

	local processed = (self.page + 1) * (numItems > 0 and numItems or 1)
	if numItems > 0 and processed < (totalAuctions or 0) and self.page < MAX_PAGES then
		self.page = self.page + 1
		AHU.UI:SetStatus(("Scanning page %d..."):format(self.page + 1))
		QueryAuctionItems("", nil, nil, nil, nil, nil, self.page, false, nil)
	else
		self:Finish()
	end
end

function Scan:ConsiderItem(itemId, itemLink, buyoutPrice)
	local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemId)
	if itemEquipLoc == nil then
		self.pending[itemId] = self.pending[itemId] or {}
		table.insert(self.pending[itemId], { itemLink = itemLink, buyoutPrice = buyoutPrice })
		return
	end
	self:ScoreCandidate(itemId, itemLink, buyoutPrice, itemEquipLoc)
end

function Scan:RetryPending(itemId)
	local queue = itemId and self.pending[itemId]
	if not queue then
		return
	end
	self.pending[itemId] = nil

	local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemId)
	if itemEquipLoc == nil then
		return
	end
	for _, entry in ipairs(queue) do
		self:ScoreCandidate(itemId, entry.itemLink, entry.buyoutPrice, itemEquipLoc)
	end
end

function Scan:ScoreCandidate(itemId, itemLink, buyoutPrice, itemEquipLoc)
	local slotName = AHU.EQUIP_LOC_TO_SLOT[itemEquipLoc]
	if not slotName then
		return -- not an equippable gear slot we track (e.g. tabard, shirt, consumable)
	end

	local baselineScore = self.baselines[slotName]
	local score = SafeScore(itemLink, slotName)

	if score <= 0 then
		local attempts = (self.rescoreAttempts[itemLink] or 0) + 1
		self.rescoreAttempts[itemLink] = attempts
		if attempts <= MAX_RESCORE_ATTEMPTS then
			C_Timer.After(1, function()
				Scan:ScoreCandidate(itemId, itemLink, buyoutPrice, itemEquipLoc)
			end)
		end
		return
	end

	local pct
	if baselineScore > 0 then
		pct = (score - baselineScore) / baselineScore * 100
	else
		pct = math.huge -- nothing equipped in this slot (or it scored 0) - treat any find as new gear
	end

	table.insert(self.results, {
		itemLink = itemLink,
		itemId = itemId,
		slotName = slotName,
		buyoutPrice = buyoutPrice,
		score = score,
		baselineScore = baselineScore,
		pct = pct,
	})
	AHU.UI:RefreshRows()
end

function Scan:Finish()
	self.active = false
	eventFrame:UnregisterEvent("AUCTION_ITEMS_UPDATE")
	AHU.UI:SetStatus(("Scan complete - %d candidate upgrade(s) found."):format(#self.results))
end

-- Re-runs a targeted browse search for this item so it shows up in the
-- Auction House's own list, where you confirm the actual bid/buyout yourself.
-- Deliberately doesn't touch specific Blizzard AH UI widgets (tab buttons,
-- the search box) by name - those globals aren't confirmed to exist under
-- the names classic/wrath clients use on this server, so only the data API
-- call (QueryAuctionItems) is used; the rest is left to you, by hand, on
-- whatever the Browse tab is actually called here.
function Scan:GoToAuction(entry)
	if not AHU.auctionHouseOpen then
		AHU.Print("Open the Auction House first.")
		return
	end

	local itemName = GetItemInfo(entry.itemId)
	local ok, err = pcall(QueryAuctionItems, itemName or "", nil, nil, nil, nil, nil, 0, false, nil)
	if not ok then
		AHU.Print("Couldn't search for it: " .. tostring(err))
		return
	end
	AHU.Print(('Searched the Auction House for "%s" - open your Browse tab to Bid/Buyout it.'):format(itemName or "item"))
end
