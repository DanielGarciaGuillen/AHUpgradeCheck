local AHU = AHUpgradeCheck

AHU.Scan = AHU.Scan or {}
local Scan = AHU.Scan

local MAX_RESCORE_ATTEMPTS = 3
local FINISH_AFTER_QUIET_SECONDS = 4

local eventFrame = CreateFrame("Frame")
Scan.eventFrame = eventFrame

-- Scoring can fail for a slot/class/spec GearQuestForever's data isn't
-- complete for yet (e.g. a class whose module isn't fully built out) - treat
-- that as "no score" rather than letting it take down the whole scan.
local function SafeScore(itemLink, slotName)
	local ok, score = pcall(GearQuest.Compare.ScoreItemLinkStats, GearQuest.Compare, itemLink, slotName)
	if not ok then
		AHU.Debug:Log("ScoreItemLinkStats failed for %s/%s: %s", tostring(itemLink), slotName, tostring(score))
		return 0
	end
	return score or 0
end

-- Baseline = the weaker of the two equipped items for Finger/Trinket (mirrors
-- GQ.Compare:GetEquippedItemLevel's own "compare against the weaker slot" rule),
-- otherwise just the one equipped item's score.
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

-- Which Auction House API this client actually exposes - checked at runtime
-- instead of assumed, since the frame name/API era isn't reliable across
-- WoW Forever's client fork (confirmed: it runs the modern C_AuctionHouse
-- API used by Cata Classic/Retail, identified via WOW_PROJECT_CAMELOT,
-- not the pre-Cata legacy QueryAuctionItems API).
function Scan:DetectMode()
	if C_AuctionHouse and C_AuctionHouse.SendBrowseQuery and C_AuctionHouse.GetBrowseResults then
		return "modern"
	elseif QueryAuctionItems and GetNumAuctionItems and GetAuctionItemInfo then
		return "legacy"
	end
	return nil
end

function Scan:Start()
	AHU.Debug:Log("Scan:Start called (active=%s, auctionHouseOpen=%s)", tostring(self.active), tostring(AHU.auctionHouseOpen))

	local ok, err = pcall(function()
		self:StartInner()
	end)
	if not ok then
		self.active = false
		AHU.Debug:Log("ERROR in Scan:Start: %s", tostring(err))
		AHU.Print("Error starting scan: " .. tostring(err))
	end
end

function Scan:StartInner()
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

	self.mode = self:DetectMode()
	AHU.Debug:Log("Detected AH API mode: %s", tostring(self.mode))
	if not self.mode then
		AHU.Print("Couldn't find a known Auction House API on this client. Run /ahup debug and send the log.")
		return
	end

	self.active = true
	self.page = 0
	self.results = {}
	self.pending = {}
	self.rescoreAttempts = {}
	self.seenItemKeys = {}
	self.counts = { considered = 0, pending = 0, scored = 0, skippedNoSlot = 0 }
	self:ComputeBaselines()

	local baselineParts = {}
	for slot, score in pairs(self.baselines) do
		table.insert(baselineParts, slot .. "=" .. tostring(score))
	end
	AHU.Debug:Log("Baselines: %s", table.concat(baselineParts, ", "))

	eventFrame:SetScript("OnEvent", function(_, event, ...)
		Scan:OnEvent(event, ...)
	end)

	if self.mode == "modern" then
		self:StartModern()
	else
		self:StartLegacy()
	end
end

function Scan:StartModern()
	eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
	eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

	AHU.UI:SetStatus("Scanning (browse query sent)...")
	local query = { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} }
	local ok, err = pcall(C_AuctionHouse.SendBrowseQuery, query)
	AHU.Debug:Log("C_AuctionHouse.SendBrowseQuery issued: ok=%s err=%s", tostring(ok), tostring(err))
	if not ok then
		self.active = false
		AHU.Print("Browse query failed: " .. tostring(err))
		return
	end
	self:ResetFinishTimer()
end

function Scan:StartLegacy()
	eventFrame:RegisterEvent("AUCTION_ITEMS_UPDATE")
	eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

	AHU.UI:SetStatus("Scanning page 1...")
	local ok, err = pcall(QueryAuctionItems, "", nil, nil, nil, nil, nil, self.page, false, nil)
	AHU.Debug:Log("QueryAuctionItems page 0 issued: ok=%s err=%s", tostring(ok), tostring(err))
	if not ok then
		self.active = false
		AHU.Print("Couldn't query the Auction House: " .. tostring(err))
	end
end

-- Modern mode's result events don't reliably signal "that's everything" on
-- every client/build, so finishing is driven by a quiet-period timer: every
-- new wave of results pushes it back, and it fires once nothing new has
-- arrived for a few seconds. HasFullBrowseResults() is also checked as an
-- earlier, more precise finish signal when it's available and accurate.
function Scan:ResetFinishTimer()
	if self.finishTimer then
		self.finishTimer:Cancel()
	end
	self.finishTimer = C_Timer.NewTimer(FINISH_AFTER_QUIET_SECONDS, function()
		if self.active then
			AHU.Debug:Log("No new browse results for %ds, finishing scan", FINISH_AFTER_QUIET_SECONDS)
			self:Finish()
		end
	end)
end

function Scan:OnEvent(event, arg1)
	local ok, err = pcall(function()
		if event == "AUCTION_ITEMS_UPDATE" then
			self:ProcessLegacyPage()
		elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
			self:ProcessModernResults(arg1)
		elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
			self:ProcessModernResults(C_AuctionHouse.GetBrowseResults())
		elseif event == "GET_ITEM_INFO_RECEIVED" then
			self:RetryPending(arg1)
		end
	end)
	if not ok then
		AHU.Debug:Log("ERROR in %s handler: %s", event, tostring(err))
		AHU.Print("Error handling " .. event .. ": " .. tostring(err))
	end
