{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  omp = pkgs.callPackage ./package.nix { };
in
{
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
    ".omp/agent/AGENTS.md".source = ./AGENTS.md;
    ".omp/agent/RULES.md".source = ./RULES.md;

    # Keep Herdr's lifecycle reporter pinned to the same revision as its CLI.
    ".omp/agent/extensions/herdr-omp-agent-state.ts".source =
      "${inputs.herdr}/src/integration/assets/omp/herdr-agent-state.ts";
  }
  // lib.optionalAttrs config.nori.agentNotify.enable {
    # Phone attention outside Herdr: settled turn, approval, or question.
    # agent-notify itself suppresses duplicates when HERDR_ENV=1 because the
    # Herdr manager owns operator attention for managed tabs.
    ".omp/agent/extensions/agent-notify.ts".source = ./agent-notify.ts;
  };
}
