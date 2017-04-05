--- Brute force minimap (proof of concept)
-- Go through each window and scrot the content without modifying the focuslist
-- Possibly cache window content, invalidating on focus
--
-- Requires screenshot program 'maim'
-- minimap.zsh must be in PATH

function render_minimap(tiling, on_done, delay, scale_p)
    delay = delay or 100
    scale_p = scale_p or 25
    tiling=current_tiling()
    local current_page = tiling:current()
    local old_animate = animate
    local old_set = ioncore.get()

    local temp_set = { mousefocus="disabled", warp=false }
    ioncore.set(temp_set)
    animate = false 

    local pages = mcollect(tiling.page_i, tiling)

    local ws_name = tiling:manager():name()
    local dir = "/dev/shm/paper-wm-"..ws_name

    local wsh = tiling:workspace_holder_of()
    local a = wsh:viewport_to_screen(0)
    local b = wsh:viewport_to_screen(wsh:viewport_geom().w)
    local scale = scale_p/100.0

    function on_complete()
        debug.print_line(a)
        move_viewport(tiling, a)
        animate = old_animate
        ioncore.set(old_set) -- gaaaah, no concise way to project a table to a set of keys ?
            
        -- "&>> ~/.notion/debug"
        os.execute(string.format("minimap.zsh %s %d %.2f %.2f %s &",
                                 dir, scale_p, a*scale, b*scale, ""))

        if on_done then
            on_done()
        end
    end

    os.execute("mkdir -p "..dir)
    os.execute("rm --force "..dir.."/*")

    local timer = ioncore.create_timer() 

    local i = 1

    --- Don't seem to be that much different from class to class
    -- local delay_table = {
    --       ["Firefox"] = 10
    --     , ["URxvt"]   = 10
    --     , ["Emacs"]   = 10
    -- }
    -- function lookup_delay(class)
    --     local d = delay_table[class]
    --     return d or delay
    -- end

    -- Note: if we don't implement any caching, it's probably better to move in
    --       full screen widths

    function render_and_next()
        local page = pages[i]

        local tex_name = tostring(i)..".png"
        local tex_path = dir.."/"..tex_name
        os.execute(string.format("maim --windowid %d --delay %.2f %s",
                                 page:xid(), 0, tex_path))

        if i >= #pages then
            on_complete()
            return
        end

        i = i + 1

        page = pages[i]
        -- local class = page:current():bottom():get_ident().class
        page:ensure_in_viewport()
        -- Skip delay unless viewport moved?
        timer:set(delay, render_and_next)
    end

    pages[i]:ensure_in_viewport()
    timer:set(delay, render_and_next)
end

function ___repl()
    tic = os.time()
    -- Urxvt actullay seems to be one of the slowest to redraw..
    minimap:rqorder("back") render_minimap(current_tiling(), done, 8, 20)
--: nil
    minimap:rqorder("front")
--: true
    minimap:rqorder("back")
--: true
    minimap:current():bottom():xid()
    current_screen():set_hidden(minimap, "set")
--: true
    function done()
        toc = os.time()
        -- minimap:rqorder("front")
        debug.print_line(tostring(toc-tic))
    end
end

function ensure_minimap()
    local screen = current_screen()
    local minimap = ioncore.lookup_region("*minimap*")
    if not minimap then
        minimap = screen:attach_new{type="WFrame",
                                    name="*minimap*",
                                    bottom=false,
                                    unnumbered=true,
                                    switchto=false,
                                    hidden=false,
                                    sizepolicy=5,
                                    pseudomodal=true,
                                    modal=false,
                                    -- passive=true,
                                    -- level=1
        }
    end

    local screen_geom = screen:geom()
    local h = math.floor(screen_geom.h*0.20)
    minimap:set_mode("tiled-alt")
    minimap:rqgeom{x=0, y=screen_geom.h - h, h=h, w=screen_geom.w}
    -- Seems better to use front/back to show/hide instead of set_hidden
    -- set_hidden(.., "set") changes focus for instance
    minimap:rqorder("back")
    return minimap
end 

function setup_minimap()
    -- IMPROVEMENT: find out how to identify a special instance of feh..
    defwinprop {
        class = "feh"
        , name = "*feh-minimap*"
        , match = function(props, cwin, ident)
            return ident.class == props.class and props.name and cwin:name():has_prefix(props.name)
        end
        , target = "*minimap*"
    }

    ioncore.set{autoraise=true}
    return ensure_minimap()
end

setup_minimap()

function ___repl()
    ioncore.lookup_region("*minimap*"):rqclose_propagate()
--: >> [string "return     ioncore.lookup_region("*minimap*")..."]:1: attempt to index a nil value
    minimap=ensure_minimap()
--: "Type:   WFrame
--:   Name:   *minimap*
--:   Parent: WScreen userdata: 0x101c3f8"
    minimap:rqorder("front")
--: true
    minimap:rqorder("back")
end
