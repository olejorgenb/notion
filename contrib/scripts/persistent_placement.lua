
-- Experimental ad-hoc session management

-- global off/on switch
restore = false
--: false

-- Not implemented: only restore these classes
restore_class = {Firefox = true, Emacs = true}

-- don't store places for these class and name combos, lua regexps
blacklist = {
    -- eg. Firefox starts off with the title Mozilla Firefox
    Firefox = { "^Mozilla Firefox", "^Nighthly" }
    , Emacs = { "^\\*Minibuf-1\\*" }
}


-- save file
persistent_file = "persistent_placement"
persistent_placement = ioncore.read_savefile(persistent_file) or {}

-- Save placements on shutdown
deinit = ioncore.get_hook("ioncore_deinit_hook")
deinit:add(function ()
        ioncore.write_savefile(persistent_file, persistent_placement)
end)


-- session cookies for clientwindows
is_placed = {}
name_counter = {}

-- utility to store all placements
function store_placements()
    ioncore.clientwin_i(function (clientwin)
            store_placement(clientwin)
            is_placed[clientwin] = true
            debug.print_line("stored ".. clientwin:name())
            return true
    end)
end

-- clientwin = ioncore.current()
function store_placement (clientwin)
    name = clientwin:name()
    frame = clientwin:parent()
    xinfo = clientwin:get_ident()

    class_blacklist = blacklist[xinfo.class]
    if class_blacklist then
        for k,n in pairs(class_blacklist) do
            if string.find(name, n) then
                debug.print_line(
                    "not storing blacklisted name "..n.." for class "..xinfo.class)
                -- don't store blacklisted names
                return
            end
        end
    end

    persistent_placement[name] = {
        xinfo = xinfo
        , frame = frame:name()
    }
end

-- Lookup clientwin name and attach the 
-- clientwin = ioncore.current()
function restore_placement(clientwin)

    if not restore then
        is_placed[clientwin] = true
        return
    end
    debug.print_line("entering restore placement")

    local name = clientwin:name()
    debug.print_line("Trying to lookup "..name)
    local place  = persistent_placement[name]

    if not place then
        debug.print_line("  no stored record")
        return
    end
    debug.print_line("  found record:")
    debug.print_table(place)

    local xinfo = clientwin:get_ident()
    -- check if the xinfo matches
    for k, v in pairs(xinfo) do
        if v ~= place.xinfo[k] then
            debug.print_line("name, "..name..", matched but not the "..k)
            return
        end
    end

    -- place the clientwinow/group
    target_frame = ioncore.lookup_region(place.frame)
    group = clientwin:manager()
    ioncore.defer(function ()
            if group then
                target_frame:attach(group)
            else
                target_frame:attach(clientwin)
            end
            debug.print_line("attached group: "..group:name())
            debug.print_line("placed "..clientwin:name().." at "..target_frame:name())

            -- Set cookie on clientwindow
            is_placed[clientwin] = true
    end)

    -- mark the clientwin as placed
end

notify = ioncore.get_hook("region_notify_hook")

-- Remove the hook if it already exists
notify:remove(name_hook)

-- Run on all namechanges
function name_hook(clientwin, name)
    if name == "name" then

        if clientwin.__typename == "WClientWin" then

            local manager = clientwin:manager()
            -- local g_manager = manager:manager()
            local frame = clientwin:parent()

            if not manager or not frame then
                -- ignore windows that aren't managed yet
                return
            end

            name_counter[clientwin] = name_counter[clientwin] or 0

            local xinfo = clientwin:get_ident()

            if xinfo.class == "Spotify" then
                return
            end

            debug.print_line("---- start notify debug ----")

            debug.print_line(return_tree(manager))
            -- debug.print_line("target frame: ".. frame:name())

            -- only update placement if the window is placed
            if is_placed[clientwin] then
                store_placement(clientwin)
                debug.print_line("Store clientwin")

            -- Regard the window as placed when the name have changed more that twice
            elseif name_counter[clientwin] > 2 then
                is_placed[clientwin] = true
            else
                debug.print_line("Restore clientwin")
                restore_placement(clientwin)
                name_counter[clientwin] = name_counter[clientwin] + 1
            end

            debug.print_line("---- stop notify debug ----")
            debug.print_line("")
        end

    end
end
notify:add(name_hook)

manage_alt = ioncore.get_hook("clientwin_do_manage_alt")
manage_alt:remove(manage_hook)
-- Run on all new windows
function manage_hook (clientwin, options)

    local xinfo = clientwin:get_ident()
    local name = clientwin:name()
    name_counter[clientwin] = 0

    debug.print_line("---- start manage_alt debug ----")
    debug.print_line("name: "..name)
    debug.print_line("xinfo:")
    debug.print_table(xinfo)
    debug.print_line("options:")
    debug.print_table(options)

    -- Possible timeout implementation
    -- timer = ioncore.create_timer()

    -- regard as placed after 4 seconds
    -- timer:set(4000, function () is_placed[clientwin] = true end)

    if persistent_placement[name] then
        restore_placement(clientwin)
    end

    debug.print_line("---- stop manage_alt debug ----")
    debug.print_line("")
end
manage_alt:add(manage_hook)

-- store_placements()
