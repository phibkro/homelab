{
  config,
  lib,
  pkgs,
  ...
}:
let
  cleanSource = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      let
        name = builtins.baseNameOf path;
      in
      name != "dist" && name != "node_modules";
  };
  serviceImplementation = pkgs.buildNpmPackage {
    pname = "nori-desktop-settings-service";
    version = "0.1.0";
    src = cleanSource;
    npmDeps = pkgs.importNpmLock { npmRoot = cleanSource; };
    npmConfigHook = pkgs.importNpmLock.npmConfigHook;
    nativeBuildInputs = [ pkgs.bun ];
    buildPhase = ''
      runHook preBuild
      bun build src/main.ts --compile --outfile dist/nori-desktop-settings
      bun build src/rice-saved-command.ts --compile --outfile dist/rice-saved-command
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 dist/nori-desktop-settings "$out/libexec/nori-desktop-settings"
      install -Dm755 dist/rice-saved-command "$out/libexec/rice-saved-command"
      runHook postInstall
    '';
  };
  nativeIngress = pkgs.stdenv.mkDerivation {
    pname = "nori-desktop-settings-ingress";
    version = "0.1.0";
    src = cleanSource;
    strictDeps = true;
    buildPhase = ''
      runHook preBuild
      $CC -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -o nori-desktop-settings-ingress src/unix-ingress.c
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 nori-desktop-settings-ingress "$out/bin/nori-desktop-settings-ingress"
      runHook postInstall
    '';
  };
  settingsIngress = pkgs.writeShellApplication {
    name = "nori-desktop-settings-ingress";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      exec ${nativeIngress}/bin/nori-desktop-settings-ingress \
        "$XDG_RUNTIME_DIR/nori-desktop/settings.sock" \
        "$XDG_RUNTIME_DIR/nori-desktop/settings-backend.sock" \
        "$(id -u)"
    '';
  };
  commonEnvironment = ''
    if [ -z "''${NORI_DESKTOP_SETTINGS_CONFIG_HOME-}" ]; then
      export NORI_DESKTOP_SETTINGS_CONFIG_HOME=${lib.escapeShellArg "${config.xdg.configHome}/nori-desktop"}
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_STATE_HOME-}" ]; then
      export NORI_DESKTOP_SETTINGS_STATE_HOME=${lib.escapeShellArg "${config.xdg.stateHome}/nori-desktop"}
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_DATA_DIR-}" ]; then
      export NORI_DESKTOP_SETTINGS_DATA_DIR=${lib.escapeShellArg "${config.xdg.dataHome}/nori-desktop"}
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_APPROVED_SOURCE-}" ]; then
      export NORI_DESKTOP_SETTINGS_APPROVED_SOURCE=/etc/nori-desktop-settings/approved-source.json
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_ACTIVE_METADATA-}" ]; then
      export NORI_DESKTOP_SETTINGS_ACTIVE_METADATA=/etc/nori-desktop-settings/generation.json
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_BUILDER-}" ]; then
      export NORI_DESKTOP_SETTINGS_BUILDER=/run/current-system/sw/bin/nori-desktop-settings-build
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_EVALUATOR-}" ]; then
      export NORI_DESKTOP_SETTINGS_EVALUATOR=/run/current-system/sw/bin/nori-desktop-settings-preview
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_ACTIVATOR-}" ]; then
      export NORI_DESKTOP_SETTINGS_ACTIVATOR=/run/current-system/sw/bin/nori-desktop-settings-activate
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_SYSTEMCTL-}" ]; then
      export NORI_DESKTOP_SETTINGS_SYSTEMCTL=${lib.escapeShellArg "${pkgs.systemd}/bin/systemctl"}
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_HYPRCTL-}" ]; then
      export NORI_DESKTOP_SETTINGS_HYPRCTL=${lib.escapeShellArg "${pkgs.hyprland}/bin/hyprctl"}
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_PKEXEC-}" ]; then
      export NORI_DESKTOP_SETTINGS_PKEXEC=/run/wrappers/bin/pkexec
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_SHELL-}" ]; then
      export NORI_DESKTOP_SETTINGS_SHELL=${lib.escapeShellArg (lib.getExe pkgs.bash)}
    fi
    if [ -z "''${RICE_VICINAE_BIN-}" ]; then
      export RICE_VICINAE_BIN=${lib.escapeShellArg (lib.getExe pkgs.vicinae)}
    fi
    if [ -z "''${XDG_RUNTIME_DIR-}" ]; then
      echo "nori-desktop-settings: XDG_RUNTIME_DIR is not configured" >&2
      exit 70
    fi
    if [ -z "''${NORI_DESKTOP_SETTINGS_SOCKET-}" ]; then
      export NORI_DESKTOP_SETTINGS_SOCKET="$XDG_RUNTIME_DIR/nori-desktop/settings.sock"
    fi
  '';
  settingsCli = pkgs.writeShellApplication {
    name = "nori-desktop-settings";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      ${commonEnvironment}
      exec ${serviceImplementation}/libexec/nori-desktop-settings "$@"
    '';
  };
  savedCommandCli = pkgs.writeShellApplication {
    name = "rice-saved-command";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      ${commonEnvironment}
      runner=$(readlink -f "$0")
      export NORI_DESKTOP_SETTINGS_RICE_COMMAND="$runner"
      exec ${serviceImplementation}/libexec/rice-saved-command "$@"
    '';
  };
  package = pkgs.symlinkJoin {
    name = "nori-desktop-settings";
    paths = [
      settingsCli
      savedCommandCli
      settingsIngress
    ];
  };
