AHUpgradeCheck = AHUpgradeCheck or {}
local AHU = AHUpgradeCheck

AHU.Debug = AHU.Debug or {}
local Debug = AHU.Debug

local MAX_LINES = 500
Debug.lines = Debug.lines or {}

function Debug:Log(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	table.insert(self.lines, ("[%.1f] %s"):format(GetTime(), msg))
	if #self.lines > MAX_LINES then
		table.remove(self.lines, 1)
	end
end

function Debug:Clear()
	self.lines = {}
	AHU.Print("Debug log cleared.")
end

-- Names we're not sure exist under this title on WoW Forever's client - this
-- is exactly the kind of thing worth dumping when something that depends on
-- them (anchoring, Go) misbehaves.
local CANDIDATE_GLOBALS = {
	"AuctionFrame", "AuctionHouseFrame", "AuctionFrameBrowse",
	"BrowseName", "AuctionFrameTab1", "AuctionFrameTab2", "AuctionFrameTab3",
}

function Debug:DumpGlobals()
	for _, name in ipairs(CANDIDATE_GLOBALS) do
		local v = _G[name]
		local shown = ""
		if v and type(v) == "table" and v.IsShown then
			local ok, isShown = pcall(v.IsShown, v)
			shown = ok and (" shown=" .. tostring(isShown)) or " shown=<error calling IsShown>"
		end
		self:Log("global %s = %s%s", name, v ~= nil and type(v) or "nil", shown)
	end
end

local MODERN_API_FUNCS = {
	"SendBrowseQuery", "GetBrowseResults", "HasFullBrowseResults",
	"SendSearchQuery", "GetItemSearchResultInfo", "GetCommoditySearchResultInfo",
}
local LEGACY_API_FUNCS = {
	"QueryAuctionItems", "GetNumAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
}

function Debug:DumpAPI()
	self:Log("C_AuctionHouse = %s", type(C_AuctionHouse))
	if type(C_AuctionHouse) == "table" then
		for _, name in ipairs(MODERN_API_FUNCS) do
			self:Log("C_AuctionHouse.%s = %s", name, type(C_AuctionHouse[name]))
		end
	end
	for _, name in ipairs(LEGACY_API_FUNCS) do
		self:Log("global %s = %s", name, type(_G[name]))
	end
end

-- Candidate fields/methods for whatever tab system AuctionHouseFrame uses
-- here - not assumed, since we've guessed this client's frame structure
-- wrong twice already. Checked before writing any tab-injection code.
local TAB_CANDIDATE_FIELDS = {
	"Tabs", "TabButtons", "NumTabs", "SelectedTab", "DisplayMode",
	"BrowseResultsFrame", "ItemBuyFrame", "CommoditiesBuyFrame", "AuctionsFrame",
	"CategoriesList", "TabSystem",
}
local TAB_CANDIDATE_METHODS = {
	"AddNamedTab", "AddTab", "SetTab", "SetDisplayMode", "GetDisplayMode",
}
local TAB_CANDIDATE_GLOBAL_FUNCS = {
	"PanelTemplates_SetNumTabs", "PanelTemplates_Tab_OnClick", "PanelTemplates_SetTab",
}

function Debug:DumpTabInfo()
	local f = AuctionHouseFrame
	if not f then
		self:Log("AuctionHouseFrame is nil, can't inspect tab structure")
		return
	end
	for _, name in ipairs(TAB_CANDIDATE_FIELDS) do
		local v = f[name]
		local extra = ""
		if type(v) == "table" then
			local ok, n = pcall(function()
				local count = 0
				for _ in pairs(v) do
					count = count + 1
				end
				return count
			end)
			extra = ok and (" (table, %d entries)"):format(n) or " (table)"
		end
		self:Log("AuctionHouseFrame.%s = %s%s", name, type(v), extra)
	end
	for _, name in ipairs(TAB_CANDIDATE_METHODS) do
		self:Log("AuctionHouseFrame.%s (method) = %s", name, type(f[name]))
	end
	for _, name in ipairs(TAB_CANDIDATE_GLOBAL_FUNCS) do
		self:Log("global %s = %s", name, type(_G[name]))
	end
	if f.GetName then
		local ok, frameName = pcall(f.GetName, f)
		self:Log("AuctionHouseFrame:GetName() = %s", ok and tostring(frameName) or "<error>")
	end
end

function Debug:DumpFilterEnum()
	self:Log("Enum.AuctionHouseFilter = %s", type(Enum) == "table" and type(Enum.AuctionHouseFilter) or "no Enum table")
	if type(Enum) == "table" and type(Enum.AuctionHouseFilter) == "table" then
		for key, value in pairs(Enum.AuctionHouseFilter) do
			self:Log("Enum.AuctionHouseFilter.%s = %s", tostring(key), tostring(value))
		end
	end
end

local exportFrame

function Debug:ShowExport()
	if not exportFrame then
		exportFrame = CreateFrame("Frame", "AHUpgradeCheckDebugFrame", UIParent)
		exportFrame:SetSize(560, 420)
		exportFrame:SetPoint("CENTER")
		exportFrame:SetMovable(true)
		exportFrame:EnableMouse(true)
		exportFrame:RegisterForDrag("LeftButton")
		exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
		exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
		exportFrame:SetToplevel(true)
		exportFrame:Hide()
		tinsert(UISpecialFrames, "AHUpgradeCheckDebugFrame")

		local bg = exportFrame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(exportFrame)
		if bg.SetColorTexture then
			bg:SetColorTexture(0, 0, 0, 0.9)
		else
			bg:SetTexture(0, 0, 0, 0.9)
		end

		local close = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)

		local title = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", 0, -12)
		title:SetText("AHUpgradeCheck Debug Log - Ctrl+A, Ctrl+C to copy")

		local scroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 16, -36)
		scroll:SetPoint("BOTTOMRIGHT", -34, 16)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(500)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function()
			exportFrame:Hide()
		end)
		scroll:SetScrollChild(edit)

		exportFrame.editBox = edit
	end

	exportFrame.editBox:SetText(table.concat(self.lines, "\n"))
	exportFrame.editBox:HighlightText()
	exportFrame.editBox:SetFocus()
	exportFrame:Show()
end
