class CfgPatches {
    class WP_Firefighting {
        name = "WoodenPlank Firefighting Modules";
        author = "WoodenPlankGames";
        url = "";
        units[] = {
            "WP_Module_Firezone",
            "WP_Module_Hotspot",
            "WP_Module_Suppression"
        };
        weapons[] = {};
        requiredVersion = 2.14;
        requiredAddons[] = {
            "A3_Modules_F",
            "RF_Data"
        };
    };
};

class CfgFactionClasses {
    class NO_CATEGORY;
    class WP_Firefighting_Category: NO_CATEGORY {
        displayName = "Firefighting (WoodenPlank)";
    };
};

class CfgFunctions {
    class WP {
        tag = "WP";
        class Firefighting {
            file = "\wp_FireFighting\functions";
            class moduleFirezone {};
            class moduleHotspot {};
            class moduleSuppression {};
            class syncWildfires {};
        };
    };
};

class CfgVehicles {
    class Logic;
    class Module_F: Logic {
        class AttributesBase {
            class Default;
            class Edit;
            class Combo;
            class Checkbox;
            class CheckboxNumber;
            class ModuleDescription;
            class Slider;
        };
        class ModuleDescription;
    };

    // 1. Firezone Module
    class WP_Module_Firezone: Module_F {
        scope = 2; // Editor & Zeus placement
        displayName = "Firezone";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\destroy_ca.paa";
        portrait = "\a3\ui_f\data\igui\cfg\simpletasks\types\destroy_ca.paa";
        picture = "\a3\ui_f\data\igui\cfg\simpletasks\types\destroy_ca.paa";
        category = "WP_Firefighting_Category";
        function = "WP_fnc_moduleFirezone";
        functionPriority = 1;
        isGlobal = 0; // Handled on server
        isTriggerActivated = 0;
        isDisposable = 0;
        is3DEN = 0;

        // Enable 3DEN Area definition (shape, dimensions, rotation)
        canSetArea = 1;
        canSetAreaShape = 1;
        canSetAreaHeight = 0;

        class AttributeValues {
            size3[] = {50, 50, -1};
            isRectangle = 0;
        };

        class Attributes: AttributesBase {
            class size: Edit {
                property = "WP_Module_Firezone_size";
                displayName = "Wildfire Size (Radius)";
                tooltip = "Radius in meters for each individual wildfire submodule (5 - 50m).";
                typeName = "NUMBER";
                defaultValue = "10";
            };
            class spacing: Edit {
                property = "WP_Module_Firezone_spacing";
                displayName = "Grid Spacing";
                tooltip = "Center-to-center distance between adjacent wildfire submodules (5 - 50m).";
                typeName = "NUMBER";
                defaultValue = "15";
            };
            class intensity: Edit {
                property = "WP_Module_Firezone_intensity";
                displayName = "Fire Intensity (%)";
                tooltip = "Initial fire intensity percentage (0 - 100%).";
                typeName = "NUMBER";
                defaultValue = "50";
            };
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Creates a hexagonal grid of Reaction Forces wildfire modules within the defined area and synchronizes them for natural fire spread.";
            sync[] = {};
        };
    };

    // 2. Hotspot Module
    class WP_Module_Hotspot: Module_F {
        scope = 2;
        displayName = "Hotspot";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\danger_ca.paa";
        portrait = "\a3\ui_f\data\igui\cfg\simpletasks\types\danger_ca.paa";
        picture = "\a3\ui_f\data\igui\cfg\simpletasks\types\danger_ca.paa";
        category = "WP_Firefighting_Category";
        function = "WP_fnc_moduleHotspot";
        functionPriority = 2; // Runs after Firezone
        isGlobal = 0; // Server-side
        isTriggerActivated = 0;
        isDisposable = 0;
        is3DEN = 0;

        // Area attributes
        canSetArea = 1;
        canSetAreaShape = 1;
        canSetAreaHeight = 0;

        class AttributeValues {
            size3[] = {30, 30, -1};
            isRectangle = 0;
        };

        class Attributes: AttributesBase {
            class intensity: Edit {
                property = "WP_Module_Hotspot_intensity";
                displayName = "Target Intensity (%)";
                tooltip = "Override fire intensity within this zone (0 - 100%). If multiple hotspots overlap, highest intensity takes priority.";
                typeName = "NUMBER";
                defaultValue = "100";
            };
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Overrides the intensity of all wildfire modules within its area. When multiple hotspots overlap on the same wildfire, the highest intensity wins.";
            sync[] = {};
        };
    };

    // 3. Fire Suppression Module (Usable as Waypoint and in Zeus)
    class WP_Module_Suppression: Module_F {
        scope = 2;
        curatorCanAttach = 1; // Allows attaching to vehicles in Zeus
        displayName = "Fire Suppression";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\defend_ca.paa";
        portrait = "\a3\ui_f\data\igui\cfg\simpletasks\types\defend_ca.paa";
        picture = "\a3\ui_f\data\igui\cfg\simpletasks\types\defend_ca.paa";
        category = "WP_Firefighting_Category";
        function = "WP_fnc_moduleSuppression";
        functionPriority = 1;
        isGlobal = 0;
        isTriggerActivated = 0;
        isDisposable = 0;
        is3DEN = 0;

        class Attributes: AttributesBase {
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Waypoint module for vehicles (e.g. fire trucks). Orders available turrets to suppress the closest in-range wildfires, distributing multiple turrets across distinct fires and compensating for ballistic drop.";
            sync[] = {"AllVehicles"};
        };
    };
};

class CfgWaypoints {
    class WP_Firefighting {
        displayName = "Firefighting";
        class WP_FireSuppression {
            displayName = "Suppress Fire";
            displayNameDebug = "WP_FireSuppression";
            file = "\wp_FireFighting\functions\fn_moduleSuppression.sqf";
            icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\defend_ca.paa";
            tooltip = "Orders vehicle turrets to engage and extinguish nearby wildfires with ballistic drop compensation.";
        };
    };
};
