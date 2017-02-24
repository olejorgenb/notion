
overlap = {x = 10, y = 0}

mod_xinerama.query_screens()
display_geoms = mod_xinerama.query_screens()
viewport_geoms = {}
for i, g in ipairs(display_geoms) do
    local view_g = {
        x = g.x + overlap.x
      , y = g.y + overlap.y
      , w = g.w - 2*overlap.x
      , h = g.h - 2*overlap.y
    }
    viewport_geoms[i] = view_g
end

function WMPlex.viewport_geom(screen)
    return viewport_geoms[screen:screen_of():id()+1]
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

function current_workspace(ws_holder)
    ws_holder = ws_holder or ioncore.current():workspace_holder_of()
    return ws_holder:current()
end

function current_tiling(ws)
    ws = ws or current_workspace()
    return ws:current()
end

function current_frame(ws)
    ws = ws or current_workspace()
    return ws:current():current()
end

--- Moves up in the manager tree until the first WFrame is found
function frame_of(reg)
    while reg and reg.__typename ~= "WFrame" do
        reg = reg:manager()
    end
    return reg
end


-- Find the mplex that holds the current workspace
-- returns nil if the parent of reg's workspace isn't a mplex
function WRegion.workspace_holder_of(reg)
    local workspace = workspace_of(reg)
    local parent = workspace and workspace:parent()
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

