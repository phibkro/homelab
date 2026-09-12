{
  config,
  pkgs,
  lib,
  ...
}:
let
  cleanNodeSource =
    src:
    lib.cleanSourceWith {
      inherit src;
      filter =
        path: _type:
        let
          name = builtins.baseNameOf path;
        in
        name != "node_modules" && name != "dist";
    };
  savedCommandSource = cleanNodeSource ./saved-command;
  savedCommandImpl = pkgs.buildNpmPackage {
    pname = "rice-saved-command-impl";
    version = "0.1.0";
    src = savedCommandSource;
    npmDeps = pkgs.importNpmLock { npmRoot = savedCommandSource; };
    npmConfigHook = pkgs.importNpmLock.npmConfigHook;
    nativeBuildInputs = [ pkgs.bun ];
    buildPhase = ''
      runHook preBuild
      bun run build
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 dist/rice-saved-command "$out/bin/rice-saved-command"
      runHook postInstall
    '';
  };
  savedCommand = pkgs.writeShellApplication {
    name = "rice-saved-command";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      runner=$(readlink -f "$0")
      export RICE_SAVED_COMMAND_BIN="$runner"
      export RICE_SAVED_COMMAND_SHELL=${lib.escapeShellArg (lib.getExe pkgs.bash)}
      export RICE_VICINAE_BIN=${lib.escapeShellArg (lib.getExe pkgs.vicinae)}

      case ''${1-} in
        create|sync)
          config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
          lock_dir="$config_home/nori-desktop"
          mkdir -p "$lock_dir"
          exec flock --exclusive --timeout 30 "$lock_dir/saved-commands.lock" \
            ${savedCommandImpl}/bin/rice-saved-command "$@"
          ;;
        *)
          exec ${savedCommandImpl}/bin/rice-saved-command "$@"
          ;;
      esac
    '';
  };
  extensionSource = cleanNodeSource ./extension;
  noriDesktopExtension = config.lib.vicinae.mkExtension {
    name = "nori-desktop";
    src = extensionSource;
  };
  actions = lib.filterAttrs (_: action: action.palette) config.nori.desktop.actions;
  dispatcher = lib.getExe config.nori.desktop.actionDispatcher;
  singleLine =
    field: value:
    assert lib.assertMsg (builtins.match "[^\n\r]*" value != null) "desktop action ${field} must fit on one line";
    value;
  scriptName = id: "nori-rice-${lib.replaceStrings [ "." ] [ "_" ] id}";
  actionScript =
    id: action:
    pkgs.writeShellScript (scriptName id) ''
      # @vicinae.schemaVersion 1
      # @vicinae.title ${singleLine "label" action.label}
      # @vicinae.mode silent
      # @vicinae.description ${singleLine "description" action.description}
      # @vicinae.keywords ${builtins.toJSON ([ action.category ] ++ action.keywords)}

      exec ${dispatcher} ${lib.escapeShellArg id}
    '';
  actionScripts = lib.mapAttrs actionScript actions;
  actionScriptFiles = lib.mapAttrs' (
    id: source:
    lib.nameValuePair "vicinae/scripts/rice/${scriptName id}" {
      inherit source;
    }
  ) actionScripts;
  actionScriptsPackage = pkgs.linkFarm "nori-desktop-vicinae-scripts" (
    lib.mapAttrsToList (id: path: {
      name = scriptName id;
      inherit path;
    }) actionScripts
  );
  actionCatalog = pkgs.writeText "nori-desktop-actions.json" (
    builtins.toJSON (
      lib.mapAttrs (
        id: action: {
          inherit (action)
            category
            description
            directBinding
            effect
            keywords
            label
            palette
            ;
          script = "rice/${scriptName id}";
        }
      ) actions
    )
  );
  vicinaeLauncherLiveTest = pkgs.writeShellApplication {
    name = "vicinae-launcher-live-test";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.sway
    ];
    text = ''
      export RICE_VICINAE_ACTION_SCRIPTS=${lib.escapeShellArg actionScriptsPackage}
      export RICE_VICINAE_EXTENSION=${lib.escapeShellArg noriDesktopExtension}
      export RICE_SAVED_COMMAND_BIN=${lib.escapeShellArg (lib.getExe savedCommand)}
      export RICE_VICINAE_BIN=${lib.escapeShellArg (lib.getExe pkgs.vicinae)}
      export RICE_VICINAE_TEST_SHELL=${lib.escapeShellArg (lib.getExe pkgs.bash)}
      ${builtins.readFile ./vicinae-launcher-live-test.sh}
    '';
  };
in
{
  programs.vicinae = {
    enable = true;
    enableFirefoxIntegration = false;
    systemd = {
      enable = true;
      target = config.wayland.systemd.target;
    };
    extensions = [ noriDesktopExtension ];
    settings.launcher_window.layer_shell.enabled = true;
  };

  home = {
    packages = [
      savedCommand
      vicinaeLauncherLiveTest
    ];
    activation.riceSavedCommands = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run --silence ${lib.getExe savedCommand} sync
    '';
  };

  systemd.user.services.vicinae.Service.Environment = [
    "RICE_SAVED_COMMAND_BIN=${lib.getExe savedCommand}"
  ];

  xdg.dataFile = actionScriptFiles // {
    "nori-desktop/actions.json".source = actionCatalog;
  };
}
