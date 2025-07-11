local utils = import "./src/utils.lua"
local base64 = import "./src/base64.lua"

local newSaveName = ""

local function encode(value)
    local bin = luabins.save(value)
    local b64 = base64.encode(bin)
    -- split into chunks
    local chunks = {}
    local linelength = 32
    for i = 1, #b64, linelength do
        table.insert(chunks, b64:sub(i, i + linelength - 1))
    end
    -- join the chunks with newlines
    return table.concat(chunks, "\n")
end

local function decode(value)
    -- remove all whitespace
    value = value:gsub("%s+", "")
    if value == nil or value == "" then
        return false, "No data to decode"
    end
    -- decode the base64 string
    local bin = base64.decode(value)
    local success, data = luabins.load(bin)
    return success, data
end

local TraitCopyFields = MergeTables(
    DeepCopyTable(PersistentKeepsakeKeys),
    {
        "ActiveSlotOffsetIndex",
        "RemainingUses",
        "RepeatedKeepsake",
        "RarityUpgradeData",
        "StartMaxMana",
        "StartMaxHealth",
        "StatMultiplier",
    }
)

local function copyTraitFields(traitName, from, to)
    local traitInfo = TraitData[traitName]
    for _, v in pairs(traitInfo.ExtractValues or {}) do
        if v.Key then to[v.Key] = from[v.Key] end
    end
    for _, k in pairs(TraitCopyFields) do
        to[k] = from[k]
    end
    return to
end

local function fullyClearGameState()
    thread( TraitTrayScreenClose, ActiveScreens.TraitTrayScreen )

    CurrentRun.Hero.MaxLastStands = 0
    GameState.Resources.Money = 0
    CurrentRun.Hero.ReserveManaSources = {}

    EndRamWeapons({ Id = CurrentRun.Hero.ObjectId })
    UnequipWeaponUpgrade()

    local currentTraits = utils.map(CurrentRun.Hero.Traits, function (n) return n end)

	for _, traitInfo in pairs(currentTraits) do
        PractiseRemoveTrait(traitInfo.Name)
	end

    ClearUpgrades()
    ReloadAllTraits()
end

