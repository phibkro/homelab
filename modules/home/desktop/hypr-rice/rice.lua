return function(hl, layout_path, native_layout)
    local layout = dofile(layout_path)
    local workspace_state = {}
    local NOTICE_INTERVAL_SECONDS = 5

    local function identity(workspace)
        if not workspace then return nil end
        local kind = workspace.special and "special" or "regular"
        return {
            key = table.concat({ kind, tostring(workspace.id), workspace.name }, "\0"),
            kind = kind,
            id = workspace.id,
            name = workspace.name,
            selector = workspace.config_name,
            workspace = workspace,
        }
    end

    local function same_identity(left, right)
        return left
            and right
            and left.kind == right.kind
            and left.id == right.id
            and left.name == right.name
    end

    local function active_workspace()
        local active_window = hl.get_active_window()
        if active_window and active_window.workspace then
            return active_window.workspace
        end

        local monitor = hl.get_active_monitor()
        local special = hl.get_active_special_workspace(monitor)
        if special then return special end
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

    local function mapped_tiled_count(workspace)
        return #hl.get_windows({
            workspace = workspace,
            mapped = true,
            floating = false,
        })
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

    local function notify_mismatch(state, actual)
        local now = os.time()
        if state.last_notice_at and now - state.last_notice_at < NOTICE_INTERVAL_SECONDS then
            return
        end
        state.last_notice_at = now
        hl.notification.create({
            text = "rice layout expects " .. #state.grid.areas .. " targets; using " .. actual .. " equal columns",
            duration = 3000,
            icon = "warning",
        })
    end

    hl.layout.register("rice", {
        recalculate = function(ctx)
            if #ctx.targets == 0 then return end

            local current = identity(workspace_from_targets(ctx.targets))
            local state = current and workspace_state[current.key]
            if not state or not same_identity(state.identity, current) then
                place_equal_columns(ctx)
                return
            end

            if #ctx.targets ~= #state.grid.areas then
                notify_mismatch(state, #ctx.targets)
                place_equal_columns(ctx)
                return
            end

            state.last_notice_at = nil
            local boxes = layout.boxes(state.grid, ctx.area)
            for index, target in ipairs(ctx.targets) do
                local box = boxes[index]
                target:place({ x = box.x, y = box.y, w = box.w, h = box.h })
            end
        end,
    })

    hl.on("workspace.removed", function(removed)
        for key, state in pairs(workspace_state) do
            if state.identity.workspace == removed then
                workspace_state[key] = nil
            end
        end
    end)

    _G.hypr_rice_apply_hex = function(action_hex, expression_hex, columns_hex, rows_hex)
        local action = decode_hex(action_hex)
        local workspace = active_workspace()
        if not workspace then
            error("hypr-rice: no active workspace", 0)
        end
        local ws_identity = identity(workspace)

        if action == "reset" then
            workspace_state[ws_identity.key] = nil
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

        local valid, arity_error = layout.validate_arity(grid, mapped_tiled_count(workspace))
        if not valid then error("hypr-rice: " .. arity_error, 0) end

        workspace_state[ws_identity.key] = {
            identity = ws_identity,
            expression = expression,
            columns = options.columns,
            rows = options.rows,
            grid = grid,
        }
        hl.workspace_rule({
            workspace = ws_identity.selector,
            layout = "lua:rice",
        })
        return "ok"
    end
end
