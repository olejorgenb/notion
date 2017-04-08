---- Generic utils

function string.has_prefix(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix
end

--- Keybindings

bindutils = {}

local function strip_mod(kcb)
    local i = string.find(kcb, "+")
    if i then
        return string.sub(kcb, i+1)
    else
        return kcb
    end
end

local function kcb_equal(kcb_spec, kcb)
    if string.has_prefix(kcb_spec, "AnyModifier") then
        kcb_spec=strip_mod(kcb_spec)
        kcb=strip_mod(kcb)
    end
    return kcb_spec == kcb
end

function bindutils.nuke_bindings(kcb, submaps_too)
    function nuke(context, bindmap, kcb)
        for i, bind in ipairs(bindmap) do
            if bind.kcb and kcb_equal(bind.kcb, kcb) then
                if bind.action == "kpress" then
                    ioncore.defbindings(context, {kpress(bind.kcb, nil)})
                elseif string.find(bind.action, "kpress_wai") then
                    ioncore.defbindings(context, {kpress_wait(bind.kcb, nil)})
                elseif submaps_too and bind.submap then
                    ioncore.defbindings(context, {submap(bind.kcb, nil)})
                end
            end
        end
    end
    for context, bindmap in pairs(ioncore.getbindings()) do
        -- IMPROVEMENT? skip query and menu context's maybe.
        nuke(context, bindmap, kcb)
    end
end

--- end Keybindings

---- Paper WM specific

paper = paper or {}

-- Create a mini workspace (aka "paper strip"?) and tile it vertically with `ws` (below)
-- Can be useful for testing
function paper.setup_ministrip(ws, name, height)
    ws = ws or current_workspace()

    if ws:aux("ministrip") then
        debug.print_line(ws:name().." already have a strip")
        return
    end

    local name = name or "mini-strip"
    local height = height or 100
    local screen = ws:screen_of()
    local viewport_h = screen:viewport_geom().h
    local strip = screen:create_workspace(name,
                                          {   x = 0
                                            , y = viewport_h - height
                                            , h = height })
    local wsp = ws:workspace_holder_of()
    local wsgeom = wsp:geom()
    wsp:rqgeom({   y = 0
                 , h = viewport_h - height - 1 })
    ws:aux().ministrip = strip
    return strip
end

function paper.unsetup_ministrip(ws)
    local strip = ws:aux().ministrip
    if not strip then
        return
    end
    strip:parent():rqclose()

    local vp_g = ws:screen_of():viewport_geom()
    ws:workspace_holder_of():rqgeom({ y = vp_g.y, h = vp_g.h })
    ws:aux().ministrip = nil
end

function paper.setup_workarounds()
    ioncore.set {
        activity_notification_on_all_screens = true -- See paper-wm_readme.org "issues" section
    }
end

