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
      bun build src/profile-validator.ts --compile --outfile dist/nori-desktop-settings-validate-profile
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 dist/nori-desktop-settings "$out/libexec/nori-desktop-settings"
      install -Dm755 dist/rice-saved-command "$out/libexec/rice-saved-command"
      install -Dm755 dist/nori-desktop-settings-validate-profile "$out/libexec/nori-desktop-settings-validate-profile"
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
      export NORI_DESKTOP_SETTINGS_SOCKET=/run/nori-desktop-settings/settings.sock
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
  runtimeAgent = pkgs.writeShellApplication {
    name = "nori-desktop-settings-runtime-agent";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      ${commonEnvironment}
      while true; do
        ${settingsCli}/bin/nori-desktop-settings state --json 2>/dev/null \
          | jq -r '.state.jobs[]? | select(.status == "awaiting_authorization") | [.id, .revision] | @tsv' \
          | while IFS="$(printf '\t')" read -r apply_id revision; do
              if ! /run/wrappers/bin/pkexec /run/current-system/sw/bin/nori-desktop-settings-activate \
                --operation org.nori.desktop-settings.activate \
                --apply-id "$apply_id" \
                --expected-revision "$revision"; then
                ${settingsCli}/bin/nori-desktop-settings authorization-failed \
                  --apply-id "$apply_id" --json >/dev/null || true
                continue
              fi
              if ! observed=$(${settingsCli}/bin/nori-desktop-settings observe-runtime --json 2>/dev/null); then
                observed='{"waybar":{"unit":"unknown","edge":"unavailable","reason":"runtime observation command failed"}}'
              fi
              ${settingsCli}/bin/nori-desktop-settings reconcile \
                --apply-id "$apply_id" --observed "$observed" --json >/dev/null || true
            done
        sleep 2
      done
    '';
  };
  profileValidator = pkgs.writeShellApplication {
    name = "nori-desktop-settings-validate-profile";
    text = ''
      exec ${serviceImplementation}/libexec/nori-desktop-settings-validate-profile "$@"
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
  options.nori.desktop.settingsService.profileValidator = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
    description = "Root-callable canonical validator for persisted desktop settings profiles.";
  };
  options.nori.desktop.settingsService.ingress = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
    description = "Credential-checking native ingress executable for the dedicated settings authority.";
  };

  config = {
    nori.desktop.settingsService.package = package;
    nori.desktop.settingsService.profileValidator = profileValidator;
    nori.desktop.settingsService.ingress = nativeIngress;
    systemd.user.services.nori-desktop-settings-runtime-agent = {
      Unit = {
        Description = "Nori desktop settings activation and Waybar reconciliation agent";
        After = [ config.wayland.systemd.target ];
        PartOf = [ config.wayland.systemd.target ];
      };
      Service = {
        ExecStart = "${runtimeAgent}/bin/nori-desktop-settings-runtime-agent";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ config.wayland.systemd.target ];
    };

    home.packages = [ package ];
  };
}
