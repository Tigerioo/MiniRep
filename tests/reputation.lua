return function(Addon)
    local Rep = assert(Addon.Reputation, "Reputation module must be loaded")
    local keys = {
        "GetText", "UnitSex", "GetNumFactions", "GetFactionInfo", "GetFactionInfoByID",
        "ExpandFactionHeader", "CollapseFactionHeader", "C_GossipInfo", "GetTime",
    }
    local saved = {}
    for _, key in ipairs(keys) do saved[key] = _G[key] end
    local oldList, oldScanning, oldScanTime = Rep.lastList, Rep.scanning, Rep.lastScanTime
    local passed = 0
    local function check(condition, message)
        assert(condition, message)
        passed = passed + 1
    end

    local ok, failure = pcall(function()
        local standings = { "仇恨", "敌对", "冷淡", "中立", "友善", "尊敬", "崇敬", "崇拜" }
        _G.GetText = function(key) return standings[tonumber(key:match("(%d+)$"))] end
        _G.UnitSex = function() return 2 end
        _G.GetTime = function() return 25 end
        _G.C_GossipInfo = { GetFriendshipReputation = function() return nil end }
        Rep.scanning, Rep.lastList, Rep.lastScanTime = false, nil, nil

        local raw = { id = 1272, name = "皇帝少昊", standingID = 7, barMin = 21000, barMax = 42000, barValue = 29400 }
        local row, problem = Rep:Normalize(raw)
        check(not problem and row.current == 8400 and row.total == 21000 and row.percentText == "40%", "ordinary rank normalization")
        check(row.standingText == "崇敬" and row.nextStandingText == "崇拜" and not row.isFriendship, "ordinary rank labels")
        check(Rep:FormatNumber(1234567) == "1,234,567", "thousands separators")
        check(Rep:FormatPercent(405, 1000, false) == "40.5%", "one decimal percent")
        check(Rep:FormatPercent(9999, 10000, false) == "99.9%", "never round incomplete rank up to 100%")
        check(Rep:FormatPercent(21000, 21000, false) == "100%", "exact boundary is 100%")

        raw.standingID, raw.barMin, raw.barMax, raw.barValue = 6, 9000, 21000, 20950
        local before = Rep:Normalize(raw)
        raw.standingID, raw.barMin, raw.barMax, raw.barValue = 7, 21000, 42000, 21120
        local after = Rep:Normalize(raw)
        check(before.current == 11950 and before.total == 12000 and before.standingText == "尊敬", "before rank transition")
        check(after.current == 120 and after.total == 21000 and after.standingText == "崇敬", "after rank transition resets stage progress")

        local friendship = { friendshipFactionID = 1275, reaction = "朋友", reactionThreshold = 8400, nextThreshold = 16800, standing = 12600 }
        row, problem = Rep:Normalize(raw, friendship)
        check(not problem and row.isFriendship and row.current == 4200 and row.total == 8400 and row.percentText == "50%", "friendship thresholds override ordinary reputation")
        check(row.standingText == "朋友" and not row.capped, "friendship rank label")
        friendship.nextThreshold, friendship.reaction = nil, "挚友"
        row, problem = Rep:Normalize(raw, friendship)
        check(not problem and row.capped and row.percentText == "100%" and row.standingText == "挚友", "friendship maximum")

        raw.standingID, raw.barMin, raw.barMax, raw.barValue = 8, 42000, 42000, 42000
        row, problem = Rep:Normalize(raw)
        check(not problem and row.capped and row.percentText == "100%" and row.standingText == "崇拜", "ordinary maximum without fake denominator")
        raw.standingID = 7
        row, problem = Rep:Normalize(raw)
        check(problem and not row.capped and row.current == nil and row.total == nil and row.percentText == "—", "invalid zero-width threshold preserves unknown values")
        raw.barMax, raw.barValue = 63000, nil
        row, problem = Rep:Normalize(raw)
        check(problem and row.current == nil and row.percentText == "—", "missing reputation is not fabricated as zero")

        local function faction(id, name)
            return { id = id, name = name, standingID = 5, barMin = 3000, barMax = 9000, barValue = 5400 }
        end
        local nested = faction(1272, "带声望分类")
        nested.isHeader, nested.hasRep, nested.collapsed = true, true, true
        nested.children = { faction(1001, "折叠子声望") }
        local root = { id = 0, name = "熊猫人之谜", isHeader = true, collapsed = true, children = { nested, faction(1004, "同级声望") } }
        local openRoot = { id = 0, name = "已展开分类", isHeader = true, collapsed = false, children = { faction(1002, "已展开声望") } }
        local inactive = { id = 0, name = "非活动", isHeader = true, collapsed = true, children = { faction(1003, "非活动声望"), faction(1001, "重复声望") } }
        local tree = { root, openRoot, inactive }
        local function visible()
            local output = {}
            local function visit(nodes)
                for _, node in ipairs(nodes) do
                    output[#output + 1] = node
                    if node.isHeader and not node.collapsed then visit(node.children or {}) end
                end
            end
            visit(tree)
            return output
        end
        local function tuple(node)
            if not node then return nil end
            return node.name, "", node.standingID, node.barMin, node.barMax, node.barValue,
                false, false, node.isHeader, node.collapsed, node.hasRep, false, false, node.id
        end
        local function unchanged()
            return root.collapsed and nested.collapsed and inactive.collapsed and not openRoot.collapsed and #visible() == 4
        end
        local events = 0
        local function event()
            events = events + 1
            assert(Rep.scanning, "scan guard must remain true during mutation and restoration")
            local _, reentryError = Rep:GetList()
            assert(reentryError == "正在读取声望", "synchronous scan reentry must be guarded")
        end
        _G.GetNumFactions = function() return #visible() end
        local failOnID
        _G.GetFactionInfo = function(index)
            local node = visible()[index]
            if node and node.id == failOnID then error("injected read failure") end
            return tuple(node)
        end
        _G.ExpandFactionHeader = function(index)
            local node = assert(visible()[index], "expand index")
            assert(node.isHeader, "only expand headers")
            node.collapsed = false
            event()
        end
        _G.CollapseFactionHeader = function(index)
            local node = assert(visible()[index], "collapse index")
            assert(node.isHeader, "only collapse headers")
            node.collapsed = true
            event()
        end
        _G.GetFactionInfoByID = nil
        local rows
        rows, problem = Rep:GetList()
        check(not problem and #rows == 5, "all collapsed and inactive reputations included once")
        local byID = {}
        for _, entry in ipairs(rows) do
            assert(not byID[entry.id], "duplicate faction ID")
            byID[entry.id] = entry
        end
        check(byID[1272] and byID[1001] and byID[1002] and byID[1003] and byID[1004], "reputation-bearing header and inactive entries retained")
        check(unchanged() and not Rep.scanning and events == 6, "nested collapse states restored with scan reentry guarded")

        failOnID = 1001
        rows, problem = Rep:GetList()
        check(problem and problem:find("injected read failure", 1, true), "mid-scan read failure reported")
        check(unchanged() and not Rep.scanning and events == 10, "mid-scan failure still restores nested headers")
        failOnID = nil

        _G.GetFactionInfoByID = function(id)
            if id == nested.id then return tuple(nested) end
        end
        row, problem = Rep:GetByID(1272)
        check(not problem and row.id == 1272 and row.current == 2400 and row.percentText == "40%", "direct ID query returns fresh normalized data")
        check(unchanged() and events == 10, "direct ID query never changes collapse state")
        row, problem = Rep:GetByID(999999)
        check(row == nil and problem and events == 10, "unknown ID returns no invented row and does not expand headers")
    end)

    -- Restore every mocked API and cache before root-agent UI smoke starts.
    for _, key in ipairs(keys) do _G[key] = saved[key] end
    Rep.lastList, Rep.scanning, Rep.lastScanTime = oldList, oldScanning, oldScanTime
    assert(ok, failure)
    return passed
end
