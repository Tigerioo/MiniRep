local _, Addon = ...
local Rep = {}
Addon.Reputation = Rep
Rep.categories = {}

local fallbackStandings = {
    "仇恨", "敌对", "冷淡", "中立", "友善", "尊敬", "崇敬", "崇拜",
}

local function IsFinite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function StandingText(standingID)
    if not IsFinite(standingID) then return "未知" end
    local key = "FACTION_STANDING_LABEL" .. standingID
    local text = GetText and GetText(key, UnitSex and UnitSex("player") or 2)
    return text or _G[key] or fallbackStandings[standingID] or "未知"
end

function Rep:FormatNumber(value)
    if not IsFinite(value) then return "—" end
    local sign = value < 0 and "-" or ""
    local digits = string.format("%.0f", math.abs(value))
    return sign .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

function Rep:FormatPercent(current, total, capped)
    if capped then return "100%" end
    if not IsFinite(current) or not IsFinite(total) or total <= 0
        or current < 0 or current > total then
        return "—"
    end
    -- Keep an unfinished rank below 100%, even when rounding 99.99%.
    local tenths = current == total and 1000 or math.min(999, math.floor(current / total * 1000 + 0.5))
    if tenths % 10 == 0 then
        return string.format("%d%%", tenths / 10)
    end
    return string.format("%.1f%%", tenths / 10)
end

-- raw uses the classic tuple names, except factionID is called id.
-- friendship is the unmodified C_GossipInfo.GetFriendshipReputation result.
function Rep:Normalize(raw, friendship)
    if type(raw) ~= "table" or not IsFinite(raw.id) or raw.id <= 0
        or type(raw.name) ~= "string" or raw.name == "" then
        return nil, "声望资料暂不可用"
    end
    local isFriendship = type(friendship) == "table"
        and IsFinite(friendship.friendshipFactionID) and friendship.friendshipFactionID > 0
    local capped = false
    local standingText, nextStandingText
    local minimum, maximum, value = raw.barMin, raw.barMax, raw.barValue
    if isFriendship then
        standingText = friendship.reaction or "未知"
        capped = friendship.nextThreshold == nil
        minimum, maximum, value = friendship.reactionThreshold, friendship.nextThreshold, friendship.standing
        if not capped then nextStandingText = "下一等级" end
    else
        standingText = StandingText(raw.standingID)
        capped = IsFinite(raw.standingID) and raw.standingID >= 8
        if IsFinite(raw.standingID) and raw.standingID >= 1 and raw.standingID < 8 then
            nextStandingText = StandingText(raw.standingID + 1)
        end
    end
    local row = {
        id = raw.id, name = raw.name, standingText = standingText,
        standingID = IsFinite(raw.standingID) and raw.standingID or nil,
        capped = capped, isFriendship = isFriendship,
        nextStandingText = nextStandingText,
    }
    local category = self.categories[raw.id]
    row.category = raw.category or (category and category.name) or "未分类"
    row.categoryOrder = raw.categoryOrder or (category and category.order) or 9999
    if capped then
        row.percentText = "100%"
        -- Keep the actual cumulative value even when the displayed bar is capped.
        -- An absent or inconsistent value must not become a daily-gain baseline.
        local validValue = IsFinite(value) and IsFinite(minimum) and value >= minimum
        if isFriendship then
            validValue = validValue and (friendship.maxRep == nil
                or (IsFinite(friendship.maxRep) and value <= friendship.maxRep))
        else
            validValue = validValue and IsFinite(maximum) and maximum >= minimum and value <= maximum
        end
        if validValue then row.absoluteValue = value end
        return row
    end
    if not IsFinite(minimum) or not IsFinite(maximum) or not IsFinite(value)
        or maximum <= minimum or value < minimum or value > maximum then
        row.percentText = "—"
        return row, "声望进度暂不可用"
    end
    row.current = value - minimum
    row.total = maximum - minimum
    row.absoluteValue = value
    row.percentText = self:FormatPercent(row.current, row.total, false)
    return row
end

