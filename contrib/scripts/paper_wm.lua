
viewport_w=1366
viewport_h=768

screen = ioncore.current():screen_of()

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
    local screen = ioncore.current():screen_of()
    screen:rqgeom({x=x})
    -- screen:rqgeom(geomTranslate(screen:geom(), x, y))
end

function left(amount)
    screen_right(amount)
end
function right(amount)
    screen_left(amount)
end

function setup()
    screen = ioncore.current():screen_of()
    ws=current_workspace()

    y_slack = -30
    slack = 3*viewport_w

    screen:rqgeom{x = -slack, w = viewport_w+slack*2, y = -y_slack, h = viewport_h + y_slack*2}

    tiling = ws:current()

    leftbuffer=tiling:farthest("left")
    rightbuffer=tiling:farthest("right")

    leftbuffer:set_name("leftbuffer")
    rightbuffer:set_name("rightbuffer")

    leftbuffer:rqgeom({w = slack})
    rightbuffer:rqgeom({w = slack})
end

setup()

-- dir == 1 | -1
function switch_workspace(dir)
  local screen = ioncore.current():screen_of()

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

-- table_to_string(screen:geom())
-- screen_to_viewport(viewport_to_screen(100))

function screen_to_viewport(sx)
    return sx - viewport_origin()
end

function viewport_to_screen(x)
    return viewport_origin() + x
end


function maximize_frame(frame)
    local g = frame:geom()
    moveScreen(g.x)
end

-- maximize_frame(current_frame())

setup()


defbindings("WScreen", {
              kpress(META.."Left", "left(viewport_w/2)")
              , kpress(META.."Right", "right(viewport_w/2)")
              , kpress(META.."Shift+Left", "left(viewport_w)")
              , kpress(META.."Shift+Right", "right(viewport_w)")

              , kpress(META.."Home", "move_screen(-current_tiling():farthest('left'):geom().w)")
              , kpress(META.."Page_Up", "left(viewport_w)")
              , kpress(META.."Page_Down", "right(viewport_w)")

              , kpress(META.."Up", "switch_workspace(1)")
              , kpress(META.."Down", "switch_workspace(-1)")

              , mdrag(META.."Button1", "WFrame.p_move(_)")
})
