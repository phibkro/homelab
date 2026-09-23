_: {
  /*
    Session-wide Wayland application hints shared by Plasma and Hyprland.
    They are intentionally separate from compositor and GPU-vendor modules.
  */
  environment.sessionVariables = {
    # NixOS-specific shim for Electron and Chromium native Wayland support.
    NIXOS_OZONE_WL = "1";
    # Electron 35+ selects Wayland when available and otherwise falls back cleanly.
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };
}
