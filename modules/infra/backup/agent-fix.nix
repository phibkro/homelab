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
    3. disposable clone OUTSIDE the homelab prefix — the box binds only $PWD
       read-write, so the clone needs a self-contained .git elsewhere. An
       assertion below enforces workRoot is not under repo.
    4. the BOXED agent (`pagu-box --profile=strict`) only EDITS files +
       writes an incident report. It has model access but NO push/deploy —
       the sandbox blocks gh/ssh/secrets. It cannot reach origin.
    5. the UN-BOXED orchestrator ALWAYS pushes the branch + `gh pr create` —
       a fire is a real failure and a started thread to fix it, whether or not
       the agent nailed it. The AI never held the push credential; a
       deterministic relay did. `nix flake check` decides draft (fails) vs
       ready (passes), never whether the PR exists; if the agent produced
       nothing, a stub incident report is committed so the thread still opens.
    6. the PR body carries a handle to RESUME the agent's conversation
       (`claude --resume <id>`, un-boxed) + the journal command, so the
       operator can pick up the thread and give feedback.

  The operator reviews + steers + merges → deploy. The agent never rebuilds
  the live system. Runbook: docs/runbooks/agent-fix-on-failure.md.
*/

let
  cfg = config.nori.agentFix;
  window = config.nori.observability.ntfyNotify.recoveryWindowSeconds;

  # claude is headless via `-p`, codex via `exec`. A headless one-shot never
  # resumes and has no operator to answer a request, so it takes the ungated
  # box, which forwards everything after `--` to the provider unchanged.
  providerInvoke = if cfg.provider == "codex" then ''exec "$prompt"'' else ''-p "$prompt"'';

  agentFix = pkgs.writeShellApplication {
    name = "agent-fix";
    # Deterministic tools the ORCHESTRATOR uses. The agent + its sandbox
    # (pagu-box, claude/codex) come from the unit's PATH; nori-alert
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
      # `pagu-box`, not `pagu box`: the pinned pagu input predates the `box`
      # subcommand dispatch, so `pagu box` would be parsed as a harness name
      # and fail. This is the exact executable agent-dispatch invoked, so the
      # migration changes the caller without changing the enforcement. Switch
      # to `pagu box` when the flake input is bumped past that dispatch.
      pagu-box --profile=strict --${cfg.provider} -- ${cfg.provider} ${providerInvoke} || true

      # 6. relay — ALWAYS open a PR. A fire means a real unit failure AND a
      #    started thread to fix it, whether or not the agent nailed the fix:
      #    the PR is the durable indicator + carries the diagnosis, the (partial)
      #    fix, and a handle to RESUME the agent's conversation. Validation only
      #    decides draft vs ready — it never suppresses the PR.
      git -C "$work" add -A
      if git -C "$work" diff --cached --quiet; then
        # No edit and no report (auth failure / crash / early give-up). Stub one
        # so the thread still exists.
        mkdir -p "$work/$(dirname "$report")"
        {
          echo "---"
          echo "summary: fix-agent produced no output for $UNIT — manual thread required"
          echo "---"
          echo
          echo "# $UNIT failed — fix-agent could not act"
          echo
          echo "The dispatched agent produced no edit and no report (likely an auth"
          echo "failure, a crash, or an early give-up). Pick up the thread manually"
          echo "using the resume instructions in the PR body."
        } > "$work/$report"
        git -C "$work" add -A
      fi
      git -C "$work" commit -q -m "fix($UNIT): fix-agent proposal — see incident report"

      # 7. validate — INFORMATIONAL (draft vs ready), no longer a gate on the PR.
      if nix flake check "$work" >/dev/null 2>&1; then
        check_status="passes nix flake check"
        draft_flag=()
      else
        check_status="FAILS nix flake check — needs a human"
        draft_flag=(--draft)
      fi

      # 8. resume handle — the boxed agent's session persisted to the real
      #    ~/.claude (bound by the `--claude` preset). Claude keys
      #    sessions by cwd, slugged '/' -> '-'; one .jsonl per run.
      slug="$(printf '%s' "$work" | sed 's#/#-#g')"
      session_id=""
      for f in "$HOME/.claude/projects/$slug"/*.jsonl; do
        [ -e "$f" ] || continue
        session_id="$(basename "$f" .jsonl)"
      done
      [ -n "$session_id" ] || session_id="(none — see the journal)"

      # 9. push + open the PR (draft when it doesn't pass flake check). origin
      #    was repointed at the real remote in step 4.
      git -C "$work" push -q -u origin "$branch"
      pr="$(gh pr create "''${draft_flag[@]}" --base main --head "$branch" \
        --title "fix($UNIT): fix-agent proposal" \
        --body "$(cat <<PRBODY
      Automated fix-agent proposal for a failed unit — opened whether or not the
      fix is complete, because the failure itself needs a thread.

      Unit:       $UNIT on $(uname -n) ($result)
      Validation: $check_status
      Provider:   ${cfg.provider}

      ## Pick up the thread

      Resume the agent's conversation (runs un-boxed, as you) to review its
      reasoning and give feedback:

          cd $work
          claude --resume $session_id

      Full run log:

          journalctl -u agent-fix@$UNIT.service

      Diagnosis + fix are in this PR's diff (incident report: $report).
      Runbook: docs/runbooks/agent-fix-on-failure.md
      PRBODY
      )" 2>&1 | tail -1 || true)"

      ${config.nori.alerts.command} --audience agents --severity warning --category fix-agent \
        --title "fix-agent: PR for $UNIT — $check_status" \
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
        Where fix clones live. MUST be outside `repo`'s path; the boxed agent
        gets $PWD read-write. Enforced by an assertion.
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
    /*
      `agent-dispatch` used to force `--pwd-ro` whenever $PWD sat under the
      homelab prefix, which is what kept a mis-set workRoot from handing the
      boxed agent write access to the canonical checkout. That script is gone,
      and the box has no equivalent implicit rule — correctly, since a
      launcher should not infer authority from a path.

      The guard becomes structural instead, and stronger: this fails at
      evaluation rather than at incident time, when nobody is watching.
    */
    assertions = [
      {
        assertion = !(lib.hasPrefix "${cfg.repo}/" "${cfg.workRoot}/");
        message = ''
          nori.agentFix.workRoot (${cfg.workRoot}) must not be inside
          nori.agentFix.repo (${cfg.repo}). The boxed agent gets $PWD bound
          read-write, so a clone beneath the canonical checkout would give it
          write access to the source of truth it is only meant to read.
        '';
      }
    ];

    systemd.services = lib.mkMerge (
      [
        {
          "agent-fix@" = {
            description = "Dispatch a coding agent to fix + PR failed unit %i";
            # Deliberately unhardened: the orchestrator drives the operator's
            # own toolchain (pagu, git, gh, nix) with their creds.
            # The SAFETY boundary is elsewhere — the dispatched agent runs in
            # `pagu-box --profile=strict` (no push/deploy), and PR-only means the operator
            # merges. A raw template like notify@, not an inventory workload.
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
