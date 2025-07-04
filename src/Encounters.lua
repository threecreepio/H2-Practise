
ModUtil.Path.Wrap("EndRun", function( base, currentRun )
    if currentRun.ActiveBounty == "Practise" then
        -- avoid registering more runs if it was a practise run
        CurrentRun.CurrentRoom = nil
        CurrentRun.ActiveBounty = nil
        PrevRun = CurrentRun
        game.CurrentRun = nil
    else
        base( currentRun )
    end
end)

ModUtil.Path.Wrap("Kill", function( base, victim, triggerArgs )
    -- if we die in practise, just jump back home without ending the run.
    if victim == CurrentRun.Hero and CurrentRun.ActiveBounty == "Practise" then
        CurrentRun.ActiveBounty = nil
	    DeathPresentation( CurrentRun, {}, {} )
        CurrentRun.ActiveBounty = "Practise"
        LoadMap({ Name = "Hub_PreRun", ResetBinks = true })
        CurrentRun.ActiveBounty = nil
    else
        return base(victim, triggerArgs)
    end
end)

ModUtil.Path.Wrap("OpenRunClearScreen", function( base )
    -- don't show the run clear screen if we're in practise mode
    if CurrentRun.ActiveBounty ~= "Practise" then
        return base()
    end
end)

ModUtil.Path.Wrap("LoadMap", function( base, arg )
    -- we want to prevent the initial map load after selecting an encounter
    if CurrentRun.ActiveBounty ~= "Practise" or CurrentRun.PractiseMode == true then
        return base( arg )
    end
end)

ModUtil.Path.Wrap("EncounterEndPresentation", function( base )
    -- we want to prevent the initial map load after selecting an encounter
    if CurrentRun.CurrentRoom.Softlock then
        AddTimerBlock( CurrentRun, "LeaveRoom" )
    end
    return base(  )
end)

local function setupGameState()
    RemoveInputBlock({ All = true })
    StopMusicianMusic({ Duration = 0.2 })
    if AudioState.MusicId ~= nil then
		-- Quick cut any music still playing
		StopSound({ Id = AudioState.MusicId, Duration = 0.25 })
		AudioState.MusicId = nil
	end
	if AudioState.StoppingMusicId ~= nil then
		-- Quick cut any music still fading out
		StopSound({ Id = AudioState.StoppingMusicId, Duration = 0.25 })
		AudioState.StoppingMusicId = nil
	end
end

local function setupNewGame( args )
    if PractiseStoredState.Blocking == true then return end
    RemoveInputBlock({ All = true })
	PlaySound({ Name = "/Leftovers/SFX/TeamWipedPulse" })

    -- copy our settings in case we end up on a bounty run
    if CurrentHubRoom ~= nil then
        StoredGameStateInit( GameState )
    end

    -- create some dummy bounty settings for our run
    BountyData.Practise = { DebugOnly = true, Encounters = args.Encounters }
    GameState.PackagedBountyClearRecordTime.Practise = nil

    -- create a quick save before starting the run, since that will wipe everything
    local saveData = PractiseCreateState("")

    -- create a new run to ensure we leave hub mode
    setupGameState()
    StartOver({ StartingBiome = "F", ActiveBounty = "Practise" })
	SetConfigOption({ Name = "FlipMapThings", Value = false })
	SetConfigOption({ Name = "BlockGameplayTimer", Value = false })
    CurrentRun.PractiseMode = true
    
    -- reload the state
    PractiseLoadState(saveData)

    -- then set up our new room
    local room = CreateRoom(args.RoomInfo, { })

    -- begin loading the new map
    RemoveInputBlock({ All = true })
    local door = { Room = room, ObjectId = -1 }
    MapState.OfferedExitDoors[door.ObjectId] = door
    LeaveRoom( CurrentRun, door )

    -- and finally restore our health
    CurrentRun.Hero.Health = GetHeroMaxAvailableHealth()
    CurrentRun.Hero.Mana = GetHeroMaxAvailableMana()
