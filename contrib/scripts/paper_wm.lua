screen_id = 0
screen = ioncore.find_screen_id(screen_id)

outputs = mod_xrandr.get_outputs(screen)
-- Assumes that screen geoms are unique
for _,v in pairs(outputs) do
    viewport_geom = v
end
viewport_w=viewport_geom.w
viewport_h=viewport_geom.h

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
    reg:screen_of():screen_left(screen_to_viewport(sx))
end

function left(reg, amount)
    reg:screen_of():screen_right(amount)
end
function right(reg, amount)
    reg:screen_of():screen_left(amount)
end

function unsetup()
    screen:rqgeom({x=0, y=0, w=viewport_w, h=viewport_h})
end

function setup()
    screen = ioncore.find_screen_id(screen_id)
    ws=screen:current()

    y_slack = -30
    slack = 3*viewport_w

    g = screen:geom()
    screen:rqgeom{x = g.x - slack, y = g.y - y_slack, w = viewport_w+slack*2, h = viewport_h + y_slack*2}

    tiling = ws:current()

    leftbuffer=tiling:farthest("left")
    rightbuffer=tiling:farthest("right")

    leftbuffer:set_name("leftbuffer")
    rightbuffer:set_name("rightbuffer")

    leftbuffer:rqgeom({w = slack})
    rightbuffer:rqgeom({w = slack})
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

function viewport_origin() -- in screen corrdig
    return -screen:geom().x
end

-- screen_to_viewport(viewport_to_screen(100))

function screen_to_viewport(sx)
    return sx - viewport_origin()
end

function viewport_to_screen(x)
    return viewport_origin() + x
end

function maximize_frame(frame)
    frame:rqgeom({w=viewport_w})
    local g = frame:geom()
    right(frame, g.x - viewport_origin())
end

-- Align left viewport edge with frame's left edge
function left_snap(frame)
    local g = frame:geom()
    move_viewport(frame, g.x - 10)
end

-- Align right viewport edge with frame's right edge
function right_snap(frame)
    local g = frame:geom()
    move_viewport(frame, g.x + g.w - viewport_w + 10)
end

-- Find the nth tiling frame where 0 is the left buffer
function WGroupWS.nth_page(ws, n)
    local tiling = current_tiling(ws)
    local next = tiling:farthest("left")
    for i = 1, n do
        -- todo: catch bound errors
        next = tiling:nextto(next, "right")
    end
    return next
end

function WGroupWS.first_page(ws)
    return ws:nth_page(1)
end

function WGroupWS.last_page(ws)
    local tiling = current_tiling(ws)
    local rbuffer = tiling:farthest("right")
    return tiling:nextto(rbuffer, "left")
end

-- Create new page/frame after last_page
function WGroupWS.new_page(ws)
    local tiling = ws:current()
    local rbuffer = tiling:farthest("right")

    local new = WTiling.split_at(tiling, rbuffer, 'left', false)
    new:rqgeom({w=viewport_w/2})
end

function WFrame.next_page(frame)
    local tiling = frame:manager()
    local next = tiling:nextto(frame, 'right')
    if next == tiling:farthest("right") then
        return
    end
    left_snap(next)
    next:goto_()
end

function WFrame.prev_page(frame)
    local tiling = frame:manager()
    local prev = tiling:nextto(frame, 'left')
    if prev == tiling:farthest("right") then
        return
    end
    left_snap(prev)
    prev:goto_()
end

defbindings("WScreen", {
              kpress(META.."Left", "left(_, viewport_w/2)")
              , kpress(META.."Right", "right(_, viewport_w/2)")
              , kpress(META.."Shift+Left", "left(_, viewport_w)")
              , kpress(META.."Shift+Right", "right(_, viewport_w)")

              , kpress(META.."Home", "_:move_screen(-current_tiling():farthest('left'):geom().w)")

              , kpress(META.."Up", "switch_workspace(1)")
              , kpress(META.."Down", "switch_workspace(-1)")

              , mdrag(META.."Button1", "WFrame.p_move(_)")
              , kpress(META.."Tab", "ioncore.goto_previous()")
})

defbindings("WFrame", {
                  kpress(META.."Page_Down", "_:next_page()")
                , kpress(META.."Page_Up", "_:prev_page()")
                , kpress(META.."period", "_:next_page()")
                , kpress(META.."comma", "_:prev_page()")
})
