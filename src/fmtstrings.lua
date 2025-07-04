local utils = import "./src/utils.lua"

local function createFormatText(text)
    if text == nil then return text end

    local output = {}
    local state = 0
    local type = ""
    local n = 1
    local m = 1
    while n <= #text + 1 do
        local c = string.char(text:byte(n))
        if state == 0 and c == "{" then
            if n > m then output[#output + 1] = { Type = "", Value = string.sub(text, m, n - 1) } end
            m = n
            n = n + 1
            state = 1
        end
        if state == 1 then
            type = string.sub(text, n, n)
            m = n + 1
            state = 2
        end
        if state == 2 and c == "}" then
            output[#output + 1] = { Type = type, Value = string.sub(text, m, n - 1) }
            m = n + 1
            state = 0
        end
        n = n + 1
    end

    if m <= #text then
        output[#output + 1] = { Type = "", Value = string.sub(text, m) }
    end

    return output
end

local fmtCache = {}
local function getFormatText(format, context)
    -- for some reason, sometimes there's just a plain string which should still be fixed
    if context[format] ~= nil then
        format = context[format]
    end

    -- for some reason, sometimes there's just a plain trait name which should still be fixed
    if PractiseTexts.Trait[format] ~= nil then
        format = PractiseTexts.Trait[format]
    end

    if fmtCache[format] == nil then
        fmtCache[format] = createFormatText(format)
    end

    return fmtCache[format]
end

local function lookupKey(key, context)
    local arr = utils.split(key, ":")
    local s = arr[1]
    local fmt = arr[2]

    -- normalize array access
    s = string.gsub(s, "%.?%[([0-9]+)%]", ".%1")

    -- find the key we're looking for from the context
    local tgt = context
    local parts = utils.split(s, ".")
    for p=1,#parts do
        if tgt ~= nil then
            local v = parts[p]
            tgt = tgt[v] or tgt[tonumber(v)]
        end
    end

    -- and return the found value
    if tgt == nil then return tostring(key) end
    if fmt == "P" then return string.format("%s%%", tostring(tgt)) end
    if fmt == "F" then return string.format("%s%%", tostring(tgt)) end
    return tostring(tgt)
end

function ImGuiTextFmt(format, context, args)
    local ImGui = rom.ImGui
    args = args or {}

    -- let's not go crazy when we start nesting calls to this guy
    if args.Depth ~= nil and args.Depth > 5 then return end

    local lines = ShallowCopyTable(getFormatText(format, context))
    local i = 1

    while i <= #lines do
        local line = lines[i]
        
        if line.Type == "!" or line.Type == "$" then
            local text = lookupKey(line.Value, context)
            local fmt = getFormatText(text, context)
            for n=1,#fmt do
                table.insert(lines, i + n, fmt[n])
            end
        elseif line.Type == "" then
            local currentX, currentY = ImGui.GetCursorPos()
            local width = ImGui.CalcTextSize(line.Value)
            ImGui.Text(line.Value)
            ImGui.SetCursorPos(currentX + width, currentY)
        end
        i = i + 1
    end
    if args.Depth == nil then
        ImGui.Text("")
    end
end

return {
    ImGuiTextFmt = ImGuiTextFmt,
}