---- Generic utils

function string.has_prefix(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix
end

function table_to_string(tab, depth_limit, param)

    function slice(tbl, first, last, step)
        local sliced = {}

        for i = first or 1, last or #tbl, step or 1 do
            sliced[#sliced+1] = tbl[i]
        end

        return sliced
    end

    function indent(levels, depth)
        local s = ""
        for i, c in ipairs(levels) do
            if i >= depth then break end
            s=s..c.." "
        end
        return s
        -- return table.concat(slice(levels, 1, depth), " ")
    end

    function table_to_linestring(tab)
        local kvs = {}
        for k,v in pairs(tab) do
            table.insert(kvs, k..": "..tostring(v))
        end
        return "{ "..table.concat(kvs, ", ").." }"
    end

    function notion_inliner(k, v)
        --- Returns the inlined value and a set of keys consumed
        if k == "geom" then
            return table_to_linestring(v), v
        elseif v["type"] then
            if v.name then
                return v["type"]..": "..v.name, { type=true, name=true }
            else
                return v["type"], { type=true }
            end
        else 
            return nil
        end
    end

    local default_param = {
        tostring_fn = function(v)
            if type(v) == "userdata" and v.__typename
            then return "["..v.__typename.."]"
            else return tostring(v)
            end
        end,
        inliner = notion_inliner,
        filter = function(k, v) return true end,
    }

    param = table.join(param or {}, default_param)

    local lines = {}

    -- indent indicators indexed by `depth`
    local levels = {}

    function filter_table(t, f)
        local res={}
        for k, v in pairs(t) do
            res[k]=f(k, v)
        end
        return res
    end

    function recurse(tab, depth, skip)
        local more = ((depth_limit == nil) or depth < depth_limit)

        function skip_filter_p(k, v)
            if skip and skip[k] then
                return nil
            end
            if not param.filter(k, v) then
                -- debug.print_line("Skipping "..k)
                return nil
            end
            return v
        end

        local filtered = filter_table(tab, skip_filter_p)

        for k,v in pairs(filtered) do
            local entry = indent(levels, depth).."+-"..k..": "

            if type(v) == "table" then
                local inlined, consumed_keys = param.inliner(k, v)
                if not inlined then
                    if not more then
                        inlined = "{...}"
                    elseif not next(v) then
                        inlined = "{}"
                    end
                end
                if inlined then
                    entry = entry..inlined
                end
                table.insert(lines, entry)

                indent_char = " "
                if next(filtered, k) then
                   indent_char = "|"
                end
                levels[depth] = indent_char
                if more then
                    recurse(v, depth+1, consumed_keys)
                end
            else
                entry = entry..param.tostring_fn(v)
                table.insert(lines, entry)
            end
        end
    end

    recurse(tab, 1)

    return table.concat(lines, "\n")
end

--- Debug

-- (Ab)use loss debug module as namespace if it's present
if debug == nil then
    debug = {}
end

-- Or simply write to stderr/stdout?
debug.output_file_name = "~/.notion/debug"
debug.output_file = nil

debug.print = nil

function debug.write(...)
    if not debug.output_file then
        debug.output_file = io.open(glob(debug.output_file_name), "a+")
    end
    for i, str in ipairs(table.pack(...)) do
        debug.output_file:write(str)
    end
    debug.output_file:flush()	
end

function debug.printf(formatstr, ...)
    formatstr = tostring(formatstr)
    debug.write(string.format(formatstr, ...), "\n")
end

--- dump all local variables to the debug file
function debug.dump_locals()
    local i = 1
    while i < 100 do
        local name, value = debug.getlocal(2, i)
        if not name then break end
        debug.print_line(name.."\t"..tostring(value))
        i = i+1
    end
end

function debug.print_line(str)
    debug.write((str or "nil").."\n")
end

function debug.log(formatstr, ...)
    debug.write(os.date("%H:%M:%S"), " ",
                string.format(formatstr, ...), "\n")
end

function pp_region_layout(root, wanted_keys)
    default_keys = {
        type=true, name=true
        , managed=true
        , split_tree=true
        , tl=true, br=true
    }
    
    wanted_keys = table.join(wanted_keys or {}, default_keys)
    return table_to_string(root:get_configuration(), nil,
                           { filter =
                                 function(k, v)
                                     return type(k) ~= "string" or wanted_keys[k]
                                 end
    })
end

-- end Debug

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

