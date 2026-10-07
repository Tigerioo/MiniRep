local _, Addon = ...
local ROW_COUNT = 8
local SORTS = {
    { key = "category", label = "资料片 / 分类" },
    { key = "name", label = "名称" },
    { key = "value_desc", label = "声望值：从高到低" },
    { key = "value_asc", label = "声望值：从低到高" },
    { key = "gain_desc", label = "今日新增：从高到低" },
    { key = "gain_asc", label = "今日新增：从低到高" },
}

local function Label(parent, text, x, y, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function Button(parent, text, width, point, x, y, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26)
    button:SetPoint(point, parent, point, x, y)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function Tooltip(button, title, lines)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 0.82, 0)
    for _, line in ipairs(lines) do
        GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true)
    end
    GameTooltip:Show()
end

local function Explain(button, title, lines)
    button:SetScript("OnEnter", function() Tooltip(button, title, lines) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnHide", function()
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end)
end

local function Finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function NameLess(left, right)
    if left.name == right.name then return left.id < right.id end
    return left.name < right.name
end

local function NumberLess(left, right, field, descending)
    local a, b = left[field], right[field]
    local knownA, knownB = Finite(a), Finite(b)
    if knownA ~= knownB then return knownA end
    if knownA and a ~= b then
        if descending then return a > b end
        return a < b
    end
    return NameLess(left, right)
end

local function SortIndex(key)
    for index, entry in ipairs(SORTS) do
        if entry.key == key then return index end
    end
    return 1
end

-- Build local view models: sorting settings must never reorder db.watched.
local function FactionRows(addon, entries)
    local rows, seen = {}, {}
    local function Add(entry)
        if seen[entry.id] then return end
        seen[entry.id] = true
        local watched = addon:IsWatched(entry.id)
        local current = addon.currentByID and addon.currentByID[entry.id]
        if not current then
            current = watched and { name = entry.name, standingText = "暂不可用" } or entry
        end
        rows[#rows + 1] = {
            id = entry.id, name = current.name or entry.name,
            current = current,
            category = entry.category or current.category or "未分类",
            categoryOrder = entry.categoryOrder or current.categoryOrder or 999,
            absoluteValue = current.absoluteValue,
            gained = addon.Daily:GetGain(entry.id),
            watched = watched,
        }
    end
    for _, entry in ipairs(entries or {}) do Add(entry) end
    -- Keep an unavailable saved selection removable from the settings panel.
    for _, watched in ipairs(addon.db.watched or {}) do
        if not seen[watched.id] then
            Add({ id = watched.id, name = watched.name or ("声望 " .. watched.id),
                standingText = "暂不可用", percentText = "—" })
        end
    end
    return rows
end

