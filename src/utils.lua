local function split(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

local function map(arr, fn)
    local n = {}
    for k,v in pairs(arr) do
        n[k] = fn(v)
    end
    return n
end

local function deformat(text)
    if text == nil then return text end
    return string.gsub(tostring(text), "{(.-)}", "")
end

local function loadTexts(name)
    local lang = "en"
    local path = string.format("Game/Text/%s/%s.%s.sjson", lang, name, lang)
    local data = sjson.decode_file(sjson.get_content_data_path(path))
    local result = {}
    local inherit = {}
    for k, value in ipairs(data.Texts) do
        local v = value
        if v.InheritFrom ~= nil then
            inherit[#inherit + 1] = v.Id
        end
        result[v.Id] = v
    end
    for _, n in pairs(inherit) do
        local target = result[n]
        local other = result[target.InheritFrom] or {}
        for kk, vv in pairs(other) do
            if target[kk] == nil then
                target[kk] = vv
            end
        end
    end
    return result
end

local function loadPractiseTexts()
    local traitText = loadTexts("TraitText")
    local helpText = loadTexts("HelpText")

    PractiseTexts = {
        Trait = map(traitText, function(n) return n.DisplayName end),
        Help = map(helpText, function(n) return n.DisplayName end),
        TraitText = traitText,
    }
end

local function toImGuiColor(clr)
    return {
        clr[1] / 256,
        clr[2] / 256,
        clr[3] / 256,
        clr[4] / 256,
    }
end

local function toImGuiColorU32(clr)
    return rom.ImGui.GetColorU32(
        clr[1] / 256,
        clr[2] / 256,
        clr[3] / 256,
        clr[4] / 256
    )
end

local function rarityColor(rarity)
    local colors = { 1, 1, 1, 1 }
    if rarity == "None" then return colors end
    local fmt = "BoonPatch" .. (rarity or "Common")
    colors = toImGuiColor(Color[fmt] or colors)
    return colors
end

local function uuid()
    return table.concat({
        string.format("%04x", math.random(0, 0xffff)),
        string.format("%04x", math.random(0, 0xffff)),
        "-",
        string.format("%04x", math.random(0, 0xffff)),
        "-",
        string.format("4%03x", math.random(0, 0x0fff)),
        "-",
        string.format("%x%03x", math.random(8, 11), math.random(0, 0x0fff)),
        "-",
        string.format("%04x", math.random(0, 0xffff)),
        string.format("%04x", math.random(0, 0xffff)),
        string.format("%04x", math.random(0, 0xffff)),
    })
end

return {
    uuid = uuid,
    split = split,
    map = map,
    deformat = deformat,
    loadPractiseTexts = loadPractiseTexts,
    toImGuiColor = toImGuiColor,
    toImGuiColorU32 = toImGuiColorU32,
    rarityColor = rarityColor,
}
