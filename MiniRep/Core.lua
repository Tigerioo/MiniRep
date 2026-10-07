local addonName, Addon = ...

Addon.name = addonName
Addon.version = "1.1.0"

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function bounded(value, fallback, minimum, maximum)
    if not finite(value) then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

function Addon:InitializeDB()
    if type(MiniRepDB) ~= "table" then MiniRepDB = {} end
    local db = MiniRepDB
    if type(db.enabled) ~= "boolean" then db.enabled = true end
    if type(db.locked) ~= "boolean" then db.locked = true end
    db.fontSize = math.floor(bounded(db.fontSize, 16, 12, 28))
    db.x = bounded(db.x, 0.5, 0, 1)
    db.y = bounded(db.y, 0.82, 0, 1)
    if not finite(db.factionID) or db.factionID <= 0 or db.factionID % 1 ~= 0 then
        db.factionID = nil
        db.factionName = nil
    end
    if type(db.factionName) ~= "string" then db.factionName = nil end
    local watched, seen = {}, {}
    for _, entry in ipairs(type(db.watched) == "table" and db.watched or {}) do
        if type(entry) == "table" and finite(entry.id) and entry.id > 0
            and entry.id % 1 == 0 and not seen[entry.id] then
            watched[#watched + 1] = { id = entry.id,
                name = type(entry.name) == "string" and entry.name or ("声望 #" .. entry.id) }
            seen[entry.id] = true
        end
    end
    -- Migrate the old single selection once, including an intentionally empty
    -- v2 watchlist on later logins. Keep legacy fields available for rollback.
    if (tonumber(db.schemaVersion) or 1) < 2 and db.factionID and not seen[db.factionID] then
        watched[#watched + 1] = { id = db.factionID, name = db.factionName or "所选声望" }
    end
    db.watched = watched
    db.schemaVersion = 2
    self.db = db
    self.currentByID = {}
    self.Daily:Initialize(db)
end

function Addon:IsWatched(id)
    for _, entry in ipairs(self.db.watched) do
        if entry.id == id then return true end
    end
    return false
end

function Addon:StoreSnapshot(entry, row)
    self.currentByID[entry.id] = row
    if row then
        entry.name = row.name
        self.Daily:Observe(row)
    else
        self.Daily:Forget(entry.id)
    end
end

function Addon:ReadWatchedFaction(id)
    for _, entry in ipairs(self.db.watched) do
        if entry.id == id then
            self:StoreSnapshot(entry, self.Reputation:GetByID(id))
            return
        end
    end
end

function Addon:Refresh()
    if not self.db then return end
    self.Daily:EnsureDay()
    local byID
    -- If direct queries are unavailable, expand and restore only once for the
    -- whole panel, instead of once for each watched faction.
    if #self.db.watched > 0 and type(GetFactionInfoByID) ~= "function" then
        byID = {}
        local rows = self.Reputation:GetList()
        for _, row in ipairs(rows) do byID[row.id] = row end
    end
    for _, entry in ipairs(self.db.watched) do
        local row
        if byID then row = byID[entry.id] else row = self.Reputation:GetByID(entry.id) end
        self:StoreSnapshot(entry, row)
    end
    self:UpdateDisplay()
    if self.options and self.options:IsShown() then self:UpdateOptions() end
end

function Addon:RequestRefresh()
    if self.refreshPending or not self.db then return end
    self.refreshPending = true
    C_Timer.After(0.1, function()
        self.refreshPending = false
        self:Refresh()
    end)
end

function Addon:ToggleFaction(id, name)
    if not finite(id) or id <= 0 or id % 1 ~= 0 then return end
    local removed = false
    for index, entry in ipairs(self.db.watched) do
        if entry.id == id then
            self:ReadWatchedFaction(id)
            table.remove(self.db.watched, index)
            self.currentByID[id] = nil
            removed = true
            break
        end
    end
    self.Daily:Forget(id)
    if not removed then
        self.db.watched[#self.db.watched + 1] = { id = id, name = name or ("声望 #" .. id) }
        self.db.enabled = true
    end
    self:Refresh()
end

function Addon:SetEnabled(enabled)
    self.db.enabled = enabled and true or false
    self:UpdateDisplay()
end

function Addon:SetLocked(locked)
    self:StopDragging()
    self.db.locked = locked and true or false
    self:UpdateDisplay()
end

function Addon:SetFontSize(size)
    self.db.fontSize = math.floor(bounded(size, 16, 12, 28))
    self:UpdateDisplay()
end

function Addon:ResetPosition()
    self:StopDragging()
    self.db.x, self.db.y = 0.5, 0.82
    self:ApplyPosition()
end

local events = CreateFrame("Frame")
Addon.events = events
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        events:UnregisterEvent("ADDON_LOADED")
        Addon:InitializeDB()
        Addon:CreateDisplay()
        events:RegisterEvent("PLAYER_LOGIN")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("UPDATE_FACTION")
        events:RegisterEvent("FACTION_STANDING_CHANGED")
        events:RegisterEvent("UI_SCALE_CHANGED")
        events:RegisterEvent("DISPLAY_SIZE_CHANGED")
        events:RegisterEvent("PLAYER_LOGOUT")
        Addon.dayTicker = C_Timer.NewTicker(30, function()
            if Addon.Daily:EnsureDay() or Addon.displayDay ~= Addon.db.daily.day then
                Addon:UpdateDisplay()
                if Addon.options and Addon.options:IsShown() then Addon:UpdateOptions() end
            end
        end)
        SLASH_MINIREP1 = "/rmini"
        SlashCmdList.MINIREP = function() Addon:ToggleOptions() end
    elseif event == "PLAYER_LOGOUT" then
        Addon:StopDragging()
    elseif event == "PLAYER_LOGIN" then
        Addon.Daily:StartSession()
        Addon.sessionStarted = true
        Addon:Refresh()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not Addon.sessionStarted then
            Addon.Daily:StartSession()
            Addon.sessionStarted = true
        end
        Addon:Refresh()
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        Addon:ApplyPosition()
    elseif event == "UPDATE_FACTION" then
        if not Addon.sessionStarted then return end
        local rep = Addon.Reputation
        -- Expanding/restoring headers can also queue UPDATE_FACTION. In the
        -- legacy scan fallback ignore that echo; real gains have their own event.
        local scanEcho = type(GetFactionInfoByID) ~= "function" and rep.lastScanTime
            and GetTime() - rep.lastScanTime < 0.2
        if not rep.scanning and not scanEcho then Addon:RequestRefresh() end
    elseif event == "FACTION_STANDING_CHANGED" then
        if Addon.sessionStarted and Addon:IsWatched(name) then
            -- Observe individual changes before coalescing UI redraws so a gain
            -- followed by a loss in one frame does not become only a net change.
            Addon:ReadWatchedFaction(name)
            Addon:RequestRefresh()
        end
    else
        Addon:RequestRefresh()
    end
end)
