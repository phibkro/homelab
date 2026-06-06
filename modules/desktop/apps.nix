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

    # Editor — Zed, Rust-based, GPU-accelerated, AI-aware. Pulled from
    # nixpkgs master rather than the host's nixpkgs (nixos-unstable)
    # because the channel ships v0.232.3 while master is at v1.1.6;
    # months of Linux/Wayland/file-watcher fixes in the gap (#55829's
    # notify-rs runaway-CPU fix among them). Revert to plain
    # `pkgs.zed-editor` once nixos-unstable catches up.
    inputs.nixpkgs-master.legacyPackages.${pkgs.stdenv.hostPlatform.system}.zed-editor

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

    # Media player — VLC. Plays effectively any codec/container without
    # transcoding (HEVC/H.265 phone footage included), so it's the quick
    # "does this file actually play / how does it sound" check that sits
    # outside the editor.
    pkgs.vlc

    # resolve-remux — batch-transcode camera clips (HEVC/H.264, often
    # VFR) into DNxHR .mov the free Resolve on Linux can edit. ffmpeg is
    # bundled via runtimeInputs, so it runs without `nix-shell -p ffmpeg`.
    #   resolve-remux <input-dir> [fps]   (fps default 29.97)
    # Writes to a sibling remux/ dir, auto-picks DNxHR HQ/HQX by source
    # bit depth, maps audio only when present. Script body in the sibling
    # resolve-remux.sh (kept out of Nix to avoid ''${} escaping).
    (pkgs.writeShellApplication {
      name = "resolve-remux";
      runtimeInputs = [ pkgs.ffmpeg ];
      text = builtins.readFile ./resolve-remux.sh;
    })

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
    pkgs.hyprpicker # eyedrop screen → hex/rgb (`hyprpicker -a` to autocopy)
    pkgs.hyprsysteminfo # Hyprland's first-party system info dashboard

    # snappy-switcher — Hyprland alt-tab overlay (pure C, Cairo/Pango,
    # Wayland layer shell; no GTK/Electron). Upstream flake; binds and
    # daemon autostart live in machines/workstation/hyprland.lua.
    inputs.snappy-switcher.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.ags # Aylur's GTK Shell — TSX/JSX over GTK widgets via Astal/GJS.
    # Declarative widget framework for status bars, OSDs, popups, panels.
    # Material You styling lands via CSS + the Stylix-fed GTK theme.

    # Voice + text chat. Slack lives in the browser; Discord's desktop
    # client is the better fit for voice quality + push-to-talk.
    pkgs.discord
    pkgs.obsidian

    # Archive handling. thunar-archive-plugin (registered below under
    # programs.thunar.plugins) is just the menu integration — it shells
    # out to xarchiver, which in turn shells out to unzip / 7z / etc.
    # Without these on PATH, right-click → Extract silently no-ops.
    pkgs.xarchiver
    pkgs.unzip
    pkgs.p7zip
  ];

  # Thunar — lightweight GUI file manager. Enabling via programs.thunar
  # (rather than just adding the package) registers it as the default
  # file:// handler so other apps' "open file manager" buttons land here,
  # plus loads its plugin set in-process.
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin # right-click extract / compress (menu only)
      thunar-volman # auto-mount USB / removable media
    ];
  };

  # Thumbnail daemon — Thunar (and other XDG file managers) talk to it
  # over D-Bus to render image/PDF/video thumbnails in place instead of
  # generic mime icons. Without this, folder views look "low-res" even
  # with a proper icon theme — Stylix paints chrome but the file tiles
  # stay as scaled-up mime symbols.
  services.tumbler.enable = true;
}
