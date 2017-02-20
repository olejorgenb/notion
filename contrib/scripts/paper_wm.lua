
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


-- Find the frame that holds the current workspace
-- returns nil if the parent of reg's workspace isn't a frame
function WRegion.workspace_holder_of(reg)
    local workspace = workspace_of(reg)
    local parent = workspace and workspace:parent()
    if parent and parent.__typename == "WFrame" then
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
    return reg:name():has_prefix("*right*")
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
    ws_holder:screen_left(ws_holder:screen_to_viewport(sx))
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
    if new_b then
        ws:first_page():snap_left()
    end
    return true
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

-- Find the nth tiling frame (1-indexed)
function WGroupWS.nth_page(ws, n)
    local tiling = current_tiling(ws)
    local current = tiling:farthest("left")
    local stop = tiling:farthest("right")
    local next = tiling:nextto(current, "right")

    while n > 1 and next ~= stop do
        current = next
        next = tiling:nextto(current, "right")
        n = n-1
    end
    return current
end

function WGroupWS.first_page(ws)
    local first = ws:nth_page(1)
    first:snap_left():goto_()
    return first
end

function WGroupWS.last_page(ws)
    local tiling = current_tiling(ws)
    local rbuffer = tiling:farthest("right")
    local last = tiling:nextto(rbuffer, "left")
    last:snap_right():goto_focus()
    return last
end

-- Create new page/frame after last_page
function WGroupWS.new_page(ws)
    local tiling = ws:current()
    local rbuffer = tiling:farthest("right")
    local new = WTiling.split_at(tiling, rbuffer, 'left', false)
    local view_g = ws:workspace_holder_of():viewport_geom()
    new:rqgeom({w=view_g.w/2})
    return new
end

-- Insert a blank page to the right/left of the current frame
function WGroupWS.insert_page(ws, direction)
    direction = direction or "right"
    local tiling = ws:current()
    local frame = tiling:current()
    local frame_g = frame:geom()
    local view_g = ws:workspace_holder_of():viewport_geom()

    frame:resize_right(view_g.w)
    local new = WTiling.split_at(tiling, frame, direction, false)
    frame:resize_right(frame_g.w)
    frame:paper_goto()
    return new
end

-- Delete frame from tiling, preserving all other page widths
-- frame = current_frame()
function WFrame.delete_page(frame)
    local tiling = frame:manager()
    local left = tiling:nextto(frame, "left")
    local right = tiling:nextto(frame, "right")
    -- remember geometry
    local left_g = left:geom()
    local right_g = right:geom()

    frame:rqclose()
    -- fix up widths
    ioncore.defer(function ()
            left:resize_right(left_g.w)
            right:resize_right(right_g.w)
    end)
end

function WFrame.next_page(frame)
    local tiling = frame:manager()
    local next = tiling:nextto(frame, 'right')
    if next == tiling:farthest("right") then
        return
    end
    local ws_holder = frame:workspace_holder_of()
    local x = ws_holder:screen_to_viewport(next:geom().x)
    local w = next:geom().w
    local view_g = frame:workspace_holder_of():viewport_geom()
    if x + w >= view_g.w then
        next:snap_right()
    end
    next:goto_()
end

function WFrame.prev_page(frame)
    local tiling = frame:manager()
    local prev = tiling:nextto(frame, 'left')
    if prev == tiling:farthest("right") then
        return
    end
    local ws_holder = frame:workspace_holder_of()
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

    reg:ensure_in_viewport()

    reg:original_goto()
end

WRegion.goto_focus = WRegion.paper_goto
WRegion.goto_ = WRegion.goto_focus


function WFrame.resize_right_delta(frame, delta)
    local new_w = frame:geom().w + delta
    return frame:resize_right(new_w)
end

function WFrame.resize_right(frame, new_w)
    local tiling = frame:manager()
    local node = tiling:node_of(frame)
    if new_w > 5 then
        node:resize_right(new_w)
    end
    return frame
end

function WFrame.paper_maximize(frame)
    local frame_aux = frame:aux()
    if frame_aux.maximized then
        frame:resize_right(frame_aux.original_g.w)
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

        frame:resize_right(view_g.w)
        right(frame, g.x - ws_holder:viewport_origin())
    end
    return frame
end

-- Expand the frame utilizing all space occupied by partially visible
-- frames
function WFrame.paper_expand_free(frame)
    -- TOOD:
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
                      })
})

defbindings("WFrame.toplevel", {
                  kpress(META.."Left", "left(_, _:viewport_geom().w/2)")
                , kpress(META.."Right", "right(_, _:viewport_geom().w/2)")

})

defbindings("WGroupWS", {
              kpress(META.."Home", "_:first_page()")
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
              , kpress(META.."0", "_:last_page()")
              --- Page creation/deletion
              , kpress(META.."N", "_:insert_page():paper_goto()")
              , kpress(META.."Shift+N", "_:new_page():paper_goto()")

              -- , mdrag(META.."Button1", "WRegion.p_move(_)") -- comment in to move the whole workspace with the mouse
})

defbindings("WFrame", {
                  kpress(META.."Page_Down", "_:next_page()")
                , kpress(META.."Page_Up", "_:prev_page()")
                , kpress(META.."period", "_:next_page()")
                , kpress(META.."comma", "_:prev_page()")
                , kpress(META.."Shift+period", "_:snap_left():paper_goto()")
                , kpress(META.."Shift+comma", "_:snap_right():paper_goto()")
                --- Resizing
                , kpress(META.."plus", "_:resize_right_delta(30):goto_focus()")
                , kpress(META.."minus", "_:resize_right_delta(-30):goto_focus()")
                , kpress(META.."H", "_:paper_maximize():goto_focus()")
                --- Page creation/deletion
                , kpress(META.."D", "_:delete_page()")
                , mclick("Button1@tab", "_:ensure_in_viewport() _:p_switch_tab()")
})
