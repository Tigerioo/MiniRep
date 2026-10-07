local _, Addon = ...

function Addon:ApplyPosition()
    if not self.display or self.dragging then return end
    self.display:ClearAllPoints()
    self.display:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
        self.db.x * UIParent:GetWidth(), self.db.y * UIParent:GetHeight())
end

function Addon:StopDragging()
    if not self.display or not self.dragging then return end
    self.display:StopMovingOrSizing()
    self.dragging = false
    local x, y = self.display:GetCenter()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if x and y and width > 0 and height > 0 then
        self.db.x = math.max(0, math.min(1, x / width))
        self.db.y = math.max(0, math.min(1, y / height))
    end
    self:ApplyPosition()
end

function Addon:GetDisplayText(entry)
    if not entry then return "MiniRep：右键添加关注声望" end
    local row = self.currentByID[entry.id]
    local name = row and row.name or entry.name or "所选声望"
    local daily = " |cff88eeaa· 今日 +" .. self.Reputation:FormatNumber(self.Daily:GetGain(entry.id)) .. "|r"
    if not row then return name .. " · 暂无数据" .. daily end
    local prefix = name .. " · " .. (row.standingText or "未知等级")
    if row.capped then return prefix .. "|cffffd37f（100%）|r" .. daily end
    if not row.current or not row.total or row.total <= 0 then
        return prefix .. " · 暂无数据" .. daily
    end
    return prefix .. " · |cffffd37f" .. self.Reputation:FormatNumber(row.current)
        .. " / " .. self.Reputation:FormatNumber(row.total)
        .. "（" .. row.percentText .. "）|r" .. daily
end

function Addon:ShowTooltip(owner)
    owner = owner or self.display
    local tooltip = GameTooltip
    tooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    local entry = owner.entry
    local row = entry and self.currentByID[entry.id]
    tooltip:AddLine(row and row.name or (entry and entry.name) or "MiniRep", 1, 0.82, 0)
    if row then
        tooltip:AddLine("当前等级：" .. (row.standingText or "未知等级"), 1, 1, 1)
        if row.capped then
            tooltip:AddLine("已达最高等级（100%）", 0.5, 1, 0.5)
        elseif row.current and row.total and row.total > 0 then
            tooltip:AddLine("等级进度：" .. self.Reputation:FormatNumber(row.current)
                .. " / " .. self.Reputation:FormatNumber(row.total)
                .. "（" .. row.percentText .. "）", 1, 1, 1)
            tooltip:AddLine("距离" .. (row.nextStandingText or "下一等级") .. "："
                .. self.Reputation:FormatNumber(row.total - row.current), 0.8, 0.8, 0.8)
        else
            tooltip:AddLine("暂无声望数据", 0.8, 0.8, 0.8)
        end
    elseif entry then
        tooltip:AddLine("暂无声望数据；保留当前选择。", 0.8, 0.8, 0.8)
    else
        tooltip:AddLine("可同时关注多个声望，每个声望显示一行。", 0.8, 0.8, 0.8)
    end
    if entry then
        tooltip:AddLine("今日增加：+" .. self.Reputation:FormatNumber(self.Daily:GetGain(entry.id)), 0.5, 1, 0.65)
        tooltip:AddLine("本机日期零点切换，仅统计关注期间记录到的正向变化。", 0.8, 0.8, 0.8, true)
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("右键：添加/取消关注或查看今日汇总", 0.8, 0.8, 0.8)
    tooltip:AddLine("Ctrl + 左键拖动：移动整个面板", 0.8, 0.8, 0.8)
    if not self.db.locked then tooltip:AddLine("左键拖动：调整位置", 0.8, 0.8, 0.8) end
    tooltip:Show()
end

function Addon:StartDragging()
    if not self.db.locked or IsControlKeyDown() then
        GameTooltip:Hide()
        self.dragging = true
        self.display:StartMoving()
    end
end