end

function Scan:ProcessModernResults(results)
	if not self.active or not results then
		return
	end
	AHU.Debug:Log("Processing %d modern browse result(s)", #results)

	for _, result in ipairs(results) do
		local itemKey = result.itemKey
		local buyout = result.minPrice
		if itemKey and itemKey.itemID and buyout and buyout > 0 then
			local keyId = itemKey.itemID .. ":" .. (itemKey.itemLevel or 0) .. ":" .. (itemKey.itemSuffix or 0)
			if not self.seenItemKeys[keyId] then
				self.seenItemKeys[keyId] = true
				-- No real auction itemLink is available at the browse-group level
				-- (only a per-group min price across possibly many auctions), so a
				-- plain "item:ID" stand-in is used for scoring/display. This misses
				-- bonus stats on randomly-suffixed items - a known beta limitation.
				local itemLink = ("item:%d"):format(itemKey.itemID)
				self:ConsiderItem(itemKey.itemID, itemLink, buyout, itemKey)
			end
		end
	end

	self:ResetFinishTimer()
	local full = C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults()
	AHU.Debug:Log("HasFullBrowseResults=%s", tostring(full))
	if full then
		self:Finish()
	end
end

function Scan:ProcessLegacyPage()
	if not self.active then
		return
	end

	local numItems, totalAuctions = GetNumAuctionItems("list")
	AHU.Debug:Log("AUCTION_ITEMS_UPDATE: page=%d numItems=%s totalAuctions=%s", self.page, tostring(numItems), tostring(totalAuctions))
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
	if numItems > 0 and processed < (totalAuctions or 0) then
		self.page = self.page + 1
		AHU.UI:SetStatus(("Scanning page %d..."):format(self.page + 1))
		QueryAuctionItems("", nil, nil, nil, nil, nil, self.page, false, nil)
	else
		self:Finish()
	end
end

function Scan:ConsiderItem(itemId, itemLink, buyoutPrice, itemKey)
	self.counts.considered = self.counts.considered + 1
	local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemId)
	if itemEquipLoc == nil then
		self.counts.pending = self.counts.pending + 1
		self.pending[itemId] = self.pending[itemId] or {}
		table.insert(self.pending[itemId], { itemLink = itemLink, buyoutPrice = buyoutPrice, itemKey = itemKey })
		return
	end
	self:ScoreCandidate(itemId, itemLink, buyoutPrice, itemEquipLoc, itemKey)
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
		self:ScoreCandidate(itemId, entry.itemLink, entry.buyoutPrice, itemEquipLoc, entry.itemKey)
	end
end

function Scan:ScoreCandidate(itemId, itemLink, buyoutPrice, itemEquipLoc, itemKey)
	local slotName = AHU.EQUIP_LOC_TO_SLOT[itemEquipLoc]
	if not slotName then
		self.counts.skippedNoSlot = self.counts.skippedNoSlot + 1
		return -- not an equippable gear slot we track (e.g. tabard, shirt, consumable)
	end

	local baselineScore = self.baselines[slotName]
	local score = SafeScore(itemLink, slotName)

	if score <= 0 then
		local attempts = (self.rescoreAttempts[itemLink] or 0) + 1
		self.rescoreAttempts[itemLink] = attempts
		if attempts <= MAX_RESCORE_ATTEMPTS then
			C_Timer.After(1, function()
				Scan:ScoreCandidate(itemId, itemLink, buyoutPrice, itemEquipLoc, itemKey)
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

	self.counts.scored = self.counts.scored + 1
	table.insert(self.results, {
		itemLink = itemLink,
		itemId = itemId,
		itemKey = itemKey,
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
	if self.finishTimer then
		self.finishTimer:Cancel()
		self.finishTimer = nil
	end
	eventFrame:UnregisterEvent("AUCTION_ITEMS_UPDATE")
	eventFrame:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
	eventFrame:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	AHU.Debug:Log(
		"Scan finished: considered=%d pending=%d scored=%d skippedNoSlot=%d results=%d",
		self.counts.considered, self.counts.pending, self.counts.scored, self.counts.skippedNoSlot, #self.results
	)
	AHU.UI:SetStatus(("Scan complete - %d candidate upgrade(s) found."):format(#self.results))
end

-- Re-runs a targeted search for this item so it shows up in the Auction
-- House's own results, where you confirm the actual bid/buyout yourself.
function Scan:GoToAuction(entry)
	local itemName = GetItemInfo(entry.itemId)
	AHU.Debug:Log("GoToAuction clicked: item=%s mode=%s auctionHouseOpen=%s", tostring(itemName or entry.itemLink), tostring(self.mode), tostring(AHU.auctionHouseOpen))

	if not AHU.auctionHouseOpen then
		AHU.Print("Open the Auction House first.")
		return
	end

	local ok, err
	if self.mode == "modern" and entry.itemKey then
		ok, err = pcall(C_AuctionHouse.SendSearchQuery, entry.itemKey, {}, false)
	else
		ok, err = pcall(QueryAuctionItems, itemName or "", nil, nil, nil, nil, nil, 0, false, nil)
	end

	if not ok then
		AHU.Debug:Log("GoToAuction search failed: %s", tostring(err))
		AHU.Print("Couldn't search for it: " .. tostring(err))
		return
	end
	AHU.Print(('Searched the Auction House for "%s" - check its results to Bid/Buyout it.'):format(itemName or "item"))
end
