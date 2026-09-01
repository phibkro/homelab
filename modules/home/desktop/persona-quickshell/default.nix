{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cavaPlugin = pkgs.stdenv.mkDerivation {
    pname = "qt6-cava-plugin";
    version = "0.1.0";
    src = inputs.persona-cava;
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
      pkgs.qt6.wrapQtAppsHook
    ];
    buildInputs = [
      pkgs.fftw
      pkgs.pipewire
      pkgs.qt6.qtbase
      pkgs.qt6.qtdeclarative
    ];
    cmakeFlags = [ "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}/lib/qt6/qml" ];
    postInstall = ''
      test -f "$out/lib/qt6/qml/CavaMonitor/qmldir"
    '';
  };
  qmlImportPath = lib.concatStringsSep ":" [
    "${cavaPlugin}/lib/qt6/qml"
    "${pkgs.qt6.qtmultimedia}/lib/qt-6/qml"
  ];
  qtPluginPath = lib.makeSearchPath "lib/qt-6/plugins" [
    pkgs.qt6.qtmultimedia
  ];

  /*
    Upstream is a mutable QML source tree rather than a Nix package. Keep the
    pinned source intact and derive the workstation-compatible tree here:
      * replace the NetworkManager-only service with the network-backend-neutral
        adapter beside this module;
      * add the native Persona notification daemon and toast layer;
      * instantiate video-backed overlays on first use, then retain the stopped
        instance after dismissal; eager construction keeps hidden decoders alive,
        while repeated QtMultimedia destruction leaks native allocations;
      * use fonts already supplied declaratively by the desktop profile instead
        of references to absent Assets/fonts files and Windows-only families.

    --replace-fail turns upstream drift into a build failure instead of silently
    shipping a half-applied adaptation.
  */
  personaSource =
    pkgs.runCommandLocal "persona-quickshell-source"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.gnused
        ];
      }
      ''
        mkdir -p "$out"
        cp -R ${inputs.persona-quickshell}/. "$out/"
        chmod -R u+w "$out"
        test -f "$out/Widgets/Info/NetInfo.qml"
        test ! -e "$out/Layers/Notifications.qml"

        cp ${./NetInfo.qml} "$out/Widgets/Info/NetInfo.qml"
        cp ${./Notifications.qml} "$out/Layers/Notifications.qml"
        cp ${./wallpaper.qml} "$out/wallpaper.qml"

        substituteInPlace "$out/shell.qml" \
          --replace-fail '    Lay.Searchapp {}' $'    Lay.Searchapp {}\n    Lay.Notifications {}' \
          --replace-fail $'import "./Widgets" as Wid\n' "" \
          --replace-fail $'    Variants {\n        model: Quickshell.screens\n        Scope {\n            id: scopeRoot\n            required property ShellScreen modelData\n            Wid.WallpaperEngine {\n                modelData: scopeRoot.modelData\n            }\n        }\n    }\n' ""

        substituteInPlace "$out/Layers/AppDrawer.qml" \
          --replace-fail $'                    id: bladesContainer\n                    anchors.left: mainCircle.right' $'                    id: bladesContainer\n                    property int hoveredBlade: -1\n                    anchors.left: mainCircle.right' \
          --replace-fail $'                            id: blade\n                            width: 120' $'                            id: blade\n                            z: bladesContainer.hoveredBlade === index ? 100 : index\n                            opacity: bladesContainer.hoveredBlade < 0 || bladesContainer.hoveredBlade === index ? 1 : 0.45\n                            Behavior on opacity {\n                                NumberAnimation {\n                                    duration: 140\n                                    easing.type: Easing.OutCubic\n                                }\n                            }\n                            width: 120' \
          --replace-fail $'                                onHoveredChanged: {\n                                    if (hovered)\n                                        autoHideTimer.stop();\n                                }' $'                                onHoveredChanged: {\n                                    if (hovered) {\n                                        bladesContainer.hoveredBlade = index;\n                                        autoHideTimer.stop();\n                                    } else if (bladesContainer.hoveredBlade === index) {\n                                        bladesContainer.hoveredBlade = -1;\n                                    }\n                                }'

        test "$(${pkgs.gnugrep}/bin/grep -c '^    FontLoader {$' "$out/Layers/OptionsList.qml")" -eq 2
        sed -i '/^    FontLoader {$/,/^    }$/d' "$out/Layers/OptionsList.qml"
        ! ${pkgs.gnugrep}/bin/grep -q '^    FontLoader {$' "$out/Layers/OptionsList.qml"
        substituteInPlace "$out/Layers/Options.qml" \
          --replace-fail '    property bool shouldShow: false' $'    property bool shouldShow: false\n    property bool hasShown: false\n    onShouldShowChanged: if (shouldShow) hasShown = true' \
          --replace-fail '        active: true' '        active: root.shouldShow || root.hasShown' \
          --replace-fail 'font.family: bebasNeue.name' 'font.family: "Montserrat"'
        substituteInPlace "$out/Layers/OptionsList.qml" \
          --replace-fail 'font.family: bebasNeue.name' 'font.family: "Montserrat"' \
          --replace-fail 'font.family: montserrat.name' 'font.family: "Montserrat"'
        substituteInPlace "$out/Layers/Calendar.qml" \
          --replace-fail $'                Rectangle {\n                    width: parent.width * 2\n                    height: parent.height * 0.2' $'                Rectangle {\n                    id: blueBand\n                    width: parent.width * 2\n                    height: parent.height * 0.2' \
          --replace-fail $'                    transform: Rotation {\n                        origin.x: parent.width / 2\n                        origin.y: parent.height / 2\n                        angle: 20' $'                    transform: Rotation {\n                        origin.x: blueBand.width / 2\n                        origin.y: blueBand.height / 2\n                        angle: 20' \
          --replace-fail $'                Rectangle {\n                    width: parent.width * 200\n                    height: 5' $'                Rectangle {\n                    id: whiteLine\n                    width: parent.width * 200\n                    height: 5' \
          --replace-fail $'                    transform: Rotation {\n                        origin.x: parent.width / 2\n                        origin.y: parent.height / 2\n                        angle: -20' $'                    transform: Rotation {\n                        origin.x: whiteLine.width / 2\n                        origin.y: whiteLine.height / 2\n                        angle: -20' \
          --replace-fail $'            anchors.left: parent.left - 109\n            anchors.verticalCenter: parent.verticalCenter * -10' $'            anchors.left: parent.left\n            anchors.leftMargin: -109\n            anchors.verticalCenter: parent.verticalCenter\n            anchors.verticalCenterOffset: -10' \
          --replace-fail 'font.family: "Microsoft Yahei"' 'font.family: "Montserrat"' \
          --replace-fail 'font.family: "Bahnschrift Condensed"' 'font.family: "Roboto Condensed"'
        substituteInPlace "$out/Layers/Clock.qml" \
          --replace-fail '                    text: Info.BatteryInfo.icon + " " + Info.BatteryInfo.percentageString' $'                    visible: Info.BatteryInfo.available\n                    text: Info.BatteryInfo.icon + " " + Info.BatteryInfo.percentageString' \
          --replace-fail 'font.family: "Microsoft Yahei"' 'font.family: "Montserrat"' \
          --replace-fail 'font.family: "Bahnschrift Condensed"' 'font.family: "Roboto Condensed"' \
          --replace-fail 'font.family: "JetBrainsMono Nerd Font"' 'font.family: "JetBrainsMono Nerd Font Mono"'
        substituteInPlace "$out/Layers/P3rpause.qml" \
          --replace-fail '    property bool shouldShow: false' $'    property bool shouldShow: false\n    property bool hasShown: false\n    onShouldShowChanged: if (shouldShow) hasShown = true' \
          --replace-fail '        active: true' '        active: root.shouldShow || root.hasShown'
        substituteInPlace "$out/Layers/Resume.qml" \
          --replace-fail '    property bool shouldShow: false' $'    property bool shouldShow: false\n    property bool hasShown: false\n    onShouldShowChanged: if (shouldShow) hasShown = true' \
          --replace-fail '        active: true' '        active: root.shouldShow || root.hasShown' \
          --replace-fail 'font.family: "proggyfonts"' 'font.family: "JetBrainsMono Nerd Font Mono"' \
          --replace-fail 'subtitle: "Wifi Networks and connections"' 'subtitle: "Active network interfaces"' \
          --replace-fail '"Wifi networks"' '"Network interfaces"'
      '';

  personaShell = pkgs.writeShellApplication {
    name = "persona-quickshell";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.hyprland
      pkgs.iproute2
      pkgs.systemd
    ];
    text = ''
      export QML_IMPORT_PATH=${lib.escapeShellArg qmlImportPath}''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}
      export QML2_IMPORT_PATH=${lib.escapeShellArg qmlImportPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}
      export QT_PLUGIN_PATH=${lib.escapeShellArg qtPluginPath}''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}
      exec ${pkgs.quickshell}/bin/qs --path ${personaSource}/shell.qml
    '';
  };
  personaWallpaper = pkgs.writeShellApplication {
    name = "persona-quickshell-wallpaper";
    text = ''
      export QML_IMPORT_PATH=${lib.escapeShellArg qmlImportPath}''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}
      export QML2_IMPORT_PATH=${lib.escapeShellArg qmlImportPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}
      export QT_PLUGIN_PATH=${lib.escapeShellArg qtPluginPath}''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}
      exec ${pkgs.quickshell}/bin/qs --path ${personaSource}/wallpaper.qml
    '';
  };
  personaDesktop = pkgs.writeShellApplication {
    name = "persona-desktop";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -eu

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/persona-desktop"
      desktop_disabled="$state_dir/desktop-disabled"
      wallpaper_disabled="$state_dir/wallpaper-disabled"

      usage() {
        echo "usage: persona-desktop {enable|disable|status|wallpaper {enable|disable}}" >&2
        exit 64
      }

      mkdir -p "$state_dir"

      case "''${1:-}" in
        enable)
          [ "$#" -eq 1 ] || usage
          rm -f "$desktop_disabled"
          systemctl --user start waybar.service hyprpaper.service persona-quickshell.service
          if [ ! -e "$wallpaper_disabled" ]; then
            systemctl --user start persona-quickshell-wallpaper.service
          fi
          ;;
        disable)
          [ "$#" -eq 1 ] || usage
          touch "$desktop_disabled"
          systemctl --user stop persona-quickshell-wallpaper.service persona-quickshell.service
          systemctl --user start hyprpaper.service waybar.service
          ;;
        wallpaper)
          [ "$#" -eq 2 ] || usage
          case "$2" in
            enable)
              rm -f "$wallpaper_disabled"
              if [ ! -e "$desktop_disabled" ]; then
                systemctl --user start persona-quickshell-wallpaper.service
              fi
              ;;
            disable)
              touch "$wallpaper_disabled"
              systemctl --user stop persona-quickshell-wallpaper.service
              systemctl --user start hyprpaper.service
              ;;
            *) usage ;;
          esac
          ;;
        status)
          [ "$#" -eq 1 ] || usage
          if [ -e "$desktop_disabled" ]; then
            echo "persona desktop: disabled"
          else
            echo "persona desktop: enabled"
          fi
          if [ -e "$wallpaper_disabled" ]; then
            echo "animated wallpaper: disabled"
          else
            echo "animated wallpaper: enabled"
          fi
          for unit in \
            persona-quickshell.service \
            persona-quickshell-wallpaper.service \
            hyprpaper.service \
            waybar.service; do
            state="$(systemctl --user is-active "$unit" 2>/dev/null || true)"
            printf '%s: %s\n' "$unit" "''${state:-unknown}"
          done
          ;;
        *) usage ;;
      esac
    '';
  };
  personaEnabled = pkgs.writeShellScript "persona-desktop-enabled" ''
    set -eu
    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/persona-desktop"
    test ! -e "$state_dir/desktop-disabled"
    if [ "''${1:-}" = wallpaper ]; then
      test ! -e "$state_dir/wallpaper-disabled"
    fi
  '';