end


local function returnToCrossroads()
    CurrentRun.Hero.IsDead = true
    SetConfigOption({ Name = "FlipMapThings", Value = false })
    SetConfigOption({ Name = "BlockGameplayTimer", Value = false })
    thread(LoadMap, { Name = "Hub_PreRun", ResetBinks = true })
    setupGameState()
end

local function startEncounter(targetConfig)
    local roomName = targetConfig.Room

    -- if we have multiple rooms, grab the first one that is legal for the game state
    if targetConfig.Rooms ~= nil then
        for _, room in pairs(targetConfig.Rooms or {}) do
            local roomInfo = RoomData[room]
            if roomInfo ~= nil and roomInfo.GameStateRequirements == nil or IsGameStateEligible( roomInfo, roomInfo.GameStateRequirements ) then
                roomName = room
                break
            end
        end
    end

    if roomName == nil then return end

    -- set up the encounter room to be empty
    local roomInfo = DeepCopyTable(RoomData[roomName]) or {}
    roomInfo.DebugOnly = true
    roomInfo.RecordClearStats = false
    roomInfo.IgnoreMusic = false

    roomInfo.ChangeReward = "RoomRewardConsolationPrize"
	roomInfo.HasHarvestPoint = false
	roomInfo.HasShovelPoint = false
	roomInfo.HasPickaxePoint = false
	roomInfo.HasFishingPoint = false
	roomInfo.HasExorcismPoint = false
    roomInfo.Flipped = RandomChance( roomInfo.FlipHorizontalChance or 0.5 )

	roomInfo.SecretSpawnChance = 0.0
	roomInfo.ChallengeSpawnChance = 0.0
	roomInfo.WellShopSpawnChance = 0.0
	roomInfo.SurfaceShopSpawnChance = 0.0

    roomInfo.Softlock = true

	thread(setupNewGame, {
        RoomInfo = roomInfo,
        Encounters = roomInfo.LegalEncounters
    })
end

local function startTeleport(targetConfig)
    local roomName = targetConfig.Room

    if roomName == "Hub_PreRun" then
        return returnToCrossroads()
    end

    local roomInfo = DeepCopyTable(RoomData[roomName]) or {}
    thread(setupNewGame, {
        RoomInfo = roomInfo,
        Encounters = targetConfig.Encounters
    })
end

