-- Narrow local smoke check. This is not a WoW renderer or game-client test.
local methods = {}
local noop = function() end
local function object(kind, name, parent)
    local value = { kind = kind, name = name, parent = parent, shown = true,
        scripts = {}, events = {}, width = 100, height = 30, text = "" }
    setmetatable(value, { __index = methods })
    if name then _G[name] = value end
    return value
end
local visualOnly = {
    "SetFrameStrata", "SetMovable", "SetClampedToScreen", "EnableMouse", "RegisterForClicks",
    "RegisterForDrag", "SetTextColor", "SetWordWrap", "SetAllPoints", "SetColorTexture",
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetJustifyH", "SetAutoFocus",
    "SetMaxLetters", "ClearFocus", "StartMoving", "StopMovingOrSizing", "EnableMouseWheel",
}
for _, name in ipairs(visualOnly) do methods[name] = noop end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:ClearAllPoints() self.point = nil end
function methods:SetPoint(...) self.point = {...} end
function methods:GetCenter() return 900, 600 end
function methods:SetText(text)
    self.text = text
    if self.kind == "EditBox" and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return self.text end
function methods:SetFont(font, size) self.font, self.fontSize = font, size end
function methods:GetFont() return "FakeGameFont.ttf", 16, "" end
function methods:GetStringWidth() return #self.text * 5 end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetShown(value)
    local changed = self.shown ~= value
    self.shown = value
    if changed and not value and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:CreateFontString(name) return object("FontString", name, self) end
