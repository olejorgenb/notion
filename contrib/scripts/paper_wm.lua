
overlap = {x = 10, y = 5}

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

function WScreen.viewport_geom(screen)
    return viewport_geoms[screen:id()+1]
end

-- Utility functions
function current_workspace(screen)
    screen = screen or ioncore.current():screen_of()
    return screen:current()
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

function find_current(mng, classname)
    while mng.current and mng.__typename ~= classname do
        mng = mng:current()
    end
    return mng
end


function WScreen.screen_left(screen, amount)
    screen:rqgeom{x=screen:geom().x-amount} -- LEFT
end

function WScreen.screen_right(screen, amount)
    screen:rqgeom{x=screen:geom().x+amount} -- RIGHT
end

function WScreen.move_screen(screen, x)
    local y = 0
    screen:rqgeom({x=x})
end

-- Align the viewport origin with sx
function move_viewport(reg, sx)
    local screen = reg:screen_of()
    screen:screen_left(screen:screen_to_viewport(sx))
end

function left(reg, amount)
    reg:screen_of():screen_right(amount)
end
function right(reg, amount)
    reg:screen_of():screen_left(amount)
end

function unsetup()
    local display_g = mod_xinerama.query_screens()[screen:id() + 1]
    screen:rqgeom({x=0, y=0, w=display_g.w, h=display_g.h})
end


-- return true if a new buffer was created
function ensure_buffer(tiling, dir, buffer_w)
    function has_prefix(String,Start)
        return string.sub(String,1,string.len(Start))==Start
    end

    local buffer_maybe = tiling:farthest(dir)
    local buffer = nil
    local buffer_name = "*"..dir.."*"
    if has_prefix(buffer_maybe:name(), buffer_name) then
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

function setup(adapt_workspaces)
    screen = ioncore.find_screen_id(screen_id)
    view_g = screen:viewport_geom()

    x_slack = 6*view_g.w

    local screen_g = screen:geom()
    -- This isn't idempotent because of 
    screen:rqgeom{ x = view_g.x,
                   y = view_g.y,
                   w = view_g.w + x_slack,
                   h = view_g.h }

    if adapt_workspaces then
        local wss = {}
        screen:managed_i(function(ws, i) table.insert(wss, ws) return true end)
        for i, ws in ipairs(wss) do
            -- managed_i operates in protected mode
            adapt_workspace(ws, x_slack)
        end
    end
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
    local screen = ws:screen_of()
    local view_g = screen:viewport_geom()
    local b, new_b = ensure_buffer(tiling, "right", screen:geom().w - view_g.w)
    if new_b then
        left_snap(ws:first_page())
    end
    return true
end

-- dir == 1 | -1
function switch_workspace(dir)
  local screen = ioncore.find_screen_id(screen_id)

  local cur_ws = screen:current()
  local i = screen:get_index(cur_ws)

  local target_ws = screen:mx_nth(i+dir)

  local cur_frame = current_frame(cur_ws)
  local target_frame = current_frame(target_ws)

  local a = cur_frame:geom()
  local b = target_frame:geom()

  local dx = b.x - a.x

  screen:rqgeom({x=screen:geom().x-dx})

  target_frame:goto_()
end

-- in screen coordinates
function WScreen.viewport_origin(screen)
    return -screen:geom().x + overlap.x
end

-- screen_to_viewport(viewport_to_screen(100))

function WScreen.screen_to_viewport(screen, sx)
    return sx - screen:viewport_origin()
end

function WScreen.viewport_to_screen(screen, x)
    return screen:viewport_origin() + x
end

function maximize_frame(frame)
    local screen = frame:screen_of()
    local view_g = screen:viewport_geom()
    frame:rqgeom({w=view_g.w})
    local g = frame:geom()
    right(frame, g.x - screen:viewport_origin())
end

-- Align left viewport edge with frame's left edge
function left_snap(frame)
    local g = frame:geom()
    move_viewport(frame, g.x)
    return frame
end

-- Align right viewport edge with frame's right edge
function right_snap(frame)
    local g = frame:geom()
    local view_g = frame:screen_of():viewport_geom()
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
    left_snap(first):goto_()
    return first
end

function WGroupWS.last_page(ws)
    local tiling = current_tiling(ws)
    local rbuffer = tiling:farthest("right")
    local last = tiling:nextto(rbuffer, "left")
    right_snap(last):goto_focus()
    return last
end

-- Create new page/frame after last_page
function WGroupWS.new_page(ws)
    local tiling = ws:current()
    local rbuffer = tiling:farthest("right")
    local new = WTiling.split_at(tiling, rbuffer, 'left', false)
    local view_g = ws:screen_of():viewport_geom()
    new:rqgeom({w=view_g.w/2})
    return new
end

function WFrame.next_page(frame)
    local tiling = frame:manager()
    local next = tiling:nextto(frame, 'right')
    if next == tiling:farthest("right") then
        return
    end
    local screen = frame:screen_of()
    local x = screen:screen_to_viewport(next:geom().x)
    local w = next:geom().w
    local view_g = frame:screen_of():viewport_geom()
    if x + w >= view_g.w then
        right_snap(next)
    end
    next:goto_()
end

function WFrame.prev_page(frame)
    local tiling = frame:manager()
    local prev = tiling:nextto(frame, 'left')
    if prev == tiling:farthest("right") then
        return
    end
    local screen = frame:screen_of()
    local x = screen:screen_to_viewport(prev:geom().x)
    if x <= 0 then
        left_snap(prev)
    end
    prev:goto_()
end

if not WRegion.old_goto then
    WRegion.old_goto = WRegion.goto_focus
end
function WRegion.paper_goto(reg)

    local target_frame = nil
    if reg.__typename == "WGroupWS" then
        target_frame = find_current(reg, "WFrame")
    else
        target_frame = frame_of(reg)
    end

    local screen = reg:screen_of()
    local g = target_frame:geom()
    local x = screen:screen_to_viewport(g.x)

    local view_g = screen:viewport_geom()
    if x < 0 then
        left_snap(target_frame)
    elseif x + g.w > view_g.w then
        right_snap(target_frame)
    end

    reg:old_goto()
end

WRegion.goto_focus = WRegion.paper_goto
WRegion.goto_ = WRegion.goto_focus



defbindings("WScreen", {
              kpress(META.."Left", "left(_, _:viewport_geom().w/2)")
              , kpress(META.."Right", "right(_, _:viewport_geom().w/2)")
              , kpress(META.."Shift+Left", "left(_, _:viewport_geom().w)")
              , kpress(META.."Shift+Right", "right(_, _:viewport_geom().w)")

              , kpress(META.."Up", "switch_workspace(1)")
              , kpress(META.."Down", "switch_workspace(-1)")

              , mdrag(META.."Button1", "WFrame.p_move(_)")
              , kpress(META.."Tab", "ioncore.goto_previous()")
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
})

defbindings("WFrame", {
                  kpress(META.."Page_Down", "_:next_page()")
                , kpress(META.."Page_Up", "_:prev_page()")
                , kpress(META.."period", "_:next_page()")
                , kpress(META.."comma", "_:prev_page()")
})