function PractiseEncountersMenu()
    local ImGui = rom.ImGui
    local disabled = PractiseStoredState.Blocking == true

    if disabled then
        ImGui.BeginDisabled()
    end

    if ImGui.Button("Kill Melinoë") then
        thread(KillHero, CurrentRun.Hero, {})
    end

    -- Region starts
    local regions = {
        {
            { Region = "The Crossroads",  Name = "",                                Room = "Hub_PreRun" },
        },{
            { Region = "Underworld",      Name = PractiseTexts.Help.BiomeF,         Room = "F_Opening01", Encounters = BountyData.HecateEncounters.Encounters           },
            { Region = "Underworld",      Name = PractiseTexts.Help.BiomeG,         Room = "G_Intro",     Encounters = BountyData.ScyllaEncounters.Encounters           },
            { Region = "Underworld",      Name = PractiseTexts.Help.BiomeH,         Room = "H_Intro",     Encounters = BountyData.InfestedCerberusEncounters.Encounters },
            { Region = "Underworld",      Name = PractiseTexts.Help.BiomeI,         Room = "I_Intro",     Encounters = BountyData.ChronosEncounters.Encounters          },
        },{
            { Region = "Surface",         Name = PractiseTexts.Help.BiomeN,         Room = "N_Opening01", Encounters = BountyData.PolyphemusEncounters.Encounters       },
            { Region = "Surface",         Name = PractiseTexts.Help.BiomeO,         Room = "O_Intro",     Encounters = BountyData.ErisEncounters.Encounters             },
            { Region = "Surface",         Name = PractiseTexts.Help.BiomeP,         Room = "P_Intro",     Encounters = BountyData.PrometheusEncounters.Encounters       },
            { Region = "Surface",         Name = PractiseTexts.Help.BiomeQ,         Room = "Q_Intro",     Encounters = BountyData.TyphonEncounters.Encounters           },
        }
    }

    ImGui.BeginTable("Areas", 3)
    ImGui.TableSetupColumn("Region", rom.ImGuiTableColumnFlags.WidthFixed, 140.0)
    ImGui.TableSetupColumn("Area")
    ImGui.TableSetupColumn("", rom.ImGuiTableColumnFlags.WidthFixed, 90.0)
    ImGui.TableHeadersRow()
    for _, areas in pairs(regions) do
        for _, targetInfo in pairs(areas) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.AlignTextToFramePadding()
            ImGui.Text(targetInfo.Region)

            ImGui.TableNextColumn()
            ImGui.Text(targetInfo.Name)

            ImGui.TableNextColumn()
            local w = ImGui.GetContentRegionAvail()
            if ImGui.Button("Enter##" .. targetInfo.Name, w, 30) then
                rom.gui.toggle()
                startTeleport(targetInfo)
            end
        end
        ImGui.Dummy(100, 8)
    end
    ImGui.EndTable()

    -- Boss encounters
    local areas = {
        {
            { Region = PractiseTexts.Help.BiomeF, Name = PractiseTexts.Help.NPC_Hecate_01,      Rooms = { "F_Boss01", "F_Boss02" } },
            { Region = PractiseTexts.Help.BiomeG, Name = PractiseTexts.Help.NPC_Scylla_01,      Rooms = { "G_Boss01", "G_Boss02" } },
            { Region = PractiseTexts.Help.BiomeH, Name = PractiseTexts.Help.NPC_Cerberus_01,    Rooms = { "H_Boss01", "H_Boss02" } },
            { Region = PractiseTexts.Help.BiomeI, Name = PractiseTexts.Help.NPC_Chronos_01,     Rooms = { "I_Boss01" } },
        },{
            { Region = PractiseTexts.Help.BiomeN, Name = PractiseTexts.Help.NPC_Cyclops_01,     Rooms = { "N_Boss01", "N_Boss02" } },
            { Region = PractiseTexts.Help.BiomeO, Name = PractiseTexts.Help.NPC_Eris_01,        Rooms = { "O_Boss01", "O_Boss02" } },
            { Region = PractiseTexts.Help.BiomeP, Name = PractiseTexts.Help.NPC_Prometheus_01,  Rooms = { "P_Boss01", "P_Boss02" } },
            { Region = PractiseTexts.Help.BiomeQ, Name = PractiseTexts.Help.CharTyphon,         Rooms = { "Q_Boss01", "Q_Boss02" } },
        }
    }
    ImGui.BeginTable("Encounters", 3)
    ImGui.TableSetupColumn("Region", rom.ImGuiTableColumnFlags.WidthFixed, 140.0)
    ImGui.TableSetupColumn("Guardian")
    ImGui.TableSetupColumn("", rom.ImGuiTableColumnFlags.WidthFixed, 90.0)
    ImGui.TableHeadersRow()
    for _, encounters in pairs(areas) do
        for _, targetInfo in pairs(encounters) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.AlignTextToFramePadding()
            ImGui.Text(targetInfo.Region)

            ImGui.TableNextColumn()
            ImGui.Text(targetInfo.Name)

            ImGui.TableNextColumn()
            local w = ImGui.GetContentRegionAvail()
            if ImGui.Button("Engage##" .. targetInfo.Name, w, 30) then
                rom.gui.toggle()
                startEncounter(targetInfo)
            end
        end
        ImGui.Dummy(100, 8)
    end
    ImGui.EndTable()

    -- Miniboss encounters
    local minibosses = {
        {
            { Biome = PractiseTexts.Help.BiomeF, Name = "Root-Stalker",     Room = "F_MiniBoss01" },
            { Biome = PractiseTexts.Help.BiomeF, Name = "Shadow-Spiller",   Room = "F_MiniBoss02" },
            { Biome = PractiseTexts.Help.BiomeF, Name = "Master-Slicer",    Room = "F_MiniBoss03" },
        },{
            { Biome = PractiseTexts.Help.BiomeG, Name = "Deep Serpent",     Room = "G_MiniBoss01" },
            { Biome = PractiseTexts.Help.BiomeG, Name = "King Vermin",      Room = "G_MiniBoss02" },
            { Biome = PractiseTexts.Help.BiomeG, Name = "Hellifish",        Room = "G_MiniBoss03" },
        },{
            { Biome = PractiseTexts.Help.BiomeH, Name = "Phantom",          Room = "H_MiniBoss01" },
            { Biome = PractiseTexts.Help.BiomeH, Name = "Bawlder",          Room = "H_MiniBoss02" },
        },{
            { Biome = PractiseTexts.Help.BiomeI, Name = "The Verminancer",  Room = "I_MiniBoss01" },
            { Biome = PractiseTexts.Help.BiomeI, Name = "Goldwrath",        Room = "I_MiniBoss02" },
        },{
            { Biome = PractiseTexts.Help.BiomeN, Name = "Satyr Raider",     Room = "N_MiniBoss01" },
            { Biome = PractiseTexts.Help.BiomeN, Name = "Erymanthian Boar", Room = "N_MiniBoss02" },
        },{
            { Biome = PractiseTexts.Help.BiomeO, Name = "Charybdis",        Room = "O_MiniBoss01" },
            { Biome = PractiseTexts.Help.BiomeO, Name = "The Yargonaut",    Room = "O_MiniBoss02" },
        },{
            { Biome = PractiseTexts.Help.BiomeP, Name = "Talos",            Room = "P_MiniBoss01" },
            { Biome = PractiseTexts.Help.BiomeP, Name = "Mega-Dracon",      Room = "P_MiniBoss02" },
         -- { Biome = PractiseTexts.Help.BiomeQ, Name = "Harpy Raptor (Debug)",     Room = "P_MiniBoss03" },
        },{
         -- { Biome = PractiseTexts.Help.BiomeQ, Name = "Arm of Typhon (Debug)", Room = "Q_MiniBoss01" },
            { Biome = PractiseTexts.Help.BiomeQ, Name = "Spawn of Typhon",  Room = "Q_MiniBoss02" },
            { Biome = PractiseTexts.Help.BiomeQ, Name = "Tail of Typhon",   Room = "Q_MiniBoss03" },
            { Biome = PractiseTexts.Help.BiomeQ, Name = "Eye of Typhon",    Room = "Q_MiniBoss04" },
            { Biome = PractiseTexts.Help.BiomeQ, Name = "Twins of Typhon",  Room = "Q_MiniBoss05" },
        }
    }

    ImGui.BeginTable("Minibosses", 3)
    ImGui.TableSetupColumn("Biome", rom.ImGuiTableColumnFlags.WidthFixed, 140.0)
    ImGui.TableSetupColumn("Encounter")
    ImGui.TableSetupColumn("", rom.ImGuiTableColumnFlags.WidthFixed, 90.0)
    ImGui.TableHeadersRow()
    for _, biome in pairs(minibosses) do
        for _, targetInfo in pairs(biome) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.AlignTextToFramePadding()
            ImGui.Text(targetInfo.Biome)

            ImGui.TableNextColumn()
            ImGui.AlignTextToFramePadding()
            ImGui.Text(targetInfo.Name)

            ImGui.TableNextColumn()
            local w = ImGui.GetContentRegionAvail()
            if ImGui.Button("Engage##Mini" .. targetInfo.Name, w, 30) then
                rom.gui.toggle()
                startEncounter(targetInfo)
            end
        end
        ImGui.Dummy(100, 8)
    end
    ImGui.EndTable()

    if disabled then
        ImGui.EndDisabled()
    end
end