function Addon:CreateDisplayLine(index)
    local line = CreateFrame("Button", nil, self.display)
    self.display.lines[index] = line
    line:EnableMouse(true)
    line:EnableMouseWheel(true)
    line:RegisterForClicks("RightButtonUp")
    line:RegisterForDrag("LeftButton")
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line.text:SetPoint("LEFT", 8, 0)
    line.text:SetTextColor(1, 1, 1)
    line.text:SetWordWrap(false)
    line:SetScript("OnClick", function() self:ToggleOptions() end)
    line:SetScript("OnDragStart", function() self:StartDragging() end)
    line:SetScript("OnDragStop", function() self:StopDragging() end)
    line:SetScript("OnEnter", function(button) self:ShowTooltip(button) end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    line:SetScript("OnMouseWheel", function(_, delta) self:ScrollDisplay(delta) end)
    line:SetScript("OnHide", function(button)
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end)
    return line
end

function Addon:ScrollDisplay(delta)
    local maxOffset = math.max(0, #self.db.watched - (self.display.visibleCount or 1))
    self.display.offset = math.max(0, math.min(maxOffset, (self.display.offset or 0) - delta))
    GameTooltip:Hide()
    self:UpdateDisplay()
end

function Addon:UpdateDisplay()
    local frame = self.display
    if not frame then return end
    local font = GameFontNormal:GetFont()
    local rowHeight = self.db.fontSize + 8
    local total = #self.db.watched
    local capacity = math.max(1, math.floor((UIParent:GetHeight() - 80) / rowHeight))
    local visible = math.max(1, math.min(total, capacity))
    frame.visibleCount = visible
    frame.offset = math.max(0, math.min(frame.offset or 0, total - visible))
    local width = 80
    for index = 1, visible do
        local line = frame.lines[index] or self:CreateDisplayLine(index)
        line.entry = self.db.watched[frame.offset + index]
        line.text:SetFont(font or STANDARD_TEXT_FONT, self.db.fontSize, "OUTLINE")
        line.text:SetText(self:GetDisplayText(line.entry))
        width = math.max(width, line.text:GetStringWidth() + 16)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -4 - (index - 1) * rowHeight)
        line:Show()
    end
    for index = visible + 1, #frame.lines do frame.lines[index]:Hide() end
    for index = 1, visible do frame.lines[index]:SetSize(width, rowHeight) end
    frame.footer:SetShown(total > visible)
    if total > visible then
        frame.footer:SetText(string.format("%d–%d / %d · 滚轮查看更多", frame.offset + 1, frame.offset + visible, total))
    end
    frame:SetSize(width, visible * rowHeight + 8 + (total > visible and 20 or 0))
    frame.moveHint:SetShown(not self.db.locked)
    frame:SetShown(self.db.enabled)
    self.displayDay = self.db.daily.day
    for _, line in ipairs(frame.lines) do
        if frame:IsShown() and GameTooltip:IsOwned(line) and line:IsShown() then self:ShowTooltip(line) end
    end
end

function Addon:CreateDisplay()
    local frame = CreateFrame("Button", "MiniRepDisplay", UIParent)
    self.display = frame
    frame.lines = {}
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:RegisterForClicks("RightButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.footer:SetPoint("BOTTOM", 0, 4)
    frame.moveHint = frame:CreateTexture(nil, "BACKGROUND")
    frame.moveHint:SetAllPoints()
    frame.moveHint:SetColorTexture(0.1, 0.4, 0.5, 0.3)
    frame:SetScript("OnClick", function() self:ToggleOptions() end)
    frame:SetScript("OnDragStart", function() self:StartDragging() end)
    frame:SetScript("OnDragStop", function() self:StopDragging() end)
    frame:SetScript("OnMouseWheel", function(_, delta) self:ScrollDisplay(delta) end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnHide", function()
        self:StopDragging()
        if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
        for _, line in ipairs(frame.lines) do
            if GameTooltip:IsOwned(line) then GameTooltip:Hide() end
        end
    end)
    self:ApplyPosition()
    self:UpdateDisplay()
end
