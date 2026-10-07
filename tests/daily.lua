return function(Addon)
    local Rep, Daily = assert(Addon.Reputation), assert(Addon.Daily)
    local keys = { "date", "GetNumFactions", "GetFactionInfo", "GetFactionInfoByID",
        "ExpandFactionHeader", "CollapseFactionHeader", "C_GossipInfo", "GetTime" }
    local saved = {}
    for _, key in ipairs(keys) do saved[key] = _G[key] end
    local oldDB, oldBaselines = Daily.db, Daily.baselines
    local oldCategories, oldList, oldScanning, oldTime = Rep.categories, Rep.lastList, Rep.scanning, Rep.lastScanTime
    local passed = 0
    local function check(condition, message)
        assert(condition, message)
        passed = passed + 1
    end
    local ok, failure = pcall(function()
        local day = "2026-10-07"
        _G.date = function(format)
            assert(format == "%Y-%m-%d")
            return day
        end
        Rep.categories, Rep.lastList, Rep.scanning = {}, nil, false
        local db = {}
        Daily:Initialize(db)
        check(db.daily.day == day and #Daily:GetRows() == 0, "new daily database starts empty")
        local raw = { id = 1272, name = "皇帝少昊", standingID = 6, barMin = 9000, barMax = 21000, barValue = 20950 }
        local before = Rep:Normalize(raw)
        check(before.absoluteValue == 20950 and before.standingID == 6, "ordinary cumulative value and standing ID are retained")
        check(Daily:Observe(before) == 0, "first observation is a baseline")
        raw.standingID, raw.barMin, raw.barMax, raw.barValue = 7, 21000, 42000, 21120
        local after = Rep:Normalize(raw)
        check(after.current == 120 and Daily:Observe(after) == 170, "rank transition uses cumulative delta")
        check(Daily:Observe(after) == 0 and Daily:GetGain(1272) == 170, "repeated events do not double count")
        raw.barValue = 21000
        check(Daily:Observe(Rep:Normalize(raw)) == 0 and Daily:GetGain(1272) == 170, "loss does not subtract daily gain")
        raw.barValue = 21200
        check(Daily:Observe(Rep:Normalize(raw)) == 200 and Daily:GetGain(1272) == 370, "gain after a loss uses latest lower baseline")

        Daily:Initialize(db)
        raw.barValue = 22000
        check(Daily:Observe(Rep:Normalize(raw)) == 0 and Daily:GetGain(1272) == 370, "same-day reload preserves total without counting offline gains")
        raw.barValue = 22100
        Daily:Observe(Rep:Normalize(raw))
        Daily:Forget(1272)
        raw.barValue = 23000
        check(Daily:Observe(Rep:Normalize(raw)) == 0 and Daily:GetGain(1272) == 470, "unfollow and refollow do not count unobserved interval")
        raw.barValue = 23100
        check(Daily:Observe(Rep:Normalize(raw)) == 100 and Daily:GetGain(1272) == 570, "refollow resumes accumulation after baseline")

        day = "2026-10-08"
        check(Daily:EnsureDay() and Daily:GetGain(1272) == 0 and not Daily:EnsureDay(), "new day clears only daily gains once")
        raw.barValue = 23250
        check(Daily:Observe(Rep:Normalize(raw)) == 150 and Daily:GetGain(1272) == 150, "first gain after midnight retains live session baseline")
        day = "2026-10-09"
        raw.barValue = 23300
        check(Daily:Observe(Rep:Normalize(raw)) == 50 and Daily:GetGain(1272) == 50, "Observe rolls over even without a timer tick")
        Daily:StartSession()
        raw.barValue = 24000
        check(Daily:Observe(Rep:Normalize(raw)) == 0 and Daily:GetGain(1272) == 50, "new login ignores offline delta")

        raw.barValue = nil
        local invalid = Rep:Normalize(raw)
        check(invalid.absoluteValue == nil and Daily:Observe(invalid) == 0, "missing data invalidates baseline")
        raw.barValue = 24500
        check(Daily:Observe(Rep:Normalize(raw)) == 0 and Daily:GetGain(1272) == 50, "first valid reading after missing data does not backfill")
        Daily:Observe({ id = 1272, name = raw.name, absoluteValue = 0 / 0 })
        raw.barValue = 24700
        check(Daily:Observe(Rep:Normalize(raw)) == 0, "NaN invalidates baseline")
        raw.barValue = 43000
        invalid = Rep:Normalize(raw)
        check(invalid.absoluteValue == nil, "out-of-range ordinary values are unavailable")

        raw.standingID, raw.barMin, raw.barMax, raw.barValue = 8, 42000, 42999, 42300
        local capped = Rep:Normalize(raw)
        check(capped.capped and capped.absoluteValue == 42300, "capped ordinary row keeps actual value")
        raw.barValue = nil
        check(Rep:Normalize(raw).absoluteValue == nil, "capped row never invents missing progress")
        local friend = { friendshipFactionID = 1275, reaction = "朋友", reactionThreshold = 8400,
            nextThreshold = 16800, standing = 16700, maxRep = 42000 }
        raw.id, raw.name = 1275, "好友"
        local friendBefore = Rep:Normalize(raw, friend)
        Daily:Observe(friendBefore)
        friend.reactionThreshold, friend.nextThreshold, friend.standing = 16800, 25200, 17000
        local friendAfter = Rep:Normalize(raw, friend)
        check(friendAfter.absoluteValue == 17000 and Daily:Observe(friendAfter) == 300, "friendship rank transition uses friendship cumulative value")
        friend.nextThreshold, friend.reactionThreshold, friend.standing = nil, 42000, 42000
        check(Rep:Normalize(raw, friend).absoluteValue == 42000, "capped friendship retains actual cumulative value")
        friend.standing = 42001
        check(Rep:Normalize(raw, friend).absoluteValue == nil, "invalid capped friendship value cannot create a delta")
        local summary = Daily:GetRows()
        check(#summary == 2 and summary[1].id == 1275 and summary[1].gained == 300
            and summary[2].id == 1272 and summary[2].gained == 50, "summary sorts gains descending and includes unfollowed recorded entries")

        -- Native top-level headers, not localized faction-name guesses, classify
        -- entries. This also verifies collapse state and the direct-ID cache.
        local function faction(id, name)
            return { id = id, name = name, standingID = 5, barMin = 3000, barMax = 9000, barValue = 4500 }
        end
        local nested = faction(900002, "子分类带声望")
        nested.isHeader, nested.hasRep, nested.isChild, nested.collapsed = true, true, true, true
        nested.children = { faction(900003, "子分类声望") }
        nested.children[1].isChild = true
        local root = { id = 0, name = "熊猫人之谜", isHeader = true, collapsed = true,
            children = { faction(900001, "原生分组声望"), nested } }
        local inactive = { id = 0, name = "非活动", isHeader = true, collapsed = true,
            children = { faction(900004, "未知来源声望") } }
        local tree = { root, inactive }
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
                false, false, node.isHeader, node.collapsed, node.hasRep, false, node.isChild, node.id
        end
        _G.GetTime = function() return 100 end
        _G.C_GossipInfo = { GetFriendshipReputation = function() return nil end }
        _G.GetNumFactions = function() return #visible() end
        _G.GetFactionInfo = function(index) return tuple(visible()[index]) end
        _G.ExpandFactionHeader = function(index) visible()[index].collapsed = false end
        _G.CollapseFactionHeader = function(index) visible()[index].collapsed = true end
        local rows, problem = Rep:GetList()
        local byID = {}
        for _, row in ipairs(rows) do byID[row.id] = row end
        check(not problem and #rows == 4 and root.collapsed and nested.collapsed and inactive.collapsed,
            "category scan restores all collapsed headers")
        check(byID[900001].category == "熊猫人之谜" and byID[900002].category == "熊猫人之谜"
            and byID[900003].category == "熊猫人之谜", "child headers retain native top-level category")
        check(byID[900004].category == "非活动" and byID[900001].categoryOrder < byID[900004].categoryOrder,
            "unknown inactive entries retain native category and native category order")
        _G.GetFactionInfoByID = function(id)
            if id == 900003 then return tuple(nested.children[1]) end
        end
        local direct = Rep:GetByID(900003)
        check(direct.category == "熊猫人之谜" and direct.categoryOrder == byID[900003].categoryOrder,
            "direct-ID refresh preserves scanned category metadata")
        check(Rep:Normalize(faction(900099, "尚未扫描声望")).category == "未分类", "unscanned unknown faction is never guessed as an expansion")
    end)
    for _, key in ipairs(keys) do _G[key] = saved[key] end
    Daily.db, Daily.baselines = oldDB, oldBaselines
    Rep.categories, Rep.lastList, Rep.scanning, Rep.lastScanTime = oldCategories, oldList, oldScanning, oldTime
    assert(ok, failure)
    return passed
end
