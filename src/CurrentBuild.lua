local utils = import "./src/utils.lua"
local fmtstrings = import "./src/fmtstrings.lua"
local Widgets = import "./src/Widgets.lua"

local function updateUI()
    -- force refresh healthbar
    TraitUIActivateTraits()
	FrameState.RequestUpdateHealthUI = true
    UpdateManaMeterUI()
end

local function clearCache()
    return {
        Upgradeable = {},
        HasRequirements = {},
        Tooltip = {}
    }
end

local rarities = {"Common", "Rare", "Epic", "Heroic", "Duo", "Legendary"}
 
local traitGods = {}

local cache = clearCache()

local function godNameColor(godName)
    local clr = nil
    if godName == "Ares" then clr = Color.AresDamageLight
    elseif godName == "Apollo" then clr = Color.ApolloDamageLight
    else clr = Color[tostring(godName) .. "Damage"] or Color[tostring(godName) .. "Voice"] or { 255, 255, 255, 255 }
    end
    return utils.toImGuiColor(clr)
end

local function traitNameColor(traitName, rarity, isValid)
    local colors = { 1, 1, 1, 0.8 }
    local hasRequirements = TraitRequirements[traitName] ~= nil

    if isValid == false then
        colors = { 1, 0, 0, 1 }
    elseif rarity ~= "None" then
        colors = utils.rarityColor(rarity)
    elseif isValid == true and hasRequirements == true then
        colors = { 0, 1, 0, 1 }
    end

    return colors
end

local function clearGameState()
    TraitTrayScreenClose( ActiveScreens.TraitTrayScreen )

    local currentTraits = utils.map(CurrentRun.Hero.Traits, function (n) return n end)

    local familiar = GameState.EquippedFamiliar
    local keepsake = GameState.LastAwardTrait
    local weapon = GetEquippedWeapon()

	for i, traitInfo in pairs(currentTraits) do
		PractiseRemoveTrait(traitInfo.Name)
	end

    CurrentRun.Hero.ReserveManaSources = {}

    ClearUpgrades()

    if keepsake ~= nil then
        EquipKeepsake(CurrentRun.Hero, keepsake, { FromLoot = true, SkipNewTraitHighlight = true })
    end

    if familiar ~= nil then
        EquipFamiliar(nil, { Unit = CurrentRun.Hero, FamiliarName = familiar, SkipNewTraitHighlight = true })
    end

    EquipPlayerWeapon(WeaponData[weapon], { LoadPackages = true })
	EquipWeaponUpgrade( CurrentRun.Hero )

    EquipMetaUpgrades( CurrentRun.Hero, { SkipTraitHighlight = true })
	UpdateHeroTraitDictionary()
	CheckActivatedTraits( CurrentRun.Hero )
    cache = clearCache()
end

local function canApplyTrait(traitName)
    if TraitRequirements[traitName] == nil then
        return true
    end
    if cache.HasRequirements[traitName] == nil then
        cache.HasRequirements[traitName] = game.HasTraitRequirements(traitName)
    end
    return cache.HasRequirements[traitName]
end

local function clearTraitAnimations(traitData)
    local animations = {
        "HexReadyFlash", "SpellReadyMelFx", "HexReadyFlashLargeA",
        "HexReadyFlashLargeB", "HexReadyLoop"
    }
    if traitData.AnchorId ~= nil then
        for _, anim in pairs(animations) do
            StopAnimation({ Name = anim, DestinationId = traitData.AnchorId })
        end
    end
end

function PractiseRemoveTrait(traitName)
    -- UnreserveMana(traitName)
    local traits = utils.map(CurrentRun.Hero.Traits, function (n) return n end)
    for _, traitData in ipairs( traits ) do
        if traitData.Name == traitName then
            clearTraitAnimations(traitData)
            RemoveTraitData(CurrentRun.Hero, traitData)
            ShowCombatUI( "AutoHide" )
        end
    end
    cache = clearCache()
end

