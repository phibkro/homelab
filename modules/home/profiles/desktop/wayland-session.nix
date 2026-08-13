{ inputs, pkgs, ... }:

/**
  Wayland session clients and command-line integration used by Hyprland.
*/
{
  home.packages = [
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

  programs.ghostty = {
    enable = true;
    settings.keybind = [
      # OMP speaks the Kitty keyboard protocol. These bindings preserve the
      # distinction between Alt+Backspace and Backspace, and between
      # Shift+Enter and Enter, when OMP runs inside Ghostty.
      "alt+backspace=text:\\x1b\\x7f"
      "shift+enter=text:\\n"
    ];
  };
}