in
{
  options.nori.desktop.settingsService.package = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
    description = "Installed client and daemon executables for the desktop settings service.";
  };

  config = {
    nori.desktop.settingsService.package = package;

    home.packages = [ package ];

    systemd.user.services.nori-desktop-config = {
      Unit.Description = "Nori desktop settings change service";
      Service = {
        Type = "simple";
        ExecStart = "${package}/bin/nori-desktop-settings daemon";
        Restart = "on-failure";
        RestartSec = 2;
        RuntimeDirectory = "nori-desktop";
        RuntimeDirectoryMode = "0700";
        Environment = [
          "NORI_DESKTOP_SETTINGS_CONFIG_HOME=${config.xdg.configHome}/nori-desktop"
          "NORI_DESKTOP_SETTINGS_STATE_HOME=${config.xdg.stateHome}/nori-desktop"
          "NORI_DESKTOP_SETTINGS_DATA_DIR=${config.xdg.dataHome}/nori-desktop"
          "NORI_DESKTOP_SETTINGS_APPROVED_SOURCE=/etc/nori-desktop-settings/approved-source.json"
          "NORI_DESKTOP_SETTINGS_ACTIVE_METADATA=/etc/nori-desktop-settings/generation.json"
          "NORI_DESKTOP_SETTINGS_EVALUATOR=/run/current-system/sw/bin/nori-desktop-settings-preview"
          "NORI_DESKTOP_SETTINGS_BUILDER=/run/current-system/sw/bin/nori-desktop-settings-build"
          "NORI_DESKTOP_SETTINGS_ACTIVATOR=/run/current-system/sw/bin/nori-desktop-settings-activate"
          "NORI_DESKTOP_SETTINGS_SYSTEMCTL=${pkgs.systemd}/bin/systemctl"
          "NORI_DESKTOP_SETTINGS_HYPRCTL=${pkgs.hyprland}/bin/hyprctl"
          "NORI_DESKTOP_SETTINGS_PKEXEC=/run/wrappers/bin/pkexec"
          "NORI_DESKTOP_SETTINGS_SOCKET=%t/nori-desktop/settings-backend.sock"
          "NORI_DESKTOP_SETTINGS_RICE_COMMAND=${package}/bin/rice-saved-command"
          "NORI_DESKTOP_SETTINGS_SHELL=${lib.getExe pkgs.bash}"
          "RICE_VICINAE_BIN=${lib.getExe pkgs.vicinae}"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
    systemd.user.services.nori-desktop-config-ingress = {
      Unit = {
        Description = "Nori desktop settings credential-checked Unix ingress";
        Requires = [ "nori-desktop-config.service" ];
        After = [ "nori-desktop-config.service" ];
        PartOf = [ "nori-desktop-config.service" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${settingsIngress}/bin/nori-desktop-settings-ingress";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
