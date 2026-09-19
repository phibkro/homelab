{
  config,
  lib,
  ...
}:
let
  profile = config.nori.desktop.profile.components."desktop.waybar";
  waybar = config.programs.waybar;
  mainBar = waybar.settings.mainBar;
  componentSetting = option: presentation: {
    option = lib.mkOption option;
    inherit presentation;
  };
  position =
    componentSetting
      {
        type = lib.types.enum [
          "top"
          "bottom"
        ];
        default = "top";
        description = "Horizontal screen edge used by the desktop status bar.";
      }
      {
        id = "position";
        title = "Bar position";
        description = "Place the horizontal status bar at the top or bottom edge.";
        group = "Desktop";
        control = "enum";
        scope = "user";
        ownership = "user";
        applyClass = "live-generation";
        runtimeAdapter = "waybar.service";
        action = {
          title = "Settings: Bar Position";
          description = "Change the horizontal status bar edge.";
          keywords = [
            "waybar"
            "panel"
            "top"
            "bottom"
          ];
        };
      };
  policyField = title: description: {
    inherit title description;
    reason = "Managed by authored Nix policy";
  };
in
{
  options.nori.desktop = {
    profile.components."desktop.waybar".position = position.option;

    resolved.components."desktop.waybar" = {
      position = lib.mkOption {
        type = lib.types.enum [
          "top"
          "bottom"
        ];
        readOnly = true;
      };
      enabled = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
      };
      package = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
      layer = lib.mkOption {
        type = lib.types.enum [
          "top"
          "bottom"
          "overlay"
        ];
        readOnly = true;
      };
      modules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
      };
      margins = lib.mkOption {
        type = lib.types.submodule {
          options = {
            top = lib.mkOption { type = lib.types.int; };
            left = lib.mkOption { type = lib.types.int; };
            right = lib.mkOption { type = lib.types.int; };
          };
        };
        readOnly = true;
      };
      cssManaged = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
      };
      sessionTarget = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
    };
  };

  config = {
    nori.desktop = {
      componentContributions = [
        {
          id = "desktop.waybar";
          title = "Waybar";
          description = "Desktop status bar presentation and lifecycle.";
          settings = [ position.presentation ];
          readOnlyFields = {
            enabled = policyField "Enabled" "Whether authored policy installs and starts Waybar.";
            package = policyField "Package" "The patched Waybar package selected by authored policy.";
            layer = policyField "Layer" "The Wayland layer selected by authored policy.";
            modules = policyField "Modules" "The authored left, center, and right module topology.";
            margins = policyField "Margins" "The authored screen-edge spacing.";
            cssManaged = policyField "Style" "Whether authored policy provides Waybar CSS.";
            sessionTarget = policyField "Session target" "The user-session lifecycle root for Waybar.";
          };
        }
      ];

      resolved.components."desktop.waybar" = {
        inherit (profile) position;
        enabled = waybar.enable;
        package = lib.getName waybar.package;
        inherit (mainBar) layer;
        modules = mainBar.modules-left ++ mainBar.modules-center ++ mainBar.modules-right;
        margins = {
          top = mainBar.margin-top;
          left = mainBar.margin-left;
          right = mainBar.margin-right;
        };
        cssManaged = waybar.style != null;
        sessionTarget = config.wayland.systemd.target;
      };
    };
  };
}