local function applyTrait(traitName, rarity, stackNum)
    thread( TraitTrayScreenClose, ActiveScreens.TraitTrayScreen )
    local traitData = game.TraitData[traitName]
    local reload = false

    local traits = utils.map(CurrentRun.Hero.Traits, function (n) return n end)
    for _, currentTrait in ipairs( traits ) do
        if currentTrait.Name == traitName then
            PractiseRemoveTrait(currentTrait.Name)
        elseif traitData.Slot and (traitData.Slot == currentTrait.Slot or (traitData.Slot == "Spell" and currentTrait.IsTalent)) then
            PractiseRemoveTrait(currentTrait.Name)
        elseif traitData.AltSlot and traitData.AltSlot == currentTrait.Slot then
            PractiseRemoveTrait(currentTrait.Name)
        end
    end

    if rarity == "None" then
        PlaySound({ Name =  "/SFX/Menu Sounds/RunHistoryClose" })
    else
		PlaySound({ Name =  "/SFX/Menu Sounds/GodBoonChoiceConfirm" })
        AddTraitToHero({
            FromLoot = true,
            StackNum = stackNum or 1,
            TraitName = traitName,
            Rarity = rarity,
            SkipNewTraitHighlight = true,
            SkipQuestStatusCheck = true,
            SkipActivatedTraitUpdate = true,
        })
    end

    if reload then
        game.ReloadAllTraits()
        updateUI()
    end
    ShowCombatUI( "AutoHide" )
    cache = clearCache()
end

local function applySpell(spellData, rarity)
    thread( TraitTrayScreenClose, ActiveScreens.TraitTrayScreen )
    if ActiveScreens.SpellScreen or ActiveScreens.TalentScreen then
        return
    end

    local traits = utils.map(CurrentRun.Hero.Traits, function (n) return n end)
    for _, currentTrait in ipairs( traits ) do
        if currentTrait.Slot == "Spell" or currentTrait.IsTalent then
            PractiseRemoveTrait(currentTrait.Name)
        end
    end

    PractiseRemoveTrait(spellData.TraitName)
    CurrentRun.Hero.SlottedSpell = nil
    if rarity == "None" then
	    PlaySound({ Name =  "/SFX/Menu Sounds/RunHistoryClose" })
        return
    end

	PlaySound({ Name =  "/SFX/SeleneMoonPickup" })
    CurrentRun.Hero.SlottedSpell = DeepCopyTable( spellData )
    local prevChance = SpellTalentData.DuoChance
    SpellTalentData.DuoChance = 1
    UpdateTalentPointInvestedCache()
    CurrentRun.Hero.SlottedSpell.Talents = CreateTalentTree( spellData )
    SpellTalentData.DuoChance = prevChance
    AddTraitToHero({
        TraitName = spellData.TraitName,
        SkipNewTraitHighlight = true,
        SkipQuestStatusCheck = true,
        SkipActivatedTraitUpdate = true,
    })
end

local function findTraitInSlot(slotName)
    if slotName == nil then return nil end
    for _, traitData in ipairs(CurrentRun.Hero.Traits) do
		if traitData.Slot == slotName then
			return traitData.Name
		end
		if traitData.AltSlot and traitData.AltSlot == slotName then
			return traitData.Name
		end
    end
end

local function describeRequirements(traitName)
    local ImGui = rom.ImGui

    local function makeDependentTable(name, options)
        ImGui.BeginTable(name, 2, 0, 250, 0, 0)
        ImGui.TableSetupColumn("God", rom.ImGuiTableColumnFlags.WidthFixed, 90.0)
        ImGui.TableSetupColumn("Boon")
        ImGui.TableHeadersRow()
        
		for n, dependentTraitName in ipairs(options) do
            local colors = { 1, 1, 1, 1 }
            if HeroHasTrait(dependentTraitName) then
                colors = { 0, 1, 0, 1 }
            end
            local godColor = godNameColor(traitGods[dependentTraitName])
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.TextColored(
                godColor[1], godColor[2], godColor[3], godColor[4],
                traitGods[dependentTraitName] or ""
            )
            ImGui.TableNextColumn()
            ImGui.TextColored(
                colors[1], colors[2], colors[3], colors[4],
                PractiseTexts.Trait[dependentTraitName] or dependentTraitName
            )
		end
        ImGui.EndTable()
    end
	local dependencyTable = TraitRequirements[traitName]
	if dependencyTable.OneOf ~= nil then
        ImGui.Text("Requires One Of:")
        makeDependentTable("RequiresOneOf", dependencyTable.OneOf)
	end


	if dependencyTable.TwoOf ~= nil then
        ImGui.Text("Requires Two Of:")
        makeDependentTable("RequiresTwoOf", dependencyTable.TwoOf)
	end

	if dependencyTable.OneFromEachSet ~= nil then
        ImGui.Text("Requires One Of Each:")
		for i, traitSet in ipairs(dependencyTable.OneFromEachSet) do
            if i > 1 then ImGui.SameLine() end
            makeDependentTable("RequiresOneOf_" .. tostring(i), traitSet)
		end
	end
