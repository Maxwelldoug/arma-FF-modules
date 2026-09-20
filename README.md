# WoodenPlank Firefighting Modules for Arma 3

This mod is designed to make working with the Reaction Forces Firefighting modules less ludicrously painful. It adds 3 modules:

- **Firezone (`WP_Module_Firezone`)**: Uses 3 sliders (size 5–50m, spacing 5–50m, intensity 0–100%) as well as the default area setup (as used by, for example, the "Hide Terrain Objects" module) to place a network of hex-gridded wildfire modules at terrain altitude. All adjacent modules are synchronized with a tolerance factor (+5% radius) to allow fire spread across terrain elevation changes and floating-point math differences. If two fire zones are close together, their modules will be synced together (using the larger spacing of the two zones) to allow fire to move between zones seamlessly.
- **Hotspot (`WP_Module_Hotspot`)**: Overrides the intensity of all wildfire modules within its area to the set value. It does not check if the new intensity is hotter than original (and thus can be used for cold spots as well), but if multiple hotspots affect the same wildfire, the highest intensity takes priority.
- **Fire Suppression (`WP_Module_Suppression` / Waypoint)**: A waypoint and module that, when added to a vehicle, orders its turrets to suppress the nearest in-range wildfire, accounting for projectile drop. If more than one turret is available, the second turret will target the second closest wildfire, etc. It is compatible with Zeus and 3DEN (both as a module and as a group waypoint), and is recommended for use with fire trucks.

While the Fire Suppression module runs an active engagement loop for AI turrets, the Firezone and Hotspot modules have no ongoing performance implications after mission start, as they place and configure their sub-modules once before permanently deactivating.

## Project Structure

- `addons/main/config.cpp`: Mod configuration declaring `CfgPatches`, `CfgVehicles` module classes, and `CfgWaypoints`.
- `addons/main/functions/fn_moduleFirezone.sqf`: Hex-grid calculation, module creation, and intra-/inter-zone synchronization.
- `addons/main/functions/fn_moduleHotspot.sqf`: Area detection and highest-intensity priority override logic.
- `addons/main/functions/fn_moduleSuppression.sqf`: AI turret assignment, ballistic drop compensation, and fire suppression loop.
- `addons/main/functions/fn_syncWildfires.sqf`: Reusable helper for synchronizing wildfire module networks with elevation tolerance.

