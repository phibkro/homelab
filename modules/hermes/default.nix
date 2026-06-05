{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  hermes = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
  dashboardPort = 9119; # hermes dashboard default — matches modules/hermes/route.nix
in

# Hermes Agent — NousResearch's open-source coding agent with persistent
# memory (SQLite session DB + MEMORY.md + pluggable provider plugins).
#
# Why its own module (not lumped into modules/claude-code/)
# --------------------------------------------------------
# Claude Code and Hermes are parallel agents, not variants of each other.
# They have distinct config dirs (~/.claude vs ~/.hermes), distinct
# upstream release cadences, distinct security postures (Claude Code is
# the operator's trusted hands; Hermes is a sandboxed agent with NO
# GitHub credentials), and will have distinct egress policies once Claw
# Patrol is wired (Hermes through CP; Claude Code unconstrained).
# Keeping them separate lets each evolve without cross-module churn.
#
# Posture (load-bearing)
# ----------------------
# 1. **No GitHub credential** plumbed in. Hermes' Skills Hub stays
#    disabled (it expects GITHUB_TOKEN). Operator-driven claude-code
#    remains the only path to commit/push.
# 2. **Box-sandbox-ready** — `box --hermes` (pagu-box preset) binds
#    `~/.hermes` RW, hides everything else under $HOME. Inside the
#    homelab tree the `box` wrapper auto-injects --pwd-ro.
# 3. **State backed up** via the existing user-data restic repo + btrbk
#    snapshots (see nori.backups.hermes declaration below).
# 4. **Egress via Claw Patrol** (planned — task #28) — Hermes will get
#    HTTPS_PROXY pointed at the local CP gateway so it never sees raw
#    API keys and egress is hostname-allowlist.

{
  # Linux only — the upstream flake doesn't expose an x86_64-darwin
  # output (aarch64-darwin only, and we don't ship hermes on the Intel
  # Mac yet). Skip cleanly on the Mac side so this module is safe to
  # import from pc.nix unconditionally.
  home.packages = lib.optional isLinux hermes;

  # Persistent dashboard — `hermes dashboard` binds 127.0.0.1:9119 by
  # default. We DELIBERATELY keep the default localhost bind (NOT the
  # `--insecure` flag) because the dashboard exposes API keys; instead,
  # Caddy reverse-proxies hermes.nori.lan → 127.0.0.1:9119 with TLS via
  # the internal CA and the `operator` audience (tailnet membership IS
  # the auth perimeter). See ./route.nix on the NixOS side.
  #
  # `--skip-build` serves the pre-built dist that the nix derivation
  # already produced — npm isn't on the runtime PATH and we don't want
  # the service to rebuild on every start.
  #
  # `--no-open` suppresses xdg-open since this is a background daemon.
  systemd.user.services.hermes-dashboard = lib.mkIf isLinux {
    Unit = {
      Description = "Hermes Agent dashboard (web UI)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${hermes}/bin/hermes dashboard --port ${toString dashboardPort} --host 127.0.0.1 --no-open --skip-build";
      Restart = "on-failure";
      # Exponential backoff (systemd >=254): start at RestartSec, ramp
      # over RestartSteps to RestartMaxDelaySec. Avoids the tight
      # fail/restart/fail spin we'd otherwise hit if a transient
      # condition keeps the bind from succeeding (e.g. port held by a
      # stale `hermes dashboard` from an interactive run). Sequence:
      # 1s, ~2s, ~4s, ~8s, ~15s, ~30s, ~1min, ~2min, ~5min, ~5min…
      RestartSec = "1s";
      RestartSteps = 9;
      RestartMaxDelaySec = "5min";
      # Hermes reads ~/.hermes/{config.yaml,.env,sessions/,...} — the
      # user service already runs as $USER with $HOME set correctly,
      # nothing extra needed here.
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Backup coverage: ~/.hermes lives under /home/nori, already inside
  # the user-data restic repo (offsite, encrypted) + the root btrbk
  # subvolume's daily snapshots. .env (API keys) and sessions/ (the
  # persistent memory SQLite DB) are inside the restic-encrypted blob,
  # so plain-text exposure isn't a concern. No explicit `nori.backups.*`
  # declaration here — that guard is scoped to modules/server/ only.
}
