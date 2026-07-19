{
  config,
  lib,
  ...
}:

/**
  Public interface for the opinionated Hyprland rice.

  Callers choose the capability through one boolean; command construction,
  layout policy, generated Lua, packages, and validation stay private to the
  sibling runtime module.
*/

{
  imports = [ ./runtime.nix ];

  options.nori.hyprRice.enable = lib.mkEnableOption "the Nori Hyprland rice";

  config.assertions = lib.optional config.nori.hyprRice.enable {
    assertion = config.wayland.windowManager.hyprland.enable;
    message = "nori.hyprRice requires wayland.windowManager.hyprland.enable";
  };
}
