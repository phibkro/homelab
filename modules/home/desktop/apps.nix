{ pkgs, inputs, ... }:
{
  /**
    Desktop session apps + Wayland CLI utilities. User-tier install —
    lands in ~/.nix-profile, on PATH for the graphical session and any
    shell. Cross-references:
      - System-level enables (Thunar's file:// handler, tumbler thumbnail
        daemon) live in modules/machines/desktop/apps.nix — those need NixOS
        module scope to wire xdg-mime + dbus.
      - Hyprland config + binds live in modules/machines/workstation/hyprland.lua.
      - Cross-platform tools (browsers, editors that also live on Mac)
        stay in modules/home/pc.nix or modules/home/core.nix.
  */
  home.packages = [
    # Terminal — same as the laptop, cross-machine consistency.
    pkgs.ghostty
    # Launcher — ~5ms cold start.
    pkgs.fuzzel
    pkgs.hyprpaper

    # Browser — community flake (zen isn't in nixpkgs).
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default

    /*
      Password manager — Electron desktop client. `bw` CLI not bundled
      by default; add `pkgs.bitwarden-cli` separately if scripted access
      is needed.
    */
    pkgs.bitwarden-desktop

    /*
      Editor — Zed, Rust-based, GPU-accelerated, AI-aware. Pulled from
      nixpkgs master rather than the host's nixpkgs (nixos-unstable)
      because the channel ships v0.232.3 while master is at v1.1.6;
      months of Linux/Wayland/file-watcher fixes in the gap (#55829's
      notify-rs runaway-CPU fix among them). Revert to plain
      `pkgs.zed-editor` once nixos-unstable catches up.
    */
    inputs.nixpkgs-master.legacyPackages.${pkgs.stdenv.hostPlatform.system}.zed-editor

    pkgs.audacity

    /*
      Remote desktop client + server (RustDesk). When the gaming laptop
      joins the tailnet, RustDesk gives a quick GUI-share path. Server
      side defaults to localhost-only; flip on via in-app settings if
      you want to host sessions.
    */
    pkgs.rustdesk

    /*
      Tailscale tray icon. The tailscale CLI is already enabled via
      services.tailscale; this is just the tray-area indicator + node
      list. tailscale-systray is the lighter Go option (no GTK runtime
      pull-in) — fits the rest of the keyboard-driven, terminal-leaning
      session aesthetic better than Trayscale's full GTK app.
    */
    pkgs.tailscale-systray

    /*
      DaVinci Resolve — professional video editor. ~3 GB closure;
      unfree license (free to use, paid Studio version). NVIDIA GPU
      used for hardware decode/encode. First launch may complain about
      missing CUDA libs on certain combinations; if so, override the
      package via overrideAttrs.cudaPackages or upgrade the driver.
    */
    pkgs.davinci-resolve

    # VLC — codec-agnostic "does this file actually play" check outside
    # the editor (HEVC/H.265 phone footage included).
    pkgs.vlc

    /**
      resolve-remux — batch-transcode camera clips (HEVC/H.264, often
      VFR) into DNxHR .mov the free Resolve on Linux can edit.
        resolve-remux <input-dir> [fps]   (fps default 29.97)
      Script body in the sibling resolve-remux.sh (kept out of Nix to
      avoid ''${} escaping).
    */
    (pkgs.writeShellApplication {
      name = "resolve-remux";
      runtimeInputs = [ pkgs.ffmpeg ];
      text = builtins.readFile ./resolve-remux.sh;
    })

    /*
      File management — yazi (TUI, run from ghostty) as primary;
      Thunar (the GUI side) is enabled at system level so it picks
      xdg-mime + plugins.
    */
    pkgs.yazi

    # Quality-of-life CLI for Wayland.
    pkgs.wl-clipboard # `wl-copy` / `wl-paste` for clipboard scripting
    pkgs.brightnessctl # backlight control (no-op on desktop, harmless)
    pkgs.playerctl # MPRIS media control hotkeys
    pkgs.grim # screenshot capture
    pkgs.slurp # region selection (paired with grim)
    pkgs.libnotify # `notify-send` for shell scripts
    pkgs.pwvucontrol # PipeWire mixer GUI (sink/source picker, per-app vol)
    pkgs.hyprpicker # eyedrop screen → hex/rgb (`hyprpicker -a` to autocopy)
    pkgs.hyprsysteminfo # Hyprland's first-party system info dashboard

    /*
      snappy-switcher — Hyprland alt-tab overlay (pure C, Cairo/Pango,
      Wayland layer shell; no GTK/Electron). Upstream flake; binds and
      daemon autostart live in modules/machines/workstation/hyprland.lua.
    */
    inputs.snappy-switcher.packages.${pkgs.stdenv.hostPlatform.system}.default
    # ags — declarative widget framework (status bars, OSDs, popups);
    # Material You styling via CSS + the Stylix-fed GTK theme.
    pkgs.ags

    # Voice + text chat. Slack lives in the browser; Discord's desktop
    # client is the better fit for voice quality + push-to-talk.
    pkgs.discord
    pkgs.obsidian

    # Archive-extraction backends — thunar-archive-plugin shells out to
    # these; without them on PATH, right-click → Extract silently no-ops.
    pkgs.xarchiver
    pkgs.unzip
    pkgs.p7zip
  ];
}
