/*
    Author: WoodenPlankGames
    Function: WP_fnc_moduleHotspot
    Description:
        Overrides the intensity of all wildfire modules within its zone to whatever is set.
        Does not check if the new intensity is hotter than original (can be used for cold spots),
        but if multiple hotspots affect the same wildfire, the highest intensity takes priority.

    Parameters:
        0: OBJECT - Module logic entity
        1: ARRAY - Synchronized units/objects
        2: BOOLEAN - Activated

    Returns:
        ARRAY of Objects - Affected wildfire modules
*/

params [
    ["_logic", objNull, [objNull]],
    ["_units", [], [[]]],
    ["_activated", true, [true]]
];

// Execute only on the server
if (!isServer) exitWith { [] };
if (!_activated || isNull _logic) exitWith { [] };

// Retrieve intensity slider attribute (0-100%)
private _intensityVal = ((_logic getVariable ["intensity", 100]) max 0) min 100;
private _newIntensity = _intensityVal / 100; // Convert to 0-1 scale

// Gather candidate wildfire modules
// Check all known created wildfires from firezones, plus any Module_WildFire_RF in the mission
private _candidateWildfires = [];

if (!isNil "WP_firezones") then {
    {
        _x params ["", "", "_zoneWildfires"];
        _candidateWildfires append _zoneWildfires;
    } forEach WP_firezones;
};

// Also search for any pre-placed Module_WildFire_RF entities
{
    if !(_x in _candidateWildfires) then {
        _candidateWildfires pushBack _x;
    };
} forEach (allMissionObjects "Module_WildFire_RF");

private _affectedWildfires = [];

{
    private _wf = _x;
    if (!isNull _wf && { (getPos _wf) inArea _logic }) then {
        // Priority rule: if multiple hotspots affect the same wildfire, highest intensity takes priority
        private _currentOverride = _wf getVariable ["WP_hotspotIntensity", -1];

        if (_newIntensity > _currentOverride) then {
            _wf setVariable ["WP_hotspotIntensity", _newIntensity, true];
            _wf setVariable ["WP_intensity", _newIntensity, true];

            if (!isNil "lxRF_fnc_wildFire") then {
                [_wf, "setIntensity", _newIntensity] remoteExec ["lxRF_fnc_wildFire", 0, true];
            };

            _affectedWildfires pushBack _wf;
        };
    };
} forEach _candidateWildfires;

_affectedWildfires
