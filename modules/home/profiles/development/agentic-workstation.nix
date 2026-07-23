{
  config,
  inputs,
  pkgs,
  ...
}:

let
  paguPackages = inputs.pagu.packages.${pkgs.stdenv.hostPlatform.system};
  agent-dispatch = pkgs.writeShellApplication {
    name = "agent-dispatch";
    runtimeInputs = [
      paguPackages.pagu
      paguPackages.pagu-box
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = builtins.readFile ../../agent-dispatch.sh;
  };

  codex-notify = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      exec ${pkgs.codex}/bin/codex \
        -c notify='["${config.nori.agentNotify.command}","codex","stop"]' \
        "$@"
    '';
  };
in
/**
  Linux workstation realization of the agentic capability. Provider-neutral
  dispatch, sandbox dependencies, orchestration, and repository-wide Codex
  policy live here instead of leaking into the machine definition.
*/
{
  home.packages = [
    pkgs.deno
    pkgs.bubblewrap
    codex-notify
    inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    agent-dispatch
  ];

  nori.agentNotify.enable = true;
  home.sessionPath = [ "$HOME/.deno/bin" ];

  home.file.".codex/AGENTS.md".text = ''
    # Cross-provider delegation

    To delegate to Claude Code, use `agent-dispatch claude ...`; never
    invoke `claude` directly from an agent. The dispatcher permits two
    delegated workers and depth two (lead → worker → reviewer), then fails
    loud. Every child enters pagu-box `strict`; sandbox access may only
    narrow, never widen. A read-only parent stays read-only and a
    network-denied parent cannot launch a cloud child. In Herdr, use
    panes/worktrees so work remains observable.
  '';
}
