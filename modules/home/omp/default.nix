{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.omp;
  soul = builtins.readFile ../agent-soul/SOUL.md;
  ompUnwrapped = pkgs.callPackage ./package.nix { };
  omp =
    if cfg.exaApiKeyFile == null then
      ompUnwrapped
    else
      pkgs.writeShellApplication {
        name = "omp";
        text = ''
          secret_file=${lib.escapeShellArg cfg.exaApiKeyFile}
          if [[ ! -r "$secret_file" ]]; then
            printf 'omp: Exa API key file is not readable: %s\n' "$secret_file" >&2
            exit 1
          fi

          EXA_API_KEY="$(<"$secret_file")"
          if [[ -z "$EXA_API_KEY" ]]; then
            printf 'omp: Exa API key file is empty: %s\n' "$secret_file" >&2
            exit 1
          fi
          export EXA_API_KEY

          exec ${ompUnwrapped}/bin/omp "$@"
        '';
      };
in
{
  options.nori.omp.exaApiKeyFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = ''
      Raw SOPS secret file whose contents become EXA_API_KEY only in the OMP
      process. Null keeps the unwrapped OMP package for hosts without Exa.
    '';
  };

  config = {
    home.packages = [
      omp
      pkgs.vscode-js-debug
    ];

    # OMP's built-in DAP tool discovers vscode-js-debug through this supported
    # override. The Nix store path keeps the adapter version reproducible.
    home.sessionVariables.JS_DEBUG_DAP_SERVER = "${pkgs.vscode-js-debug}/lib/node_modules/js-debug/dist/src/dapDebugServer.js";

    # OMP writes setup and interactive configuration back to config.yml. Keep
    # the declared baseline in Nix, but materialize it as a regular writable
    # file instead of a read-only store symlink. Each activation deliberately
    # restores the declared baseline; runtime changes remain ephemeral until
    # promoted back into this module.
    home.activation.ompConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f ${config.home.homeDirectory}/.omp/agent/config.yml
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 ${./config.yml} ${config.home.homeDirectory}/.omp/agent/config.yml
    '';

    home.file = {
      # Shared user-wide preferences precede OMP-specific operator policy.
      ".omp/agent/AGENTS.md".text = soul + "\n" + builtins.readFile ./AGENTS.md;
      ".omp/agent/RULES.md".source = ./RULES.md;

      # Keep Herdr's lifecycle reporter pinned to the same revision as its CLI.
      ".omp/agent/extensions/herdr-omp-agent-state.ts".source =
        "${inputs.herdr}/src/integration/assets/omp/herdr-agent-state.ts";
    }
    // lib.optionalAttrs config.nori.agentNotify.enable {
      # Phone attention for settled turns outside Herdr, plus settled-turn
      # notifications from Herdr project panes. Herdr keeps its native handling
      # for approval and question events.
      ".omp/agent/extensions/agent-notify.ts".source = ./agent-notify.ts;
    };
  };
}
