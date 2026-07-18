{
  config,
  lib,
  pkgs,
  ...
}:

/**
  nori.agentFix — a failed unit dispatches a coding agent that proposes a
  fix as a PR. The control-flow companion to nori.alerts: the SAME failure
  event that alerts the operator (notify@) also, for allowlisted units,
  dispatches an agent to act on it.

      unit fails ─OnFailure→ ├─ notify@      (data: tell the operator)
                             └─ agent-fix@   (control: act on it)

  Autonomy is PR-ONLY, enforced by construction (see the flow below), and
  scoped by an explicit allowlist (`units`). Design + rationale:
  docs/specs/2026-07-18-agent-fix-on-failure-design.md.

  Flow (why the agent can never deploy or push a broken fix):

    1. survive the recovery window — transient failures self-heal (shared
       rationale with notify@); recovered → exit quiet.
    2. cooldown per unit — never re-dispatch the same unit within the
       window (loop-breaker; the fix-agent's own faults aren't allowlisted).
    3. disposable clone OUTSIDE the homelab prefix — agent-dispatch forces
       read-only under /srv/share/projects/homelab, and pagu-box binds only
       $PWD, so the clone needs a self-contained .git elsewhere.
    4. the BOXED agent (agent-dispatch, pagu-box strict) only EDITS files +
       writes an incident report. It has model access but NO push/deploy —
       the sandbox blocks gh/ssh/secrets. It cannot reach origin.
    5. the UN-BOXED orchestrator validates the result with `nix flake check`
       — the fix is proven green before a PR can exist; the agent's claim is
       never trusted. A failing check alerts and stops (nothing pushed).
    6. only then does the orchestrator push the branch + `gh pr create`.
       The AI never held the push credential; a deterministic relay did.

  The operator reviews + merges → deploy. The agent never rebuilds the
  live system.
*/

let
  cfg = config.nori.agentFix;
  window = config.nori.observability.ntfyNotify.recoveryWindowSeconds;

  # claude is headless via `-p`, codex via `exec` — agent-dispatch forwards
  # everything after `--` to the provider.
  providerInvoke = if cfg.provider == "codex" then ''exec "$prompt"'' else ''-p "$prompt"'';

  agentFix = pkgs.writeShellApplication {
    name = "agent-fix";
    # Deterministic tools the ORCHESTRATOR uses. The agent + its sandbox
    # (agent-dispatch, claude/codex) come from the unit's PATH; nori-alert
    # is referenced by its absolute nori.alerts.command below.
    runtimeInputs = [
      pkgs.git
      pkgs.gh
      pkgs.nix
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      UNIT="''${1:?agent-fix: unit name required}"
      repo=${lib.escapeShellArg cfg.repo}
      work_root=${lib.escapeShellArg cfg.workRoot}

      # 1. recovery window — most transient failures self-heal in the backoff.
      sleep ${toString window}
      if systemctl is-active "$UNIT" --quiet; then
        exit 0
      fi

      # 2. cooldown / loop-break (state in StateDirectory=/var/lib/agent-fix).
      state="/var/lib/agent-fix/$UNIT.last"
      now="$(date +%s)"
      if [ -f "$state" ]; then
        last="$(cat "$state" 2>/dev/null || echo 0)"
        if [ "$(( now - last ))" -lt ${toString cfg.cooldownSeconds} ]; then
          echo "agent-fix: $UNIT dispatched within cooldown; skipping" >&2
          exit 0
        fi
      fi
      printf '%s' "$now" > "$state"

      # 3. gather context.
      ts="$(date +%Y%m%d-%H%M%S)"
      journal="$(journalctl -u "$UNIT" -n 60 --no-pager 2>&1 | tail -c 4000 || true)"
      result="$(systemctl show "$UNIT" -p Result -p ExecMainStatus --no-pager 2>/dev/null | tr '\n' ' ' || true)"
      commits="$(git -C "$repo" log --oneline -10 2>/dev/null || true)"

      # 4. disposable clone OUTSIDE the homelab prefix, self-contained .git.
      work="$work_root/$UNIT-$ts"
      branch="fix/$UNIT-$ts"
      report="docs/reports/$ts-$UNIT-failure.md"
      rm -rf "$work"
      mkdir -p "$work_root"
      git clone --quiet --local --no-hardlinks "$repo" "$work"
      # Base the fix on the DEPLOYED main, never the operator's working HEAD
      # or uncommitted state. Re-point origin at the real remote (its push
      # URL — ssh — serves both this fetch and the later push) and branch
      # off origin/main; fall back to the clone HEAD only if main is
      # unreachable (fail loud, don't silently base on scratch).
      origin_url="$(git -C "$repo" remote get-url --push origin)"
      git -C "$work" remote set-url origin "$origin_url"
      if git -C "$work" fetch --quiet origin main; then
        git -C "$work" checkout -q -B "$branch" origin/main
      else
        echo "agent-fix: could not fetch origin/main; basing on $repo HEAD" >&2
        git -C "$work" checkout -q -b "$branch"
      fi
      git -C "$work" config user.name "homelab fix-agent"
      git -C "$work" config user.email "fix-agent@localhost"

      # 5. dispatch the boxed agent — it EDITS + writes the report only.
      prompt="$(cat <<PROMPT
      A systemd unit failed on $(uname -n): $UNIT ($result).

      Recent journal (tail):
      $journal

      Recent repo commits:
      $commits

      You are in a disposable clone of the homelab repo (branch $branch). Task:
      1. Diagnose the ROOT CAUSE of the $UNIT failure — read the relevant
         modules/ and any matching runbook under docs/runbooks/.
      2. Fix it by editing the repo. Prefer the smallest correct change.
      3. Write an incident report to $report: what failed, root cause, the
         fix, and what to watch. Terse and technical.
      Do NOT commit, push, rebuild, or deploy — a deterministic relay runs
      'nix flake check' on your change and opens a PR. If you cannot
      confidently fix it, still write $report with your diagnosis and change
      nothing else.
      PROMPT
      )"

      cd "$work"
      AGENT_DISPATCH_DEPTH=0 agent-dispatch ${cfg.provider} -- ${providerInvoke} || true

      # 6. relay — did the agent change anything?
      git -C "$work" add -A
      if git -C "$work" diff --cached --quiet; then
        ${config.nori.alerts.command} --audience agents --severity urgent --category fix-agent \
          --title "fix-agent: no change for $UNIT — needs you" \
          --body "Agent produced no edit. Context + journal left in $work."
        exit 0
      fi
      git -C "$work" commit -q -m "fix($UNIT): automated fix-agent proposal

      See $report."

      # 7. deterministic validation — prove it green BEFORE a PR exists.
      if ! nix flake check "$work" 2>&1 | tail -c 2000; then
        ${config.nori.alerts.command} --audience agents --severity urgent --category fix-agent \
          --title "fix-agent: proposed fix for $UNIT fails flake check" \
          --body "Branch $branch left at $work for review; nothing pushed."
        exit 0
      fi

      # 8. push + open the PR from the clone (origin was already repointed at
      #    the real remote in step 4); the operator's working clone is never
      #    touched.
      git -C "$work" push -q -u origin "$branch"
      pr="$(gh pr create --base main --head "$branch" \
        --title "fix($UNIT): automated fix-agent proposal" \
        --body-file "$work/$report" 2>&1 | tail -1 || true)"

      ${config.nori.alerts.command} --audience agents --severity warning --category fix-agent \
        --title "fix-agent: PR opened for $UNIT" \
        --body "$pr"
    '';
  };
