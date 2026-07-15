local M = {}

local MAX_INPUT_BYTES = 4096
local MAX_TRACKS = 64
local MAX_CELLS = 4096
local MAX_WEIGHT = 1000000

local function parse_number(token)
    if not token:match("^%d+$") and not token:match("^%d+%.%d+$") then
        return nil
    end

    local value = tonumber(token)
    if not value or value <= 0 or value > MAX_WEIGHT then
        return nil
    end
    return value
end

local function tokens(expression)
    if expression == "" or expression:match("^[ \t]") or expression:match("[ \t]$") then
        return nil
    end

    local result = {}
    local position = 1
    while position <= #expression do
        local first, last = expression:find("[^ \t]+", position)
        if first ~= position then
            return nil
        end
        result[#result + 1] = expression:sub(first, last)
        position = last + 1
        if position <= #expression then
            local _, separator_end = expression:find("^[ \t]+", position)
            if not separator_end then
                return nil
            end
            position = separator_end + 1
        end
    end
    return result
end

local function parse_weights(expression)
    if type(expression) ~= "string" or #expression > MAX_INPUT_BYTES then
        return nil, "weight expression must be at most 4096 bytes"
    end

    expression = expression:gsub(
        "repeat%([ \t]*(%d+%.?%d*)[ \t]*,[ \t]*(%d+)[ \t]*%)",
        "repeat(%1,%2)"
    )

    local expressions = tokens(expression)
    if not expressions then
        return nil, "invalid weight expression"
    end

    local weights = {}
    for _, token in ipairs(expressions) do
        local weight_token, count_token = token:match("^repeat%(([^,]+),([^,]+)%)$")
        local weight
        local count = 1

        if weight_token then
            weight = parse_number(weight_token)
            if not count_token:match("^%d+$") then
                return nil, "invalid repeat count"
            end
            count = tonumber(count_token)
            if count < 1 or count > MAX_TRACKS then
                return nil, "repeat count must be in 1..64"
            end
        else
            weight = parse_number(token)
        end

        if not weight then
            return nil, "weight must be a decimal greater than zero and at most 1000000"
        end
        if #weights + count > MAX_TRACKS then
            return nil, "weight expansion exceeds 64 tracks"
        end
        for _ = 1, count do
            weights[#weights + 1] = weight
        end
    end

    return weights
end

local function parse_area_grid(expression, options)
    local row_texts = {}
    local start = 1
    while true do
        local separator = expression:find(";", start, true)
        if not separator then
            row_texts[#row_texts + 1] = expression:sub(start)
            break
        end
        row_texts[#row_texts + 1] = expression:sub(start, separator - 1)
        start = separator + 1
    end

    if #row_texts < 2 or #row_texts > MAX_TRACKS then
        return nil, "area grid must contain 2..64 rows"
    end

    local cells = {}
    local column_count
    local area_order = {}
    local by_name = {}

    for row_index, row_text in ipairs(row_texts) do
        row_text = row_text:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
        local row = tokens(row_text)
        if not row or #row > MAX_TRACKS then
            return nil, "invalid area row"
        end
        if column_count and #row ~= column_count then
            return nil, "area rows must have equal column counts"
        end
        column_count = #row
        cells[row_index] = row

        for column_index, name in ipairs(row) do
            if name ~= "." then
                if not name:match("^[A-Za-z][A-Za-z0-9_-]*$") then
                    return nil, "invalid area name"
                end
                local area = by_name[name]
                if not area then
                    if #area_order == MAX_TRACKS then
                        return nil, "area grid exceeds 64 named areas"
                    end
                    area = {
                        name = name,
                        row = row_index,
                        column = column_index,
                        row_end = row_index,
                        column_end = column_index,
                    }
                    by_name[name] = area
                    area_order[#area_order + 1] = area
                else
                    area.row_end = math.max(area.row_end, row_index)
                    area.column_end = math.max(area.column_end, column_index)
                end
            end
        end
    end

    if #row_texts * column_count > MAX_CELLS then
        return nil, "area grid exceeds 4096 cells"
    end

    local columns = {}
    local rows = {}
    for _ = 1, column_count do columns[#columns + 1] = 1 end
    for _ = 1, #row_texts do rows[#rows + 1] = 1 end

    if options.columns then
        local err
        columns, err = parse_weights(options.columns)
        if not columns then return nil, err end
    end
    if options.rows then
        local err
        rows, err = parse_weights(options.rows)
        if not rows then return nil, err end
    end
    if #columns ~= column_count then
        return nil, "column track count must match the area grid"
    end
    if #rows ~= #row_texts then
        return nil, "row track count must match the area grid"
    end

    for _, area in ipairs(area_order) do
        for row = area.row, area.row_end do
            for column = area.column, area.column_end do
                if cells[row][column] ~= area.name then
                    return nil, "area " .. area.name .. " must form one complete rectangle"
                end
            end
        end
        area.row_span = area.row_end - area.row + 1
        area.column_span = area.column_end - area.column + 1
        area.row_end = nil
        area.column_end = nil
    end

    return {
        columns = columns,
        rows = rows,
        areas = area_order,
    }
end

local function track_edges(weights, origin, extent)
    local total = 0
    for _, weight in ipairs(weights) do
        total = total + weight
    end

    local edges = { origin }
    local cumulative = 0
    for index, weight in ipairs(weights) do
        cumulative = cumulative + weight
        edges[index + 1] = index == #weights and origin + extent
            or origin + extent * cumulative / total
    end
    return edges
end

function M.boxes(grid, area)
    local column_edges = track_edges(grid.columns, area.x, area.w)
    local row_edges = track_edges(grid.rows, area.y, area.h)
    local boxes = {}

    for index, named_area in ipairs(grid.areas) do
        local right = named_area.column + named_area.column_span
        local bottom = named_area.row + named_area.row_span
        boxes[index] = {
            name = named_area.name,
            x = column_edges[named_area.column],
            y = row_edges[named_area.row],
            w = column_edges[right] - column_edges[named_area.column],
            h = row_edges[bottom] - row_edges[named_area.row],
        }
    end

    return boxes
end

function M.validate_arity(grid, target_count)
    if type(target_count) ~= "number" or target_count < 0 or target_count % 1 ~= 0 then
        return nil, "target count must be a non-negative integer"
    end
    if #grid.areas ~= target_count then
        return nil, "layout has " .. #grid.areas .. " areas but received " .. target_count .. " targets"
    end
    return true
end

function M.parse(expression, options)
    options = options or {}
    if type(expression) ~= "string" or #expression > MAX_INPUT_BYTES then
        return nil, "layout expression must be a string of at most 4096 bytes"
    end
    if expression == "" or expression:match("^[ \t]") or expression:match("[ \t]$") then
        return nil, "layout expression must not be empty or padded"
    end

    if expression:find(";", 1, true) then
        return parse_area_grid(expression, options)
    end
    if options.columns or options.rows then
        return nil, "track overrides require an area grid"
    end

    local columns, err = parse_weights(expression)
    if not columns then
        return nil, err
    end

    local areas = {}
    for index = 1, #columns do
        areas[index] = {
            name = tostring(index),
            row = 1,
            column = index,
            row_span = 1,
            column_span = 1,
        }
    end

    return {
        columns = columns,
        rows = { 1 },
        areas = areas,
    }
end

return M
