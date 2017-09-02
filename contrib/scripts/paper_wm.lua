
overlap = {x = 10, y = 0}


function WMPlex.viewport_geom(scroll_frame)
    return scroll_frame:parent():geom()
end

-- Utility functions

-- IMPROVEMENT: Find a way to store (and restore) the region aux table in saved_layout.lua
local region_aux_map = { __mode="k" }
-- Return the region's /auxiliary/ table - allowing lua code to associate
-- arbitrary data with a region.
--
-- With non-nil key: equivalent to reg:aux()[key] except the table isn't created
function WRegion.aux(reg, key)
    local tab = region_aux_map[reg]
    if key then
        return tab and tab[key]
    end

    if not tab then
        tab = {}
        region_aux_map[reg] = tab
    end
    return tab
end

function manager_of(class_name, reg)
    local reg = reg or ioncore.current()
    while reg and not obj_is(reg, class_name) do
        reg = reg:manager()
    end
    return reg
end

function parent_of(class_name, reg)
    local reg = reg or ioncore.current()
    while reg and not obj_is(reg, class_name) do
        reg = reg:parent()
    end
    return reg
end

function screen_of(reg)
    return parent_of("WScreen", reg)
end

function workspace_of(reg)
    return manager_of("WGroupWS", reg)
end

function tiling_of(reg)
    return manager_of("WTiling", reg)
end

--- Moves up in the manager tree until the first WFrame is found
function frame_of(reg)
    return parent_of("WFrame", reg)
end

-- Find the mplex that holds the current tiling
-- returns nil if the parent of reg's workspace isn't a mplex
function WRegion.scroll_frame_of(reg)
    local tiling = tiling_of(reg)
    local parent = tiling and tiling:parent()
    if parent and obj_is(parent, "WMPlex") then
        return parent
    end
    return nil
end

function find_current(mng, classname)
    while mng.current and mng.__typename ~= classname do
        mng = mng:current()
    end
    return mng
end

function other_dir(dirstr)
    -- TERMINOLOGY: opposite_dir instead maybe?
    if dirstr == "left" then
        return "right"
    elseif dirstr == "right" then
        return "left"
    else
        error("invalid dirstr: "..dirstr) -- or just nil? (ref. snapped_at)
    end
end