in
{
  options.nori.agentFix = {
    enable = lib.mkEnableOption "auto-dispatch a coding agent to fix + PR a failed unit (PR-only)";

    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "restic-check-weekly"
        "btrbk-media"
      ];
      description = ''
        Allowlist of systemd unit names to wire `OnFailure → agent-fix@`
        onto (in addition to their existing notify@). Default-deny: empty
        means the template is deployed but nothing triggers it — arm it by
        listing specific units after a manual dry run
        (`systemctl start agent-fix@<unit>.service`).
      '';
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "/srv/share/projects/homelab";
      description = ''
        Clone with a GitHub origin + push auth. The fix-agent clones from
        here into an isolated worktree; the relay derives origin's push URL
        from it and pushes the fix branch. The operator's working tree here
        is never checked out or disturbed.
      '';
    };

    workRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/nori/agent-fix";
      description = ''
        Where fix clones live. MUST be outside `repo`'s path — agent-dispatch
        forces read-only whenever $PWD is under the homelab prefix.
      '';
    };

    provider = lib.mkOption {
      type = lib.types.enum [
        "claude"
        "codex"
      ];
      default = "claude";
      description = "Which harness the fix-agent runs (v1: fixed; usage-based routing is deferred — see the spec).";
    };

    cooldownSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 21600; # 6h
      description = "Minimum seconds between dispatches for the same unit — the loop-breaker.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "nori";
      description = "Operator user the orchestrator + relay run as (needs the agent creds, gh auth, ssh push key).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mkMerge (
      [
        {
          "agent-fix@" = {
            description = "Dispatch a coding agent to fix + PR failed unit %i";
            # Deliberately unhardened: the orchestrator drives the operator's
            # own toolchain (agent-dispatch, git, gh, nix) with their creds.
            # The SAFETY boundary is elsewhere — the dispatched agent runs in
            # pagu-box strict (no push/deploy), and PR-only means the operator
            # merges. A raw template like notify@, not a nori.services entry.
            serviceConfig = {
              Type = "oneshot";
              User = cfg.user;
              Environment = [
                "HOME=/home/${cfg.user}"
                "PATH=/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin:/run/wrappers/bin"
              ];
              StateDirectory = "agent-fix";
              # recovery window + agent runtime + flake check headroom.
              TimeoutStartSec = "${toString (window + 2400)}s";
              ExecStart = "${agentFix}/bin/agent-fix %i";
            };
          };
        }
      ]
      ++ map (u: {
        "${u}".unitConfig.OnFailure = [ "agent-fix@${u}.service" ];
      }) cfg.units
    );
  };
}
