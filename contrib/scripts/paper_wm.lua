

--- Mulig vei:
-- Bytt slik at mod_tiling "tar plass fra" de ytterste tilingene når en split blir større


---

f=ioncore.current():parent()

table_to_string(f:rqgeom{w=400})

-- f.__typename


-- t = f:manager()

-- table_to_string(t:rqgeom{x=-50})

w=current_workspace()


s=w:parent()
s:name()

--- RESET POSITION
function reset()
  slack=800 s:rqgeom{x=-slack, w=1440+slack*2}
end

-- WHERE?
function where()
  table_to_string(s:geom())
end

-- MOVE CONTROLS
function screenLeft()
  s:rqgeom{x=s:geom().x-40} -- LEFT
end

function screenRight()
  s:rqgeom{x=s:geom().x+40} -- RIGHT
end

function geomTranslate(g, x, y)
  return { x=g.x + x,
           y=g.y + y,

           w=g.w, g=g.h}
end

function moveScreen(x, y)
  s:rqgeom(geomTranslate(s:geom(), x, y))
end


function left()
  screenRight()
end
function right()
  screenLeft()
end

function up()
  moveScreen(0, snap_size)
end

function down()
  moveScreen(0, -snap_size)
end

function controlWidget()
  reset()

  left()
  right()

  where()
end

reset()


snap_size=40

defbindings("WScreen", {
              kpress(META.."Left",  left)
              , kpress(META.."Right", right)
              , kpress(META.."Up", up)
              , kpress(META.."Down", down)
})