function methods:CreateTexture(name) return object("Texture", name, self) end
function methods:SetOwner(owner) self.owner = owner; self.lines = {} end
function methods:IsOwned(owner) return self.owner == owner and self.shown end
function methods:AddLine(text) self.lines[#self.lines + 1] = text end

CreateFrame = function(kind, name, parent) return object(kind, name, parent) end
UIParent = object("Frame")
UIParent:SetSize(1920, 1080)
GameFontNormal = object("Font")
GameTooltip = object("Tooltip")
GameTooltip:Hide()
SlashCmdList, UISpecialFrames = {}, {}
local queue, time, tickers = {}, 1, {}
local day = "2026-10-07"
date = function() return day end
local controlDown = false
IsControlKeyDown = function() return controlDown end
C_Timer = {
    After = function(_, callback) queue[#queue + 1] = callback end,
    NewTicker = function(_, callback) tickers[#tickers + 1] = callback; return {} end,
}
GetTime = function() return time end
local function flush()
    local count = 0
    while #queue > 0 do
        count = count + 1
        assert(count < 10, "Refresh loop")
        local pending = queue
        queue = {}
        time = time + 0.1
        for _, callback in ipairs(pending) do callback() end
    end
end

local Addon = {}
for _, file in ipairs({"Core.lua", "Reputation.lua", "Daily.lua", "Display.lua", "Options.lua"}) do
    assert(loadfile("MiniRep/" .. file))("MiniRep", Addon)
end
local dataPassed = assert(loadfile("tests/reputation.lua"))()(Addon)
print("Data and folded-list checks passed: " .. tostring(dataPassed))
local newPassed = assert(loadfile("tests/daily.lua"))()(Addon)
print("Daily and category checks passed: " .. tostring(newPassed))

local raw = {id = 1492, name = "皇帝少昊", standingID = 7, barMin = 21000, barMax = 42000, barValue = 29400}
raw.category, raw.categoryOrder = "熊猫人之谜", 1
local secondRaw = {id = 1011, name = "贫民窟", standingID = 5, barMin = 3000,
    barMax = 9000, barValue = 5400, category = "燃烧的远征", categoryOrder = 2}
local gains = function() return Addon.Reputation:Normalize(raw) end
Addon.Reputation.GetByID = function(_, id)
    if id == 1492 then return gains() end
    if id == 1011 then return Addon.Reputation:Normalize(secondRaw) end
end
Addon.Reputation.GetList = function()
    local rows = {gains(), Addon.Reputation:Normalize(secondRaw)}
    for i = 1, 12 do
        rows[#rows + 1] = {id = 2000 + i, name = "其他声望" .. i, standingText = "友善",
            category = "其他", categoryOrder = 3, absoluteValue = 1000 + i}
    end
    return rows
end
GetFactionInfoByID = function() end
local function fire(event, ...)
    if Addon.events.events[event] then Addon.events.scripts.OnEvent(Addon.events, event, ...) end
end
fire("ADDON_LOADED", "OtherAddon")
assert(not Addon.db, "Unrelated addon initialized MiniRep")
-- Upgrade the existing single selection without losing its appearance or position.
MiniRepDB = {schemaVersion = 1, factionID = 1492, factionName = "皇帝少昊", fontSize = 18, x = 0.4, y = 0.7}
fire("ADDON_LOADED", "MiniRep")
fire("PLAYER_LOGIN")
flush()
assert(Addon.db.locked and Addon.display:IsShown())
assert(Addon:IsWatched(1492) and #Addon.db.watched == 1 and Addon.db.fontSize == 18 and Addon.db.x == 0.4)
assert(Addon.Daily:GetGain(1492) == 0, "Upgrade falsely counted historical reputation")
SlashCmdList.MINIREP()
assert(Addon.options:IsShown())
assert(Addon.options.next.enabled, "Pagination unavailable")
Addon.options.next.scripts.OnClick()
assert(Addon.options.page == 2)
Addon.options.search:SetText("贫民")
assert(Addon.options.page == 1 and Addon.options.rows[1].data.id == 1011)
assert(not Addon.options.rows[2]:IsShown(), "Search retained unrelated result")
Addon.options.rows[1].scripts.OnClick(Addon.options.rows[1])
assert(Addon:IsWatched(1492) and Addon:IsWatched(1011) and #Addon.db.watched == 2)
assert(Addon.display.lines[1].text:GetText():find("崇敬", 1, true))
assert(Addon.display.lines[1].text:GetText():find("8,400 / 21,000（40%）", 1, true))
assert(Addon.display.lines[2].text:GetText():find("贫民窟", 1, true))
Addon.options.search:SetText("")
Addon.options.categoryButton.scripts.OnClick(Addon.options.categoryButton, "LeftButton")
assert(Addon.db.optionsCategory == "熊猫人之谜" and Addon.options.rows[1].data.id == 1492)
assert(not Addon.options.rows[2]:IsShown(), "Category filter leaked another expansion")
Addon.options.categoryButton.scripts.OnClick(Addon.options.categoryButton, "RightButton")
assert(Addon.db.optionsCategory == nil)
Addon.options.scopeButton.scripts.OnClick()
assert(Addon.db.optionsWatchedOnly and Addon.options.rows[2]:IsShown() and not Addon.options.rows[3]:IsShown())
Addon.options.scopeButton.scripts.OnClick()
Addon.options.sortButton.scripts.OnClick(Addon.options.sortButton, "LeftButton")
Addon.options.sortButton.scripts.OnClick(Addon.options.sortButton, "LeftButton")
assert(Addon.db.optionsSort == "value_desc" and Addon.options.rows[1].data.id == 1492)
assert(Addon.db.watched[1].id == 1492 and Addon.db.watched[2].id == 1011, "Settings sort reordered HUD")
Addon.display.lines[1].scripts.OnEnter(Addon.display.lines[1])
assert(table.concat(GameTooltip.lines):find("12,600", 1, true))
raw.barValue = 31500
fire("UPDATE_FACTION")
fire("UPDATE_FACTION")
assert(#queue == 1, "Burst events were not coalesced")
flush()
assert(Addon.display.lines[1].text:GetText():find("50%", 1, true))
assert(Addon.display.lines[1].text:GetText():find("今日 +2,100", 1, true))
-- Preserve gross gains even when gain/loss events occur before one redraw.
raw.barValue = 31600
fire("FACTION_STANDING_CHANGED", 1492)
raw.barValue = 31550
fire("FACTION_STANDING_CHANGED", 1492)
flush()
assert(Addon.Daily:GetGain(1492) == 2200)
raw.standingID, raw.barMin, raw.barMax, raw.barValue = 8, 42000, 42999, 42000
fire("FACTION_STANDING_CHANGED", 1492)
flush()
assert(Addon.display.lines[1].text:GetText():find("崇拜", 1, true))
assert(Addon.display.lines[1].text:GetText():find("100%", 1, true))
local earned = Addon.Daily:GetGain(1492)
Addon:ToggleFaction(1492, raw.name)
assert(not Addon:IsWatched(1492) and Addon:IsWatched(1011) and Addon.Daily:GetGain(1492) == earned)
Addon.options.todayTab.scripts.OnClick()
assert(Addon.options.view == "today" and Addon.options.rows[1].data.id == 1492)
assert(Addon.options.rows[1].data.gained == earned and not Addon.options.rows[1].data.watched)
assert(Addon.options.todayTotal:GetText():find(Addon.Reputation:FormatNumber(earned), 1, true))
Addon.options.factionsTab.scripts.OnClick()
raw.barValue = 42500
Addon:ToggleFaction(1492, raw.name)
assert(Addon.Daily:GetGain(1492) == earned, "Re-follow counted unattended gains")
Addon:SetEnabled(false)
assert(not Addon.display:IsShown())
assert(not GameTooltip:IsShown(), "Hidden panel left its line tooltip visible")
Addon.options:Hide()
SlashCmdList.MINIREP()
assert(Addon.options:IsShown(), "Hidden tracker cannot reopen settings")
Addon:SetEnabled(true)
Addon:SetLocked(false)
Addon.display.scripts.OnDragStart()
assert(Addon.dragging)
Addon.display.scripts.OnDragStop()
assert(not Addon.dragging and Addon.db.x == 900 / 1920 and Addon.db.y == 600 / 1080)
Addon:SetLocked(true)
Addon.display.scripts.OnDragStart()
assert(not Addon.dragging, "Locked tracker moved")
controlDown = true
Addon.display.lines[1].scripts.OnDragStart()
assert(Addon.dragging, "Ctrl did not override drag lock")
Addon.display.lines[1].scripts.OnDragStop()
controlDown = false
Addon:SetFontSize(100)
assert(Addon.db.fontSize == 28)
local saved = MiniRepDB
Addon.db = nil
Addon:InitializeDB()
assert(Addon.db == saved and #Addon.db.watched == 2 and Addon:IsWatched(1492) and Addon.db.x == 900 / 1920)
Addon:Refresh()
assert(Addon.Daily:GetGain(1492) == earned, "Reload changed daily total")
day = "2026-10-08"
-- A tooltip can reset the date before the ticker; the visible panel must still catch up.
assert(Addon.Daily:GetGain(1492) == 0)
tickers[1]()
assert(Addon.display.lines[2].text:GetText():find("今日 +0", 1, true))
Addon.Reputation.GetByID = function() return nil, "Unavailable" end
Addon:Refresh()
assert(Addon:IsWatched(1492) and Addon.display.lines[2].text:GetText():find("暂无数据", 1, true))
assert(not Addon.display.lines[2].text:GetText():find("%%"), "Missing data faked percentage")
Addon:ToggleFaction(1492, raw.name)
Addon:ToggleFaction(1011, secondRaw.name)
Addon:InitializeDB()
Addon:Refresh()
assert(#Addon.db.watched == 0, "Legacy selection resurrected after clearing the watchlist")
assert(Addon.display.lines[1].text:GetText():find("添加关注", 1, true))
print("UI/event smoke passed: v1 migration, multi-watch, search/paging, daily events, cap, tooltip, Ctrl-drag, config reuse, day rollover, missing data")
print("Mock API checks only; real WoW rendering/events/persistence not verified.")
