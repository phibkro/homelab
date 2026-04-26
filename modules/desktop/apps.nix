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

    # Tailscale tray icon (community GTK GUI). The tailscale CLI is
    # already enabled via services.tailscale; trayscale is just the
    # tray-area indicator + node list.
    pkgs.trayscale

    # Claude Code CLI — Anthropic doesn't ship a Linux desktop client;
    # the CLI is the canonical way to interact from a terminal. Already
    # installed elsewhere (Mac), but having it here makes nori-station
    # usable as a dev environment in its own right.
    pkgs.claude-code

    # Quality-of-life CLI for Wayland.
    pkgs.wl-clipboard # `wl-copy` / `wl-paste` for clipboard scripting
    pkgs.brightnessctl # backlight control (no-op on desktop, harmless)
    pkgs.playerctl # MPRIS media control hotkeys
    pkgs.grim # screenshot capture
    pkgs.slurp # region selection (paired with grim)
    pkgs.libnotify # `notify-send` for shell scripts
    pkgs.pwvucontrol # PipeWire mixer GUI (sink/source picker, per-app vol)
  ];

  # Required for proper screen sharing under PipeWire+Wayland.
  services.dbus.enable = true;

  # Fonts — minimal default set so apps don't render in toofu boxes
  # (squares for missing glyphs). Nerd-font (Hack) for terminal/launcher
  # icons; plain Hack for documents that don't need Nerd Font icons.
  fonts.packages = [
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
    pkgs.dejavu_fonts
    pkgs.hack-font
    pkgs.nerd-fonts.hack
  ];
}
