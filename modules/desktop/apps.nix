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
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default

    # Password manager — Electron desktop client. `bw` CLI not bundled
    # by default; add `pkgs.bitwarden-cli` separately if scripted access
    # is needed.
    pkgs.bitwarden-desktop

    # Editor — Zed, Rust-based, GPU-accelerated, AI-aware.
    pkgs.zed-editor

    # Audio editor — multi-track recording + editing.
    pkgs.audacity

    # Remote desktop client + server (RustDesk). When the gaming laptop
    # joins the tailnet, RustDesk gives a quick GUI-share path. Server
    # side defaults to localhost-only; flip on via in-app settings if
    # you want to host sessions.
    pkgs.rustdesk

    # Tailscale tray icon. The tailscale CLI is already enabled via
    # services.tailscale; this is just the tray-area indicator + node
    # list. tailscale-systray is the lighter Go option (no GTK runtime
    # pull-in) — fits the rest of the keyboard-driven, terminal-leaning
    # session aesthetic better than Trayscale's full GTK app.
    pkgs.tailscale-systray

    # DaVinci Resolve — professional video editor. ~3 GB closure;
    # unfree license (free to use, paid Studio version). NVIDIA GPU
    # used for hardware decode/encode. First launch may complain about
    # missing CUDA libs on certain combinations; if so, override the
    # package via overrideAttrs.cudaPackages or upgrade the driver.
    pkgs.davinci-resolve

    # File management — yazi (TUI, run from ghostty) as primary;
    # Thunar (GUI) as fallback for drag-drop / file:// xdg-open from
    # other apps. Thunar's NixOS-side wiring is below via
    # programs.thunar.enable, which sets up xdg-mime + plugins.
    pkgs.yazi

    # Quality-of-life CLI for Wayland.
    pkgs.wl-clipboard # `wl-copy` / `wl-paste` for clipboard scripting
    pkgs.brightnessctl # backlight control (no-op on desktop, harmless)
    pkgs.playerctl # MPRIS media control hotkeys
    pkgs.grim # screenshot capture
    pkgs.slurp # region selection (paired with grim)
    pkgs.libnotify # `notify-send` for shell scripts
    pkgs.pwvucontrol # PipeWire mixer GUI (sink/source picker, per-app vol)
  ];

  # Thunar — lightweight GUI file manager. Enabling via programs.thunar
  # (rather than just adding the package) registers it as the default
  # file:// handler so other apps' "open file manager" buttons land here,
  # plus loads its plugin set in-process.
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin # right-click extract / compress
      thunar-volman # auto-mount USB / removable media
    ];
  };

  # Fonts — minimal default set so apps don't render in toofu boxes
  # (squares for missing glyphs). Nerd-font (JetBrainsMono) for terminal
  # / launcher / hyprlock; plain JetBrainsMono for documents that don't
  # need Nerd Font icons.
  fonts.packages = [
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
    pkgs.dejavu_fonts
    pkgs.jetbrains-mono
    pkgs.nerd-fonts.jetbrains-mono
  ];
}
