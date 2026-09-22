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
  # RustDesk's Wayland capturer creates the GStreamer pipewiresrc element at
  # runtime. The upstream Nix wrapper omits PipeWire's plugin directory.
  rustdesk = pkgs.symlinkJoin {
    name = "${pkgs.rustdesk.pname}-${pkgs.rustdesk.version}";
    paths = [ pkgs.rustdesk ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/rustdesk" \
        --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${pkgs.pipewire}/lib/gstreamer-1.0"
    '';
    meta = pkgs.rustdesk.meta;
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
