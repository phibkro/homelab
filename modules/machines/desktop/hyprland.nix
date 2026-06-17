{ pkgs, ... }:
{
  /*
    System-side Hyprland: provides /run/current-system/sw/bin/Hyprland (the
    binary greetd execs), polkit + dbus integration, and the
    xdg-desktop-portal-hyprland config. Per-user config (keybinds, monitors,
    autostart) lives in modules/machines/workstation/home.nix via home-manager.
  */
  programs.hyprland = {
    enable = true;
    /*
      UWSM (Universal Wayland Session Manager) wraps the Hyprland start
      so systemd-user services depending on graphical-session.target
      (waybar, mako, hypridle, hyprsunset) activate cleanly on login
      instead of needing a manual `systemctl --user restart` dance.
      Hyprland upstream warns at session start if UWSM isn't used.
      Exposes `hyprland-uwsm.desktop` — see modules/machines/desktop/greetd.nix
      for the greetd-side wiring.
    */
    withUWSM = true;
  };

  /*
    GTK fallback portal — needed for "open file" dialogs in apps that haven't
    implemented the native Hyprland portal (e.g. Electron pre-35 fallback).
  */
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  /*
    Wayland session env vars. Driver 595 + explicit-sync removes most
    historical NVIDIA-Wayland pain (see TOPOLOGY.md § GPU access); keep
    the set minimal and add hints only when something actually breaks.
  */
  environment.sessionVariables = {
    # NixOS-specific shim — flips Electron/Chromium to native Wayland.
    NIXOS_OZONE_WL = "1";
    /*
      Disambiguate libglvnd vendor under XWayland on hybrid setups
      (single-GPU here but harmless + future-proof).
    */
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    /*
      Hardware video decode/encode (NVENC/NVDEC) for VA-API consumers
      — Jellyfin transcodes, ffmpeg, browser hardware decode. Without
      this, mpv/firefox-style apps fall back to software decode.
    */
    LIBVA_DRIVER_NAME = "nvidia";
    /*
      Newer Electron flag (Hyprland NVIDIA wiki). NIXOS_OZONE_WL
      covers most cases; ELECTRON_OZONE_PLATFORM_HINT=auto is the
      upstream-supported approach for Electron 35+ that picks Wayland
      when available, falls back to X11 cleanly otherwise.
    */
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  /*
    Polkit agent autostart — needed for any app that prompts for elevation
    (network manager applet, mount helpers). Hyprland doesn't ship one;
    hyprpolkitagent is the small Wayland-native option.
  */
  security.polkit.enable = true;
  environment.systemPackages = [
    pkgs.hyprpolkitagent
    /*
      programs.hyprland.withUWSM registers the uwsm-flavored desktop
      session entry but doesn't add the binary to systemPackages.
      greetd's tuigreet runs as the `greeter` user and needs `uwsm` on
      its PATH to launch the session.
    */
    pkgs.uwsm
  ];

  # Real-time scheduling for Wayland compositors + audio.
  security.rtkit.enable = true;
}
