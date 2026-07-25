{
  config,
  inputs,
  pkgs,
  ...
}:

let
  paguPackages = inputs.pagu.packages.${pkgs.stdenv.hostPlatform.system};

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

    /*
      `pagu` is the agent-launch surface (box + gate) and the only one. It was
      previously reachable only as an `agent-dispatch` runtimeInput, so
      `command -v pagu` failed for the operator and for every agent told to
      use it. Guidance that names a command the environment does not install
      is a latent lie; install it explicitly.

      `agent-dispatch` is gone — see
      docs/decisions/0008-agents-launch-directly-inside-pagu.md. Its last
      caller (modules/infra/backup/agent-fix.nix) now runs `pagu box`, and the
      read-only guard it enforced at runtime is a module assertion there.
    */
    paguPackages.pagu
  ];

  nori.agentNotify.enable = true;
  home.sessionPath = [ "$HOME/.deno/bin" ];

  /*
    Codex's global context. Keep this the same policy Claude reads in
    modules/home/claude-code/CLAUDE.md § "Delegation, sandboxing,
    observability" — two providers disagreeing about the launch boundary is
    the failure this file exists to prevent. Both point at the `pagu` and
    `herdr` skills for procedure rather than restating flags that drift.
  */
  home.file.".codex/AGENTS.md".text = ''
    # Delegation, sandboxing, observability

    Every agent on this workstation runs inside `pagu`, which owns the box
    (the enforcement point) and the outside gate. Because pagu is the
    enforceable outer boundary, a harness's own permission bypass inside a
    box is acceptable — the sandbox, not the harness prompt, is the security
    control. Sandbox authority is monotone: a child may narrow it, never
    widen it. A read-only parent stays read-only and a network-denied parent
    cannot launch a cloud child.

    Use `pagu <harness>` for a gated session and `pagu box -- COMMAND ...`
    for anything else. The bare `pagu-box` executable is compatibility-only.

    Observable work runs as one agent session per Herdr tab; the tab is the
    organizational unit. Keep delegation to at most two concurrent delegated
    workers and depth two (lead → worker → reviewer), and give each worker
    explicit file or worktree ownership.

    Read the `pagu` and `herdr` skills for procedure, and treat
    `pagu --help` / `herdr --help` as the authority for the installed
    version. Do not reconstruct flags from memory.
  '';
}
