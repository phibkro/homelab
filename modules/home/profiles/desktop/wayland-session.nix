{ inputs, pkgs, ... }:

/**
  Wayland session clients and command-line integration used by Hyprland.
*/
{
  home.packages = [
    pkgs.ghostty
    pkgs.fuzzel
    pkgs.hyprpaper
    pkgs.rustdesk
    pkgs.tailscale-systray
    pkgs.yazi
    pkgs.wl-clipboard
    pkgs.brightnessctl
    pkgs.playerctl
    pkgs.grim
    pkgs.slurp
    pkgs.libnotify
    pkgs.pwvucontrol
    pkgs.hyprpicker
    pkgs.hyprsysteminfo
    inputs.snappy-switcher.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.ags
    pkgs.xarchiver
    pkgs.unzip
    pkgs.p7zip
  ];
}
