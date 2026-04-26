{ pkgs, ... }:
{
  # System-side Hyprland: provides /run/current-system/sw/bin/Hyprland (the
  # binary greetd execs), polkit + dbus integration, and the
  # xdg-desktop-portal-hyprland config. Per-user config (keybinds, monitors,
  # autostart) lives in ./home.nix via home-manager.
  programs.hyprland = {
    enable = true;
    # UWSM (Universal Wayland Session Manager) wraps the Hyprland start
    # so systemd-user services that depend on graphical-session.target
    # activate cleanly — waybar, mako, hypridle, etc. all start
    # automatically on session start instead of needing a manual
    # `systemctl --user restart` dance. Hyprland upstream now strongly
    # recommends UWSM and warns at session start if it isn't used.
    #
    # Setting this true exposes a `hyprland-uwsm.desktop` session entry
    # that greetd's tuigreet can launch via:
    #   uwsm start hyprland-uwsm.desktop
    # See modules/desktop/greetd.nix for the greetd-side wiring.
    withUWSM = true;
  };

  # GTK fallback portal — needed for "open file" dialogs in apps that haven't
  # implemented the native Hyprland portal (e.g. Electron pre-35 fallback).
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Wayland session env vars.
  #
  # Driver 595 + explicit-sync removes most historical NVIDIA-Wayland pain
  # (see DESIGN.md L355-363); we keep the set deliberately minimal and add
  # hints only when something actually breaks.
  #
  #   NIXOS_OZONE_WL=1                 — NixOS-specific shim that flips
  #                                       Electron/Chromium to native Wayland
  #   __GLX_VENDOR_LIBRARY_NAME=nvidia — disambiguate libglvnd vendor under
  #                                       XWayland on hybrid setups (single-
  #                                       GPU here but harmless + future-proof)
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  # Polkit agent autostart — needed for any app that prompts for elevation
  # (network manager applet, mount helpers). Hyprland doesn't ship one;
  # hyprpolkitagent is the small Wayland-native option.
  security.polkit.enable = true;
  environment.systemPackages = [ pkgs.hyprpolkitagent ];

  # Real-time scheduling for Wayland compositors + audio.
  security.rtkit.enable = true;
}