end

local iconText = import './src/icon_to_text.lua'

local function showTraitTooltip(traitName, rarity, stacks, showRequirements)
    local ImGui = rom.ImGui
    local traitData = TraitData[traitName]
    ImGui.BeginTooltip()

    if rarity == "None" then
        local levels = traitData.RarityLevels or { Common = true }
        for _, v in pairs(rarities) do
            if levels[v] then
                rarity = v
                break
            end
        end
    end

    local colors = traitNameColor(traitName, rarity, nil)
    ImGui.TextColored(
        colors[1], colors[2], colors[3], colors[4],
        utils.deformat(PractiseTexts.Trait[traitName] or traitName)
    )

    if stacks ~= nil and stacks > 1 then
        ImGui.SameLine()
        ImGui.Text("+" .. tostring(stacks))
    end

    local cacheKey = string.format("%s:%s:%d", traitName, rarity, stacks)
    if cache.Tooltip[cacheKey] == nil then
        local tooltipData = DeepCopyTable((CurrentRun.Hero.TraitDictionary[traitName] or {})[1] or {})

        tooltipData = GetProcessedTraitData({
            Unit = CurrentRun.Hero,
            TraitName = traitName,
            Rarity = rarity or "Common",
            StackNum = stacks,
            ForBoonInfo = true,
            ForceMin = true
        })
        tooltipData.ForBoonInfo = true
        SetTraitTextData( tooltipData )
        cache.Tooltip[cacheKey] = tooltipData
    end

    local newTraitData = cache.Tooltip[cacheKey]

    local fmtcontext = {
        DeltaNewTotal1 = PractiseTexts.Trait.DeltaNewTotal1,
        CurrentRun = CurrentRun,
        ConsumableData = ConsumableData,
        TooltipData = newTraitData,
        Keywords = PractiseTexts.Help,
        TraitData = TraitData,
        Icons = iconText
    }

    fmtstrings.ImGuiTextFmt(PractiseTexts.TraitText[traitName].Description, fmtcontext)
    
    if not newTraitData.HideStatLinesInCodex then
        local statLines = newTraitData.StatLines
        if newTraitData.CustomStatLinesWithShrineUpgrade ~= nil and GetNumShrineUpgrades( newTraitData.CustomStatLinesWithShrineUpgrade.ShrineUpgradeName ) > 0 then
            statLines = newTraitData.CustomStatLinesWithShrineUpgrade.StatLines
        end
        ImGui.BeginTable("StatLines", 2)
        ImGui.TableSetupColumn("Name")
        ImGui.TableSetupColumn("Description")

        for _, statLine in ipairs( statLines or {} ) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            fmtstrings.ImGuiTextFmt(PractiseTexts.TraitText[statLine].DisplayName, fmtcontext)
            ImGui.TableNextColumn()
            fmtstrings.ImGuiTextFmt(PractiseTexts.TraitText[statLine].Description, fmtcontext)
        end
        ImGui.EndTable()
    end

    if TraitRequirements[traitName] ~= nil and showRequirements ~= false then
        ImGui.Dummy(0, 0)
        describeRequirements(traitName)
    end
    ImGui.EndTooltip()
end

