screen_id = 0
screen = ioncore.find_screen_id(screen_id)

outputs = mod_xrandr.get_outputs(screen)
-- Assumes that screen geoms are unique
for _,v in pairs(outputs) do
    viewport_geom = v
end
viewport_w=viewport_geom.w
viewport_h=viewport_geom.h

function current_tiling()
    return current_workspace():current()
end

function current_frame(ws)
    ws = ws or current_workspace()
    return ws:current():current()
end

function screen_left(amount)
    screen:rqgeom{x=screen:geom().x-amount} -- LEFT
end

function screen_right(amount)
    screen:rqgeom{x=screen:geom().x+amount} -- RIGHT
end

function move_screen(x)
    local y = 0
    local screen = ioncore.find_screen_id(screen_id)
    screen:rqgeom({x=x})
    -- screen:rqgeom(geomTranslate(screen:geom(), x, y))
end

-- Align the viewport origin with sx
function move_viewport(sx)
  screen_left(screen_to_viewport(sx))
end

function left(amount)
    screen_right(amount)
end
function right(amount)
    screen_left(amount)
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
    right(g.x - viewport_origin())
end

-- Align left viewport edge with frame's left edge
function left_snap(frame)
    local g = frame:geom()
    move_viewport(g.x)
end

-- Align right viewport edge with frame's right edge
function right_snap(frame)
    local g = frame:geom()
    move_viewport(g.x + g.w - viewport_w)
end

function next_page(frame)
    local next = workspace_of(frame):current():nextto(frame, 'right')
    left_snap(next)
   next:goto_()
end

function prev_page(frame)
    local prev = workspace_of(frame):current():nextto(frame, 'left')
    left_snap(prev)
    prev:goto_()
end

defbindings("WScreen", {
              kpress(META.."Left", "left(viewport_w/2)")
              , kpress(META.."Right", "right(viewport_w/2)")
              , kpress(META.."Shift+Left", "left(viewport_w)")
              , kpress(META.."Shift+Right", "right(viewport_w)")

              , kpress(META.."Home", "move_screen(-current_tiling():farthest('left'):geom().w)")

              , kpress(META.."Up", "switch_workspace(1)")
              , kpress(META.."Down", "switch_workspace(-1)")

              , mdrag(META.."Button1", "WFrame.p_move(_)")
})

defbindings("WFrame", {
                  kpress(META.."Page_Down", "next_page(_)")
                , kpress(META.."Page_Up", "prev_page(_)")
})