function string.has_prefix(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix
end

function is_buffer_frame(reg)
    local n = reg:name()
    return n:has_prefix("*right*") or n:has_prefix("*left*")
end

function is_paper_tiling(tiling)
    if not tiling or tiling.__typename ~= "WTiling" then
        return false
    end
    local scroll_frame = tiling:scroll_frame_of()
    return scroll_frame and scroll_frame.__typename == "WFrame"
end

function WMPlex.screen_left(scroll_frame, amount)
    scroll_frame:move_screen(scroll_frame:geom().x-amount)
end

function WMPlex.screen_right(scroll_frame, amount)
    scroll_frame:move_screen(scroll_frame:geom().x+amount)
end

function WMPlex.move_screen(scroll_frame, x)
    if x > 0 then
        x = 0
    end
    scroll_frame:rqgeom({x=x})
end

-- Only one animation at a time. Starting a second animation cancels the first.
-- CAVEAT: This means that concurrent animation on different workspaces doesn't work.
--         If this is needed it should be simple to add one timer per workspace.
local animation_timer = ioncore.create_timer()
-- Simple animation along the x axis
function WMPlex.animate_move_right(scroll_frame, delta, duration, curve)
    animation_timer:reset()
    local duration = duration or 250
    local time = 0
    local travelled = 0
    local t_delta = 10

    -- linear curve
    function linear(time)
        return delta/duration*t_delta
    end
    curve = curve or linear

    local rest = 0
    function animate ()
        local raw_step = curve(time, t_delta) + rest
        local step = math.floor(raw_step)
        rest = raw_step - step
        if math.abs(travelled + step) >= math.abs(delta) then
            scroll_frame:screen_right(delta - travelled)
            return
        end
        travelled = travelled + step
        scroll_frame:screen_right(step)
        time = time + t_delta

        -- set up new frame
        animation_timer:set(t_delta, animate)
    end
    animate()
end

-- Align the viewport origin with sx
function move_viewport(reg, sx)
    local scroll_frame = reg:scroll_frame_of()
    if animate then
        scroll_frame:animate_move_right(-scroll_frame:screen_to_viewport(sx))
    else
        scroll_frame:screen_left(scroll_frame:screen_to_viewport(sx))
    end
end

function left(reg, amount)
    reg:scroll_frame_of():screen_right(amount)
end
function right(reg, amount)
    reg:scroll_frame_of():screen_left(amount)
end

-- return true if a new buffer was created
function ensure_buffer(tiling, dir, buffer_w)
    local buffer_maybe = tiling:farthest(dir)
    local buffer = nil
    local buffer_name = "*"..dir.."*"
    if buffer_maybe:name():has_prefix(buffer_name) then
        buffer = buffer_maybe
    else
        local dirmost = tiling:farthest(dir)
        buffer = tiling:split_at(dirmost, dir)
        buffer:set_name(buffer_name)
        buffer:rqgeom({w = buffer_w})
    end
    buffer:set_mode("tiled-alt")
    buffer:set_grattr("paperbuffer")

    return buffer, buffer ~= buffer_maybe
end

function make_room_for_statusbar(reg)
    local reg = reg or ioncore.current()
    local screen = reg:screen_of()
    local statusbars = mod_statusbar.statusbars()
    for _, s in ipairs(statusbars) do
        if s:screen_of() == screen then
            local scroll_frame = reg:scroll_frame_of()
            scroll_frame:rqgeom{h=screen:geom().h - s:geom().h}
        end
    end
end

function adapt_tiling(tiling)
    if not tiling or tiling.__typename ~= "WTiling" then
        debug.print_line("Can only adapt tiling workspaces atm. "
                             .. ((tiling and tiling.__typename) or "nil"))
        return false
    end
    local scroll_frame = tiling:parent()
    local view_g = scroll_frame:viewport_geom()
    local b, new_b = ensure_buffer(tiling, "right", scroll_frame:geom().w - view_g.w)
    make_room_for_statusbar(tiling)
    if new_b or new_a then
        tiling:first_page():snap_left()
    end
    return true
end
-- Returns the geometry of region in workspace coordinates
function WRegion.workspace_geom(reg)
    scroll_frame = reg:scroll_frame_of()
    parent = reg:parent()
    parent_g = parent:geom()
    g = reg:geom()
    while parent ~= scroll_frame do
        g.x = g.x + parent_g.x
        g.y = g.y + parent_g.y
        parent = parent:parent()
        parent_g = parent:geom()
    end
    return g
end

-- in scroll_frame coordinates
function WMPlex.viewport_origin(scroll_frame)
    return -scroll_frame:geom().x
end

-- screen_to_viewport(viewport_to_screen(100))

function WMPlex.screen_to_viewport(scroll_frame, sx)
    return sx - scroll_frame:viewport_origin()
end

function WMPlex.viewport_to_screen(scroll_frame, x)
    return scroll_frame:viewport_origin() + x
end

local function compute_gap(frame)
    local gap = 0
    local scroll_frame = frame:scroll_frame_of()
    local view_g = scroll_frame:viewport_geom()
    local manager = frame:manager()
    if obj_is(manager, "WTiling") then
        if manager:first_page() == frame or manager:last_page() == frame then
            gap = 0
        elseif view_g.w - 2*overlap.x <= frame:geom().w then
            gap = math.floor(math.max(0, (view_g.w - frame:geom().w)/2));
        elseif manager:first_page() ~= frame and manager:last_page() ~= frame then
            gap = overlap.x
        end
    end
    return gap
end

-- Align left viewport edge with frame's left edge
function WFrame.snap_left(frame)
    local g = frame:geom()
    local gap = compute_gap(frame)
    move_viewport(frame, g.x - gap)
    return frame
end

-- Align right viewport edge with frame's right edge
function WFrame.snap_right(frame)
    local g = frame:geom()
    local gap = compute_gap(frame)
    local scroll_frame = frame:scroll_frame_of()
    local view_g = scroll_frame:viewport_geom()
    move_viewport(frame, g.x + g.w - view_g.w + gap)
    return frame
end

function WFrame.snapped_at(frame)
    local g = frame:geom()
    local scroll_frame = frame:scroll_frame_of()
    local vpg = scroll_frame:viewport_geom()
    local vx = scroll_frame:screen_to_viewport(g.x)

    if math.abs(vx - overlap.x) <= 1 then
        return "left"
    elseif math.abs(vx+g.w - vpg.w) <= 1 then
        return "right"
    else
        return nil
    end
end

function WFrame.snap_other(frame)
    local snapped_at = frame:snapped_at()
    if snapped_at == "left" then
        frame:snap_right()
    elseif snapped_at == "right" then
        frame:snap_left()
    else
        frame:snap_left() -- could "snap_closest" to of course
    end
    return frame
end

--[[ Peek to the other side
-- Primary usecase:
-- A|ABBB|  rightmost content in B less useful => peek_toggle
--     ^
-- |AABB|B
--     ^
-- IMPROVEMENT: This function probably make too many assumptions.
--              Likely to behave strange if a neighbour is maximized for instance.
]]
function WFrame.peek_toggle(frame)
    local tiling = tiling_of(frame)

    -- Determine if we're "left" or "right"
    local snapped_at = frame:snapped_at()
    if not snapped_at then
        -- approx. for if we're peeking
        local is_visible, partial = frame:is_fully_visible()

        if not partial then
            return
        end

        if partial < 0 then
            frame:snap_left()
        else
            frame:snap_right()
        end
    else
        local peekdir = other_dir(snapped_at)
        local neighbour = tiling:nextto(frame, peekdir)
        if is_buffer_frame(neighbour) then
            return
        end
        if peekdir == "right" then
            neighbour:snap_right()
        else
            neighbour:snap_left()
        end
    end
end


--[[
Iterates through the /pages/ of the tiling - in order. (excluding buffers by default)

 The intention is that this function should iterate through the top-level
 horizontal splits (aka. /pages/?).

 Atm. it iterates through frames though, choosing an arbitrary from vertical splits.

 As with all other notion iterators - don't modify the collection during iterations. (insert new pages, etc.)

 Does not wrap around.
 
 Note that WTiling.managed_i descends into all the splits (both vertical and horizontal)
]]
function WTiling.page_i(tiling, iter_fn, from, dir, include_buffers)
    from = from or tiling:first_page()
    dir = dir or "right"
    include_buffers = include_buffers or false

    local lbuffer = tiling:farthest("left")
    local rbuffer = tiling:farthest("right")

    local next = from
    local i = 1
    while true do
        if not iter_fn(next) then
            return false
        end
        i = i+1
        next = tiling:nextto(next, dir)
        if next == rbuffer or next == lbuffer then
            if include_buffers then
                return not iter_fn(next)
            else
                return true
            end
        end
    end
end

-- Weird this isn't available already?
-- NB: buffers are excluded
-- FIXME: handle vertical splits (is a vertical split one or multiple pages?)
function WTiling.page_count(tiling)
    local count = 0
    tiling:managed_i(function()
            count = count + 1
            return true
    end)
    return count-1 -- just assume there's one buffer
end

-- NB! only checks horizontal visibility
-- As a extra "service": return the amount of partial viewport overlap when the
-- frame isn't fully visible (EXPERIMENTAL: negative if the overlap "is to the
-- right")
-- IMPROVEMENT: Make this work for all regions. Ie. regions that aren't direct
-- children of the workspace holder
function WFrame.is_fully_visible(frame)
    local scroll_frame = frame:scroll_frame_of()
    local g = frame:geom()
    local vp_g = scroll_frame:viewport_geom()
    g.x = scroll_frame:screen_to_viewport(g.x)

    local is_fully = true
    local partial_w = nil
    if g.x < 0 then
        if g.x+g.w > 0 then
            partial_w = -(g.x + g.w)
        end
        is_fully = false
    elseif g.x+g.w > vp_g.w then
        if g.x < vp_g.w then
            partial_w = vp_g.w - g.x
        end
        is_fully = false
    end
    -- return 0 <= g.x and g.x+g.w <= vp_g.w
    return is_fully, partial_w
end


-- Find the nth tiling frame (1-indexed)
function WTiling.nth_page(tiling, n)
    local stop = tiling:last_page()
    local next = tiling:first_page()

    if n == 0 then
        return stop
    end

    while n > 1 and next ~= stop do
        next = tiling:nextto(next, "right")
        n = n-1
    end
    return next
end

function switch_nth(frame, nth)
    local tiling = tiling_of(frame)
    if tiling and frame:mx_count() < 2 then
        tiling:nth_page(nth + 1):goto_focus()
    else
        if nth < 0 then
            nth = frame:mx_count() + nth
        end
        frame:switch_nth(nth)
    end
end

-- Returns the page which is considered First
-- Use this to constrain page movement
function WTiling.first_page(tiling)
    local first = tiling:farthest("left")
    return first
end

-- Returns the page which is considered Last
-- Use this to constrain page movement
function WTiling.last_page(tiling)
    local rbuffer = tiling:farthest("right")
    local last = tiling:nextto(rbuffer, "left")
    return last
end


-- Returns the page number of frame in tiling (lbuffer == 0, first_page == 1)
function WTiling.page_number_of(tiling, frame)
    local page_number = 0
    local lbuffer = tiling:farthest("left")
    while frame ~= lbuffer do
        page_number = page_number + 1
        frame = tiling:nextto(frame, "left")
    end
    return page_number
end

-- Create new page/frame after last_page
function WTiling.new_page(tiling)
    local new = tiling:insert_page(tiling:last_page())
    return new
end

-- Insert a blank page to the right/left of frame
function WTiling.insert_page(tiling, frame, direction)
    direction = direction or "right"
    local frame_g = frame:geom()
    local view_g = tiling:scroll_frame_of():viewport_geom()

    tiling:resize_right(frame, view_g.w - 2*overlap.x)
    local new = tiling:split_at(frame, direction, false)
    tiling:resize_right(frame, frame_g.w)
    frame:paper_goto()
    return new
end

-- Delete frame from tiling, preserving all other page widths
-- frame = current_frame()
function WTiling.delete_page(tiling, frame)
    local left = tiling:nextto(frame, "left")
    local right = tiling:nextto(frame, "right")
    -- remember geometry
    local left_g = left:geom()
    local right_g = right:geom()

    frame:rqclose()
    -- fix up widths
    ioncore.defer(function ()
            tiling:resize_right(left, left_g.w)
            tiling:resize_right(right, right_g.w)
    end)
    return left
end

function WTiling.merge_pages(tiling, frame)
    if frame:mx_count() == 0 then
        return tiling:delete_page(frame)
    end

    local frame_g = frame:geom()
    local scroll_frame = frame:scroll_frame_of()
    local x = scroll_frame:screen_to_viewport(frame_g.x)

    local screen_g = frame:screen_of():geom()
    if (x + frame_g.w/2) <= screen_g.w/2 then
        debug.print_line("merging right")
        return tiling:merge_pages_right(frame)
    else
        debug.print_line("merging left")
        return tiling:merge_pages_left(frame)
    end
end

local function move_clients(from, to)
    for _, reg in ipairs(mcollect(from.mx_i, from)) do
        to:attach(reg)
    end
end

-- Delete a frame and insert it's content into the left page
function WTiling.merge_pages_left(tiling, frame)
    if frame == tiling:first_page() then
        return tiling:merge_pages_right(frame)
    end

    local left = tiling:nextto(frame, "left")
    move_clients(left, frame)
    tiling:delete_page(left)
    return frame
end

function WTiling.merge_pages_right(tiling, frame)
    local right = tiling:nextto(frame, "right")
    if is_buffer_frame(right) then
        return
    end
    move_clients(right, frame)

    tiling:delete_page(right)

    return frame
end

-- Metaphor: Frame as a stack of pages/windows
-- Moves 'reg' to a new page to the right
-- Atm: Focus is moved to the next page in the stack/frame.
function WTiling.unstack(tiling, frame, reg)
    local new_page = tiling:insert_page(frame, "right")
    WTiling.resize_right(tiling, new_page, frame:geom().w)
    new_page:attach(reg)
end

-- |A|B|C| => |A|C|B|
--  ^          ^
function WTiling.swap_siblings(tiling, frame, dir)
    -- TODO: choose direction intelligently like in merge_pages?
    dir = dir or 'right'
    local a = tiling:nextto(frame, dir)
    local b = tiling:nextto(a, dir)

    if is_buffer_frame(a) or is_buffer_frame(b) then
        return
    end

    -- TODO: support vertical splits too (need changes in swap_leaves)
    tiling:swap_leaves(tiling:node_of(a), tiling:node_of(b))
end

-- Move frame in direction 'dir'
function WTiling.move_page(tiling, frame, dir)
    dir = dir or "right"
    local next_frame_in_dir = tiling:nextto(frame, dir)
    if not is_buffer_frame(next_frame_in_dir) then 
        -- Should maybe separate such logic from the more raw functionality?
        tiling:swap_leaves(tiling:node_of(frame), tiling:node_of(next_frame_in_dir))
    end
    return frame
end

function WRegion.move(reg, direction)
    local tiling = tiling_of(reg)
    local frame = frame_of(reg)
    if is_paper_tiling(tiling) then
        return tiling:move_page(frame, direction)
    else
        if direction == "right" then
            return frame:inc_index(frame:current())
        else
            return frame:dec_index(frame:current())
        end
    end
end

function WTiling.next_page(tiling, frame)
    if frame == tiling:last_page() then
        return frame
    else
        return tiling:nextto(frame, 'right')
    end
end

function WTiling.prev_page(tiling, frame)
    if frame == tiling:first_page() then
        return frame
    else
        return tiling:nextto(frame, 'left')
    end
end

-- Sensitive to scratchpad
function focus_next(frame)
    local tiling = tiling_of(frame)
    if is_scratchpad(frame) then
        frame:switch_next()
    else
        tiling:next_page(frame):goto_focus()
    end
end

function focus_prev(frame)
    local tiling = tiling_of(frame)
    if is_scratchpad(frame) then
        frame:switch_prev()
    else
        tiling:prev_page(frame):goto_focus()
    end
end

-- Move the viewport (if needed) such that the frame /associated/ with `reg`
-- is inside the viewport.
-- A frame is /associated/ with `reg` by being the current frame of `reg` or
-- by being the closest parenting frame.
--
-- Designed as a support function for `goto_focus`.
-- 
-- IMPROVEMENT: Make this work for all regions. Ie. regions that aren't direct
-- children workspace holder
function WRegion.ensure_in_viewport(reg)

    local scroll_frame = reg:scroll_frame_of()
    if not obj_is(scroll_frame, "WFrame") then
        return
    end

    local target_frame = nil
    if reg.__typename == "WGroupWS" then
        return
    else
        target_frame = frame_of(reg)
    end

    if not target_frame then
        debug.print_line("Could not find a target frame")
        return
    end

    local g = target_frame:geom()
    local x = scroll_frame:screen_to_viewport(g.x)

    local view_g = scroll_frame:viewport_geom()
    if x < 0 then
        target_frame:snap_left()
    elseif x + g.w > view_g.w then
        target_frame:snap_right()
    end
end

if not WRegion.original_goto then
    WRegion.original_goto = WRegion.goto_focus
end

-- A viewport aware `WRegion.goto_focus`
function WRegion.paper_goto(reg)
    if obj_is(reg:scroll_frame_of(), "WFrame") then
        reg:ensure_in_viewport()
    end
    reg:original_goto()
end

WRegion.goto_focus = WRegion.paper_goto
WRegion.goto_ = WRegion.goto_focus


function WTiling.resize_right_delta(tiling, frame, delta)
    local new_w = frame:geom().w + delta
    return tiling:resize_right(frame, new_w)
end

-- NB: Rounds down to closest width increment unless 'exact' is true
function WTiling.resize_right(tiling, frame, new_w, exact)
    if not exact then
        local inc_w = frame:size_hints().inc_w or 1
        local inc_rounding = new_w % inc_w
        new_w = new_w - inc_rounding
    end
    local node = tiling:node_of(frame)
    if new_w > 5 then
        node:resize_right(new_w)
    end
    return frame
end

function WTiling.paper_maximize(tiling, frame)
    local frame_aux = frame:aux()
    if frame_aux.maximized then
        tiling:resize_right(frame, frame_aux.original_g.w)
        local gap = compute_gap(frame)
        left(frame, frame_aux.original_viewport_x - gap)
        frame_aux.maximized = nil
        frame_aux.original_g = nil
    else
        local scroll_frame = frame:scroll_frame_of()
        local view_g = scroll_frame:viewport_geom()

        local g = frame:geom()

        frame_aux.maximized = true
        frame_aux.original_g = frame:geom()
        frame_aux.original_viewport_x = scroll_frame:screen_to_viewport(g.x)

        local gap = compute_gap(frame)
        tiling:resize_right(frame, view_g.w - overlap.x - gap)
        right(frame, g.x - scroll_frame:viewport_origin() - gap)
    end
    return frame
end

function WTiling.cycle_page_width(tiling, frame)
    local gr = 1/1.618
    local ratios = { (1-gr), 1/2, gr, }

    function find_next(tr)
        -- Find the first ratio that is significantly bigger than 'tr'
        for i, r in ipairs(ratios) do
            if tr <= r then
                if tr/r > 0.9 then
                    return (i % #ratios) + 1
                else
                    return i
                end
            end
        end
        return 1 -- cycle
    end

    local sw = frame:screen_of():geom().w
    local r = frame:geom().w / sw

    local i = find_next(r)
    local next_w = math.floor(ratios[i]*sw)

    frame:aux().maximized = nil

    local snapped_at = frame:snapped_at() -- check _before_ resize

    tiling:resize_right(frame, next_w)

    if snapped_at == "right" then
        -- WEAKNESS: depends on resize_right to be instant (eg. not animated)
        --           (we should have a system for smoothly combine resize and move actions)
        frame:snap_right()
    end
    return frame
end

-- Expand the frame utilizing all space occupied by partially visible frames
function WTiling.paper_expand_free(tiling, frame)

    if not frame:is_fully_visible() then
        -- Bail!
        return
    end

    function find_first_partial_visible(dir)
        -- Or hidden if none are /partial/ visible
        -- Or last fully visible if all are fully visible
        -- Can return the left/right buffers
        local found_frame = nil
        local inside_w
        tiling:page_i(function(p)
                local fully
                fully, inside_w = p:is_fully_visible()

                found_frame = p 
                if not fully then
                    return false
                end
                return true
        end, frame, dir, true)
        return found_frame, (inside_w and math.abs(inside_w)) or 0
    end

    local a, a_free_w = find_first_partial_visible("left")
    local b, b_free_w = find_first_partial_visible("right")

    -- Edge-cases:

    local scroll_frame = tiling:scroll_frame_of()
    local first_in_vp = tiling:nextto(a, "right")

    if a_free_w == 0 and is_buffer_frame(a) then
        a_free_w = scroll_frame:screen_to_viewport(first_in_vp:geom().x)
    end
    if b_free_w == 0 and is_buffer_frame(b) then
        -- will never happen as long as the right buffer is huge though
        local vp_w = scroll_frame:viewport_geom().w
        b_free_w = vp_w - scroll_frame:screen_to_viewport(b:geom().x)
    end

    local total_free_w = a_free_w + b_free_w

    if(total_free_w > 0) then
        if(a_free_w > 0) then
            first_in_vp:snap_left()
        end
        tiling:resize_right_delta(frame, total_free_w)
    end
    return frame
end

-- IDEA: slurp / barf for pages (assoc lisp editing mode)

function WScreen.create_workspace(screen, name, geom)
    local rootws = ioncore.create_ws(screen, {name=name, sizepolicy="full"}, "empty")
    local geom = geom or screen:geom()
    geom.w = 20000
    local scroll_frame = rootws:attach_new({name="*workspaceholder*", type="WFrame", geom=geom})
    scroll_frame:set_mode("tiled-alt")
    scroll_frame:set_grattr("workspaceholder", "set")

    local tiling = scroll_frame:attach_new{type="WTiling"}
    adapt_tiling(tiling)
    tiling:first_page():goto_focus()

    return scroll_frame
end

local attach_workspace_handler = function (mplex, name)
    local ws =ioncore.lookup_region(name, "WGroupWS")
    if ws then
        local screen = mplex:screen_of()
        screen:attach(ws, {switchto = true})
        ws:managed_i(function (frame)
                if frame:name():has_prefix("*workspaceholder*") then
                    ioncore.defer(function ()
                            frame:rqgeom{h=screen:geom().h}
                    end)
                end
                return true
        end, "WFrame")
    else
        mod_query.warn(mplex, "No workspace with that name")
    end
end

function mod_query.attach_workspace(mplex)
    return mod_query.query(mplex:screen_of(), TR("Attach workspace:"),
                           nil,
                           attach_workspace_handler,
                           mod_query.make_completor(mod_query.complete_workspace),
                           "workspacename")
end

-- Attach new windows in a new page
function manage_handler(clientwin, options)
    if options.tfor or options.dockapp then
        return false
    end

    local winprop = ioncore.getwinprop(clientwin)
    if winprop and (
        winprop.target
            or winprop.float
            or winprop.transient_mode == "current"
    ) then
        return false
    end

    local tiling = tiling_of()

    if tiling and is_paper_tiling(tiling) then
        local frame
        if tiling:current():mx_count() == 0 then
            -- Fill empty pages
            frame = tiling:current()
        else
            frame = tiling:insert_page(tiling:current())
        end
        -- See https://github.com/raboof/notion/issues/41 for some details
        frame:attach_new { type="WGroupCW", managed={{reg=clientwin, bottom=true}} }
        clientwin:paper_goto()
        return true
    end
end
function manage_handler_wrap(clientwin, options)
    -- Make it more convenient to re-eval the actual hook (TODO: remove me when stabilized)
    return manage_handler(clientwin, options)
end

manage_hook = ioncore.get_hook("clientwin_do_manage_alt")
manage_hook:add(manage_handler_wrap)

-- delete empty pages
function frame_handler(params)
    local frame = params.reg
    local tiling = frame:manager()
    if is_paper_tiling(tiling) and frame:mx_count() == 0 then
        if tiling:page_count() == 1 then
            return
        end
        ioncore.defer(function ()
                tiling:delete_page(frame)
        end)
    end
end

function frame_handler_wrap(frame, mode, sw, sub)
    return frame_handler(frame, mode, sw, sub)
end

frame_hook = ioncore.get_hook("frame_managed_changed_hook")
frame_hook:add(frame_handler_wrap)

-- Guard against deleting the last page
function rqclose_propagate_paper(reg, sub)
    local tiling = reg:manager()
    if is_paper_tiling(tiling) then
        local frame = reg
        local count = frame:mx_count()
        if count > 1 then
            return frame:rqclose_propagate(sub)
        elseif count == 1 then
            local new_focus = tiling:prev_page(frame)
            frame:rqclose_propagate(sub)
            return new_focus
        elseif is_paper_tiling(tiling) and tiling:page_count() == 1 then
            return frame
        elseif count == 0 then
            tiling:delete_page(frame)
        else
            return frame:rqclose_propagate(sub)
        end
    else
        return reg:rqclose_propagate(sub)
    end
end

function WTiling.attach(tiling, reg, params)
    local frame = tiling:current()
    if frame:mx_count() > 0 then
        frame = tiling:insert_page(frame)
        tiling:resize_right(frame, reg:geom().w)
    end
    if obj_is(reg, "WFrame") then
        move_clients(reg, frame)
    else
        frame:attach(reg)
    end
    if params and params.switchto then
        frame:paper_goto()
    end
end

function WRegion.attach_dispatch(reg)
    local tiling = tiling_of(reg)
    if is_paper_tiling(tiling) then
        ioncore.tagged_attach(tiling)
    end
    ioncore.tagged_attach(reg)
end

-- Utility for alt_tab menus
function WRegion.in_scratchpad(reg)
    -- scratchpads are either frames or workspaces
    local frame = frame_of(reg)
    local ws = workspace_of(reg)
    return (frame and is_scratchpad(frame)) or
           (ws and is_scratchpad(ws))
end

local last_previewed = nil
local function addto(list)
    return function(tgt, attr)
        local e=menuentry(tgt:name(),
                          -- reg and sub refers to where the menu is displayed
                          function(reg, sub, is_preview)
                              if last_previewed then
                                  last_previewed:set_grattr("preview", "unset")
                              end
                              if is_preview then
                                  local frame = frame_of(tgt)
                                  if frame then
                                      frame:set_grattr("preview", "set")
                                      last_previewed = frame
                                  end
                              else
                                  last_previewed = nil
                              end

                              tgt:rqorder("front")
                              tgt:goto_focus()
                          end
        )

        e.attr=attr;
        table.insert(list, e)
        return true
    end
end

-- <alt-tab> menu
local function alt_tab()
    local do_act = true
    local entries={}
    local seen={}
    local iter_=addto(entries)
    local current = ioncore.current()
    local start_in_scratchpad = current:in_scratchpad()

    local function iter(obj, attr)
        if obj_is(obj, "WClientWin") then
            -- Ignore scratchpad if we didn't start there
            if not start_in_scratchpad and obj:in_scratchpad() then
                return true
            end
            iter_(obj, attr)
            seen[obj]=true
        end
        return true
    end

    local function iter_act(obj)
        iter_(obj, "activity")
        seen[obj]=true
        return true
    end

    local function iter_foc(obj)
        return (seen[obj] or iter(obj))
    end

    -- Add the current window to the top of the list
    iter(current)

    if do_act then
        -- Windows with activity first
        ioncore.activity_i(iter_act)
    end

    -- The ones that have been focused in their lifetime
    ioncore.focushistory_i(iter_foc)

    -- And then the rest
    ioncore.clientwin_i(iter_foc)

    return entries
end
ioncore.defmenu("alttab", alt_tab)

local function ws_or_fullscreen_of(reg)
    local ws=ioncore.find_manager(reg, "WGroupWS")
    local is_scratch=false

    if not ws then
        -- Fullscreen windows doesn't have a WGroupWS manager
        -- but are the child of Screen
        ws=obj_is(reg:parent(), "WScreen") and reg
        -- Scratchpads can be a frame
        local frame=ioncore.find_manager(reg, "WFrame")
        is_scratch=mod_sp and frame and mod_sp.is_scratchpad(frame)
    else
        -- Or a ws
        is_scratch=mod_sp and mod_sp.is_scratchpad(ws)
    end

    if not ws or is_scratch then
        -- Ignore scratchpads
        return false
    else
        return ws
    end
end

local function alt_tab_workspace()
    local entries={}
    local seen={}
    local iter_=addto(entries)
    -- local focused_ws=ws_or_fullscreen_of(ioncore.current())

    local function iter(reg)
        local ws=ws_or_fullscreen_of(reg)

        -- If we started in a scratchpad consider the first visited
        -- workspace as the one we started in and ignore it
        -- if not focused_ws and ws then
        --     focused_ws=ws
        --     seen[ws]=true
        -- end

        if ws and not seen[ws] then
            iter_(ws)
            seen[ws]=true
        end
        return true
    end

    -- Add the focused workspace
    iter(ioncore.current())

    -- Add workspaces which have had focus
    ioncore.focushistory_i(iter)

    -- Add the rest
    ioncore.region_i(iter, "WGroupWS")

    -- Add create workspace entry
    local create_ws=menuentry(" -- Create new workspace -- ",
                              "mod_query.query_workspace(_)")
    table.insert(entries, create_ws)

    return entries
end
ioncore.defmenu("workspace-alt-tab", alt_tab_workspace)
--: nil



defbindings("WMPlex", {
                  bdoc("Close current object.")
                , kpress(META.."C", "_:rqclose_propagate(_sub)")
})

defbindings("WMPlex.toplevel", {
                  kpress(META.."T", "_sub:set_tagged('toggle')", "_sub:non-nil")
                , bdoc("Close current object.")
                , kpress(META.."C", "rqclose_propagate_paper(_, _sub):paper_goto()")
                , submap(META.."space", {
                             kpress("space"
                                    , "mod_query.query_menu(_, _, 'ctxmenu', 'Context menu:')"),
                        })
                , bdoc("Query for Lua code to execute.")
                , kpress(META.."F3", "mod_query.query_lua(_)")
})

defbindings("WScreen", {
                kpress(META.."Up", "switch_workspace(1)")
              , kpress(META.."Down", "switch_workspace(-1)")

              --- MRU lists/menus
              , kpress(META.."Tab", "mod_menu.grabmenu(_, _sub, 'alttab', {sizepolicy = 'center', big=true, preview=true, max_w=400, max_h=400})")
              , submap(META.."space", {
                           kpress("Tab", "mod_menu.grabmenu(_, _sub, 'workspace-alt-tab', { sizepolicy = 'center', big=true, preview=true, max_w=400, max_h=400})")
                           , kpress("N", "_:create_workspace()")
                      })

              -- workspaces
              , submap(META.."space", {
                           kpress("A", "mod_query.attach_workspace(_)")
                      })

              -- queries
              , kpress(ALTMETA.."F12", "mod_query.query_menu(_, _sub, 'mainmenu', 'Main menu:')"),
})

defbindings("WTiling", {
                -- Moving
                kpress(META.."Page_Down", "_:next_page(_sub):paper_goto()")
              , kpress(META.."Page_Up", "_:prev_page(_sub):paper_goto()")
              , kpress(META.."Home", "_:first_page():snap_left():original_goto()")
              , kpress(META.."End", "_:last_page():snap_right():original_goto()")
              , kpress(META.."0", "_:last_page():snap_right():goto_focus()")

              , kpress(META.."L", "_sub:snap_other():original_goto()")
              , kpress(META.."Shift+L", "_sub:peek_toggle()")

              , kpress(META.."E", "_:swap_siblings(_sub)")

              --- Page creation/deletion
              , kpress(META.."N", "_:insert_page(_sub):paper_goto()")
              , kpress(META.."Shift+N", "_:new_page():paper_goto()")
              , kpress(META.."D", "_:merge_pages_right(_sub):snap_left()")
              , kpress(META.."Q", "_:unstack(_sub, _sub:current())")

              -- , mdrag(META.."Button1", "WRegion.p_move(_)") -- comment in to move the whole workspace with the mouse

              --- Resizing
              , kpress(META.."plus", "_:resize_right_delta(_sub, 30):goto_focus()")
              , kpress(META.."minus", "_:resize_right_delta(_sub, -30):goto_focus()")
              , kpress(META.."H", "_:paper_maximize(_sub):goto_focus()")
              , kpress(META.."Shift+H", "_:paper_expand_free(_sub):goto_focus()")
              , kpress(META.."R", "_:cycle_page_width(_sub):goto_focus()")
})

defbindings("WFrame.toplevel", {
                -- Moving
                kpress(META.."Left", "left(_, 2)")
                , kpress(META.."Right", "right(_, 2)")
                --   kpress(META.."Left", "left(_, _:workspace_holder_of():viewport_geom().w/2)")
                -- , kpress(META.."Right", "right(_, _:workspace_holder_of():viewport_geom().w/2)")
                , bdoc("Query for a client window to attach.")
                , kpress(META.."A", "mod_query.query_attachclient(_)")

                , mclick("Button1@tab", "_:paper_goto() _:p_switch_tab()")
                -- terminal
                , kpress(ALTMETA.."F2", "ioncore.exec_on(_, XTERM or 'xterm')")

                -- tabs/pages
                , bdoc("Switch to n:th object within the frame.")
                , kpress(META.."0", "switch_nth(_, -1)")
                , kpress(META.."1", "switch_nth(_, 0)")
                , kpress(META.."2", "switch_nth(_, 1)")
                , kpress(META.."3", "switch_nth(_, 2)")
                , kpress(META.."4", "switch_nth(_, 3)")
                , kpress(META.."5", "switch_nth(_, 4)")
                , kpress(META.."6", "switch_nth(_, 5)")
                , kpress(META.."7", "switch_nth(_, 6)")
                , kpress(META.."8", "switch_nth(_, 7)")
                , kpress(META.."9", "switch_nth(_, 8)")

                -- Goto to next thing, either a tab or page
                , kpress(META.."period", "focus_next(_)")
                , kpress(META.."comma", "focus_prev(_)")

                -- tag/attach
                , kpress(META.."Shift+T", "_:attach_dispatch()")

                --- Page rearranging
                , kpress(META.."Shift+period", "_:move('right'):goto_focus()")
                , kpress(META.."Shift+comma", "_:move('left'):goto_focus()")
})