function PractiseCreateState(name, currentRun)
    local obj = {}
    obj.Version = 1
    obj.ID = utils.uuid()
    obj.Name = name
    obj.CreatedAt = os.time()

    obj.RoomHealth = 0
    obj.RoomMana = 0
    obj.Health = currentRun.Hero.MaxHealth
    obj.Mana = currentRun.Hero.MaxMana

    obj.HealthBuffer = currentRun.Hero.HealthBuffer
    obj.ReserveManaSources = currentRun.Hero.ReserveManaSources

    obj.HealthBufferSources = MapState.HealthBufferSources

    obj.Traits = {}
    obj.MetaUpgrades = {}

    if currentRun.Hero.SlottedSpell ~= nil then
        obj.Spell = {}
        obj.Spell.TraitName = currentRun.Hero.SlottedSpell
        obj.Spell.HasDuoTalent = currentRun.Hero.SlottedSpell.HasDuoTalent
        obj.Spell.Talents = currentRun.Hero.SlottedSpell.Talents
    end

    local familiarTraits = {}
    local ignoreTraits = { RestedFamiliarResourceBonus = true }
    for familiarName, familiarData in pairs(FamiliarData) do
        for _, n in pairs(familiarData.TraitNames or {}) do
            familiarTraits[n] = familiarName
        end
    end

	for i, traitInfo in pairs(currentRun.Hero.Traits) do
        local o = copyTraitFields(traitInfo.Name, traitInfo, {
            TraitName = traitInfo.Name,
            Rarity = traitInfo.Rarity,
            StackNum = traitInfo.StackNum,
        })

        if ignoreTraits[traitInfo.Name] then
            -- do nothing

        elseif familiarTraits[traitInfo.Name] then
            -- determine which familiar is active
            obj.Familiar = familiarTraits[traitInfo.Name]

        elseif traitInfo.Slot == "Hex" then
            -- already handled selene spells

        elseif traitInfo.MetaUpgrade then
            -- skip arcana

        elseif traitInfo.Slot == "Aspect" then
            obj.Weapon = traitInfo.RequiredWeapon
            obj.WeaponAspect = traitInfo.Name
            obj.WeaponAspectRarity = traitInfo.Rarity

        elseif traitInfo.Slot == "Keepsake" and traitInfo.TraitName == GameState.LastAwardTrait then
            obj.Keepsake = o

        elseif traitInfo.Name == "RoomRewardMaxManaTrait" then
            obj.RoomMana = obj.RoomMana + traitInfo.PropertyChanges[1].ChangeValue

        elseif traitInfo.Name == "RoomRewardMaxHealthTrait" or traitInfo.Name == "RoomRewardEmptyMaxHealthTrait" then
            obj.RoomHealth = obj.RoomHealth + traitInfo.PropertyChanges[1].ChangeValue

        elseif traitInfo.Name ~= obj.Weapon
           and traitInfo.Name ~= obj.WeaponAspect
           and traitInfo.Name ~= obj.Keepsake
           and traitInfo.Name ~= obj.Assist
           and traitInfo.Name ~= obj.Familiar
        then
            obj.Traits[#obj.Traits + 1] = o
        end
    end

    return DeepCopyTable(obj)
end

local function equipWeaponKit( weapon, weaponAspect )
    local weaponKit = WeaponData[weapon]
    GameState.LastWeaponUpgradeName[weapon] = weaponAspect
	ClearObjectives()
	Halt({ Id = CurrentRun.Hero.ObjectId })
	EndRamWeapons({ Id = CurrentRun.Hero.ObjectId })
	wait( 0.02 )
	CreateAnimation({ Name = "ItemGet_Weapon", DestinationId = CurrentRun.Hero.ObjectId, Scale = 2 })
	UnequipWeaponUpgrade()
	wait( 0.02 )-- Distribute workload
	EquipPlayerWeapon( weaponKit, {} )
	wait( 0.02 )-- Distribute workload
	EquipWeaponUpgrade( CurrentRun.Hero )
	SelectCodexEntry( weaponKit.Name )
end

local function threadPractiseLoadState(saveData)
    fullyClearGameState()
    -- if true then return end

    local obj = DeepCopyTable(saveData)

    if GameState.LastAwardTrait == "ReincarnationKeepsake" then
        wait ( 0.02 )
        RemoveLastStand(CurrentRun.Hero, "ReincarnationKeepsake")
        CurrentRun.Hero.MaxLastStands = CurrentRun.Hero.MaxLastStands - 1
    end

    if obj.Keepsake ~= nil then
        wait ( 0.02 )
        EquipKeepsake( CurrentRun.Hero, obj.Keepsake.TraitName, {
            FromLoot = true,
            SkipNewTraitHighlight = true,
            ForceRarity = obj.Keepsake.Rarity or "Common"
        })
    end

    if obj.Familiar ~= nil then
        wait ( 0.02 )
        EquipFamiliar(nil, {
            Unit = CurrentRun.Hero,
            FamiliarName = obj.Familiar,
            SkipNewTraitHighlight = true
        })
    end

    if obj.Weapon ~= nil then
        wait ( 0.02 )
        equipWeaponKit( obj.Weapon, obj.WeaponAspect )
    end

    for _, traitInfo in pairs(obj.Traits) do
        wait ( 0.02 )
        local o = traitInfo
        o.Unit = CurrentRun.Hero
        local prc = GetProcessedTraitData(o)

        -- force fixed values into random boons
        for k, v in pairs(prc.PropertyChanges or {}) do
            if type(v) == "table" and type(v.ReportValues) == "table" then
                for reportKey, dataKey in pairs(v.ReportValues) do
                    v[dataKey] = o[reportKey] or 0
                end
            end
        end

        local addedTrait = AddTraitToHero({
            TraitData = prc,
            SkipNewTraitHighlight = true,
            SkipQuestStatusCheck = true,
            SkipActivatedTraitUpdate = true,
            SkipAddToHUD = true
        })
        copyTraitFields(addedTrait.Name, o, addedTrait)

        addedTrait.QueuedNumberUpdate = true
    end

    if obj.Spell ~= nil then
        wait ( 0.02 )
        local spellData = nil
        for _, v in pairs( SpellData ) do
            if v.TraitName == obj.Spell.TraitName then
                spellData = DeepCopyTable( v )
                break
            end
        end
        if spellData ~= nil then
            CurrentRun.UseRecord.SpellDrop = 1
	        CurrentRun.Hero.SlottedSpell = spellData
            CurrentRun.Hero.SlottedSpell.HasDuoTalent = obj.Spell.HasDuoTalent
	        CurrentRun.Hero.SlottedSpell.Talents = obj.Spell.Talents
        	UpdateTalentPointInvestedCache()
            AddTraitToHero({
                Name = obj.Spell.TraitName,
                SkipAddToHUD = true,
                SkipNewTraitHighlight = true,
                SkipQuestStatusCheck = true,
                SkipActivatedTraitUpdate = true,
            })
        end
    end

    -- restore arcana
        wait ( 0.02 )
    EquipMetaUpgrades( CurrentRun.Hero, { SkipTraitHighlight = true })

    if obj.RoomMana ~= 0 then
        wait ( 0.02 )
        AddMaxMana(obj.RoomMana, {}, { Silent = true })
    end
    
    if obj.RoomHealth ~= 0 then
        wait ( 0.02 )
        AddMaxHealth(obj.RoomHealth, {}, { Silent = true })
    end

    CurrentRun.Hero.Health = GetHeroMaxAvailableHealth()
    CurrentRun.Hero.Mana = GetHeroMaxAvailableMana()
    CurrentRun.Hero.HealthBuffer = obj.HealthBuffer
    MapState.HealthBufferSources = obj.HealthBufferSources
    CurrentRun.Hero.ReserveManaSources = obj.ReserveManaSources

    -- refresh ui
    TraitUIActivateTraits()
	FrameState.RequestUpdateHealthUI = true
    HandleWeaponAnimSwaps()
    SetupCostume()
	GatherAndEquipWeapons( CurrentRun )
	CheckAttachmentTextures( CurrentRun.Hero )
      
end

function PractiseLoadState(saveData)
    local function run()
        AddInputBlock({ Name = "PractiseLoadState" })
        threadPractiseLoadState( saveData )
        ShowTraitUI( {} )
        wait( 1 )
        RemoveInputBlock({ Name = "PractiseLoadState" })
    end
    thread(run)
end

local function savedBuildDetails(data, i)
    local savedBuilds = PractiseStoredState.SavedBuilds
    local ImGui = rom.ImGui

    if ImGui.Button("Copy to clipboard") then
        local result = encode(data)
        ImGui.SetClipboardText(result)
    end
    
    -- move the state up in the list
    ImGui.SameLine()
    if ImGui.Button("Up") then
        local swap = savedBuilds[i + 1]
        if swap ~= nil then
            savedBuilds[i] = swap
            savedBuilds[i + 1] = data
        end
    end

    -- move the state down in the list
    ImGui.SameLine()
    if ImGui.Button("Down") then
        local swap = savedBuilds[i - 1]
        if swap ~= nil then
            savedBuilds[i] = swap
            savedBuilds[i - 1] = data
        end
    end

    -- fully delete the state
    ImGui.SameLine()
    local w = ImGui.GetContentRegionAvail()
    local x, y = ImGui.GetCursorScreenPos()
    ImGui.SetCursorScreenPos(x + w - 60, y)
    if ImGui.Button("Delete") then
        table.remove(savedBuilds, i)
    end

    data.Name = ImGui.InputText("Name", data.Name, 100)

    ImGui.BeginTable("SaveData", 2)
    ImGui.TableSetupColumn("Name", rom.ImGuiTableColumnFlags.WidthFixed, 120.0)
    ImGui.TableSetupColumn("Value")

    if data.Armor ~= nil then
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text("Armor")
        ImGui.TableNextColumn()
        ImGui.Text(tostring(data.Armor))
    end

    if data.WeaponAspect ~= nil then
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text("Nocturnal Arm")
        ImGui.TableNextColumn()
        local colors = utils.rarityColor(data.WeaponAspectRarity)
        ImGui.TextColored(
            colors[1], colors[2], colors[3], colors[4],
            tostring(PractiseTexts.Trait[data.WeaponAspect] or data.WeaponAspect)
        )
    end

    if data.Familiar ~= nil then
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text("Familiar")
        ImGui.TableNextColumn()
        ImGui.Text(tostring(PractiseTexts.Help[data.Familiar] or data.Familiar))
    end

    if data.Keepsake ~= nil then
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text("Keepsake")
        ImGui.TableNextColumn()
        local colors = utils.rarityColor(data.Keepsake.Rarity)
        ImGui.TextColored(
            colors[1], colors[2], colors[3], colors[4],
            tostring(PractiseTexts.Trait[data.Keepsake.TraitName] or data.Keepsake.TraitName)
        )
    end

    if data.Mana > 0 then
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text("Mana")
        ImGui.TableNextColumn()
        ImGui.Text(tostring(data.Mana))
    end

    if data.Health > 0 then
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text("Health")
        ImGui.TableNextColumn()
        ImGui.Text(tostring(data.Health))
    end

    ImGui.EndTable()

    ImGui.Dummy(0, 0)
    ImGui.Text("Boons:")
    for _, n in pairs(data.Traits or {}) do
        local traitName = utils.deformat(PractiseTexts.Trait[n.TraitName])
        if traitName ~= nil and traitName ~= "" then
            local colors = utils.rarityColor(n.Rarity)
            ImGui.TextColored(
                colors[1], colors[2], colors[3], colors[4],
                traitName
            )
        end
    end
end

local expandedSavedBuild = nil
local importing = false
local importText = ""

function PractiseSavedBuildsMenu()
    local state = PractiseStoredState
    local savedBuilds = state.SavedBuilds

    local ImGui = rom.ImGui
    if ImGui.Button("Import") then
        if importing then importing = false else importing = true end
    end

    if importing then
        ImGui.Text("Paste your save file in the text area and click import")
        importText = ImGui.InputTextMultiline("", importText, 100000)

        if PractiseStoredState.Blocking then ImGui.BeginDisabled() end
        if ImGui.Button("Import##save") and PractiseStoredState.Blocking ~= true then
            local success, tbl = decode(importText)
            if success then
                importing = false
                importText = ""
                PractiseLoadState(tbl)
            else
                importText = tostring(tbl) or ""
            end
        end
        if PractiseStoredState.Blocking then ImGui.EndDisabled() end

        ImGui.SameLine()
        if ImGui.Button("Cancel") then
            importing = false
            importText = ""
        end

        return
    end

    ImGui.SameLine()

    local hasPrevRun = CurrentHubRoom ~= nil and PrevRun ~= nil and PrevRun.ActiveBounty ~= "Practise"
    local saveBtnWidth = 48
    if hasPrevRun then saveBtnWidth = 175 end
    ImGui.BeginTable("NewSave", 2)
    ImGui.TableSetupColumn("Name")
    ImGui.TableSetupColumn("", rom.ImGuiTableColumnFlags.WidthFixed, saveBtnWidth)
    ImGui.TableNextRow()
    ImGui.TableNextColumn()
    newSaveName = ImGui.InputText("Name", newSaveName or "", 100)
    ImGui.TableNextColumn()
    if ImGui.Button("Save") then
        local name = newSaveName
        newSaveName = ""
        if name == nil or name == "" then
            name = "Quick save"
        end
        savedBuilds[#savedBuilds + 1] = PractiseCreateState(name, CurrentRun)
        state.PendingCheckpoint = true
    end
    if hasPrevRun then
        ImGui.SameLine()
        if ImGui.Button("Save Last Run") then
            local name = newSaveName
            newSaveName = ""
            if name == nil or name == "" then
                name = "Quick save"
            end
            savedBuilds[#savedBuilds + 1] = PractiseCreateState(name, PrevRun)
            state.PendingCheckpoint = true
        end
    end
    ImGui.EndTable()
    ImGui.Dummy(0, 0)

    for i=#savedBuilds,1,-1 do
        local data = savedBuilds[i]
        local id = tostring(data.ID or data.CreatedAt)

        local args = {
            Label = data.Name,
            Description = os.date("%x %X", data.CreatedAt or 0),
            ButtonLabel = "Load",
            IsOpen = expandedSavedBuild == id
        }

        if PractiseStoredState.Blocking then ImGui.BeginDisabled() end
        local isOpen, buttonClicked, panelClicked = Panel("Save_" .. id, args)
        if PractiseStoredState.Blocking then ImGui.EndDisabled() end

        -- load state
        if buttonClicked and not PractiseStoredState.Blocking then
            PlaySound({ Name = "/SFX/TimeSlowStart" })
            PractiseLoadState(data)
        end

        if panelClicked then
            if expandedSavedBuild == id then
                expandedSavedBuild = -1
            else
                expandedSavedBuild = id
            end
        end

        -- load details view
        if isOpen then
            if utils.SafeBeginChild("Save" .. tostring(data.ID), 0, 250) then
                savedBuildDetails(data, i)
                ImGui.EndChild()
            end
        end

        ImGui.Dummy(0, 0)
    end
end
