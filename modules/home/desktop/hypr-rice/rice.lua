return function(hl, layout_path, native_layout)
    local layout = dofile(layout_path)
    local workspace_state = { regular = {}, special = {} }
    local NOTICE_INTERVAL_SECONDS = 5

    local function identity(workspace)
        if not workspace then return nil end
        local kind = workspace.special and "special" or "regular"
        return {
            kind = kind,
            id = workspace.id,
            name = workspace.name,
            selector = workspace.config_name,
            workspace = workspace,
        }
    end

    local function state_for(ws_identity)
        if not ws_identity then return nil end
        return workspace_state[ws_identity.kind][ws_identity.id]
    end

    local function set_state(ws_identity, state)
        workspace_state[ws_identity.kind][ws_identity.id] = state
    end

    local function same_identity(left, right)
        return left and right and left.kind == right.kind and left.id == right.id
    end

    local function interaction_workspace()
        local monitor = hl.get_active_monitor()
        if not monitor then return nil end

        local special = hl.get_active_special_workspace(monitor)
        if special then return special end

        local active_window = hl.get_active_window()
        if active_window and active_window.monitor == monitor and active_window.workspace then
            return active_window.workspace
        end
        return hl.get_active_workspace(monitor)
    end

    local function decode_hex(encoded)
        if type(encoded) ~= "string" or #encoded % 2 ~= 0 or encoded:find("[^0-9a-fA-F]") then
            error("hypr-rice: invalid hex argument", 0)
        end
        return (encoded:gsub("..", function(pair)
            return string.char(tonumber(pair, 16))
        end))
    end

    local function usable_stable_id(value)
        return type(value) == "number" and value > 0 and value % 1 == 0
    end

    local function capture_windows(workspace)
        local windows = hl.get_windows({
            workspace = workspace,
            mapped = true,
            floating = false,
        })
        local seen = {}

        for _, window in ipairs(windows) do
            if window.hidden then
                return nil, "hidden windows are not supported"
            end
            if not usable_stable_id(window.stable_id) then
                return nil, "every tiled window must expose a positive integer stable_id"
            end
            if seen[window.stable_id] then
                return nil, "tiled windows must expose unique stable_id values"
            end
            if not window.at or type(window.at.x) ~= "number" or type(window.at.y) ~= "number" then
                return nil, "every tiled window must expose visual coordinates"
            end
            seen[window.stable_id] = true
        end

        table.sort(windows, function(left, right)
            if left.at.y ~= right.at.y then return left.at.y < right.at.y end
            if left.at.x ~= right.at.x then return left.at.x < right.at.x end
            return left.stable_id < right.stable_id
        end)
        return windows
    end

    local function captured_order(windows)
        local rank_by_stable_id = {}
        local expected_ids = {}
        for rank, window in ipairs(windows) do
            rank_by_stable_id[window.stable_id] = rank
            expected_ids[window.stable_id] = true
        end
        return rank_by_stable_id, expected_ids
    end

    local function place_equal_columns(ctx)
        local count = #ctx.targets
        for index, target in ipairs(ctx.targets) do
            target:place({
                x = ctx.area.x + ctx.area.w * (index - 1) / count,
                y = ctx.area.y,
                w = ctx.area.w / count,
                h = ctx.area.h,
            })
        end
    end

    local function workspace_from_targets(targets)
        for _, target in ipairs(targets) do
            if target.window and target.window.workspace then
                return target.window.workspace
            end
        end
    end

    local function notify_mismatch(state, actual, detail)
        if not same_identity(state.identity, identity(interaction_workspace())) then return end

        local now = os.time()
        if state.last_notice_at and now - state.last_notice_at < NOTICE_INTERVAL_SECONDS then
            return
        end
        state.last_notice_at = now
        local text = "rice layout expects " .. #state.grid.areas .. " targets; using " .. actual .. " equal columns"
        if detail then text = text .. " (" .. detail .. ")" end
        hl.notification.create({
            text = text,
            duration = 3000,
            icon = "warning",
        })
    end

    local function target_entries(targets)
        local entries = {}
        local ids = {}
        for index, target in ipairs(targets) do
            local stable_id = target.window and target.window.stable_id
            if not usable_stable_id(stable_id) or ids[stable_id] then
                return nil
            end
            ids[stable_id] = true
            entries[#entries + 1] = {
                target = target,
                stable_id = stable_id,
                source_index = index,
            }
        end
        return entries, ids
    end

    local function same_id_set(left, right)
        for stable_id in pairs(left) do
            if not right[stable_id] then return false end
        end
        for stable_id in pairs(right) do
            if not left[stable_id] then return false end
        end
        return true
    end

    local function order_targets(state, targets)
        local entries, ids = target_entries(targets)
        if not entries then return nil, "invalid target identity" end

        if not state.confirmed then
            if not same_id_set(state.expected_ids, ids) then
                return nil, "target identities changed before activation"
            end
            state.confirmed = true
        end

        table.sort(entries, function(left, right)
            local left_rank = state.rank_by_stable_id[left.stable_id]
            local right_rank = state.rank_by_stable_id[right.stable_id]
            if left_rank and right_rank then return left_rank < right_rank end
            if left_rank then return true end
            if right_rank then return false end
            if left.stable_id ~= right.stable_id then return left.stable_id < right.stable_id end
            return left.source_index < right.source_index
        end)
        return entries
    end

    hl.layout.register("rice", {
        recalculate = function(ctx)
            if #ctx.targets == 0 then return end

            local current = identity(workspace_from_targets(ctx.targets))
            local state = state_for(current)
            if not state then
                place_equal_columns(ctx)
                return
            end

            if #ctx.targets ~= #state.grid.areas then
                notify_mismatch(state, #ctx.targets)
                place_equal_columns(ctx)
                return
            end

            local ordered, order_error = order_targets(state, ctx.targets)
            if not ordered then
                notify_mismatch(state, #ctx.targets, order_error)
                place_equal_columns(ctx)
                return
            end

            state.last_notice_at = nil
            local boxes = layout.boxes(state.grid, ctx.area)
            for index, entry in ipairs(ordered) do
                local box = boxes[index]
                entry.target:place({ x = box.x, y = box.y, w = box.w, h = box.h })
            end
        end,
    })

    hl.on("workspace.removed", function(removed)
        for _, states in pairs(workspace_state) do
            for id, state in pairs(states) do
                if state.identity.workspace == removed then
                    states[id] = nil
                end
            end
        end
    end)

    _G.hypr_rice_apply_hex = function(action_hex, expression_hex, columns_hex, rows_hex)
        local action = decode_hex(action_hex)
        local workspace = interaction_workspace()
        if not workspace then
            error("hypr-rice: no active workspace", 0)
        end
        local ws_identity = identity(workspace)

        if action == "reset" then
            set_state(ws_identity, nil)
            hl.workspace_rule({
                workspace = ws_identity.selector,
                layout = native_layout,
            })
            return "ok"
        end
        if action ~= "apply" then
            error("hypr-rice: unknown action", 0)
        end

        local expression = decode_hex(expression_hex)
        local columns = decode_hex(columns_hex)
        local rows = decode_hex(rows_hex)
        local options = {
            columns = columns ~= "" and columns or nil,
            rows = rows ~= "" and rows or nil,
        }

        local grid, parse_error = layout.parse(expression, options)
        if not grid then error("hypr-rice: " .. parse_error, 0) end
        if workspace.groups ~= 0 then
            error("hypr-rice: grouped workspaces are not supported", 0)
        end

        local windows, capture_error = capture_windows(workspace)
        if not windows then error("hypr-rice: " .. capture_error, 0) end
        local valid, arity_error = layout.validate_arity(grid, #windows)
        if not valid then error("hypr-rice: " .. arity_error, 0) end
        local rank_by_stable_id, expected_ids = captured_order(windows)

        set_state(ws_identity, {
            identity = ws_identity,
            expression = expression,
            columns = options.columns,
            rows = options.rows,
            grid = grid,
            rank_by_stable_id = rank_by_stable_id,
            expected_ids = expected_ids,
            confirmed = false,
        })
        hl.workspace_rule({
            workspace = ws_identity.selector,
            layout = "lua:rice",
        })
        return "ok"
    end
end
