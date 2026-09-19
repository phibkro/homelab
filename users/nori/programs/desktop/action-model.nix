{ lib, ... }:
let
  commandCategories = [
    "layout"
    "space"
    "window"
    "system"
    "help"
    "utility"
    "testing"
  ];
  commandEffects = [
    "launch"
    "query"
    "toggle"
    "layout"
    "window"
    "session"
    "destructive"
  ];
  directBindingType = lib.types.submodule {
    options = {
      mod = lib.mkOption {
        type = lib.types.enum [
          "$mod"
          "$mod SHIFT"
        ];
      };
      key = lib.mkOption { type = lib.types.str; };
    };
  };
  commandType = lib.types.submodule {
    options = {
      label = lib.mkOption { type = lib.types.str; };
      description = lib.mkOption { type = lib.types.str; };
      category = lib.mkOption { type = lib.types.enum commandCategories; };
      keywords = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      icon = lib.mkOption {
        type = lib.types.str;
        default = "system-run";
      };
      executable = lib.mkOption { type = lib.types.str; };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      effect = lib.mkOption {
        type = lib.types.enum commandEffects;
        default = "launch";
      };
      palette = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      directBinding = lib.mkOption {
        type = lib.types.nullOr directBindingType;
        default = null;
      };
    };
  };
in
{
  options.nori.desktop = {
    actions = lib.mkOption {
      type = lib.types.attrsOf commandType;
      readOnly = true;
      internal = true;
      description = "Evaluated desktop action catalog consumed by bindings and launcher adapters.";
    };

    actionDispatcher = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Package that executes one desktop action by stable ID.";
    };
  };
}
