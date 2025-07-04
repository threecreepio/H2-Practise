local version = 1

function LoadIfNeeded()
	if PractiseStoredState ~= nil then return true end
	if GameState == nil then return false end
	if not GameState.ThreecreepioPractise or GameState.ThreecreepioPractise.Version ~= version then
		GameState.ThreecreepioPractise = {
            Version = version,
            Data = {}
        }
	end
	PractiseStoredState = GameState.ThreecreepioPractise.Data
	PractiseStoredState.SavedBuilds = PractiseStoredState.SavedBuilds or {}
	return true
end

if GameState ~= nil then
	LoadIfNeeded()
end

return LoadIfNeeded