in
{
  home.packages = [
    personaDesktop
    personaShell
    personaWallpaper
    pkgs.quickshell
    pkgs.montserrat
  ];

  # Quickshell discovers named configurations below the XDG quickshell root.
  xdg.configFile."quickshell/persona".source = personaSource;

  /*
    Keep the Stylix wallpaper alive underneath Persona. The static service is
    the fallback, not a second source of truth: Stylix owns the image and both
    Persona modes merely reveal or cover it.
  */
  stylix.targets.hyprpaper.enable = true;
  services.hyprpaper.enable = true;

  /*
    Restart stays disabled until the exact command has been exercised after the
    Pi rebuild. A malformed QML import must fail once, not become a GPU-heavy
    restart loop during the next workstation activation.
  */
  systemd.user.services.persona-quickshell = {
    Unit = {
      Description = "Persona Quickshell desktop shell";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
    };
    Install.WantedBy = [ config.wayland.systemd.target ];
    Service = {
      Type = "simple";
      ExecCondition = "${personaEnabled} desktop";
      ExecStart = "${personaShell}/bin/persona-quickshell";
      Restart = "no";
    };
  };

  systemd.user.services.persona-quickshell-wallpaper = {
    Unit = {
      Description = "Persona Quickshell animated wallpaper";
      PartOf = [ config.wayland.systemd.target ];
      After = [
        config.wayland.systemd.target
        "hyprpaper.service"
      ];
    };
    Install.WantedBy = [ config.wayland.systemd.target ];
    Service = {
      Type = "simple";
      ExecCondition = "${personaEnabled} wallpaper";
      ExecStart = "${personaWallpaper}/bin/persona-quickshell-wallpaper";
      Restart = "no";
    };
  };
}
