/*
    Author: WoodenPlankGames
    Function: WP_fnc_moduleSuppression
    Description:
        Waypoint / Module for AI vehicle suppression of wildfires.
        Orders vehicle turrets to suppress the nearest in-range wildfire,
        accounting for projectile drop. If multiple turrets are available,
        the 2nd turret targets the 2nd closest wildfire, etc.
*/

private _vehicle = objNull;
private _group = grpNull;

// Determine vehicle / group whether invoked as a module or as a waypoint
if (count _this > 0) then {
    private _first = _this select 0;

    if (_first isEqualType "") then {
        // Module called via BIS module system: [mode, [logic, units], activated]
        private _input = _this param [1, [], [[]]];
        if (count _input > 0) then {
            private _logic = _input select 0;
            if (!isNull _logic) then {
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
            };
        };
    } else {
        if (_first isEqualType objNull) then {
            if (_first isKindOf "Logic") then {
                // Direct module call: [logic, units, activated]
                private _synced = synchronizedObjects _first;
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

                if (isNull _vehicle && !isNull (attachedTo _first)) then {
                    _vehicle = attachedTo _first;
                    _group = group _vehicle;
                };
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
        } else {
            if (_first isEqualType grpNull) then {
                _group = _first;
                _vehicle = vehicle (leader _group);
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

    private _initSpeed = 45;
    private _gravity = 9.80665;
    private _maxRange = 120;

    diag_log format ["[WP Firefighting] Starting fire suppression loop for vehicle: %1", typeOf _veh];

    while { alive _veh && (_veh getVariable ["WP_suppressionActive", false]) } do {
        private _allTurrets = allTurrets [_veh, false];
        private _activeTurretUnits = [];

        {
            private _turretPath = _x;
            private _gunner = _veh turretUnit _turretPath;

            if (!isNull _gunner && {alive _gunner}) then {
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

        private _vehPos = getPosASL _veh;
        private _candidateWildfires = [];

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

        _candidateWildfires sort true;

        {
            _x params ["_turretPath", "_gunner", "_weaponName"];
            private _targetIndex = _forEachIndex;

            if (_targetIndex < count _candidateWildfires) then {
                private _wfTarget = (_candidateWildfires select _targetIndex) select 1;
                private _wfPosASL = getPosASL _wfTarget;

                // Turret elevation limits
                private _minElev = -10;
                private _maxElev = 80;
                private _turretLimits = _veh getTurretLimits _turretPath;
                if (count _turretLimits >= 4) then {
                    _minElev = _turretLimits select 2;
                    _maxElev = _turretLimits select 3;
                } else {
                    private _turretCfg = [_veh, _turretPath] call BIS_fnc_turretConfig;
                    if (isClass _turretCfg) then {
                        if (isNumber (_turretCfg >> "minElev")) then { _minElev = getNumber (_turretCfg >> "minElev"); };
                        if (isNumber (_turretCfg >> "maxElev")) then { _maxElev = getNumber (_turretCfg >> "maxElev"); };
                    };
                };
                if (_maxElev <= 0) then { _maxElev = 80; };
                private _effectiveMaxElev = _maxElev min 85;

                // Muzzle velocity
                private _turretSpeed = _initSpeed;
                private _currentMag = (_veh magazinesTurret _turretPath) param [0, ""];
                if (_currentMag != "") then {
                    private _magSpeed = getNumber (configFile >> "CfgMagazines" >> _currentMag >> "initSpeed");
                    if (_magSpeed > 0) then { _turretSpeed = _magSpeed; };
                };

                // Turret origin ASL
                private _originPosASL = eyePos _gunner;
                if (_originPosASL isEqualTo [0, 0, 0]) then {
                    _originPosASL = getPosASL _veh;
                };

                private _dx = (_wfPosASL select 0) - (_originPosASL select 0);
                private _dy = (_wfPosASL select 1) - (_originPosASL select 1);
                private _dz = (_wfPosASL select 2) - (_originPosASL select 2);
                private _horizDist = sqrt (_dx * _dx + _dy * _dy);

                private _aimPosASL = _wfPosASL;

                if (_horizDist < 0.1) then {
                    _aimPosASL = [
                        _wfPosASL select 0,
                        _wfPosASL select 1,
                        (_originPosASL select 2) + _dz
                    ];
                } else {
                    private _v2 = _turretSpeed ^ 2;
                    private _v4 = _v2 ^ 2;
                    private _g = _gravity;
                    private _term = _v4 - (2 * _g * _dz * _v2) - ((_g ^ 2) * (_horizDist ^ 2));

                    private _chosenAngle = 0;

                    if (_term >= 0) then {
                        private _sqrtTerm = sqrt _term;
                        private _denom = _g * _horizDist;
                        private _lowAngle = atan ((_v2 - _sqrtTerm) / _denom);
                        private _highAngle = atan ((_v2 + _sqrtTerm) / _denom);

                        // Prefer higher elevation angle where possible for obstacle clearance and dispersion
                        if (_highAngle <= _effectiveMaxElev && _highAngle >= _minElev) then {
                            _chosenAngle = _highAngle;
                        } else {
                            if (_lowAngle <= _effectiveMaxElev && _lowAngle >= _minElev) then {
                                _chosenAngle = _lowAngle;
                            } else {
                                _chosenAngle = (_lowAngle min _effectiveMaxElev) max _minElev;
                            };
                        };
                    } else {
                        // Beyond maximum physical range: aim at optimal distance angle
                        _chosenAngle = (45 min _effectiveMaxElev) max _minElev;
                    };

                    _aimPosASL = [
                        _wfPosASL select 0,
                        _wfPosASL select 1,
                        (_originPosASL select 2) + (_horizDist * tan _chosenAngle)
                    ];
                };

                _gunner doWatch (ASLToAGL _aimPosASL);
                _gunner lookAt (ASLToAGL _aimPosASL);

                if (_veh currentWeaponTurret _turretPath != _weaponName) then {
                    _veh selectWeaponTurret [_weaponName, _turretPath];
                };

                if (combatMode (group _gunner) == "BLUE") then {
                    (group _gunner) setCombatMode "YELLOW";
                };

                _gunner doSuppressiveFire _aimPosASL;
            } else {
                _gunner doWatch objNull;
            };
        } forEach _activeTurretUnits;

        sleep 1.5;
    };

    {
        private _gunner = _veh turretUnit _x;
        if (!isNull _gunner) then {
            _gunner doWatch objNull;
        };
    } forEach (allTurrets [_veh, false]);

    _veh setVariable ["WP_suppressionActive", false];
    diag_log format ["[WP Firefighting] Fire suppression loop ended for vehicle: %1", typeOf _veh];
};

true
