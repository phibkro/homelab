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

  /*
    projects-tier: the /srv/share/projects OMP extension package — the Effect
    skill tier (skills/), its profiles (agents/), and the repository
    instruction-chain hook (index.ts). OMP discovers skills/ and agents/ from
    the `extensions:` entry in the policy overlay below and runs index.ts in
    every session and task subagent, whatever its working directory.
  */
  projectsTier = builtins.path {
    path = ../projects-tier;
    name = "omp-projects-tier";
  };

  /*
    Settings ownership. ~/.omp/agent/config.yml belongs to the operator: OMP's
    /settings and `omp config` write it, Nix never touches it, and btrbk and
    restic `user-data` protect it with the rest of /home. Nix owns only values
    derived from this repository, delivered as a read-only overlay through
    PI_CONFIG_FILES. Overlays outrank the global file and OMP never writes
    them, so these keys cannot drift and `/settings` changes to them do not
    persist.
  */
  policyOverlay = pkgs.writeText "omp-policy.yml" ''
    extensions:
      - ${projectsTier}
  '';

  ompUnwrapped = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
  omp = pkgs.writeShellApplication {
    name = "omp";
    text = ''
      overlay=${policyOverlay}
      case ":''${PI_CONFIG_FILES:-}:" in
        *":$overlay:"*) ;;
        *) export PI_CONFIG_FILES="''${PI_CONFIG_FILES:+$PI_CONFIG_FILES:}$overlay" ;;
      esac
    ''
    + lib.optionalString (cfg.exaApiKeyFile != null) ''

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
    ''
    + ''

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
      process. Null launches OMP without Exa.
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