local function makeRaritySelect(traitName, currentRarity, stacks)
    local ImGui = rom.ImGui
    local traitData = TraitData[traitName]
    local changed = false
    local result = nil

    ImGui.PushItemWidth(-1)
    if ImGui.BeginCombo(string.format("##%s:rarity", traitName), currentRarity or "Common") then
        if ImGui.Selectable("None", currentRarity == "None") then
            if "None" ~= currentRarity then
                changed = true
                result = "None"
            end
        end
        
        local traitRarities = traitData.RarityLevels or { Common = true }
        
        for i, rarity in ipairs(rarities) do
            if traitRarities[rarity] ~= nil then
                if ImGui.Selectable(rarity, currentRarity == rarity) then
                    if rarity ~= currentRarity then
                        changed = true
                        result = rarity
                    end
                end
                if ImGui.IsItemHovered() then
                    showTraitTooltip(traitName, rarity, stacks or 1, false)
                end
            end
        end
        ImGui.EndCombo()
    end
    return changed, result
end

local function showTraitName(traitName, isValid, rarity, stacks)
    local ImGui = rom.ImGui

    local colors = traitNameColor(traitName, rarity, isValid)
    ImGui.TextColored(
        colors[1], colors[2], colors[3], colors[4],
        utils.deformat(PractiseTexts.Trait[traitName]) or traitName
    )

    if ImGui.IsItemHovered() then
        showTraitTooltip(traitName, rarity, stacks, true)
    end
end

local function changeTraitStacks(traitName, fromStacks, toStacks)
    local traitInfo = CurrentRun.Hero.TraitDictionary[traitName][1]
    IncreaseTraitLevel( traitInfo, toStacks - fromStacks )
end

local function makeTraitSelect(traitName)
    local ImGui = rom.ImGui

    local stacks = 1
    local traitData = TraitData[traitName]
    local hasTrait = HeroHasTrait(traitName)
    local currentRarity = "None"

    if cache.Upgradeable[traitName] == nil then
        cache.Upgradeable[traitName] = traitData.RemainingUses == nil and IsGodTrait(traitData.Name) and not traitData.BlockStacking
    end
    local isUpgradable = cache.Upgradeable[traitName]

    if hasTrait then
        local data = GetHeroTrait(traitName)
        if data ~= nil then
            currentRarity = data.Rarity
            stacks = data.StackNum or 1
        end
    end
    local valid = hasTrait or canApplyTrait(traitName)

    ImGui.TableNextRow()
    ImGui.TableNextColumn()
    ImGui.AlignTextToFramePadding()

    showTraitName(traitName, valid, currentRarity, stacks)

    if valid then
        ImGui.TableNextColumn()

        local traitInSlot = findTraitInSlot(traitData.Slot)
        local hasOtherTrait = traitInSlot ~= nil and traitInSlot ~= traitName

        if hasOtherTrait then
            ImGui.TextDisabled(PractiseTexts.Trait[traitInSlot] or traitInSlot)
        end
        ImGui.TableNextColumn()

        local changed, newRarity = makeRaritySelect(traitName, currentRarity, stacks)
        if changed then applyTrait(traitName, newRarity, stacks) end

        if hasTrait and isUpgradable then
            ImGui.TableNextColumn()
            ImGui.PushItemWidth(-1)
            if ImGui.BeginCombo(string.format("##%s:stacks", traitName), tostring(stacks)) then
                for i=1,100 do
                    if ImGui.Selectable(tostring(i), i == stacks) then
                        if i ~= stacks then
                            changeTraitStacks(traitName, stacks, i)
                        end
                    end
                    if ImGui.IsItemHovered() then
                        showTraitTooltip(traitName, currentRarity, i, false)
                    end
                end
                ImGui.EndCombo()
            end
        end
    end
end

