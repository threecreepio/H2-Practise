import "./src/PractiseStoredState.lua"
import './src/SavedBuilds.lua'
import './src/CurrentBuild.lua'
import './src/Encounters.lua'
import './src/Widgets.lua'
local utils = import './src/utils.lua'

local started = false
local function sharedStart()
    if started == true then return true end
    if GameState == nil then return false end
    local createStateIfNeeded = import "./src/PractiseStoredState.lua"
    createStateIfNeeded()
    started = true
    return true
end

ModUtil.Path.Wrap("RequestSave", function( base, args )
    PractiseStoredState.PendingCheckpoint = false
    base( args )
end)

local isOpen = false

local function TabItem(name)
    local state = WidgetState()
    local open = rom.ImGui.BeginTabItem(name)
    if state.openPanel == nil then open = true end
    local isOpening = open and (state.openPanel ~= name or isOpen == false)
    if open then
        state.openPanel = name
        isOpen = true
    end
    return open, isOpening
end

function PractisePerFrame()
    if sharedStart() == false then return end

    if PractiseStoredState.PendingCheckpoint then
        if CurrentHubRoom ~= nil then
	        RequestSave({ DevSaveName = CreateDevSaveName( CurrentRun, { StartNextMap = deathMap, PostDeath = true, } ), })
            PractiseStoredState.PendingCheckpoint = false
        end
    end

    RemoveInputBlock({ Name = "Practise" })
    if rom.gui.is_open() then
        PractiseStoredState.Blocking = not IsInputAllowed()
        AddInputBlock({ Name = "Practise" })
        PractiseMenu()
        WidgetStateGC()
    else
        isOpen = false
    end

end

function PractiseMenu()
    local ImGui = rom.ImGui
    ImGui.SetNextWindowSizeConstraints(500, 250, 2048, 2048)
    ImGui.SetNextWindowSize(600, 800, rom.ImGuiCond.FirstUseEver)

    if ImGui.Begin("Threecreepio Practise") then
        ImGui.BeginTabBar("ThreecreepioPractise")

        local open, appearing = TabItem("Saved Builds")
        if open then
            if utils.SafeBeginChild("Content", 0, 0, false) then
                PractiseSavedBuildsMenu(appearing)
                ImGui.EndChild()
            end
            ImGui.EndTabItem()
        end
        
        local open, appearing = TabItem("Build")
        if open then
            if utils.SafeBeginChild("Content", 0, 0, false) then
                PractiseCurrentBuildMenu(appearing)
                ImGui.EndChild()
            end
            ImGui.EndTabItem()
        end

        local open, appearing = TabItem("Encounters")
        if open then
            if utils.SafeBeginChild("Content", 0, 0, false) then
                PractiseEncountersMenu(appearing)
                ImGui.EndChild()
            end
            ImGui.EndTabItem()
        end

        ImGui.EndTabBar()
        ImGui.End()
    end
end