function string.has_prefix(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix
end

function is_buffer_frame(reg)
    local n = reg:name()
    return n:has_prefix("*right*") or n:has_prefix("*left*")
end

function WMPlex.screen_left(ws_holder, amount)
    ws_holder:rqgeom{x=ws_holder:geom().x-amount} -- LEFT
end

function WMPlex.screen_right(ws_holder, amount)
    ws_holder:rqgeom{x=ws_holder:geom().x+amount} -- RIGHT
end

function WMPlex.move_screen(ws_holder, x)
    local y = 0
    ws_holder:rqgeom({x=x})
end

-- Simple animation along the x axis
function WMPlex.animate_move_right(ws_holder, delta, duration, curve)
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
        if math.abs(travelled + step) > math.abs(delta) then
            ws_holder:screen_right(delta - travelled)
            return
        end
        travelled = travelled + step
        ws_holder:screen_right(step)
        time = time + t_delta

        -- set up new frame
        local timer = ioncore.create_timer()
        timer:set(t_delta, animate)
    end
    animate()
end

-- Align the viewport origin with sx
function move_viewport(reg, sx)
    local ws_holder = reg:workspace_holder_of()
    if animate then
        ws_holder:animate_move_right(-ws_holder:screen_to_viewport(sx))
    else
        ws_holder:screen_left(ws_holder:screen_to_viewport(sx))
    end
end

function left(reg, amount)
    reg:workspace_holder_of():screen_right(amount)
end
function right(reg, amount)
    reg:workspace_holder_of():screen_left(amount)
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

function unadapt_workspace(ws)
    local tiling = ws:current()
    if tiling.__typename ~= "WTiling" then
        debug.print_line("Can only unadapt tiling workspaces atm. " .. tiling.__typename)
        return
    end

    local rbuffer = tiling:farthest("right")
    rbuffer:rqclose()
end

function adapt_workspace(ws)
    --- Makes 'ws' usable in a paper_wm
    local tiling = ws:current()
    if not tiling or tiling.__typename ~= "WTiling" then
        debug.print_line("Can only adapt tiling workspaces atm. "
                             .. ((tiling and tiling.__typename) or "nil"))
        return false
    end
    local ws_holder = ws:workspace_holder_of()
    local view_g = ws_holder:viewport_geom()
    local b, new_b = ensure_buffer(tiling, "right", ws_holder:geom().w - view_g.w)
    local a, new_a = ensure_buffer(tiling, "left", overlap.x)
    if new_b or new_a then
        tiling:first_page():snap_left()
    end
    return true
end

-- Returns the geometry of region in workspace coordinates
function WRegion.workspace_geom(reg)
    ws_holder = reg:workspace_holder_of()
    parent = reg:parent()
    parent_g = parent:geom()
    g = reg:geom()
    while parent ~= ws_holder do
        g.x = g.x + parent_g.x
        g.y = g.y + parent_g.y
        parent = parent:parent()
        parent_g = parent:geom()
    end
    return g
end

-- in ws_holder coordinates
function WMPlex.viewport_origin(ws_holder)
    return -ws_holder:geom().x + overlap.x
end

-- screen_to_viewport(viewport_to_screen(100))

function WMPlex.screen_to_viewport(ws_holder, sx)
    return sx - ws_holder:viewport_origin()
end

function WMPlex.viewport_to_screen(ws_holder, x)
    return ws_holder:viewport_origin() + x
end

-- Align left viewport edge with frame's left edge
function WFrame.snap_left(frame)
    local g = frame:geom()
    move_viewport(frame, g.x)
    return frame
end

-- Align right viewport edge with frame's right edge
function WFrame.snap_right(frame)
    local g = frame:geom()
    local view_g = frame:workspace_holder_of():viewport_geom()
    move_viewport(frame, g.x + g.w - view_g.w)
    return frame
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

-- NB! only checks horizontal visibility
-- As a extra "service": return the amount of partial viewport overlap when the
-- frame isn't fully visible (EXPERIMENTAL: negative if the overlap "is to the
-- right")
-- IMPROVEMENT: Make this work for all regions. Ie. regions that aren't direct
-- children of the workspace holder
function WFrame.is_fully_visible(frame)
    local wsh = frame:workspace_holder_of()
    local g = frame:geom()
    local vp_g = wsh:viewport_geom()
    g.x = wsh:screen_to_viewport(g.x)

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

    while n > 1 and next ~= stop do
        next = tiling:nextto(next, "right")
        n = n-1
    end
    return next
end

-- Returns the page which is considered First
-- Use this to constrain page movement
function WTiling.first_page(tiling)
    local lbuffer = tiling:farthest("left")
    local first = tiling:nextto(lbuffer, "right")
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
    local view_g = tiling:workspace_holder_of():viewport_geom()

    tiling:resize_right(frame, view_g.w)
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
end

-- Move frame in direction 'dir'
function WTiling.move_page(tiling, frame, dir)
    dir = dir or "right"
    local next_frame_in_dir = tiling:nextto(frame, dir)
    tiling:swap_leaves(tiling:node_of(frame), tiling:node_of(next_frame_in_dir))
    return frame
end

function WTiling.next_page(tiling, frame)
    if frame == tiling:last_page() then
        return
    end
    local next = tiling:nextto(frame, 'right')
    local ws_holder = tiling:workspace_holder_of()
    local x = ws_holder:screen_to_viewport(next:geom().x)
    local w = next:geom().w
    local view_g = frame:workspace_holder_of():viewport_geom()
    if x + w >= view_g.w then
        next:snap_right()
    end
    next:goto_()
end

function WTiling.prev_page(tiling, frame)
    if frame == tiling:first_page() then
        return
    end
    local prev = tiling:nextto(frame, 'left')
    local ws_holder = tiling:workspace_holder_of()
    local x = ws_holder:screen_to_viewport(prev:geom().x)
    if x <= 0 then
        prev:snap_left()
    end
    prev:goto_()
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

    local ws_holder = reg:workspace_holder_of()
    if ws_holder == nil then
        return
    end

    local target_frame = nil
    if reg.__typename == "WGroupWS" then
        target_frame = find_current(reg, "WFrame")
    else
        target_frame = frame_of(reg)
    end

    if not target_frame then
        debug.print_line("Could not find a target frame")
        return
    end

    local g = target_frame:geom()
    local x = ws_holder:screen_to_viewport(g.x)

    local view_g = ws_holder:viewport_geom()
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
    debug.print_line("paper_goto: "..reg:name())

    if obj_is(reg:workspace_holder_of(), "WFrame") then
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

function WTiling.resize_right(tiling, frame, new_w)
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
        left(frame, frame_aux.original_viewport_x)
        frame_aux.maximized = nil
        frame_aux.original_g = nil
    else
        local ws_holder = frame:workspace_holder_of()
        local view_g = ws_holder:viewport_geom()

        local g = frame:geom()

        frame_aux.maximized = true
        frame_aux.original_g = frame:geom()
        frame_aux.original_viewport_x = ws_holder:screen_to_viewport(g.x)

        tiling:resize_right(frame, view_g.w)
        right(frame, g.x - ws_holder:viewport_origin())
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

    local wsh = tiling:workspace_holder_of()
    local first_in_vp = tiling:nextto(a, "right")

    if a_free_w == 0 and is_buffer_frame(a) then
        a_free_w = wsh:screen_to_viewport(first_in_vp:geom().x)
    end
    if b_free_w == 0 and is_buffer_frame(b) then
        -- will never happen as long as the right buffer is huge though
        local vp_w = wsh:viewport_geom().w
        b_free_w = vp_w - wsh:screen_to_viewport(b:geom().x)
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
    local rootws = ioncore.lookup_region("*rootws*")
    if not rootws then
        rootws = ioncore.create_ws(screen, {name="*rootws*", sizepolicy="full"}, "empty")
    end
    local geom = geom or screen:geom()
    geom.w = 20000
    local wsholder = rootws:attach_new({name="*workspaceholder*", type="WFrame", geom=geom})
    wsholder:set_mode("tiled-alt")
    wsholder:set_grattr("workspaceholder", "set")

    local workspace = ioncore.create_ws(wsholder, {name=name, sizepolicy="full"}, "full")
    adapt_workspace(workspace)

    return workspace
end


defbindings("WScreen", {
                kpress(META.."Up", "switch_workspace(1)")
              , kpress(META.."Down", "switch_workspace(-1)")

              --- MRU lists/menus
              , kpress(META.."Tab", "mod_menu.grabmenu(_, _sub, 'focuslist', {sizepolicy = 'center', big=true })")
              , submap(META.."space", {
                           kpress("Tab", "mod_menu.grabmenu(_, _sub, 'workspacefocuslist', { sizepolicy = 'center', big=true})")
                           , kpress("N", "_:create_workspace()")
                      })
})

defbindings("WTiling", {
                -- Moving
                kpress(META.."Page_Down", "_:next_page(_sub)")
              , kpress(META.."Page_Up", "_:prev_page(_sub)")
              , kpress(META.."period", "_:next_page(_sub)")
              , kpress(META.."comma", "_:prev_page(_sub)")
              , kpress(META.."Home", "_:first_page():snap_left():goto_focus()")
              , kpress(META.."End", "_:last_page()")
              , kpress(META.."1", "_:nth_page(1):goto_focus()")
              , kpress(META.."2", "_:nth_page(2):goto_focus()")
              , kpress(META.."3", "_:nth_page(3):goto_focus()")
              , kpress(META.."4", "_:nth_page(4):goto_focus()")
              , kpress(META.."5", "_:nth_page(5):goto_focus()")
              , kpress(META.."6", "_:nth_page(6):goto_focus()")
              , kpress(META.."7", "_:nth_page(7):goto_focus()")
              , kpress(META.."8", "_:nth_page(8):goto_focus()")
              , kpress(META.."9", "_:nth_page(9):goto_focus()")
              , kpress(META.."0", "_:last_page():snap_right():goto_focus()")

              --- Page creation/deletion
              , kpress(META.."N", "_:insert_page(_sub):paper_goto()")
              , kpress(META.."Shift+N", "_:new_page():paper_goto()")
              , kpress(META.."D", "_:delete_page(_sub)")

              -- , mdrag(META.."Button1", "WRegion.p_move(_)") -- comment in to move the whole workspace with the mouse

              --- Resizing
              , kpress(META.."plus", "_:resize_right_delta(_sub, 30):goto_focus()")
              , kpress(META.."minus", "_:resize_right_delta(_sub, -30):goto_focus()")
              , kpress(META.."H", "_:paper_maximize(_sub):goto_focus()")
              , kpress(META.."Shift+H", "_:paper_expand_free(_sub):goto_focus()")
              --- Page rearranging
              , kpress(META.."Shift+period", "_:move_page(_sub, 'right'):paper_goto()")
              , kpress(META.."Shift+comma", "_:move_page(_sub, 'left'):paper_goto()")
})

defbindings("WFrame.toplevel", {
                -- Moving
                  kpress(META.."Left", "left(_, _:viewport_geom().w/2)")
                , kpress(META.."Right", "right(_, _:viewport_geom().w/2)")
                -- , kpress(META.."Shift+period", "_:snap_left():paper_goto()")
                -- , kpress(META.."Shift+comma", "_:snap_right():paper_goto()")
                , mclick("Button1@tab", "_:ensure_in_viewport() _:p_switch_tab()")
                -- , kpress(META.."Shift+period", "_:snap_left():paper_goto()")
                -- , kpress(META.."Shift+comma", "_:snap_right():paper_goto()")
                , kpress(META.."Left", "left(_, _:viewport_geom().w/2)")
                , kpress(META.."Right", "right(_, _:viewport_geom().w/2)")
})
