{ pkgs, inputs, ... }:
{
  # System-wide desktop apps. User-specific config (themes, keybinds,
  # ghostty/fuzzel options) lives in home-manager — see ./home.nix.
  environment.systemPackages = [
    # Terminal — same as the laptop, cross-machine consistency.
    pkgs.ghostty
    # Launcher — Wayland-native, fast (~5ms cold start).
    pkgs.fuzzel
    # Wallpaper daemon — Hyprland's own; lightweight, IPC-driven.
    pkgs.hyprpaper

    # Browser — community flake (zen isn't in nixpkgs).
    inputs.zen-browser.packages.${pkgs.system}.default

    # Quality-of-life CLI for Wayland.
    pkgs.wl-clipboard # `wl-copy` / `wl-paste` for clipboard scripting
    pkgs.brightnessctl # backlight control (no-op on desktop, harmless)
    pkgs.playerctl # MPRIS media control hotkeys
    pkgs.grim # screenshot capture
    pkgs.slurp # region selection (paired with grim)
    pkgs.libnotify # `notify-send` for shell scripts
  ];

  # Required for proper screen sharing under PipeWire+Wayland.
  services.dbus.enable = true;

  # Fonts — minimal default set so apps don't render in toofu boxes
  # (squares for missing glyphs). Nerd-font for terminal/launcher icons.
  fonts.packages = [
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
    pkgs.dejavu_fonts
    pkgs.nerd-fonts.jetbrains-mono
  ];
}
