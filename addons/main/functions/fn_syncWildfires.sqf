/*
    Author: WoodenPlankGames
    Function: WP_fnc_syncWildfires
    Description:
        Synchronizes wildfire modules that are within range of each other,
        taking into account elevation differences and floating point tolerance.

    Parameters:
        0: ARRAY of Objects - Source wildfire modules to connect.
        1: ARRAY of Objects - Candidate wildfire modules to connect with (can be same array or different).
        2: NUMBER - Spacing distance between modules.
        3: NUMBER - Tolerance factor (default: 1.05 = 5% extra radius).

    Returns:
        NUMBER - Count of synchronization links created.
*/

params [
    ["_sourceWildfires", [], [[]]],
    ["_targetWildfires", [], [[]]],
    ["_spacing", 15, [0]],
    ["_tolerance", 1.05, [0]]
];

private _maxDistance = _spacing * _tolerance;
private _linksCreated = 0;

{
    private _source = _x;
    if (!isNull _source) then {
        private _sourcePos = getPosASL _source;
        private _alreadySynced = synchronizedObjects _source;

        {
            private _target = _x;
            if (!isNull _target && {_source != _target} && {!(_target in _alreadySynced)}) then {
                // Check 3D distance accounting for elevation differences
                if ((_sourcePos distance (getPosASL _target)) <= _maxDistance) then {
                    _source synchronizeObjectsAdd [_target];
                    _target synchronizeObjectsAdd [_source];
                    _alreadySynced pushBack _target;
                    _linksCreated = _linksCreated + 1;
                };
            };
        } forEach _targetWildfires;
    };
} forEach _sourceWildfires;

_linksCreated
