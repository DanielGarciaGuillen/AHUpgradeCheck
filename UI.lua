local AHU = AHUpgradeCheck

AHU.UI = AHU.UI or {}
local UI = AHU.UI

local ROW_HEIGHT = 20
local NUM_ROWS = 18

local frame

local function FormatPct(pct)
	if pct == math.huge then
		return "|cff00ff00NEW|r"
	end
	local color = pct > 0 and "|cff00ff00" or (pct < 0 and "|cffff4444" or "|cffffffff")
	return ("%s%+.1f%%|r"):format(color, pct)
end

local function FormatMoney(copper)
	if not copper then
		return ""
	end
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	return tostring(copper)
end

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(448, ROW_HEIGHT)

	row.pct = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.pct:SetPoint("LEFT", 0, 0)
	row.pct:SetWidth(55)
	row.pct:SetJustifyH("LEFT")

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.name:SetPoint("LEFT", row.pct, "RIGHT", 4, 0)
	row.name:SetWidth(200)
	row.name:SetJustifyH("LEFT")

	row.slot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.slot:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
	row.slot:SetWidth(75)
	row.slot:SetJustifyH("LEFT")

	row.goButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.goButton:SetSize(44, 18)
	row.goButton:SetPoint("RIGHT", 0, 0)
	row.goButton:SetText("Go")

	row.price = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.price:SetPoint("RIGHT", row.goButton, "LEFT", -6, 0)
	row.price:SetJustifyH("RIGHT")
	row.price:SetWidth(90)

	row:SetScript("OnEnter", function(self)
		if self.itemLink then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.itemLink)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return row
end

function UI:Create()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "AHUpgradeCheckFrame", UIParent)
	frame:SetSize(480, 420)
	frame:SetPoint("CENTER")

	-- Plain texture background instead of SetBackdrop: SetBackdrop needs
	-- BackdropTemplateMixin on newer clients and isn't guaranteed here, so
	-- avoid it entirely rather than risk Create() erroring out before Show().
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(frame)
	if bg.SetColorTexture then
		bg:SetColorTexture(0, 0, 0, 0.85)
	else
		bg:SetTexture(0, 0, 0, 0.85)
	end

	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetToplevel(true)
	frame:Hide()
	tinsert(UISpecialFrames, "AHUpgradeCheckFrame")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOP", frame, "TOP", 0, -14)
	frame.title:SetText("AH Upgrade Check")

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.status:SetPoint("TOPLEFT", 20, -36)
	frame.status:SetWidth(340)
	frame.status:SetJustifyH("LEFT")
	frame.status:SetText("Open the Auction House, then press Scan Now.")

	frame.scanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.scanButton:SetSize(100, 22)
	frame.scanButton:SetPoint("TOPRIGHT", -20, -34)
	frame.scanButton:SetText("Scan Now")
	frame.scanButton:SetScript("OnClick", function()
		AHU.Scan:Start()
	end)

	frame.rows = {}
	for i = 1, NUM_ROWS do
		local row = CreateRow(frame, i)
		if i == 1 then
			row:SetPoint("TOPLEFT", 20, -64)
		else
			row:SetPoint("TOPLEFT", frame.rows[i - 1], "BOTTOMLEFT", 0, -2)
		end
		frame.rows[i] = row
	end

	return frame
end

function UI:SetStatus(text)
	self:Create()
	frame.status:SetText(text)
end

function UI:RefreshRows()
	self:Create()
	local results = AHU.Scan.results or {}

	table.sort(results, function(a, b)
		if a.pct == math.huge then
			return b.pct ~= math.huge
		end
		if b.pct == math.huge then
			return false
		end
		return a.pct > b.pct
	end)

	for i, row in ipairs(frame.rows) do
		local entry = results[i]
		if entry then
			row.itemLink = entry.itemLink
			row.pct:SetText(FormatPct(entry.pct))
			row.name:SetText(GetItemInfo(entry.itemLink) or entry.itemLink)
			row.slot:SetText(entry.slotName)
			row.price:SetText(FormatMoney(entry.buyoutPrice))
			row.goButton:SetScript("OnClick", function()
				AHU.Scan:GoToAuction(entry)
			end)
			row:Show()
		else
			row.itemLink = nil
			row:Hide()
		end
	end
end

function UI:Toggle()
	self:Create()
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end

function UI:OnAuctionHouseShown()
	self:Create()
	if AuctionFrame then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 4, 0)
	end
	frame:Show()
end

function UI:OnAuctionHouseClosed()
	if frame then
		frame:Hide()
	end
end
