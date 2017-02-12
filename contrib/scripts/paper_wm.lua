
display_w=1366

screen = ioncore.current():screen_of()

function switch_workspace(dir)
  local screen = ioncore.current():screen_of()

  local current_ws = screen:current()
  local i = screen:get_index(current_ws)
  debug.print_line("i: "..i)

  function current_frame(ws)
    return ws:current():current()
  end

  local a = current_frame(screen:current()):geom()

  -- dir -1 / +1
  local target_ws = screen:mx_nth(i+dir)
  debug.print_line("target_ws: "..target_ws:name())

  local b = current_frame(target_ws):geom()

  local dx = b.x - a.x

  debug.print_line(dx)

  screen:rqgeom({x=screen:geom().x-dx})
  current_frame(target_ws):goto_()
end

function setup()
    screen = ioncore.current():screen_of()
    w=current_workspace()
    y_slack = -80
    slack=3*display_w screen:rqgeom{x=-slack, w=display_w+slack*2, y=-y_slack, h=768+y_slack*2}
    tiling = w:current()
    tiling:farthest("left"):rqgeom({w=slack})
    tiling:farthest("right"):rqgeom({w=slack})
end

-- MOVE CONTROLS
function screenLeft(amount)
    screen:rqgeom{x=screen:geom().x-amount} -- LEFT
end

function screenRight(amount)
    screen:rqgeom{x=screen:geom().x+amount} -- RIGHT
end

function moveScreen(x)
    local y = 0
    local screen = ioncore.current():screen_of()
    screen:rqgeom({x=x})
    -- screen:rqgeom(geomTranslate(screen:geom(), x, y))
end

function left(amount)
    screenRight(amount)
end
function right(amount)
    screenLeft(amount)
end

function current_tiling()
    return current_workspace():current()
end

defbindings("WScreen", {
              kpress(META.."Left", "left(display_w/2)")
              , kpress(META.."Right", "right(display_w/2)")
              , kpress(META.."Shift+Left", "left(display_w)")
              , kpress(META.."Shift+Right", "right(display_w)")

              , kpress(META.."Home", "moveScreen(-current_tiling():farthest('left'):geom().w)")
              , kpress(META.."Page_Up", "left(display_w)")
              , kpress(META.."Page_Down", "right(display_w)")

              , kpress(META.."Up", "switch_workspace(1)")
              , kpress(META.."Down", "switch_workspace(-1)")

              , mdrag(META.."Button1", "WFrame.p_move(_)")
})
