
function DebugImGuiObject(object)
    local ImGui = rom.ImGui
    local function draw_node(tbl, key, value)
        local val_type = type(value)
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        
        if val_type == "table" then
            local open = ImGui.TreeNodeEx(tostring(key));
            if open then
                for k, v in pairs(value) do
                    draw_node(value, k, v)
                end
                ImGui.TreePop()
            end
        else
            ImGui.Text(tostring(key))
            ImGui.TableNextColumn()
            ImGui.Text(tostring(value))
        end
    end

    ImGui.BeginTable("Data", 3)
    ImGui.TableSetupColumn("Name", rom.ImGuiTableColumnFlags.NoHide)
    ImGui.TableSetupColumn("Value")
    ImGui.TableSetupColumn("Edit", rom.ImGuiTableColumnFlags.WidthFixed, 50)
    ImGui.TableHeadersRow()
    for k, v in pairs(object) do
        draw_node(object, k, v)
    end
    ImGui.EndTable()
end

local function expandoTriangle(draw_list, x, y, open)
    if open then
        rom.ImGui.ImDrawListAddTriangleFilled(draw_list,
            x +  8, y +  3,
            x + 24, y +  3,
            x + 16, y + 19,
            0xFFFFFFFF
        )
    else
        rom.ImGui.ImDrawListAddTriangleFilled(draw_list,
            x +  8, y +  3,
            x + 24, y + 11,
            x +  8, y + 19,
            0xFFFFFFFF
        )
    end
end

local PanelStates = {}

local function Panel(name, args)
    args = args or {}
    local ImGui = rom.ImGui
    local style = ImGui.GetStyle()
    ImGui.PushID(name)
    local panelID = tostring(ImGui.GetID("Panel"))
    if PanelStates[panelID] == nil then
        PanelStates[panelID] = {}
    end
    local panelState = PanelStates[panelID]
    local wasOpen = args.WasOpen
    local isOpen = args.IsOpen
    args.WasOpen = isOpen
    if isOpen == nil then isOpen = panelState.IsOpen == true end
    local isButtonClicked = false

    local cols = 1
    local buttonWidth = 0
    local descWidth = 0
    if args.Description ~= nil then
        descWidth = ImGui.CalcTextSize(args.Description)
        cols = cols + 1
    end
    if args.ButtonLabel ~= nil then
        buttonWidth = ImGui.CalcTextSize(args.ButtonLabel) + (style.FramePadding.x * 2)
        cols = cols + 1
    end

    local line_height = ImGui.GetTextLineHeight()
    local draw_list = ImGui.GetWindowDrawList()
    local w = ImGui.GetContentRegionAvail()

    local x, y = ImGui.GetCursorScreenPos()
    local padding = 8

    -- alternate colors based on hover state
    local bg_color = args.Color or ImGui.GetColorU32(rom.ImGuiCol.Header, 1.0)
    local hvr_color = args.HoverColor or args.Color or ImGui.GetColorU32(rom.ImGuiCol.HeaderHovered, 1.0)
    local pos = { x, y - padding, x + w, y + line_height + padding }
    
    -- background fill
    ImGui.SetCursorScreenPos(x, y - padding)
    ImGui.InvisibleButton("##bg", w - buttonWidth, line_height + (padding * 2))
    ImGui.SetCursorScreenPos(x, y)

    local isClickingPanel = ImGui.IsItemClicked()

    if ImGui.IsItemHovered() or isOpen then
        bg_color = hvr_color
    end

    ImGui.ImDrawListAddRectFilled(draw_list, pos[1], pos[2], pos[3], pos[4], bg_color, 2.0)

    -- chevron right or down to show expanded state
    expandoTriangle(draw_list, x, y, isOpen)
    
    local posx, posy = ImGui.GetCursorScreenPos()
    panelState.Position = { x = posx, y = posy }
    ImGui.SetCursorScreenPos(x + 32, y - padding)
    
    ImGui.BeginTable("StatLines", cols)
    ImGui.TableSetupColumn("Name")
    if args.Description ~= nil then
        ImGui.TableSetupColumn("Description", rom.ImGuiTableColumnFlags.WidthFixed, descWidth)
    end
    if args.ButtonLabel ~= nil then
        ImGui.TableSetupColumn("Button", rom.ImGuiTableColumnFlags.WidthFixed, buttonWidth + 2)
    end

    ImGui.TableNextRow()
    ImGui.TableNextColumn()
    ImGui.AlignTextToFramePadding()
    ImGui.Text(args.Label or "")

    if args.Description ~= nil then
        ImGui.TableNextColumn()
        ImGui.Text(args.Description or "")
    end

    if args.ButtonLabel ~= nil then
        ImGui.TableNextColumn()
        ImGui.Button(args.ButtonLabel, buttonWidth, line_height + (padding * 2) - 4)
        if ImGui.IsItemClicked() then
            isButtonClicked = true
            isClickingPanel = false
        end
    end

    ImGui.EndTable()

    if isClickingPanel then
        panelState.IsOpen = not isOpen
    end
    
    ImGui.SetCursorScreenPos(posx, posy + 30)


    if isOpen and not wasOpen and panelState.PrevY ~= nil then
        local distance = y - panelState.PrevY
        if distance < 0 then
            ImGui.SetScrollY(ImGui.GetScrollY() + distance)
        end
        panelState.PrevY = nil
    end

    if not isOpen then
        panelState.PrevY = y
    end

    ImGui.PopID()

    return isOpen == true, isButtonClicked, isClickingPanel
end

return {
    Panel = Panel,
}
