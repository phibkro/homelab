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
  imports = [ ../../saturation-alert.nix ];

  home.packages = [
    pkgs.deno
    pkgs.bubblewrap
    pkgs.t3code
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
  nori.omp.exaApiKeyFile = "/run/secrets/exa-api-key";
  nori.saturationAlert.enable = true;
  home.sessionPath = [ "$HOME/.deno/bin" ];

  /*
    Codex's global operator charter. Keep it concise and cross-project:
    repository semantics and live state belong in repository AGENTS.md files
    and durable handoffs, not in this always-loaded context.
  */
  home.file.".codex/AGENTS.md".text = ''
    # Operator-wide engineering charter

    ## Operating policy

    - Treat handoffs, plans, dashboards, generated views, and agent reports as
      evidence, not authority. Independently verify live repository, process,
      session, test, and provider state before relying on it.
    - Preserve dirty user-owned work. Clean up completed or abandoned agent
      sessions, tabs, processes, and worktrees after preserving durable
      evidence; remove only worktrees proven clean and integrated or explicitly
      disposable.
    - Keep development product-oriented. Orchestration, dashboards,
      scaffolding, and status prose must not substitute for executable user- or
      developer-facing capability.
    - Never equate proof, static analysis, model checking, testing,
      benchmarking, runtime validation, human assertion, or assumption. State
      the evidence that exists, its scope, unsupported claims, and transitive
      assumptions.
    - Require appropriate operator authority for external or destructive
      effects, including publishing, filing upstream issues, remote PR
      mutation, deployment, provider or DNS changes, credentials, and material
      deletion. Draft first when authority is unclear.
    - Give shared mutable resources explicit ownership. Prevent RAW, WAR, and
      WAW races with isolated instances, actors, locks, transactions, or
      serialized custody.
    - Report checks that were not run or unavailable. Never infer success from
      related checks or stale evidence.
    - Prefer direct evidence about resource consumers over aggregate pressure
      signals. Attribute expensive work to processes, cgroups, devices,
      sessions, and owners before throttling unrelated development.

    ## Lazy senior engineer posture

    - Search the repository and installed tooling for an existing command,
      scaffold, generator, library, or established pattern before hand-writing
      infrastructure.
    - Reuse or adapt license-compatible upstream code and techniques with source
      and license provenance. Never let copied code silently define semantics.
    - Automate deterministic, bounded, repeatable work when the automation is
      cheaper to own than repeated manual execution.
    - Stop automating when it becomes an unbounded side quest; implement the
      smallest direct solution that satisfies the frozen contract.
    - Report which scaffold, command, dependency, or prior art was evaluated,
      what was reused, and why relevant established options were rejected.

    ## Delegation and model routing

    - Use native subagents for GPT-family work by default and Herdr for
      Anthropic model lanes by default. Follow an explicit operator request to
      use a different harness for a particular lane.
    - Never claim a specific model or reasoning effort unless the active
      harness exposes or independently verifies it.
    - Freeze a bounded contract before delegated implementation. Give writers
      isolated ownership, executable acceptance gates, forbidden paths,
      assumptions, expected deliverables, and a cleanup condition.
    - Model output is advisory or contributory evidence. The integrating lead
      owns semantic decisions, exact-head verification, independent review,
      and acceptance.

    ## Preferred default technology

    - Start applicable new projects with TypeScript 7, Bun, Effect v4, Oxfmt,
      Oxlint, the Oxlint Effect plugin, and Alchemy v2 for infrastructure.
    - Treat this as a preferred default, not an unconditional mandate. Record
      the technical reason when a project deliberately diverges.
    - Python is acceptable for disposable one-off investigation, but not as
      committed project source or scripts.
  '';
}
