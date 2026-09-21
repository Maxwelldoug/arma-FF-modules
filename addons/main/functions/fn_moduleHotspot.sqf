/*
    Author: WoodenPlankGames
    Function: WP_fnc_moduleHotspot
    Description:
        Overrides the intensity of all wildfire modules within its zone to whatever is set.
        Does not check if the new intensity is hotter than original (can be used for cold spots),
        but if multiple hotspots affect the same wildfire, the highest intensity takes priority.
*/

// Support both [mode, input, activated] and [logic, units, activated] calling styles
private _logic = objNull;
private _units = [];
private _activated = true;

if (count _this > 0) then {
    private _first = _this select 0;
    if (_first isEqualType "") then {
        private _input = _this param [1, [], [[]]];
        _activated = _this param [2, true, [true]];
        if (count _input > 0) then {
            _logic = _input select 0;
            if (count _input > 1) then { _units = _input select 1; };
        };
    } else {
        _logic = _first;
        _units = _this param [1, [], [[]]];
        _activated = _this param [2, true, [true]];
    };
};

// Execute only on the server
if (!isServer) exitWith { [] };
if (!_activated || isNull _logic) exitWith { [] };

diag_log format ["[WP Firefighting] Initializing Hotspot module: %1 at %2", _logic, getPos _logic];

// Retrieve intensity slider attribute (support both "property" name and short name)
private _intensityRaw = _logic getVariable ["intensity", _logic getVariable ["WP_Module_Hotspot_intensity", 100]];
private _newIntensity = ((_intensityRaw max 0) min 100) / 100;

// Retrieve module area definition: check for trigger object in "areas" variable first, fall back to "objectArea"
private _areas = _logic getVariable ["areas", []];
private _areaTrigger = if (count _areas > 0) then { _areas select 0 } else { objNull };

private _center = getPosWorld _logic;
private _areaDef = if (!isNull _areaTrigger) then {
    _areaTrigger
} else {
    private _area = _logic getVariable ["objectArea", [30, 30, 0, false]];
    _area params [
        ["_a", 30, [0]],
        ["_b", 30, [0]],
        ["_angle", 0, [0]],
        ["_isRectangle", false, [false]]
    ];
    if (_a <= 0) then { _a = 30; };
    if (_b <= 0) then { _b = 30; };
    [_center, _a, _b, _angle, _isRectangle]
};

// Gather candidate wildfire modules
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
    private _inHotspot = if (count _areas > 0) then {
        _areas findIf { !isNull _x && { (getPos _wf) inArea _x } } != -1
    } else {
        (getPos _wf) inArea _areaDef
    };

    if (!isNull _wf && { _inHotspot }) then {
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

diag_log format ["[WP Firefighting] Hotspot %1 affected %2 wildfire nodes.", _logic, count _affectedWildfires];

// Clean up associated trigger entities created for the module
{
    if (!isNull _x) then { deleteVehicle _x; };
} forEach _areas;

// Delete the module entity after setup
deleteVehicle _logic;

_affectedWildfires
