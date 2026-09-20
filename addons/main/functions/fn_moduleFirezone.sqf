/*
    Author: WoodenPlankGames
    Function: WP_fnc_moduleFirezone
    Description:
        Places a network of hex-gridded wildfire modules at terrain altitude
        within the module's defined area. Synchronizes adjacent modules for fire spread,
        merges overlapping zones to prevent duplicate wildfire nodes,
        and connects with neighboring firezones if in range.
*/

// Support both [mode, input, activated] and [logic, units, activated] calling styles
private _logic = objNull;
private _units = [];
private _activated = true;

if (count _this > 0) then {
    private _first = _this select 0;
    if (_first isEqualType "") then {
        // [mode, input, activated]
        private _input = _this param [1, [], [[]]];
        _activated = _this param [2, true, [true]];
        if (count _input > 0) then {
            _logic = _input select 0;
            if (count _input > 1) then { _units = _input select 1; };
        };
    } else {
        // [logic, units, activated]
        _logic = _first;
        _units = _this param [1, [], [[]]];
        _activated = _this param [2, true, [true]];
    };
};

// Execute only on the server
if (!isServer) exitWith { [] };
if (!_activated || isNull _logic) exitWith { [] };

diag_log format ["[WP Firefighting] Initializing Firezone module: %1 at %2", _logic, getPos _logic];

// Retrieve module area properties: [a, b, angle, isRectangle, c]
private _area = _logic getVariable ["objectArea", [50, 50, 0, false]];
_area params [
    ["_a", 50, [0]],
    ["_b", 50, [0]],
    ["_angle", 0, [0]],
    ["_isRectangle", false, [false]]
];

// Fallback dimensions if 0 or negative
if (_a <= 0) then { _a = 50; };
if (_b <= 0) then { _b = 50; };

// Retrieve slider attributes (support both "property" names and short names)
private _sizeRaw = _logic getVariable ["size", _logic getVariable ["WP_Module_Firezone_size", 10]];
private _spacingRaw = _logic getVariable ["spacing", _logic getVariable ["WP_Module_Firezone_spacing", 15]];
private _intensityRaw = _logic getVariable ["intensity", _logic getVariable ["WP_Module_Firezone_intensity", 50]];

private _size = ((_sizeRaw max 5) min 50);
private _spacing = ((_spacingRaw max 5) min 50);
private _intensity = (((_intensityRaw max 0) min 100) / 100);

private _center = getPosWorld _logic;
_center params ["_centerX", "_centerY"];

// Hexagonal grid geometry parameters
private _rowHeight = _spacing * (sqrt 3 / 2);
private _colWidth = _spacing;

// Determine bounding box around the area
private _maxRadius = (_a max _b) * 1.5;
private _minX = -_maxRadius;
private _maxX = _maxRadius;
private _minY = -_maxRadius;
private _maxY = _maxRadius;

private _createdWildfires = [];
private _rowIndex = 0;

// Track global registry of firezones
if (isNil "WP_firezones") then {
    WP_firezones = [];
};

// Also track all placed wildfire positions across all firezones to prevent duplicate nodes when zones overlap
if (isNil "WP_allWildfirePositions") then {
    WP_allWildfirePositions = [];
};

// Generate hex grid points
for "_yRel" from _minY to _maxY step _rowHeight do {
    private _xOffset = if ((_rowIndex mod 2) != 0) then { _colWidth * 0.5 } else { 0 };

    for "_xRel" from (_minX + _xOffset) to _maxX step _colWidth do {
        private _worldX = _centerX + _xRel;
        private _worldY = _centerY + _yRel;
        private _testPos = [_worldX, _worldY, 0];

        // Check if candidate point is within module's defined area
        if (_testPos inArea _logic) then {
            // Check if this location overlaps an existing wildfire node from another firezone
            // If another wildfire exists within (spacing * 0.75), skip creating a duplicate node
            private _duplicate = false;
            private _minDuplicateDist = _spacing * 0.75;

            {
                _x params ["_existingX", "_existingY", "_existingWf"];
                private _dist2D = [_worldX, _worldY] distance [_existingX, _existingY];
                if (_dist2D < _minDuplicateDist) exitWith {
                    _duplicate = true;
                    // Merge node: include existing wildfire into this zone's group so it syncs properly
                    if (!isNull _existingWf && {!(_existingWf in _createdWildfires)}) then {
                        _createdWildfires pushBack _existingWf;
                    };
                };
            } forEach WP_allWildfirePositions;

            if (!_duplicate) then {
                private _terrainZ = getTerrainHeightASL [_worldX, _worldY];
                private _spawnPosASL = [_worldX, _worldY, _terrainZ];

                private _wf = objNull;
                if (!isNil "lxRF_fnc_wildFire") then {
                    _wf = [_spawnPosASL, "fireCreate", [_intensity, _size]] call lxRF_fnc_wildFire;
                };

                // Fallback if Reaction Forces function returned null or is unavailable
                if (isNull _wf) then {
                    _wf = createVehicle ["Module_WildFire_RF", [_worldX, _worldY, 0], [], 0, "CAN_COLLIDE"];
                    if (!isNull _wf) then {
                        _wf setPosASL _spawnPosASL;
                        _wf setVariable ["size", _size, true];
                        _wf setVariable ["intensity", _intensity, true];
                        if (!isNil "lxRF_fnc_wildFire") then {
                            [_wf, "setIntensity", _intensity] remoteExec ["lxRF_fnc_wildFire", 0, true];
                        };
                    };
                };

                if (!isNull _wf) then {
                    _wf setVariable ["WP_size", _size, true];
                    _wf setVariable ["WP_spacing", _spacing, true];
                    _wf setVariable ["WP_intensity", _intensity, true];
                    _wf setVariable ["WP_parentZone", _logic, true];
                    _createdWildfires pushBack _wf;
                    WP_allWildfirePositions pushBack [_worldX, _worldY, _wf];
                };
            };
        };
    };
    _rowIndex = _rowIndex + 1;
};

diag_log format ["[WP Firefighting] Firezone %1 generated %2 wildfire nodes.", _logic, count _createdWildfires];

// 1. Synchronize adjacent modules within this firezone
[_createdWildfires, _createdWildfires, _spacing, 1.05] call WP_fnc_syncWildfires;

// 2. Synchronize with existing neighboring firezones
{
    private _otherZoneData = _x;
    _otherZoneData params ["_otherLogic", "_otherSpacing", "_otherWildfires"];

    if (!isNull _otherLogic && {_otherLogic != _logic}) then {
        private _crossSpacing = _spacing max _otherSpacing;
        [_createdWildfires, _otherWildfires, _crossSpacing, 1.05] call WP_fnc_syncWildfires;
    };
} forEach WP_firezones;

// Register this firezone into global list
WP_firezones pushBack [_logic, _spacing, _createdWildfires];

// Store spawned wildfire references on logic
_logic setVariable ["WP_wildfires", _createdWildfires, true];

// Delete the module entity after placement and configuration is complete
deleteVehicle _logic;

_createdWildfires
