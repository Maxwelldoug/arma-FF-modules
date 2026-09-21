/*
    Author: WoodenPlankGames
    Function: WP_fnc_moduleSuppression
    Description:
        Waypoint / Module for AI vehicle suppression of wildfires.
        Orders the vehicle to suppress the nearest in-range wildfire,
        preferring high-elevation ballistic trajectories for obstacle
        clearance and water dispersion.
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

    private _suppressTarget = objNull;
    private _currentTarget = objNull;
    private _isNewTarget = true;
    private _savedOriginalState = false;
    private _origBehaviour = "CARELESS";
    private _origCombatMode = "YELLOW";
    private _disabledAbilities = ["AIMINGERROR", "AUTOTARGET", "FSM", "PATH", "SUPPRESSION", "TARGET"];

    while { alive _veh && (_veh getVariable ["WP_suppressionActive", false]) } do {
        private _mainTurret = [0];
        private _allTurrets = allTurrets [_veh, false];
        if (count _allTurrets > 0) then {
            _mainTurret = _allTurrets select 0;
        };

        private _gunner = gunner _veh;
        if (isNull _gunner) then {
            _gunner = _veh turretUnit _mainTurret;
        };
        if (isNull _gunner) then {
            _gunner = effectiveCommander _veh;
        };

        if (!isNull _gunner && {!alive _gunner}) then {
            sleep 2;
            continue;
        };

        if (!_savedOriginalState && {!isNull _gunner}) then {
            _origBehaviour = combatBehaviour _gunner;
            _origCombatMode = unitCombatMode _gunner;
            _savedOriginalState = true;
        };

        // Check if vehicle has water/ammunition remaining
        private _hasAmmo = someAmmo _veh;
        private _allMags = magazinesAllTurrets _veh;
        private _foundTurretMag = false;
        private _turretHasAmmo = false;

        {
            _x params ["", "_tPath", "_count"];
            if (_tPath isEqualTo _mainTurret) then {
                _foundTurretMag = true;
                if (_count > 0) then { _turretHasAmmo = true; };
            };
        } forEach _allMags;

        if (_foundTurretMag) then {
            _hasAmmo = _turretHasAmmo;
        };

        if (!_hasAmmo) exitWith {
            if (!isNull _suppressTarget) then {
                deleteVehicle _suppressTarget;
                _suppressTarget = objNull;
            };
            _currentTarget = objNull;
            _veh doWatch objNull;
            if (!isNull _gunner) then { _gunner doWatch objNull; };
            diag_log format ["[WP Firefighting] Vehicle %1 is out of water/ammunition. Ending suppression.", typeOf _veh];
        };

        private _weapons = _veh weaponsTurret _mainTurret;
        private _weaponName = "";
        {
            if !(_x isKindOf ["CarHorn", configFile >> "CfgWeapons"]) exitWith {
                _weaponName = _x;
            };
        } forEach _weapons;
        if (_weaponName == "" && count _weapons > 0) then {
            _weaponName = _weapons select 0;
        };

        if (_weaponName != "" && {_veh currentWeaponTurret _mainTurret != _weaponName}) then {
            _veh selectWeaponTurret [_weaponName, _mainTurret];
        };

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

        if (count _candidateWildfires == 0) then {
            // No active wildfires remaining in range (e.g. fire extinguished)
            if (!isNull _suppressTarget) then {
                deleteVehicle _suppressTarget;
                _suppressTarget = objNull;
            };
            _currentTarget = objNull;
            _isNewTarget = true;
            _veh doWatch objNull;
            if (!isNull _gunner) then {
                _gunner doWatch objNull;
                _gunner lookAt objNull;
                _gunner doTarget objNull;
            };
            sleep 2;
            continue;
        };

        private _wfTarget = (_candidateWildfires select 0) select 1;
        private _wfPosASL = getPosASL _wfTarget;

        // Clean up target if fire has changed
        if (!isNull _currentTarget && {_currentTarget != _wfTarget}) then {
            if (!isNull _suppressTarget) then {
                deleteVehicle _suppressTarget;
                _suppressTarget = objNull;
            };
            _isNewTarget = true;
        };
        _currentTarget = _wfTarget;

        // Turret elevation limits
        private _minElev = -10;
        private _maxElev = 80;
        private _turretLimits = _veh getTurretLimits _mainTurret;
        if (count _turretLimits >= 4) then {
            _minElev = _turretLimits select 2;
            _maxElev = _turretLimits select 3;
        } else {
            private _turretCfg = [_veh, _mainTurret] call BIS_fnc_turretConfig;
            if (isClass _turretCfg) then {
                if (isNumber (_turretCfg >> "minElev")) then { _minElev = getNumber (_turretCfg >> "minElev"); };
                if (isNumber (_turretCfg >> "maxElev")) then { _maxElev = getNumber (_turretCfg >> "maxElev"); };
            };
        };
        if (_maxElev <= 0) then { _maxElev = 80; };
        private _effectiveMaxElev = _maxElev min 85;

        // Muzzle velocity
        private _turretSpeed = _initSpeed;
        private _currentMag = (_veh magazinesTurret _mainTurret) param [0, ""];
        if (_currentMag != "") then {
            private _magSpeed = getNumber (configFile >> "CfgMagazines" >> _currentMag >> "initSpeed");
            if (_magSpeed > 0) then { _turretSpeed = _magSpeed; };
        };

        // Origin ASL (gunner eyePos or vehicle position)
        private _originPosASL = getPosASL _veh;
        if (!isNull _gunner) then {
            private _eye = eyePos _gunner;
            if !(_eye isEqualTo [0, 0, 0]) then {
                _originPosASL = _eye;
            };
        };

        private _dx = (_wfPosASL select 0) - (_originPosASL select 0);
        private _dy = (_wfPosASL select 1) - (_originPosASL select 1);
        private _dz = (_wfPosASL select 2) - (_originPosASL select 2);
        private _horizDist = sqrt (_dx * _dx + _dy * _dy);

        private _aimPosASL = _wfPosASL;

        if (_horizDist < 2) then {
            _aimPosASL = [
                _wfPosASL select 0,
                _wfPosASL select 1,
                (_originPosASL select 2) + 5
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
                private _practicalMaxElev = _effectiveMaxElev min 55;

                if (_highAngle <= _practicalMaxElev && _highAngle >= _minElev) then {
                    _chosenAngle = _highAngle;
                } else {
                    if (_practicalMaxElev >= _lowAngle && _practicalMaxElev >= _minElev) then {
                        _chosenAngle = _practicalMaxElev;
                    } else {
                        if (_lowAngle <= _effectiveMaxElev && _lowAngle >= _minElev) then {
                            _chosenAngle = _lowAngle;
                        } else {
                            _chosenAngle = (_lowAngle min _effectiveMaxElev) max _minElev;
                        };
                    };
                };
            } else {
                // Beyond maximum physical range: aim at optimal distance angle
                _chosenAngle = (45 min _effectiveMaxElev) max _minElev;
            };

            // Place target at the peak (apex) of the ballistic trajectory arc
            // At the horizontal midpoint (x = d / 2), the ballistic height above origin is:
            // z_mid = (d * tan(theta) + dz) / 4
            private _zMid = ((_horizDist * tan _chosenAngle) + _dz) / 4;

            // Ensure the peak target is elevated above line-of-sight to clear obstacles
            _zMid = _zMid max ((_dz / 2) + 3);

            _aimPosASL = [
                (_originPosASL select 0) + (_dx * 0.5),
                (_originPosASL select 1) + (_dy * 0.5),
                (_originPosASL select 2) + _zMid
            ];
        };

        // Create or update invisible target entity at high-elevation aim coordinates
        if (isNull _suppressTarget) then {
            _suppressTarget = createVehicle ["Land_HelipadEmpty_F", ASLToAGL _aimPosASL, [], 0, "CAN_COLLIDE"];
            _suppressTarget allowDamage false;
            _isNewTarget = true;
        };
        _suppressTarget setPosASL _aimPosASL;

        // Configure AI for direct turret engagement (matching ZEN's suppressive fire technique)
        if (!isNull _gunner) then {
            { _gunner disableAI _x; } forEach _disabledAbilities;
            _gunner setSkill 1;
            _gunner setCombatBehaviour "COMBAT";
            _gunner setUnitCombatMode "BLUE";

            _gunner reveal [_suppressTarget, 4];
            _gunner lookAt _suppressTarget;
            _gunner doWatch _suppressTarget;
            _gunner doTarget _suppressTarget;
        };

        // Give turret time to traverse and align on new target
        if (_isNewTarget) then {
            sleep 2;
            _isNewTarget = false;
        };

        // Fire burst of rounds
        private _reloadTime = 0.08;
        if (_weaponName != "") then {
            private _wCfg = configFile >> "CfgWeapons" >> _weaponName;
            if (isNumber (_wCfg >> "reloadTime")) then {
                _reloadTime = getNumber (_wCfg >> "reloadTime");
            };
        };
        if (_reloadTime <= 0) then { _reloadTime = 0.08; };
        _reloadTime = _reloadTime max 0.05;

        private _burstCount = 12;
        for "_i" from 1 to _burstCount do {
            if (!alive _veh || isNull _gunner || !alive _gunner) exitWith {};
            if (!someAmmo _veh) exitWith {};
            if (!(_veh getVariable ["WP_suppressionActive", false])) exitWith {};

            if (!isNil "zen_common_fnc_fireWeapon") then {
                [_gunner, false] call zen_common_fnc_fireWeapon;
            } else {
                private _magDetail = _veh currentMagazineDetailTurret _mainTurret;
                if (_magDetail != "") then {
                    private _split = _magDetail splitString "[:/]";
                    if (count _split >= 2) then {
                        private _id = parseNumber (_split select (count _split - 2));
                        private _owner = parseNumber (_split select (count _split - 1));
                        _veh action ["UseMagazine", _veh, _gunner, _owner, _id];
                    };
                };
                _gunner forceWeaponFire [_weaponName, "FullAuto"];
            };

            sleep _reloadTime;
        };

        sleep 0.4;
    };

    if (!isNull _suppressTarget) then {
        deleteVehicle _suppressTarget;
        _suppressTarget = objNull;
    };

    if (!isNull _gunner && {alive _gunner}) then {
        {
            _gunner enableAI _x;
        } forEach _disabledAbilities;

        _gunner setCombatBehaviour _origBehaviour;
        _gunner setUnitCombatMode _origCombatMode;
        _gunner doWatch objNull;
        _gunner lookAt objNull;
        _gunner doTarget objNull;
    };
    _veh doWatch objNull;

    _veh setVariable ["WP_suppressionActive", false];
    diag_log format ["[WP Firefighting] Fire suppression loop ended for vehicle: %1", typeOf _veh];
};

true
