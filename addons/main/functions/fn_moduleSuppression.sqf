/*
    Author: WoodenPlankGames
    Function: WP_fnc_moduleSuppression
    Description:
        Waypoint / Module for AI vehicle suppression of wildfires.
        Orders vehicle turrets to suppress the nearest in-range wildfire,
        accounting for projectile drop. If multiple turrets are available,
        the 2nd turret targets the 2nd closest wildfire, etc.

    Parameters:
        Module syntax:
            0: OBJECT - Module logic entity
            1: ARRAY - Synchronized units/objects
            2: BOOLEAN - Activated
        Waypoint syntax:
            0: GROUP or OBJECT - Group/Vehicle executing waypoint
            1: ARRAY - Waypoint position

    Returns:
        BOOLEAN - Success / Handled
*/

params [
    ["_targetParam", objNull, [objNull, []]]
];

private _vehicle = objNull;
private _group = grpNull;

// Determine vehicle / group whether invoked as a module or as a waypoint
if (_targetParam isEqualType objNull) then {
    private _logic = _targetParam;
    private _synced = synchronizedObjects _logic;
    {
        if (_x isKindOf "AllVehicles") exitWith {
            _vehicle = _x;
            _group = group _vehicle;
        };
        if (_x isEqualType grpNull) exitWith {
            _group = _x;
            _vehicle = vehicle (leader _group);
        };
        if (_x isKindOf "CAManBase") exitWith {
            _vehicle = vehicle _x;
            _group = group _x;
        };
    } forEach _synced;

    if (isNull _vehicle && !isNull (attachedTo _logic)) then {
        _vehicle = attachedTo _logic;
        _group = group _vehicle;
    };
} else {
    // Array passed: waypoint syntax [group, waypointPosition] or module param array
    if (count _this >= 1) then {
        private _first = _this select 0;
        if (_first isEqualType grpNull) then {
            _group = _first;
            _vehicle = vehicle (leader _group);
        } else {
            if (_first isKindOf "AllVehicles") then {
                _vehicle = _first;
                _group = group _vehicle;
            } else {
                if (_first isKindOf "CAManBase") then {
                    _vehicle = vehicle _first;
                    _group = group _first;
                };
            };
        };
    };
};

if (isNull _vehicle) exitWith {
    diag_log "[WP Firefighting] Fire Suppression module: No target vehicle found.";
    false
};

// Check if suppression loop is already running on this vehicle
if (_vehicle getVariable ["WP_suppressionActive", false]) exitWith {
    true
};
_vehicle setVariable ["WP_suppressionActive", true];

// Launch async suppression loop
[_vehicle] spawn {
    params ["_veh"];

    // Default muzzle velocity for water cannon (m/s)
    private _initSpeed = 45;
    private _gravity = 9.80665;
    private _maxRange = 120; // Effective range of water cannon

    diag_log format ["[WP Firefighting] Starting fire suppression loop for vehicle: %1", typeOf _veh];

    while { alive _veh && (_veh getVariable ["WP_suppressionActive", false]) } do {
        // Collect operable turrets and gunners
        private _allTurrets = allTurrets [_veh, false];
        private _activeTurretUnits = [];

        {
            private _turretPath = _x;
            private _gunner = _veh turretUnit _turretPath;

            // Include if gunner is alive, conscious, and vehicle can fire
            if (!isNull _gunner && {alive _gunner}) then {
                // Find current weapon for this turret
                private _weapons = _veh weaponsTurret _turretPath;
                if (count _weapons > 0) then {
                    _activeTurretUnits pushBack [_turretPath, _gunner, _weapons select 0];
                };
            };
        } forEach _allTurrets;

        if (count _activeTurretUnits == 0) then {
            sleep 2;
            continue;
        };

        // Locate active wildfires in range
        private _vehPos = getPosASL _veh;
        private _candidateWildfires = [];

        // Check firezones registry
        if (!isNil "WP_firezones") then {
            {
                _x params ["", "", "_zoneWildfires"];
                {
                    if (!isNull _x) then {
                        private _dist = _veh distance _x;
                        if (_dist <= _maxRange) then {
                            private _intensity = _x getVariable ["WP_intensity", 1];
                            if (!isNil "lxRF_fnc_wildFire") then {
                                _intensity = [_x, "getIntensity"] call lxRF_fnc_wildFire;
                            };
                            if (_intensity > 0.05) then {
                                _candidateWildfires pushBack [_dist, _x];
                            };
                        };
                    };
                } forEach _zoneWildfires;
            } forEach WP_firezones;
        };

        // Check any standalone Module_WildFire_RF in vicinity
        {
            private _wf = _x;
            private _dist = _veh distance _wf;
            if (_dist <= _maxRange) then {
                private _alreadyIn = false;
                {
                    if ((_x select 1) == _wf) exitWith { _alreadyIn = true; };
                } forEach _candidateWildfires;

                if (!_alreadyIn) then {
                    private _intensity = _wf getVariable ["WP_intensity", 1];
                    if (!isNil "lxRF_fnc_wildFire") then {
                        _intensity = [_wf, "getIntensity"] call lxRF_fnc_wildFire;
                    };
                    if (_intensity > 0.05) then {
                        _candidateWildfires pushBack [_dist, _wf];
                    };
                };
            };
        } forEach (nearestObjects [_veh, ["Module_WildFire_RF"], _maxRange]);

        // Sort wildfires by distance (nearest first)
        _candidateWildfires sort true;

        // Assign each turret to distinct nearest wildfire
        // Turret 0 -> nearest, Turret 1 -> 2nd nearest, etc.
        {
            _x params ["_turretPath", "_gunner", "_weaponName"];
            private _targetIndex = _forEachIndex;

            if (_targetIndex < count _candidateWildfires) then {
                private _wfTarget = (_candidateWildfires select _targetIndex) select 1;
                private _wfPosASL = getPosASL _wfTarget;

                // Ballistic drop compensation:
                // Horizontal distance d
                private _dx = (_wfPosASL select 0) - (_vehPos select 0);
                private _dy = (_wfPosASL select 1) - (_vehPos select 1);
                private _horizDist = sqrt (_dx * _dx + _dy * _dy);

                // Projectile drop: drop = (0.5 * g * t^2) where t = d / v
                private _timeOfFlight = _horizDist / _initSpeed;
                private _drop = 0.5 * _gravity * (_timeOfFlight ^ 2);

                // Aim position offset upwards by drop distance
                private _aimPosASL = [
                    _wfPosASL select 0,
                    _wfPosASL select 1,
                    (_wfPosASL select 2) + _drop
                ];

                // Direct gunner aim and engage
                _gunner doWatch (ASLToAGL _aimPosASL);
                _gunner lookAt (ASLToAGL _aimPosASL);

                // Fire turret weapon at target
                if (_veh currentWeaponTurret _turretPath != _weaponName) then {
                    _veh selectWeaponTurret [_weaponName, _turretPath];
                };

                // Order fire
                _gunner doFire _wfTarget;
                _veh fireAtTarget [_wfTarget, _weaponName];
            } else {
                // No target available for this turret
                _gunner doWatch objNull;
            };
        } forEach _activeTurretUnits;

        sleep 1.5;
    };

    _veh setVariable ["WP_suppressionActive", false];
    diag_log format ["[WP Firefighting] Fire suppression loop ended for vehicle: %1", typeOf _veh];
};

true
