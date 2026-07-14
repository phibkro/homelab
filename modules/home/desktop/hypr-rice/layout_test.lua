local layout = dofile(arg[1])

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function test_weighted_rows_normalize_to_a_grid()
    local grid = assert(layout.parse("1 2 1"))

    equal(#grid.columns, 3)
    equal(grid.columns[1], 1)
    equal(grid.columns[2], 2)
    equal(grid.columns[3], 1)
    equal(#grid.rows, 1)
    equal(grid.rows[1], 1)
    equal(#grid.areas, 3)
    equal(grid.areas[1].name, "1")
    equal(grid.areas[2].name, "2")
    equal(grid.areas[3].name, "3")
end

local function test_repeat_expands_inside_weighted_rows()
    local grid = assert(layout.parse("1 repeat(2,3) 1"))

    equal(#grid.columns, 5)
    equal(grid.columns[1], 1)
    equal(grid.columns[2], 2)
    equal(grid.columns[3], 2)
    equal(grid.columns[4], 2)
    equal(grid.columns[5], 1)
end

local function test_area_grids_normalize_named_rectangles_in_first_appearance_order()
    local grid = assert(layout.parse("a b; a .; c c"))

    equal(#grid.columns, 2)
    equal(grid.columns[1], 1)
    equal(grid.columns[2], 1)
    equal(#grid.rows, 3)
    equal(#grid.areas, 3)
    equal(grid.areas[1].name, "a")
    equal(grid.areas[1].row, 1)
    equal(grid.areas[1].column, 1)
    equal(grid.areas[1].row_span, 2)
    equal(grid.areas[1].column_span, 1)
    equal(grid.areas[2].name, "b")
    equal(grid.areas[3].name, "c")
    equal(grid.areas[3].row, 3)
    equal(grid.areas[3].column, 1)
    equal(grid.areas[3].column_span, 2)
end

local function rejected(expression, options)
    local value, err = layout.parse(expression, options)
    if value ~= nil or type(err) ~= "string" or err == "" then
        error("expected expression to be rejected: " .. string.format("%q", expression), 2)
    end
end

local function test_malformed_empty_and_oversized_input_is_rejected()
    local invalid = {
        "",
        " ",
        " 1",
        "1 ",
        "1\n2",
        "0",
        "1000001",
        "-1",
        "+1",
        ".5",
        "1.",
        "1e2",
        "repeat(1,0)",
        "repeat(1,65)",
        "repeat(1, 2)",
        "repeat(1,64) 1",
        "a b;",
        "a 1; a b",
        "a @; a b",
    }

    for _, expression in ipairs(invalid) do
        rejected(expression)
    end
    rejected(string.rep("1", 4097))

    local too_many_columns = {}
    for _ = 1, 65 do too_many_columns[#too_many_columns + 1] = "a" end
    rejected(table.concat(too_many_columns, " ") .. "; " .. table.concat(too_many_columns, " "))

    local too_many_rows = {}
    for _ = 1, 65 do too_many_rows[#too_many_rows + 1] = "a" end
    rejected(table.concat(too_many_rows, ";"))

    local too_many_areas = {}
    for index = 1, 65 do too_many_areas[index] = "a" .. index end
    rejected(table.concat(too_many_areas, " ") .. "; " .. table.concat(too_many_areas, " "))
end

local function test_inconsistent_and_non_rectangular_area_grids_are_rejected()
    rejected("a b; a")
    rejected("a a; a b")
    rejected("a b a; c c c")
end

local function test_bad_track_weights_and_dimension_mismatches_are_rejected()
    rejected("a b; a .; c c", { columns = "1" })
    rejected("a b; a .; c c", { rows = "1 1" })
    rejected("a b; a .; c c", { columns = "0 1" })
    rejected("a b; a .; c c", { rows = "repeat(1,0) 1 1" })
end

local function test_target_arity_must_match_normalized_areas()
    local grid = assert(layout.parse("a b; a .; c c"))
    assert(layout.validate_arity(grid, 3))

    local valid, err = layout.validate_arity(grid, 2)
    equal(valid, nil)
    if type(err) ~= "string" or err == "" then
        error("arity mismatch must return an error")
    end
end

local function close(actual, expected, message)
    if math.abs(actual - expected) > 1e-9 then
        error((message or "numbers differ") .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

local function test_boxes_use_cumulative_edges_cover_the_workarea_and_skip_empty_cells()
    local row = assert(layout.parse("1 2 1"))
    local boxes = assert(layout.boxes(row, { x = 10, y = 20, width = 100, height = 40 }))

    equal(#boxes, 3)
    close(boxes[1].x, 10)
    close(boxes[1].width, 25)
    close(boxes[1].x + boxes[1].width, boxes[2].x, "first shared edge")
    close(boxes[2].width, 50)
    close(boxes[2].x + boxes[2].width, boxes[3].x, "second shared edge")
    close(boxes[3].x + boxes[3].width, 110, "right workarea edge")
    close(boxes[1].width + boxes[2].width + boxes[3].width, 100, "workarea coverage")

    local grid = assert(layout.parse("a b; a .; c c", {
        columns = "1 2",
        rows = "1 1 3",
    }))
    boxes = assert(layout.boxes(grid, { x = 5, y = 7, width = 120, height = 100 }))

    equal(#boxes, 3)
    equal(boxes[1].name, "a")
    close(boxes[1].x, 5)
    close(boxes[1].y, 7)
    close(boxes[1].width, 40)
    close(boxes[1].height, 40)
    equal(boxes[2].name, "b")
    close(boxes[2].x, 45)
    close(boxes[2].height, 20)
    equal(boxes[3].name, "c")
    close(boxes[3].x, 5)
    close(boxes[3].y, 47)
    close(boxes[3].width, 120)
    close(boxes[3].height, 60)

    for index, box in ipairs(boxes) do
        assert(box.x >= 5 and box.y >= 7)
        assert(box.x + box.width <= 125)
        assert(box.y + box.height <= 107)
        for other_index = index + 1, #boxes do
            local other = boxes[other_index]
            local overlap_width = math.min(box.x + box.width, other.x + other.width) - math.max(box.x, other.x)
            local overlap_height = math.min(box.y + box.height, other.y + other.height) - math.max(box.y, other.y)
            assert(overlap_width <= 0 or overlap_height <= 0, box.name .. " overlaps " .. other.name)
        end
    end
end

local function test_area_grids_accept_column_and_row_weight_expressions()
    local grid = assert(layout.parse("a b; a .; c c", {
        columns = "1 2",
        rows = "repeat(1,2) 3",
    }))

    equal(grid.columns[1], 1)
    equal(grid.columns[2], 2)
    equal(grid.rows[1], 1)
    equal(grid.rows[2], 1)
    equal(grid.rows[3], 3)
end

test_weighted_rows_normalize_to_a_grid()
test_repeat_expands_inside_weighted_rows()
test_area_grids_normalize_named_rectangles_in_first_appearance_order()
test_area_grids_accept_column_and_row_weight_expressions()
test_malformed_empty_and_oversized_input_is_rejected()
test_inconsistent_and_non_rectangular_area_grids_are_rejected()
test_bad_track_weights_and_dimension_mismatches_are_rejected()
test_target_arity_must_match_normalized_areas()
test_boxes_use_cumulative_edges_cover_the_workarea_and_skip_empty_cells()
print("layout tests passed")
