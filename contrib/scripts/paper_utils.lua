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

function bindutils.nuke_bindings(kcb)
    function nuke(context, bindmap, kcb)
        for i, bind in ipairs(bindmap) do
            if bind.kcb and kcb_equal(bind.kcb, kcb) then
                if bind.action == "kpress" then
                    ioncore.defbindings(context, {kpress(bind.kcb, nil)})
                elseif string.find(bind.action, "kpress_wai") then
                    ioncore.defbindings(context, {kpress_wait(bind.kcb, nil)})
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

-- paper = {}
