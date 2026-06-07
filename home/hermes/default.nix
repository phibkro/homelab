{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  # `.messaging` pre-bundles discord.py + python-telegram-bot + slack-sdk.
  # `.default` would lazy-pip-install these at runtime → writes into the
  # read-only /nix/store → infinite "Lazy-installing discord.py" loop in
  # ~/.hermes/logs/agent.log every 10s. Upstream's packages.nix names the
  # constraint. Swap to `.full` if external memory (Honcho/Mem0/
  # Hindsight) or voice/edge-tts become wanted.
  hermes = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
  dashboardPort = 9119; # hermes dashboard default — matches modules/services/hermes.nix
in

# Hermes Agent — NousResearch's open-source coding agent with persistent
# memory (SQLite session DB + MEMORY.md + pluggable providers).
#
# Separate from home/claude-code/ because Claude Code and Hermes are
# parallel agents with distinct config dirs, release cadences, and
# security postures — and will have distinct egress policies once Claw
# Patrol is wired (Hermes through CP; Claude Code unconstrained).
#
# Posture (load-bearing):
# 1. **No GitHub credential** plumbed in. Skills Hub stays disabled (it
#    expects GITHUB_TOKEN). Operator-driven claude-code is the only
#    commit/push path.
# 2. **Box-sandbox-ready** — `box --hermes` binds ~/.hermes RW, hides
#    the rest of $HOME. Inside the homelab tree `box` auto-injects
#    --pwd-ro.
# 3. **State backed up** via the user-data restic repo + btrbk snapshots
#    on the root subvol.
# 4. **Egress via Claw Patrol** (planned — task #28): HTTPS_PROXY → local
#    CP gateway, hostname-allowlist, no raw API keys to Hermes.

{
  # Linux-only: upstream doesn't ship x86_64-darwin (aarch64-darwin
  # only, not wired here). Safe to import from pc.nix unconditionally.
  #
  # python313 on PATH so hermes's `terminal` tool can exec `python`
  # directly. NO pip binary — global pip installs would pollute
  # ~/.local site-packages with untracked state. For non-stdlib needs,
  # use `python313.withPackages` here and rebuild.
  home.packages = lib.optional isLinux hermes
    ++ lib.optional isLinux pkgs.python313;

  # Persistent dashboard. Deliberately localhost-bound — the dashboard
  # exposes API keys, so tailnet exposure goes through Caddy at
  # hermes.nori.lan with `operator` audience (tailnet IS the auth
  # perimeter). NOT `--insecure`. `--skip-build` serves the nix-built
  # dist (no npm on PATH); `--no-open` suppresses xdg-open for a daemon.
  systemd.user.services.hermes-dashboard = lib.mkIf isLinux {
    Unit = {
      Description = "Hermes Agent dashboard (web UI)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${hermes}/bin/hermes dashboard --port ${toString dashboardPort} --host 127.0.0.1 --no-open --skip-build";
      Restart = "on-failure";
      # modules/effects/restart-policy.nix covers systemd.services but
      # NOT systemd.user.services — backoff is declared here so a stale
      # `hermes dashboard` holding the port doesn't trigger a tight spin.
      RestartSec = "1s";
      RestartSteps = 9;
      RestartMaxDelaySec = "5min";
      # Belt-and-suspenders with "no pip on PATH": blocks `python -m pip
      # install` from polluting ~/.local outside an active venv.
      Environment = [ "PIP_REQUIRE_VIRTUALENV=true" ];
    };
    Install.WantedBy = [ "default.target" ];
  };

  # No explicit `nori.backups.*` here — that guard is scoped to
  # modules/server/. ~/.hermes is covered by the user-data restic repo
  # (encrypts .env + sessions/) + root btrbk snapshots.
}