local function getGodTraits(godName)
    local upgradeName = string.format("%sUpgrade", godName)
    local types = { "WeaponUpgrades", "Traits" }
    local result = {}
    for _, type in ipairs(types) do
        for _, traitName in ipairs(LootSetData[godName][upgradeName][type]) do
            result[#result + 1] = traitName
        end
    end
    local scoring = { Melee = 1, Secondary = 2, Ranged = 3, Rush = 4, Mana = 5, Legendary = 6, Misc = 7, Duo = 8 }
    table.sort(result, function (aName, bName)
        function getScore(name)
            local traitInfo = TraitData[name]
            if scoring[traitInfo.Slot] then
                return scoring[traitInfo.Slot]
            end
            if traitInfo.IsDuoBoon then
                return scoring.Duo
            end
            if traitInfo.RarityLevels and traitInfo.RarityLevels.Legendary then
                return scoring.Legendary
            end
            return scoring.Misc
        end
        local a = getScore(aName)
        local b = getScore(bName)
        if a == b then return aName < bName end
        return a < b
    end)
    return result
end

local function getWeaponUpgrades()
    local weapon = GetEquippedWeapon()
    local result = {}
    for i, n in pairs(LootSetData.Loot.WeaponUpgrade.Traits) do
        local traitData = TraitData[n]
        if traitData.CodexWeapon == weapon then
            result[#result + 1] = n
        end
    end
    return result
end

local consumableLines = {
    {
        { Name = "Small Soul Tonic",        Description = "+10 MP",    Consumable = "MaxManaDropSmall" },
        { Name = "Soul Tonic",              Description = "+30 MP",    Consumable = "MaxManaDrop" },
        { Name = "Mega Soul Tonic",         Description = "+60 MP",    Consumable = "MaxManaDropBig" },
    },
    {
        { Name = "Small Centaur Heart",     Description = "+5 HP",     Consumable = "MaxHealthDropSmall" },
        { Name = "Centaur Heart",           Description = "+25 HP",    Consumable = "MaxHealthDrop" },
        { Name = "Mega Centaur Heart",      Description = "+50 HP",    Consumable = "MaxHealthDropBig" },
    },
    {
        { Description = "+50 GP",           Consumable = "RoomMoneySmallDrop" },
        { Description = "+100 GP",          Consumable = "RoomMoneyDrop" },
        { Description = "+200 GP",          Consumable = "RoomMoneyBigDrop" },
        { Description = "+300 GP",          Consumable = "RoomMoneyTripleDrop" },
    },
    {
        { Description = "+20 Armor",        Consumable = "ArmorBoostStore" },
        { Description = "Special Dmg+",     Trait = "TemporaryImprovedSecondaryTrait" },
        { Description = "Cast Dmg+",        Trait = "TemporaryImprovedCastTrait" },
        { Description = "Move Speed+",      Trait = "TemporaryMoveSpeedTrait" },
        { Description = "Boon Rarity+",     Trait = "TemporaryBoonRarityTrait" },
        { Description = "Omega Dmg+",       Trait = "TemporaryImprovedExTrait" },
        { Description = "Defense+",         Trait = "TemporaryImprovedDefenseTrait" },
        { Description = "Store Discount",   Trait = "TemporaryDiscountTrait" },
        { Description = "Force Chaos",      Trait = "TemporaryForcedSecretDoorTrait" },
        { Description = "Empty Dmg+",       Trait = "TemporaryEmptySlotDamageTrait" },
        { Description = "Extend Item",      Trait = "ExtendedShopTrait" },
        { Description = "Random Item",      Consumable = "RandomStoreItem" },
        { Description = "Mana Regen",       Consumable = "LimitedManaRegenDrop" },
        { Description = "Swap Boons",       Consumable = "LimitedSwapTraitDrop" }
    }
}

local function makeConsumableTable(lines)
    local ImGui = rom.ImGui

    for _, group in pairs(lines) do
        ImGui.BeginTable("Consumables", 3)
        ImGui.TableSetupColumn("Name", rom.ImGuiTableColumnFlags.WidthFixed, 200.0)
        ImGui.TableSetupColumn("Description")
        ImGui.TableSetupColumn("", rom.ImGuiTableColumnFlags.WidthFixed, 60.0)
        ImGui.TableHeadersRow()
        for i, data in pairs(group) do
            local name = data.Name or PractiseTexts.Trait[data.Consumable or data.Trait] or data.Trait or data.Consumable
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.AlignTextToFramePadding()
            ImGui.Text(name)

            ImGui.TableNextColumn()
            ImGui.Text(data.Description)

            ImGui.TableNextColumn()
            if ImGui.Button("Collect##" .. name) then
                if data.Trait ~= nil then
                    applyTrait(data.Trait, "Common", 1)
                    return
                end
                if data.Consumable ~= nil then
                    if MapState.RoomRequiredObjects == nil then
                        MapState.RoomRequiredObjects = {}
                    end
                    local consumable = DeepCopyTable(ConsumableData[data.Consumable])
                    consumable.ResourceCosts = { Money = 0 }
                    consumable.ObjectId = -1 --  "ThreecreepioPractise"
                    thread(UseConsumableItem, consumable, {}, CurrentRun.Hero)
                    ShowCombatUI( "AutoHide" )
                end
            end
        end
        ImGui.EndTable()
    end
end

local function makeSpellTable()
    local ImGui = rom.ImGui
    
    ImGui.BeginTable("SeleneHex", 3)
    ImGui.TableSetupColumn("Name", rom.ImGuiTableColumnFlags.WidthFixed, 200.0)
    ImGui.TableSetupColumn("Rarity", rom.ImGuiTableColumnFlags.WidthStretch)
    ImGui.TableSetupColumn("Tree", rom.ImGuiTableColumnFlags.WidthFixed, 60.0)
    ImGui.TableHeadersRow()
    for _, spellData in pairs(SpellData) do
        local traitName = spellData.TraitName
        local traitData = TraitData[traitName]
        local currentRarity = "None"
        local hasSpell = HeroHasTrait(traitName)
        local valid =  hasSpell or canApplyTrait(traitName)
        if hasSpell then currentRarity = traitData.Rarity end

        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.AlignTextToFramePadding()
        showTraitName(traitName, valid, currentRarity, 1)

        if valid then
            ImGui.TableNextColumn()
            if ActiveScreens.TalentScreen then ImGui.BeginDisabled() end
            local changed, newRarity = makeRaritySelect(traitName, currentRarity, 1)
            if changed then applySpell(spellData, newRarity) end
            if ActiveScreens.TalentScreen then ImGui.EndDisabled() end

            ImGui.TableNextColumn()
            if hasSpell then
                if ActiveScreens.TalentScreen then
                    if ImGui.Button("Close") then
                        thread(LeaveTalentTree, ActiveScreens.TalentScreen)
                    end
                else
                    if ImGui.Button("Open") then
                        thread( TraitTrayScreenClose, ActiveScreens.TraitTrayScreen )
                        thread( OpenTalentScreen, { ReadOnly = true }, nil )
                    end
                end
            end
        end
    end
    ImGui.EndTable()

    local disabled = CurrentRun.Hero.SlottedSpell == nil or CurrentRun.Hero.SlottedSpell.TraitName == nil or ActiveScreens.TalentScreen
    if disabled then ImGui.BeginDisabled() end
    makeConsumableTable({
        {
            { Description = "+1 Hex", Consumable = "MinorTalentDrop" },
            { Description = "+3 Hex", Consumable = "TalentDrop" },
            { Description = "+5 Hex", Consumable = "TalentBigDrop" },
        }
    })
    if disabled then ImGui.EndDisabled() end

end


local openedPanel = nil

local function panel(name, currentPanel)
    local clr = godNameColor(name)

    rom.ImGui.Dummy(0, 0)
    local isOpen = name == currentPanel
    local _, _, clickedPanel = Widgets.Panel(name, {
        Label = name,
        IsOpen = isOpen,
        Color = rom.ImGui.GetColorU32(clr[1], clr[2], clr[3], 0.5),
        HoverColor = rom.ImGui.GetColorU32(clr[1], clr[2], clr[3], 0.8),
    })

    if clickedPanel then
        if openedPanel == name then
            openedPanel = nil
        else
            openedPanel = name
        end
    end

    return isOpen
end

local boonGiverCache = nil
local function getBoonGivers()
    if boonGiverCache ~= nil then return boonGiverCache end
    boonGiverCache = {
        { Name = "Zeus",            Traits = getGodTraits("Zeus") },
        { Name = "Hera",            Traits = getGodTraits("Hera") },
        { Name = "Poseidon",        Traits = getGodTraits("Poseidon") },
        { Name = "Demeter",         Traits = getGodTraits("Demeter") },
        { Name = "Apollo",          Traits = getGodTraits("Apollo") },
        { Name = "Aphrodite",       Traits = getGodTraits("Aphrodite") },
        { Name = "Hephaestus",      Traits = getGodTraits("Hephaestus") },
        { Name = "Hestia",          Traits = getGodTraits("Hestia") },
        { Name = "Ares",            Traits = getGodTraits("Ares") },
        { Name = "Athena",          Traits = UnitSetData.NPC_Athena.NPC_Athena_01.Traits },
        { Name = "Dionysus",        Traits = UnitSetData.NPC_Dionysus.NPC_Dionysus_01.Traits },
        { Name = "Artemis",         Traits = UnitSetData.NPC_Artemis.NPC_Artemis_Field_01.Traits },
        { Name = "Hermes",          Traits = getGodTraits("Hermes") },
        { Name = "Hades",           Traits = UnitSetData.NPC_Hades.NPC_Hades_Field_01.Traits },
        { Name = "Chaos",           Traits = LootSetData.Chaos.TrialUpgrade.PermanentTraits },
        { Name = "Arachne",         Traits = utils.map(PresetEventArgs.ArachneCostumeChoices.UpgradeOptions, function (n) return n.ItemName end) },
        -- { Name = "Narcissus",       Traits = UnitSetData.NPC_Narcissus.NPC_Narcissus_01.Traits },
        { Name = "Echo",            Traits = UnitSetData.NPC_Echo.NPC_Echo_01.Traits },
        { Name = "Medea",           Traits = UnitSetData.NPC_Medea.NPC_Medea_01.Traits },
        { Name = "Icarus",          Traits = UnitSetData.NPC_Icarus.NPC_Icarus_01.Traits },
        { Name = "Circe",           Traits = UnitSetData.NPC_Circe.NPC_Circe_01.Traits },
        { Name = "Deadalus Hammer", Traits = getWeaponUpgrades() }
    }
    for _, n in pairs(boonGiverCache) do
        for _, t in pairs(n.Traits or {}) do
            traitGods[t] = n.Name
        end
    end
    return boonGiverCache
end

function PractiseCurrentBuildMenu(appearing)
    if appearing then cache = clearCache() end
    local ImGui = rom.ImGui
    local currentPanel = openedPanel
    local disabled = PractiseStoredState.Blocking == true

    if ImGui.Button("Reset player") then
        thread(clearGameState)
    end

    ImGui.SameLine()
    if ImGui.Button("Refill Health and Mana") then
        CurrentRun.Hero.Health = GetHeroMaxAvailableHealth()
        CurrentRun.Hero.Mana = GetHeroMaxAvailableMana()
        updateUI()
    end

    if panel("Consumables", currentPanel) then
        if disabled then ImGui.BeginDisabled() end
        makeConsumableTable(consumableLines)
        if disabled then ImGui.EndDisabled() end
    end

    for _, boonGiver in pairs(getBoonGivers()) do
        if boonGiver.Traits ~= nil then
            if panel(boonGiver.Name, currentPanel) then
                if disabled then ImGui.BeginDisabled() end
                ImGui.BeginTable(boonGiver.Name, 4)
                ImGui.TableSetupColumn("Name")
                ImGui.TableSetupColumn("", rom.ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Rarity", rom.ImGuiTableColumnFlags.WidthFixed, 120.0)
                ImGui.TableSetupColumn("Level", rom.ImGuiTableColumnFlags.WidthFixed, 70.0)
                ImGui.TableHeadersRow()
                for _, traitName in ipairs(boonGiver.Traits) do
                    makeTraitSelect(traitName)
                end
                ImGui.EndTable()
                if disabled then ImGui.EndDisabled() end
            end
        end
    end

    if panel("Selene Hex", currentPanel, "SeleneVoice") then
        if disabled then ImGui.BeginDisabled() end
        makeSpellTable()
        if disabled then ImGui.EndDisabled() end
    end
    
end