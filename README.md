# WoodenPlank Firefighting Modules for Arma 3

This mod is designed to make working with the Reaction Forces Firefighting modules less ludicrously painful. It adds 3 modules:

- **Firezone**: Uses 3 sliders (size 5–50m, spacing 5–50m, intensity 0–100%) as well as the default area setup (as used by, for example, the "Hide Terrain Objects" module) to place a network of hex-gridded wildfire modules (at terrain altitude). All adjacent modules are synced for fire spread. If two fire zones are close together, their modules will be synced together (using the radius of the larger set of wildfire modules) to allow fire to move between zones as well.
- **Hotspot**: Overrides the intensity of all wildfire modules within its zone to the set value. It does not check if the new intensity is hotter than original (and thus can be used for cold spots as well), but if multiple hotspots affect the same wildfire, the highest intensity takes priority.
- **Fire Suppression**: A waypoint module that, when added to a vehicle, orders its turrets to suppress the nearest in-range wildfire, accounting for projectile drop. If more than one turret is available, the second turret will target the second closest wildfire, etc. It is the only module added that can be placed in Zeus (as a waypoint), and it is recommended to only use it with fire trucks, as firing a machine gun at a fire seems unproductive.

While the Fire Suppression module may have performance implications due to its looped interaction with AI, the Firezone and Hotspot modules should have no performance implications after mission start, as they only need to place down their sub-modules once before permanently deactivating.

