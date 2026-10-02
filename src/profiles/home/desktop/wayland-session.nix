{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
/**
  Shared Wayland session clients and command-line integration.
*/
let
  # nixpkgs c59305b pins rustdesk 1.5.0 with a source hash that no longer
  # matches the tag's fetched tree (specified sha256-xuIUWx…, got
  # sha256-1xa7X+…, observed 2026-10-02). Correct the fixed-output hash here
  # and retire this override when nixpkgs refreshes it.
  rustdeskUpstream = pkgs.rustdesk.overrideAttrs (old: {
    src = old.src.overrideAttrs {
      outputHash = "sha256-1xa7X+swBIb8Lz3c6m8SeNZAiJWNCUpw+UbdSsMkeSk=";
    };
  });
  # RustDesk's Wayland capturer creates the GStreamer pipewiresrc element at
  # runtime. The upstream Nix wrapper omits PipeWire's plugin directory.
  rustdesk = pkgs.symlinkJoin {
    name = "${rustdeskUpstream.pname}-${rustdeskUpstream.version}";
    paths = [ rustdeskUpstream ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/rustdesk" \
        --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${pkgs.pipewire}/lib/gstreamer-1.0"
    '';
    inherit (rustdeskUpstream) meta;
  };
in
{
  # qtct still selects Kvantum for widget applications. The global override
  # also makes Plasma load Kvantum as a Qt Quick Controls module, which leaves
  # the shell without its wallpaper and other QML surfaces.
  home.sessionVariables.QT_STYLE_OVERRIDE = lib.mkForce "";
  # Plasma rewrites this Stylix-owned file during a session. Replace that
  # derived copy on activation instead of accumulating colliding backups.
  home.file."${config.gtk.gtk2.configLocation}".force = lib.mkForce true;

  home.packages = [
    pkgs.fuzzel
    pkgs.moonlight-qt
    rustdesk
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