local function ReadRaw(reader, argument)
    local name, _, standingID, barMin, barMax, barValue, _, _,
        isHeader, isCollapsed, hasRep, _, isChild, factionID = reader(argument)
    if not name then return nil end
    return {
        id = factionID, name = name, standingID = standingID,
        barMin = barMin, barMax = barMax, barValue = barValue,
        isHeader = isHeader, isCollapsed = isCollapsed, hasRep = hasRep, isChild = isChild,
    }
end

local function NormalizeRaw(raw)
    local friendship
    if C_GossipInfo and type(C_GossipInfo.GetFriendshipReputation) == "function" then
        friendship = C_GossipInfo.GetFriendshipReputation(raw.id)
    end
    return Rep:Normalize(raw, friendship)
end

local function ErrorText(message)
    return "读取声望失败：" .. tostring(message)
end

function Rep:GetList()
    if self.scanning then return self.lastList or {}, "正在读取声望" end
    if type(GetNumFactions) ~= "function" or type(GetFactionInfo) ~= "function"
        or type(ExpandFactionHeader) ~= "function" or type(CollapseFactionHeader) ~= "function" then
        return {}, "当前客户端缺少怀旧服声望接口"
    end

    self.scanning = true
    local expanded, rows, seen = {}, {}, {}
    local dataError
    local ok, failure = pcall(function()
        local index = 1
        local categoryName, categoryOrder = "未分类", 9999
        local nextCategoryOrder = 0
        -- Expand every header, including the inactive group and headers with rep.
        -- Record current indices in ascending order; restore in reverse order.
        while index <= GetNumFactions() do
            if index > 10000 then error("声望列表长度异常") end
            local raw = ReadRaw(GetFactionInfo, index)
            if not raw then error("声望列表正在更新，请重试") end
            -- The native list supplies expansion/category names in the user's
            -- locale. Child headers (e.g. Shattrath) keep their top-level group.
            if raw.isHeader and not raw.isChild then
                nextCategoryOrder = nextCategoryOrder + 1
                categoryName, categoryOrder = raw.name, nextCategoryOrder
            end
            if raw.isHeader and raw.isCollapsed then
                expanded[#expanded + 1] = index
                ExpandFactionHeader(index)
            end
            if (not raw.isHeader or raw.hasRep) and IsFinite(raw.id) and raw.id > 0 and not seen[raw.id] then
                self.categories[raw.id] = { name = categoryName, order = categoryOrder }
                raw.category, raw.categoryOrder = categoryName, categoryOrder
                local row, problem = NormalizeRaw(raw)
                if row then
                    seen[raw.id] = true
                    rows[#rows + 1] = row
                end
                dataError = dataError or problem
            end
            index = index + 1
        end
    end)

    -- Always attempt every restoration, even if reading or a prior collapse fails.
    local restoreError
    for index = #expanded, 1, -1 do
        local restored, problem = pcall(CollapseFactionHeader, expanded[index])
        if not restored then restoreError = restoreError or problem end
    end
    self.scanning = false
    self.lastScanTime = GetTime and GetTime() or nil
    if restoreError then
        return rows, "声望分类恢复失败，请检查游戏声望面板：" .. tostring(restoreError)
    end
    if not ok then return rows, ErrorText(failure) end

    table.sort(rows, function(left, right)
        if left.name == right.name then return left.id < right.id end
        return left.name < right.name
    end)
    self.lastList = rows
    return rows, dataError
end

function Rep:GetByID(id)
    if not IsFinite(id) or id <= 0 then return nil, "尚未选择声望" end
    if self.scanning then
        for _, row in ipairs(self.lastList or {}) do
            if row.id == id then return row end
        end
        return nil, "正在读取声望"
    end
    -- Direct ID queries avoid expanding headers on UPDATE_FACTION, which could
    -- itself emit UPDATE_FACTION. Never assume a retail C_Reputation API exists.
    if type(GetFactionInfoByID) == "function" then
        local ok, row, problem = pcall(function()
            local raw = ReadRaw(GetFactionInfoByID, id)
            if not raw then return nil, "当前角色尚未发现此声望" end
            raw.id = id
            return NormalizeRaw(raw)
        end)
        if not ok then return nil, ErrorText(row) end
        return row, problem
    end
    local rows, problem = self:GetList()
    for _, row in ipairs(rows) do
        if row.id == id then return row, problem end
    end
    return nil, problem or "当前角色尚未发现此声望"
end
