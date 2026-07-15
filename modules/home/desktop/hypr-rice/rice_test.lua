local layout_path = arg[1]
local adapter_path = arg[2]

local registered
local rules = {}
local notices = {}
local active_window
local active_special
local active_regular

local hl
hl = {
    layout = {
        register = function(name, provider)
            assert(name == "rice")
            registered = provider
        end,
    },
    get_active_window = function() return active_window end,
    get_active_monitor = function() return {} end,
    get_active_special_workspace = function() return active_special end,
    get_active_workspace = function() return active_regular end,
    get_windows = function(filter)
        local result = {}
        for _, window in ipairs(filter.workspace._windows or {}) do
            if window.mapped and not window.floating then
                result[#result + 1] = window
            end
        end
        return result
    end,
    workspace_rule = function(rule) rules[#rules + 1] = rule end,
    notification = {
        create = function(notice) notices[#notices + 1] = notice end,
    },
    on = function(name, callback)
        assert(name == "workspace.removed")
        hl._workspace_removed = callback
    end,
}

local function workspace(id, name, special, count, groups)
    local ws = {
        id = id,
        name = name,
        special = special,
        groups = groups or 0,
        config_name = special and name or (id > 0 and tostring(id) or "name:" .. name),
        _windows = {},
    }
    for _ = 1, count do
        ws._windows[#ws._windows + 1] = { workspace = ws, mapped = true, floating = false }
    end
    return ws
end

local function hex(value)
    return (value:gsub(".", function(char) return string.format("%02x", string.byte(char)) end))
end

local function apply(expression, columns, rows)
    return _G.hypr_rice_apply_hex(hex("apply"), hex(expression), hex(columns or ""), hex(rows or ""))
end

local function reset()
    return _G.hypr_rice_apply_hex(hex("reset"), "", "", "")
end

local function rejects(fn, fragment)
    local ok, err = pcall(fn)
    assert(not ok, "expected rejection")
    assert(tostring(err):find(fragment, 1, true), tostring(err))
end

local function target(ws)
    local placed
    return {
        window = { workspace = ws },
        place = function(_, box) placed = box end,
        placed = function() return placed end,
    }
end

local install = assert(loadfile(adapter_path))()
install(hl, layout_path, "dwindle")
assert(registered and type(registered.recalculate) == "function")
assert(type(_G.hypr_rice_apply_hex) == "function")

local regular = workspace(3, "3", false, 3)
local special = workspace(-99, "special:notes", true, 3)
local focused = workspace(-5, "named", false, 3)
active_regular = regular
active_special = special
active_window = { workspace = focused }

assert(apply("1 2 1") == "ok")
assert(#rules == 1)
assert(rules[1].workspace == "name:named")
assert(rules[1].layout == "lua:rice")

active_window = nil
assert(apply("1 1 1") == "ok")
assert(rules[#rules].workspace == "special:notes")
active_special = nil
assert(apply("1 1 1") == "ok")
assert(rules[#rules].workspace == "3")

local before = #rules
rejects(function() apply("1 1") end, "received 3 targets")
assert(#rules == before, "arity failure mutated workspace rules")
rejects(function() apply("not valid") end, "weight must be a decimal")
assert(#rules == before, "syntax failure mutated workspace rules")
regular.groups = 1
rejects(function() apply("1 1 1") end, "grouped workspaces")
assert(#rules == before, "group rejection mutated workspace rules")
regular.groups = 0
rejects(function() _G.hypr_rice_apply_hex("zz", "", "", "") end, "invalid hex")

local a, b, c = target(regular), target(regular), target(regular)
registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { a, b, c },
})
assert(a.placed().w == 40 and b.placed().w == 40 and c.placed().x == 80)

assert(apply("1 2 1") == "ok")
registered.recalculate({
    area = { x = 10, y = 20, w = 100, h = 40 },
    targets = { a, b, c },
})
assert(a.placed().x == 10 and a.placed().w == 25)
assert(b.placed().x == 35 and b.placed().w == 50)
assert(c.placed().x == 85 and c.placed().w == 25)

local d = target(regular)
registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { a, b, c, d },
})
assert(a.placed().w == 30 and d.placed().x == 90)
assert(#notices == 1)
assert(notices[1].icon == "warning")
registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { a, b, c, d },
})
assert(#notices == 1, "target drift notification was not throttled")

registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { a, b, c },
})
assert(a.placed().w == 30 and b.placed().w == 60 and c.placed().x == 90)

assert(reset() == "ok")
assert(rules[#rules].workspace == "3")
assert(rules[#rules].layout == "dwindle")

hl._workspace_removed(regular)
print("rice adapter tests passed")
