/*
    Author:  WoodenPlankGames
    Function: WP_fnc_moduleFirezone
    Description:
        Places a network of hex-gridded wildfire modules at terrain altitude
        within the module's defined area. Synchronizes adjacent modules for fire spread,
        and connects with neighboring firezones if in range.

    Parameters:
        0: OBJECT - Module logic entity
        1: ARRAY - Synchronized units/objects
        2: BOOLEAN - Activated

    Returns:
        ARRAY of Objects - Created wildfire modules
*/

params [
    ["_logic", objNull, [objNull]],
    ["_units", [], [[]]],
    ["_activated", true, [true]]
];

// Execute only on the server
if (!isServer) exitWith { [] };
if (!_activated || isNull _logic) exitWith { [] };

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

// Retrieve slider attributes (clamped to 5-50m for size/spacing, 0-1 for intensity)
private _size = ((_logic getVariable ["size", 10]) max 5) min 50;
private _spacing = ((_logic getVariable ["spacing", 15]) max 5) min 50;
private _intensity = ((_logic getVariable ["intensity", 50]) max 0) min 100;
_intensity = _intensity / 100; // Convert 0-100% slider to 0-1 ratio

private _center = getPosWorld _logic;
_center params ["_centerX", "_centerY"];

// Hexagonal grid geometry parameters
// Row height (distance between rows in hex grid): h = spacing * sqrt(3)/2
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

// Track global registry of firezones for cross-zone synchronization
if (isNil "WP_firezones") then {
    WP_firezones = [];
};

// Generate hex grid points
for "_yRel" from _minY to _maxY step _rowHeight do {
    // Hexagonal staggered offset: every odd row is shifted by half column width
    private _xOffset = if ((_rowIndex mod 2) != 0) then { _colWidth * 0.5 } else { 0 };

    for "_xRel" from (_minX + _xOffset) to _maxX step _colWidth do {
        // Calculate world 2D position
        private _worldX = _centerX + _xRel;
        private _worldY = _centerY + _yRel;
        private _testPos = [_worldX, _worldY, 0];

        // Check if candidate point is within module's defined area
        if (_testPos inArea _logic) then {
            // Place at terrain altitude (ASL)
            private _terrainZ = getTerrainHeightASL [_worldX, _worldY];
            private _spawnPosASL = [_worldX, _worldY, _terrainZ];

            private _wf = objNull;
            if (!isNil "lxRF_fnc_wildFire") then {
                // Official Reaction Forces creation method
                _wf = [_spawnPosASL, "fireCreate", [_intensity, _size]] call lxRF_fnc_wildFire;
            };

            // Fallback if Reaction Forces function returned null or not available
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
            };
        };
    };
    _rowIndex = _rowIndex + 1;
};

// 1. Synchronize adjacent modules within this firezone
// Use 1.05 tolerance factor (5% extra radius) for elevation and float math
[_createdWildfires, _createdWildfires, _spacing, 1.05] call WP_fnc_syncWildfires;

// 2. Synchronize with existing neighboring firezones
// "If two fire zones are close together, their modules will be synced (using the radius
// of the larger set of wildfire modules) together to allow fire to move between the zones as well."
{
    private _otherZoneData = _x;
    _otherZoneData params ["_otherLogic", "_otherSpacing", "_otherWildfires"];

    if (!isNull _otherLogic && {_otherLogic != _logic}) then {
        // Use the larger spacing between the two zones
        private _crossSpacing = _spacing max _otherSpacing;
        [_createdWildfires, _otherWildfires, _crossSpacing, 1.05] call WP_fnc_syncWildfires;
    };
} forEach WP_firezones;

// Register this firezone into global list
WP_firezones pushBack [_logic, _spacing, _createdWildfires];

// Store spawned wildfire references on logic
_logic setVariable ["WP_wildfires", _createdWildfires, true];

_createdWildfires
