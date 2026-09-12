{
  config,
  lib,
  pkgs,
  ...
}:
let
  settingsSource = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      let
        name = builtins.baseNameOf path;
      in
      !lib.elem name [
        ".git"
        "dist"
        "node_modules"
        "result"
      ];
  };
  qmlImportPath = lib.makeSearchPath "lib/qt-6/qml" [
    pkgs.qt6.qtdeclarative
    pkgs.qt6.qtquickcontrols2
  ];
  settingsApp = pkgs.writeShellApplication {
    name = "nori-desktop-settings-ui";
    runtimeInputs = [ config.nori.desktop.settingsService.package ];
    text = ''
      export QML_IMPORT_PATH=${lib.escapeShellArg qmlImportPath}''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}
      export QML2_IMPORT_PATH=${lib.escapeShellArg qmlImportPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}
      exec ${pkgs.quickshell}/bin/qs --path ${settingsSource}/shell.qml
    '';
  };
in
{
  home.packages = [ settingsApp ];

  xdg.desktopEntries.nori-desktop-settings = {
    name = "Desktop Settings";
    genericName = "Desktop configuration";
    comment = "View and apply the managed desktop settings profile";
    exec = "${settingsApp}/bin/nori-desktop-settings-ui";
    icon = "preferences-system";
    categories = [
      "Settings"
      "System"
    ];
    keywords = [
      "desktop"
      "settings"
      "waybar"
    ];
    startupNotify = true;
    terminal = false;
  };
}
