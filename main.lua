local mods = rom.mods

---@module 'SGG_Modding-ENVY-auto'
mods['SGG_Modding-ENVY'].auto()

_PLUGIN = _PLUGIN

---@module 'game'
game = rom.game

---@module 'game-import'
import_as_fallback(game)

---@module 'SGG_Modding-ModUtil'
modutil = mods['SGG_Modding-ModUtil']

---@module 'SGG_Modding-ReLoad'
reload = mods['SGG_Modding-ReLoad']

---@module 'SGG_Modding-SJSON'
sjson = mods['SGG_Modding-SJSON']


function startup()
    local utils = import 'src/utils.lua'
    utils.loadPractiseTexts()

    import 'src/PractiseMenu.lua'
    rom.gui.add_always_draw_imgui(PractisePerFrame)
end

local function on_ready()
    -- startup()
end

local function on_reload()
    startup()
end

local loader = nil
if reload ~= nil then
    -- this allows us to limit certain functions to not be reloaded.
    loader = reload.auto_single()
end

-- this runs only when modutil and the game's lua is ready
modutil.once_loaded.game(function()
    if loader == nil then
        startup()
    else
        loader.load(on_ready, on_reload)
    end
end)
