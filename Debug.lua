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
