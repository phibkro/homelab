local layout_path = arg[1]
local adapter_path = arg[2]

local registered
local rules = {}
local notices = {}
local active_window
local active_special
local active_regular
local active_monitor = {}

local hl
hl = {
    layout = {
        register = function(name, provider)
            assert(name == "rice")
            registered = provider
        end,
    },
    get_active_window = function() return active_window end,
    get_active_monitor = function() return active_monitor end,
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

local next_stable_id = 1

local function add_window(ws, x, y, overrides)
    local window = {
        workspace = ws,
        monitor = active_monitor,
        mapped = true,
        floating = false,
        hidden = false,
        stable_id = next_stable_id,
        at = { x = x or 0, y = y or 0 },
    }
    next_stable_id = next_stable_id + 1
    for key, value in pairs(overrides or {}) do window[key] = value end
    ws._windows[#ws._windows + 1] = window
    return window
end

local function workspace(id, name, special, count, groups)
    local ws = {
        id = id,
        name = name,
        special = special,
        groups = groups or 0,
        config_name = special and name or (id > 0 and tostring(id) or "name:" .. name),
        _windows = {},
    }
    for index = 1, count do add_window(ws, (index - 1) * 100, 0) end
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

local function target(window)
    local placed
    return {
        window = window,
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
active_window = { workspace = focused, monitor = active_monitor }

assert(apply("1 2 1") == "ok")
assert(#rules == 1)
assert(rules[1].workspace == "special:notes")
assert(rules[1].layout == "lua:rice")

active_special = nil
assert(apply("1 1 1") == "ok")
assert(rules[#rules].workspace == "name:named")
active_window = { workspace = focused, monitor = {} }
assert(apply("1 1 1") == "ok")
assert(rules[#rules].workspace == "3")
active_window = nil

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

local ordered = workspace(8, "8", false, 0)
local left = add_window(ordered, 0, 0, { stable_id = 30 })
local middle = add_window(ordered, 100, 0, { stable_id = 10 })
local right = add_window(ordered, 200, 0, { stable_id = 20 })
ordered._windows = { right, left, middle }
active_window = { workspace = ordered, monitor = active_monitor }
active_special = nil
assert(apply("1 2 1") == "ok")
local right_target = target(right)
local middle_target = target(middle)
local left_target = target(left)
registered.recalculate({
    area = { x = 0, y = 0, w = 100, h = 40 },
    targets = { right_target, middle_target, left_target },
})
assert(left_target.placed().x == 0 and left_target.placed().w == 25)
assert(middle_target.placed().x == 25 and middle_target.placed().w == 50)
assert(right_target.placed().x == 75 and right_target.placed().w == 25)

registered.recalculate({
    area = { x = 0, y = 0, w = 100, h = 40 },
    targets = { left_target, right_target, middle_target },
})
assert(left_target.placed().x == 0 and middle_target.placed().x == 25 and right_target.placed().x == 75)

right.at.x = 0
left.at.x = 100
middle.at.x = 200
assert(apply("1 2 1") == "ok")
registered.recalculate({
    area = { x = 0, y = 0, w = 100, h = 40 },
    targets = { left_target, middle_target, right_target },
})
assert(right_target.placed().x == 0 and left_target.placed().x == 25 and middle_target.placed().x == 75)

local unknown = add_window(ordered, 300, 0, { stable_id = 40 })
local unknown_target = target(unknown)
registered.recalculate({
    area = { x = 0, y = 0, w = 100, h = 40 },
    targets = { unknown_target, left_target, right_target },
})
assert(right_target.placed().x == 0 and left_target.placed().x == 25 and unknown_target.placed().x == 75)

local unconfirmed = workspace(9, "9", false, 3)
active_window = { workspace = unconfirmed, monitor = active_monitor }
assert(apply("1 2 1") == "ok")
local unexpected_window = add_window(unconfirmed, 300, 0, { stable_id = 99 })
local unconfirmed_a = target(unconfirmed._windows[1])
local unconfirmed_b = target(unconfirmed._windows[2])
local unexpected_target = target(unexpected_window)
local notice_count = #notices
registered.recalculate({
    area = { x = 0, y = 0, w = 90, h = 40 },
    targets = { unconfirmed_a, unconfirmed_b, unexpected_target },
})
assert(unconfirmed_a.placed().w == 30 and unexpected_target.placed().x == 60)
assert(#notices == notice_count + 1)

local invalid_capture = workspace(10, "10", false, 0)
add_window(invalid_capture, 0, 0, { hidden = true })
active_window = { workspace = invalid_capture, monitor = active_monitor }
before = #rules
rejects(function() apply("1") end, "hidden windows")
assert(#rules == before)
invalid_capture._windows[1].hidden = false
invalid_capture._windows[1].stable_id = 0
rejects(function() apply("1") end, "positive integer stable_id")
assert(#rules == before)
local duplicate = add_window(invalid_capture, 100, 0, { stable_id = 50 })
invalid_capture._windows[1].stable_id = duplicate.stable_id
rejects(function() apply("1 1") end, "unique stable_id")
assert(#rules == before)

active_window = nil
active_regular = regular
local a = target(regular._windows[1])
local b = target(regular._windows[2])
local c = target(regular._windows[3])
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

local replacement = add_window(regular, 300, 0)
local d = target(replacement)
local regular_notice_count = #notices
active_special = special
registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { a, b, c, d },
})
assert(a.placed().w == 30 and d.placed().x == 90)
assert(#notices == regular_notice_count, "background mismatch emitted a notification")
active_special = nil
registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { a, b, c, d },
})
assert(#notices == regular_notice_count + 1)
assert(notices[#notices].icon == "warning")
registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { a, b, c, d },
})
assert(#notices == regular_notice_count + 1, "target drift notification was not throttled")

registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { a, b, c },
})
assert(a.placed().w == 30 and b.placed().w == 60 and c.placed().x == 90)

regular.name = "renamed"
registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { c, a, b },
})
assert(a.placed().w == 30 and b.placed().w == 60 and c.placed().x == 90)

local collision_special = workspace(3, "special:collision", true, 3)
active_special = collision_special
assert(apply("1 1 1") == "ok")
local special_a = target(collision_special._windows[1])
local special_b = target(collision_special._windows[2])
local special_c = target(collision_special._windows[3])
registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { special_c, special_a, special_b },
})
assert(special_a.placed().x == 0 and special_b.placed().x == 40 and special_c.placed().x == 80)
active_special = nil
registered.recalculate({
    area = { x = 0, y = 0, w = 120, h = 50 },
    targets = { b, c, a },
})
assert(a.placed().w == 30 and b.placed().w == 60 and c.placed().x == 90)

assert(reset() == "ok")
assert(rules[#rules].workspace == "3")
assert(rules[#rules].layout == "dwindle")

hl._workspace_removed(regular)
print("rice adapter tests passed")
