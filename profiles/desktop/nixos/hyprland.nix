{ pkgs, ... }:
{
  /*
    System-side Hyprland: provides /run/current-system/sw/bin/Hyprland (the
    binary greetd execs), polkit + dbus integration, and the
    xdg-desktop-portal-hyprland config. Per-user config (keybinds, monitors,
    autostart) lives in users/nori/programs/desktop/hypr-rice/ via home-manager.
  */
  programs.hyprland = {
    enable = true;
    /*
      UWSM (Universal Wayland Session Manager) wraps the Hyprland start
      so systemd-user services tied to the graphical/Hyprland session targets
      (Persona, hypridle, hyprsunset) activate cleanly on login
      instead of needing a manual `systemctl --user restart` dance.
      Hyprland upstream warns at session start if UWSM isn't used.
      Exposes `hyprland-uwsm.desktop` — see services/greetd/nixos.nix
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
    Polkit agent autostart — needed for any app that prompts for elevation
    (network manager applet, mount helpers). Hyprland doesn't ship one;
    hyprpolkitagent is the small Wayland-native option.
  */
  security.polkit.enable = true;
  environment.systemPackages = [
    pkgs.hyprpolkitagent
    # Gracefully closes Wayland clients before exit, reboot, or poweroff.
    pkgs.hyprshutdown
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
