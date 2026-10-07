local _, Addon = ...
local Daily = {}
Addon.Daily = Daily

local function IsFinite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function IsID(value)
    return IsFinite(value) and value > 0 and value % 1 == 0
end

local function Today()
    -- WoW's date() uses the computer's local calendar, not the realm reset time.
    return date("%Y-%m-%d")
end

function Daily:Initialize(db)
    self.db = db
    self:StartSession()
    if type(db.daily) ~= "table" then db.daily = {} end
    if type(db.daily.gains) ~= "table" then db.daily.gains = {} end
    self:EnsureDay()
    local clean = {}
    for id, entry in pairs(db.daily.gains) do
        if IsID(id) and type(entry) == "table" and type(entry.name) == "string"
            and entry.name ~= "" and IsFinite(entry.gained) and entry.gained > 0 then
            clean[id] = { name = entry.name, gained = entry.gained }
        end
    end
    db.daily.gains = clean
end

function Daily:StartSession()
    -- Do not persist baselines: login/reload never attributes offline changes.
    self.baselines = {}
end

function Daily:EnsureDay()
    if not self.db then return false end
    local day = Today()
    if self.db.daily.day == day then return false end
    self.db.daily.day = day
    self.db.daily.gains = {}
    -- Retain live session baselines so the first gain after midnight counts.
    return true
end

function Daily:Forget(id)
    if self.baselines and IsID(id) then self.baselines[id] = nil end
end

function Daily:Observe(row)
    if not self.db then return 0 end
    self:EnsureDay()
    if type(row) ~= "table" or not IsID(row.id) then return 0 end
    if not IsFinite(row.absoluteValue) or type(row.name) ~= "string" or row.name == "" then
        self:Forget(row.id)
        return 0
    end
    local before = self.baselines[row.id]
    self.baselines[row.id] = row.absoluteValue
    if before == nil then return 0 end
    local gain = row.absoluteValue - before
    if not IsFinite(gain) or gain <= 0 then return 0 end
    local entry = self.db.daily.gains[row.id]
    if not entry then
        entry = { name = row.name, gained = 0 }
        self.db.daily.gains[row.id] = entry
    end
    entry.name = row.name
    entry.gained = entry.gained + gain
    return gain
end

function Daily:GetGain(id)
    if not self.db then return 0 end
    self:EnsureDay()
    local entry = self.db.daily.gains[id]
    return entry and entry.gained or 0
end

function Daily:GetRows()
    if not self.db then return {} end
    self:EnsureDay()
    local rows = {}
    for id, entry in pairs(self.db.daily.gains) do
        rows[#rows + 1] = { id = id, name = entry.name, gained = entry.gained }
    end
    table.sort(rows, function(left, right)
        if left.gained ~= right.gained then return left.gained > right.gained end
        if left.name ~= right.name then return left.name < right.name end
        return left.id < right.id
    end)
    return rows
end