local function Categories(rows)
    local result, seen = {}, {}
    for _, row in ipairs(rows) do
        if not seen[row.category] then
            seen[row.category] = true
            result[#result + 1] = { name = row.category, order = row.categoryOrder }
        end
    end
    table.sort(result, function(left, right)
        if left.order == right.order then return left.name < right.name end
        return left.order < right.order
    end)
    table.insert(result, 1, { name = "全部资料片 / 分类" })
    return result
end

function Addon:ReloadOptionsList()
    local frame = self.options
    frame.entries, frame.listError = self.Reputation:GetList()
    frame.page = 1
    self:UpdateOptions()
end

function Addon:UpdateOptions()
    local frame = self.options
    if not frame or not self.db then return end
    frame.showCheck:SetChecked(self.db.enabled)
    frame.lockCheck:SetChecked(self.db.locked)
    frame.fontLabel:SetText("字号：" .. self.db.fontSize)
    frame.smaller:SetEnabled(self.db.fontSize > 12)
    frame.larger:SetEnabled(self.db.fontSize < 28)
    frame.selection:SetText("已关注 " .. #(self.db.watched or {}) .. " 个声望 · 屏幕按添加顺序显示")

    local isToday = frame.view == "today"
    frame.factionsTab:SetEnabled(isToday)
    frame.todayTab:SetEnabled(not isToday)
    frame.scopeButton:SetShown(not isToday)
    frame.categoryButton:SetShown(not isToday)
    frame.sortButton:SetShown(not isToday)
    frame.todayInfo:SetShown(isToday)
    frame.todayTotal:SetShown(isToday)
    frame.nameHeader:SetText("声望名称")
    frame.categoryHeader:SetText(isToday and "记录" or "资料片 / 分类")
    frame.valueHeader:SetText(isToday and "今日新增" or "当前等级 / 声望值")
    frame.actionHeader:SetText(isToday and "关注状态" or "点击整行切换")

    local rows = FactionRows(self, frame.entries)
    frame.categories = Categories(rows)
    local categoryIndex = 1
    for index, category in ipairs(frame.categories) do
        if index > 1 and category.name == self.db.optionsCategory then categoryIndex = index end
    end
    -- A category can disappear after switching clients or refreshing reputation.
    if categoryIndex == 1 then self.db.optionsCategory = nil end
    frame.categoryIndex = categoryIndex
    frame.categoryButton:SetText("分类：" .. frame.categories[categoryIndex].name)
    frame.scopeButton:SetText(self.db.optionsWatchedOnly and "范围：仅关注" or "范围：全部声望")
    local sortIndex = SortIndex(self.db.optionsSort)
    frame.sortButton:SetText("排序：" .. SORTS[sortIndex].label)

    if isToday then
        rows = {}
        local total = 0
        for _, entry in ipairs(self.Daily:GetRows()) do
            if Finite(entry.gained) and entry.gained > 0 then
                total = total + entry.gained
                rows[#rows + 1] = {
                    id = entry.id, name = entry.name or ("声望 " .. entry.id),
                    gained = entry.gained, watched = self:IsWatched(entry.id),
                }
            end
        end
        frame.todayTotal:SetText("今日新增合计：+" .. self.Reputation:FormatNumber(total)
            .. " · " .. #rows .. " 个声望（所有今日记录）")
        table.sort(rows, function(left, right) return NumberLess(left, right, "gained", true) end)
    else
        local sortKey = SORTS[sortIndex].key
        table.sort(rows, function(left, right)
            if sortKey == "category" then
                if left.categoryOrder ~= right.categoryOrder then
                    return left.categoryOrder < right.categoryOrder
                end
                if left.category ~= right.category then return left.category < right.category end
            elseif sortKey == "value_desc" or sortKey == "value_asc" then
                return NumberLess(left, right, "absoluteValue", sortKey == "value_desc")
            elseif sortKey == "gain_desc" or sortKey == "gain_asc" then
                return NumberLess(left, right, "gained", sortKey == "gain_desc")
            end
            return NameLess(left, right)
        end)
    end

    local query = string.lower(frame.search:GetText() or ""):match("^%s*(.-)%s*$")
    local filtered = {}
    for _, entry in ipairs(rows) do
        local matches = query == "" or string.find(string.lower(entry.name), query, 1, true)
        if matches and (isToday or ((not self.db.optionsWatchedOnly or entry.watched)
            and (not self.db.optionsCategory or entry.category == self.db.optionsCategory))) then
            filtered[#filtered + 1] = entry
        end
    end
    local pages = math.max(1, math.ceil(#filtered / ROW_COUNT))
    frame.page = math.max(1, math.min(frame.page or 1, pages))
    for index, button in ipairs(frame.rows) do
        local row = filtered[(frame.page - 1) * ROW_COUNT + index]
        button.data = row
        button:SetShown(row ~= nil)
        if row then
            button.nameLabel:SetText(row.name)
            button.categoryLabel:SetText(isToday and "本机今日" or row.category)
            if isToday then
                button.rankLabel:SetText("+" .. self.Reputation:FormatNumber(row.gained))
                button.actionLabel:SetText(row.watched and "已关注" or "未关注")
            else
                button.rankLabel:SetText((row.current.standingText or "未知") .. " · "
                    .. self.Reputation:FormatNumber(row.absoluteValue))
                button.actionLabel:SetText(row.watched and "取消关注" or "+ 关注")
            end
            button.selection:SetShown(row.watched)
        end
    end
    frame.previous:SetEnabled(frame.page > 1)
    frame.next:SetEnabled(frame.page < pages)
    frame.pageLabel:SetText(string.format("%d / %d 页 · %d 个", frame.page, pages, #filtered))
    frame.empty:SetShown(#filtered == 0)
    if isToday then
        frame.empty:SetText(query ~= "" and "没有匹配的今日记录。" or "今日尚无新增记录；关注声望后开始累计。")
        frame.hint:SetText("取消关注后今日记录仍保留；统计口径请查看“记录说明”。")
    elseif frame.listError then
        frame.empty:SetText("暂时无法完整读取声望，点击右上角“刷新”。")
        frame.hint:SetText("部分数据暂不可用，请刷新重试。Ctrl + 左键可拖动屏幕面板。")
    else
        frame.empty:SetText("没有匹配声望，请调整搜索、范围或分类；也可点击“刷新”。")
        frame.hint:SetText("Ctrl + 左键拖动屏幕面板；分类和排序按钮支持左 / 右键切换。")
    end
end

function Addon:CreateOptions()
    local frame = CreateFrame("Frame", "MiniRepOptions", UIParent, "BackdropTemplate")
    self.options = frame
    frame:Hide()
    frame:SetSize(680, 640)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        if frame.search then frame.search:ClearFocus() end
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.055, 0.065, 0.08, 0.97)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    Label(frame, "MiniRep · 声望关注", 18, -18, "GameFontNormalLarge")
    frame.selection = Label(frame, "", 18, -47)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)
    UISpecialFrames[#UISpecialFrames + 1] = "MiniRepOptions"

    local function SetView(view)
        frame.view, frame.page = view, 1
        frame.search:ClearFocus()
        frame.search:SetText("")
        self:UpdateOptions()
    end
    frame.factionsTab = Button(frame, "关注声望", 145, "TOPLEFT", 16, -73, function() SetView("factions") end)
    frame.todayTab = Button(frame, "今日汇总", 145, "TOPLEFT", 171, -73, function() SetView("today") end)
    local notes = Button(frame, "记录说明", 105, "TOPRIGHT", -16, -73, function() end)
    Explain(notes, "今日新增的统计口径", {
        "按本机日期统计，午夜后自动开始新一天。重登保留当天累计。",
        "仅记录插件启用、角色在线且声望处于关注状态期间的正向增量。",
        "首次关注只建立基线，不把原有声望计为今日新增；离线、未关注期间不补记。",
        "声望下降不抵扣已获得的数值；取消关注后仍保留当天记录。",
        "重置位置、调整字号和列表排序不会清除记录。",
    })
    Label(frame, "搜索", 18, -119)
    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.search = search
    search:SetSize(475, 28)
    search:SetPoint("TOPLEFT", 63, -111)
    search:SetAutoFocus(false)
    search:SetMaxLetters(100)
    search:SetScript("OnEscapePressed", function(edit) edit:ClearFocus(); frame:Hide() end)
    search:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        frame.page = 1
        self:UpdateOptions()
    end)
    Button(frame, "刷新", 105, "TOPRIGHT", -16, -111, function() self:ReloadOptionsList() end)

    frame.scopeButton = Button(frame, "", 198, "TOPLEFT", 16, -149, function()
        self.db.optionsWatchedOnly = not self.db.optionsWatchedOnly
        frame.page = 1
        self:UpdateOptions()
    end)
    frame.categoryButton = Button(frame, "", 440, "TOPRIGHT", -16, -149, function(_, mouseButton)
        local step = mouseButton == "RightButton" and -1 or 1
        local index = ((frame.categoryIndex or 1) - 1 + step) % #frame.categories + 1
        self.db.optionsCategory = index > 1 and frame.categories[index].name or nil
        frame.page = 1
        self:UpdateOptions()
    end)
    frame.categoryButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Explain(frame.categoryButton, "按资料片 / 分类筛选", {
        "左键：下一分类；右键：上一分类。分类取自当前角色的声望资料。",
        "选择“全部资料片 / 分类”可恢复显示全部；尚未发现的声望不在列表内。",
    })
    frame.sortButton = Button(frame, "", 648, "TOPLEFT", 16, -185, function(_, mouseButton)
        local step = mouseButton == "RightButton" and -1 or 1
        local index = (SortIndex(self.db.optionsSort) - 1 + step) % #SORTS + 1
        self.db.optionsSort = SORTS[index].key
        frame.page = 1
        self:UpdateOptions()
    end)
    frame.sortButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Explain(frame.sortButton, "声望列表排序", {
        "左键：下一种排序；右键：上一种排序。",
        "可按资料片 / 分类、名称、声望值高低、今日新增高低排列。",
        "声望值比较游戏返回的累计数值，包含当前等级之前的进度；未知值放在末尾。",
        "不同声望的等级阈值可能不同，数值排序不代表等级或完成度排序。",
        "只改变设置列表；屏幕上的关注声望始终按添加顺序显示。",
    })
    frame.todayInfo = Label(frame, "记录角色在线且关注期间的新增；取消关注后仍保留今日记录。", 20, -154)
    frame.todayTotal = Label(frame, "", 20, -189, "GameFontNormal")
    frame.nameHeader = Label(frame, "", 24, -226, "GameFontNormalSmall")
    frame.categoryHeader = Label(frame, "", 257, -226, "GameFontNormalSmall")
    frame.valueHeader = Label(frame, "", 407, -226, "GameFontNormalSmall")
    frame.actionHeader = Label(frame, "", 568, -226, "GameFontNormalSmall")

    frame.rows = {}
    for index = 1, ROW_COUNT do
        local row = CreateFrame("Button", nil, frame)
        frame.rows[index] = row
        row:SetSize(648, 29)
        row:SetPoint("TOPLEFT", 16, -247 - (index - 1) * 29)
        row:RegisterForClicks("LeftButtonUp")
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)
        row.selection = row:CreateTexture(nil, "BACKGROUND")
        row.selection:SetAllPoints()
        row.selection:SetColorTexture(0.2, 0.65, 0.65, 0.25)
        local function Column(x, width, font)
            local text = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
            text:SetPoint("LEFT", x, 0)
            text:SetWidth(width)
            text:SetJustifyH("LEFT")
            text:SetWordWrap(false)
            return text
        end
        row.nameLabel = Column(8, 225)
        row.categoryLabel = Column(241, 142, "GameFontHighlightSmall")
        row.rankLabel = Column(391, 153, "GameFontNormalSmall")
        row.actionLabel = Column(552, 88, "GameFontHighlightSmall")
        row:SetScript("OnClick", function(button)
            if button.data and frame.view ~= "today" then
                search:ClearFocus()
                self:ToggleFaction(button.data.id, button.data.name)
                self:UpdateOptions()
                GameTooltip:Hide()
            end
        end)
        row:SetScript("OnEnter", function(button)
            local data = button.data
            if not data then return end
            local lines = {}
            if frame.view ~= "today" then
                local current = data.current
                lines[#lines + 1] = data.category .. " · " .. (current.standingText or "未知等级")
                if current.capped then
                    lines[#lines + 1] = "已达最高等级（100%）"
                elseif current.current and current.total then
                    lines[#lines + 1] = self.Reputation:FormatNumber(current.current) .. " / "
                        .. self.Reputation:FormatNumber(current.total) .. "（" .. (current.percentText or "—") .. "）"
                end
                lines[#lines + 1] = "累计声望值：" .. self.Reputation:FormatNumber(data.absoluteValue)
            end
            lines[#lines + 1] = "今日新增：+" .. self.Reputation:FormatNumber(data.gained)
            if frame.view == "today" then
                lines[#lines + 1] = data.watched and "当前已关注，继续累计。" or "当前未关注；今日记录继续保留。"
            else
                lines[#lines + 1] = data.watched and "点击取消关注；今日记录会保留。" or "点击添加关注，可同时关注多个声望。"
            end
            Tooltip(button, data.name, lines)
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnHide", function(button)
            if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        end)
    end
    frame.empty = Label(frame, "", 24, -298)
    frame.empty:SetWidth(632)
    frame.empty:SetJustifyH("CENTER")
    frame.previous = Button(frame, "上一页", 90, "TOPLEFT", 16, -490, function()
        frame.page = frame.page - 1
        self:UpdateOptions()
    end)
    frame.next = Button(frame, "下一页", 90, "TOPRIGHT", -16, -490, function()
        frame.page = frame.page + 1
        self:UpdateOptions()
    end)
    frame.pageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.pageLabel:SetPoint("TOP", 0, -498)
    frame.showCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.showCheck:SetPoint("TOPLEFT", 14, -531)
    frame.showCheck:SetSize(26, 26)
    Label(frame, "显示声望文字", 44, -538)
    frame.showCheck:SetScript("OnClick", function(button) self:SetEnabled(button:GetChecked()) end)
    frame.lockCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.lockCheck:SetPoint("TOPLEFT", 325, -531)
    frame.lockCheck:SetSize(26, 26)
    Label(frame, "锁定位置（Ctrl 仍可拖动）", 355, -538)
    frame.lockCheck:SetScript("OnClick", function(button) self:SetLocked(button:GetChecked()) end)
    frame.fontLabel = Label(frame, "", 20, -580)
    frame.smaller = Button(frame, "−", 32, "TOPLEFT", 126, -573, function()
        self:SetFontSize(self.db.fontSize - 1)
        self:UpdateOptions()
    end)
    frame.larger = Button(frame, "+", 32, "TOPLEFT", 164, -573, function()
        self:SetFontSize(self.db.fontSize + 1)
        self:UpdateOptions()
    end)
    Button(frame, "重置位置", 110, "TOPRIGHT", -16, -573, function() self:ResetPosition() end)
    frame.hint = Label(frame, "", 20, -614, "GameFontHighlightSmall")
    frame.hint:SetWidth(640)
    frame.hint:SetJustifyH("LEFT")
    frame.entries, frame.page, frame.view = {}, 1, "factions"
end

function Addon:ToggleOptions()
    if not self.options then self:CreateOptions() end
    if self.options:IsShown() then
        self.options:Hide()
    else
        self:ReloadOptionsList()
        self.options:Show()
    end
end
