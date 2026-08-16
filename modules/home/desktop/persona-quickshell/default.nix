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

        substituteInPlace "$out/shell.qml" \
          --replace-fail '    Lay.Searchapp {}' $'    Lay.Searchapp {}\n    Lay.Notifications {}'

        substituteInPlace "$out/Layers/AppDrawer.qml" \
          --replace-fail $'                    id: bladesContainer\n                    anchors.left: mainCircle.right' $'                    id: bladesContainer\n                    property int hoveredBlade: -1\n                    anchors.left: mainCircle.right' \
          --replace-fail $'                            id: blade\n                            width: 120' $'                            id: blade\n                            z: bladesContainer.hoveredBlade === index ? 100 : index\n                            opacity: bladesContainer.hoveredBlade < 0 || bladesContainer.hoveredBlade === index ? 1 : 0.45\n                            Behavior on opacity {\n                                NumberAnimation {\n                                    duration: 140\n                                    easing.type: Easing.OutCubic\n                                }\n                            }\n                            width: 120' \
          --replace-fail $'                                onHoveredChanged: {\n                                    if (hovered)\n                                        autoHideTimer.stop();\n                                }' $'                                onHoveredChanged: {\n                                    if (hovered) {\n                                        bladesContainer.hoveredBlade = index;\n                                        autoHideTimer.stop();\n                                    } else if (bladesContainer.hoveredBlade === index) {\n                                        bladesContainer.hoveredBlade = -1;\n                                    }\n                                }'

        test "$(${pkgs.gnugrep}/bin/grep -c '^    FontLoader {$' "$out/Layers/OptionsList.qml")" -eq 2
        sed -i '/^    FontLoader {$/,/^    }$/d' "$out/Layers/OptionsList.qml"
        ! ${pkgs.gnugrep}/bin/grep -q '^    FontLoader {$' "$out/Layers/OptionsList.qml"
        substituteInPlace "$out/Layers/Options.qml" \
          --replace-fail 'font.family: bebasNeue.name' 'font.family: "Montserrat"'
        substituteInPlace "$out/Layers/OptionsList.qml" \
          --replace-fail 'font.family: bebasNeue.name' 'font.family: "Montserrat"' \
          --replace-fail 'font.family: montserrat.name' 'font.family: "Montserrat"'
        substituteInPlace "$out/Layers/Calendar.qml" \
          --replace-fail 'font.family: "Microsoft Yahei"' 'font.family: "Montserrat"' \
          --replace-fail 'font.family: "Bahnschrift Condensed"' 'font.family: "Roboto Condensed"'
        substituteInPlace "$out/Layers/Clock.qml" \
          --replace-fail '                    text: Info.BatteryInfo.icon + " " + Info.BatteryInfo.percentageString' $'                    visible: Info.BatteryInfo.available\n                    text: Info.BatteryInfo.icon + " " + Info.BatteryInfo.percentageString' \
          --replace-fail 'font.family: "Microsoft Yahei"' 'font.family: "Montserrat"' \
          --replace-fail 'font.family: "Bahnschrift Condensed"' 'font.family: "Roboto Condensed"' \
          --replace-fail 'font.family: "JetBrainsMono Nerd Font"' 'font.family: "JetBrainsMono Nerd Font Mono"'
        substituteInPlace "$out/Layers/Resume.qml" \
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
      exec ${pkgs.quickshell}/bin/qs -c persona
    '';
  };
in
{
  home.packages = [
    personaShell
    pkgs.quickshell
    pkgs.montserrat
  ];

  # Quickshell discovers named configurations below the XDG quickshell root.
  xdg.configFile."quickshell/persona".source = personaSource;

  # Persona's animated bottom-layer surface is the session wallpaper.
  stylix.targets.hyprpaper.enable = false;
  services.hyprpaper.enable = lib.mkForce false;

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
      ExecStart = "${personaShell}/bin/persona-quickshell";
      Restart = "no";
    };
  };
}
