{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.nori.saturationAlert;
  herdrPkg = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
/**
  saturation-alert — per-user memory-pressure watchdog with per-agent
  checkpoint remediation.

  WHY A USER UNIT: this module merges two independently-built monitors.
  The system-unit predecessor (git history: modules/infra/observability/
  saturation-alert/) covered host-wide PSI + a task-count leak canary but
  could only alert — it had no way to reach into the agent fleet.
  /tmp/clamor-manager-monitor.sh (a bespoke, hand-run script, one operator
  session, 2026-07-27) proved the higher-value move: on checkpoint
  pressure, PROMPT running agents to finish their atomic edit and commit
  before oomd picks a victim — alerting after the fact would not have
  saved the three panes oomd killed that day. `herdr agent prompt` needs
  the user's session socket, unreachable from a root service without
  contortions, and the thing monitored IS the user's agent fleet — so the
  whole watchdog moved to home-manager. `nori-alert` (a system binary,
  environment.systemPackages in ../infra/observability/alerts.nix) stays
  reachable from user context the same way agent-notify and
  user-restart-policy's user-notify@ already resolve it: PATH first, the
  system profile as fallback.

  SIGNALS (host-wide unless noted):
  - memoryPressureFull  — /proc/pressure/memory "full" avg300. Warn/critical
    tiering: critical is the ORIGINAL system-unit's incident-calibrated
    number, unchanged; warn is Half B's earlier read of the SAME file.
  - taskCeiling         — /proc/loadavg task count. The leak canary,
    deliberately single-tier: it has no Half B equivalent and no warn
    reading was ever calibrated for it.
  - swapUsed            — swap %, absent from the system-unit predecessor
    entirely; Half B's numbers.
  - pressureSome        — /proc/pressure/memory "some" avg10 (host-wide)
    AND, per watched agent pane, cgroup memory.pressure "some" avg10 (the
    per-agent attribution Half B's `scope_pressure_for_pane` introduced).
    ONE threshold pair for both granularities — Half B used the same
    numbers for its system_some and scope_some checks, so this keeps one
    calibrated fact instead of two copies that could drift apart.

  DELIBERATELY DROPPED from Half B: the absolute mem_available_kib
  warn/critical thresholds. They measure the same exhaustion the "full"
  and "some" PSI percentages already measure, just in KiB instead of a
  normalized stall percentage, and swap-used% already covers the
  memory-plus-swap tail Half B was reaching for with them. A fourth
  near-duplicate host-wide signal wasn't worth the option surface.

  DISCOVERY, NOT HARDCODING: Half B hardcoded "clamor-manager" and two
  worker names — a bespoke instrument for one operator session, not
  infrastructure. This queries `herdr agent list` once per run and reuses
  that same snapshot both for per-agent cgroup attribution and for
  choosing who gets a checkpoint prompt. Unreachable herdr (socket down,
  no session running) degrades to host-wide alerting only — the fleet not
  running must never fail this unit.

  COOLDOWN + RECOVERY: state (last severity, last alert epoch) persists
  across runs in $STATE_DIRECTORY, because a `Type=oneshot` triggered by a
  timer starts a fresh process every time — Half B's in-process bash
  variables would not have survived that shape. Re-alerting on every 5min
  tick while degraded (the system-unit predecessor's behaviour) is exactly
  what the cooldown + severity-change gate below replaces.

  CHECKPOINT-PROMPT GATE: prompting every discovered agent costs each of
  them a turn and context, precisely when the box is struggling — a
  flapping threshold must not turn into a prompt storm. Gated on ALL of:
  critical tier only (never warn), the same cooldown/severity-change test
  that gates the ntfy alert (so a flap that doesn't re-alert doesn't
  re-prompt either), and `checkpointPrompt.enable` as a hard operator
  escape hatch.
*/
{
  options.nori.saturationAlert = {
    enable = lib.mkEnableOption "per-user memory-pressure watchdog with per-agent checkpoint remediation";

    memoryPressureFull = {
      warnPct = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 2;
        description = ''
          Early warning on `/proc/pressure/memory` "full" avg300 (every
          non-idle task stalled on memory). From clamor-manager-monitor.sh's
          `psi_full_warn`, itself "deliberately below oomd's 60%/30s scope
          pressure, 50% user-slice pressure, and 90% swap-used boundaries" —
          minutes of runway before the criticalPct incident threshold below.
        '';
      };
      criticalPct = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 10;
        description = ''
          Unchanged from the system-unit predecessor. Measured 2026-07-26:
          27.34% while the box was unusable, 0.29% healthy. 10% sits clear
          of both, and a legitimate heavy build does not full-stall unless
          it is genuinely OOM-thrashing — worth waking someone for. Note
          this equals clamor-manager-monitor.sh's independently-set
          `psi_full_critical`: two monitors, built separately, converged on
          the same incident-calibrated number.
        '';
      };
    };

    taskCeiling = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4000;
      description = ''
        Alert when the kernel's total task count (`/proc/loadavg` field 4,
        after the slash) crosses this. The leak canary, and deliberately a
        SEPARATE signal from pressure: a process leak shows up here long
        before it costs enough memory to stall anything. Measured
        2026-07-26: 4749 tasks at the peak (898 of them V8 workers from 141
        leaked harnesses), ~3300 healthy with the full agent fleet running.
        Single-tier (critical only) — no warn reading was ever calibrated,
        and clamor-manager-monitor.sh has no equivalent signal.
      '';
    };

    swapUsed = {
      warnPct = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 70;
        description = ''
          From clamor-manager-monitor.sh's `swap_warn_percent`, carried
          unchanged: early warning ahead of oomd's 90% swap-used boundary.
          Absent from the system-unit predecessor entirely.
        '';
      };
      criticalPct = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 82;
        description = ''
          From clamor-manager-monitor.sh's `swap_critical_percent`, carried
          unchanged: still below oomd's 90% swap-used boundary by design.
        '';
      };
    };

    pressureSome = {
      warnPct = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 5;
        description = ''
          From clamor-manager-monitor.sh's `psi_some_warn`. Applied at TWO
          granularities with one number: host-wide `/proc/pressure/memory`
          "some" avg10, and per-watched-agent cgroup `memory.pressure` "some"
          avg10 (the per-agent attribution this module adds over the
          system-unit predecessor). Same threshold in Half B for both
          checks, so this stays one calibrated fact rather than two copies
          that could drift.
        '';
      };
      criticalPct = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 20;
        description = ''
          From clamor-manager-monitor.sh's `psi_some_critical`, applied at
          the same two granularities as warnPct above.
        '';
      };
    };

    /*
      Route by severity, because the two channels cost the operator very
      differently.

      The warn thresholds came from clamor-manager-monitor.sh, whose only
      output was `herdr notification show` — a desktop toast: free to glance
      at, free to ignore. Transplanting those numbers into a unit whose output
      is an ntfy push to a PHONE changes what they mean. Measured 2026-07-27:
      `full avg300` sat at 27%, 22% and 13% during routine `nix flake check`
      runs, and the merged unit fired a genuine warn at 2.54% caused by a
      `nix build`. On a machine where `just rebuild` is constant, a 2% warn
      tier pushed to the phone fires on ordinary work — which trains the
      operator to ignore the channel, the exact failure this module's own
      comments cite as the reason cpu PSI is not watched at all.

      So: warn is real and worth surfacing, but on the cheap channel. Only
      critical earns the phone.
    */
    desktopNotify = lib.mkEnableOption "show warn-tier breaches as a desktop notification" // {
      default = true;
    };

    phoneOnCriticalOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Send ntfy (phone) alerts only for the critical tier. Warn-tier
        breaches go to the desktop instead. Set false to push both, accepting
        that a heavy build will page you.

        Recovery notices follow the tier that raised them: a critical that
        clears notifies the phone, a warn that clears does not.
      '';
    };

    cooldownSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = ''
        From clamor-manager-monitor.sh's `alert_cooldown_seconds`. While a
        breach persists at the SAME severity, re-alert (and re-prompt, see
        checkpointPrompt) no more often than this. A severity change
        (warn → critical, or a drop to ok) always alerts immediately,
        cooldown or not.
      '';
    };

    checkpointPrompt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          On a critical-tier breach (never warn), gated by the same
          cooldown/severity-change test as the ntfy alert, prompt every
          agent `herdr agent list` currently reports to finish its current
          atomic edit and checkpoint. The highest-value behaviour
          clamor-manager-monitor.sh proved: on 2026-07-27 systemd-oomd
          killed three agent panes mid-work and the operator lost
          accumulated context; alerting would not have saved that,
          checkpointing would have. Escape hatch for an operator who wants
          alerting without the fleet being interrupted.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    /*
      gawk (PSI values are decimals) + jq (herdr agent list is JSON) +
      herdr itself, all explicit on Service.Environment's PATH rather than
      assumed ambient. home-manager's systemd.user.services has no NixOS-
      style `path` sugar, so this sets PATH directly. The system-unit
      predecessor died on first activation with `awk: command not found`
      because it copied `path = [ pkgs.coreutils ]` from disk-alert, which
      never needed awk — a unit's PATH is whatever it's given, not
      whatever the interactive shell that wrote the script happened to
      have.
    */
    systemd.user.services.saturation-alert = {
      Unit = {
        Description = "Check memory pressure, swap, task count, and per-agent cgroup pressure; alert + checkpoint the fleet if saturated";
        OnFailure = [ "user-notify@saturation-alert.service" ];
      };
      Service = {
        Type = "oneshot";
        StateDirectory = "saturation-alert";
        Environment = "PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.gawk
            pkgs.jq
            herdrPkg
          ]
        }:/run/current-system/sw/bin";
        ExecStart = pkgs.writeShellScript "saturation-alert-check" ''
          set -eu

          state_dir="''${STATE_DIRECTORY:-$HOME/.local/state/saturation-alert}"
          mkdir -p "$state_dir"
          state_file="$state_dir/state"

          last_severity="ok"
          last_alert_epoch=0
          if [ -r "$state_file" ]; then
            # shellcheck disable=SC1090
            . "$state_file"
          fi

          # psi_field <file> <some|full> <avg10|avg300>
          psi_field() {
            awk -v kind="$2" -v key="$3" '
              $1 == kind {
                for (i = 2; i <= NF; i++) {
                  if ($i ~ "^" key "=") {
                    split($i, kv, "=")
                    print kv[2]
                    exit
                  }
                }
              }
            ' "$1" 2>/dev/null || true
          }

          float_ge() { awk -v l="$1" -v r="$2" 'BEGIN { exit !(l + 0 >= r + 0) }'; }
          max_float() { awk -v l="$1" -v r="$2" 'BEGIN { print (l + 0 >= r + 0) ? l : r }'; }

          severity="ok"
          bump() {
            case "$1:$severity" in
              critical:*) severity="critical" ;;
              warn:ok) severity="warn" ;;
            esac
          }

          breach_lines=""
          add_breach() { breach_lines="$breach_lines

          $1"; }

          # --- host-wide memory pressure: full avg300 (the 2026-07-26 incident signal) ---
          mem_full="$(psi_field /proc/pressure/memory full avg300)"
          mem_full="''${mem_full:-0}"
          if float_ge "$mem_full" ${toString cfg.memoryPressureFull.criticalPct}; then
            bump critical
            add_breach "full-pressure CRITICAL: $mem_full% of the last 5min every task was stalled on memory (limit ${toString cfg.memoryPressureFull.criticalPct}%).
          Triage: ps -eLf --no-headers | wc -l ; ps -eo pid,pcpu,pmem,rss,etime,comm --sort=-rss | head -20 ; systemd-cgls --no-pager | head -40"
          elif float_ge "$mem_full" ${toString cfg.memoryPressureFull.warnPct}; then
            bump warn
            add_breach "full-pressure WARN: $mem_full% (limit ${toString cfg.memoryPressureFull.warnPct}%, early warning below the incident threshold)"
          fi

          # --- task-count leak canary ---
          tasks="$(cut -d' ' -f4 /proc/loadavg | cut -d/ -f2)"
          if [ "$tasks" -ge ${toString cfg.taskCeiling} ]; then
            bump critical
            add_breach "task-count CRITICAL: $tasks kernel tasks (limit ${toString cfg.taskCeiling}) — usually a process leak, not real work.
          Triage: ps -eLo comm --no-headers | sort | uniq -c | sort -rn | head ; ps -eo pid,ppid,etimes,comm --sort=etimes | head -20"
          fi

          # --- swap ---
          swap_total="$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)"
          swap_free="$(awk '/^SwapFree:/ { print $2 }' /proc/meminfo)"
          swap_pct=0
          if [ "$swap_total" -gt 0 ]; then
            swap_pct=$(( (swap_total - swap_free) * 100 / swap_total ))
          fi
          if [ "$swap_pct" -ge ${toString cfg.swapUsed.criticalPct} ]; then
            bump critical
            add_breach "swap-used CRITICAL: $swap_pct% (limit ${toString cfg.swapUsed.criticalPct}%)"
          elif [ "$swap_pct" -ge ${toString cfg.swapUsed.warnPct} ]; then
            bump warn
            add_breach "swap-used WARN: $swap_pct% (limit ${toString cfg.swapUsed.warnPct}%)"
          fi

          # --- host-wide "some" pressure (at least one task stalled) ---
          mem_some="$(psi_field /proc/pressure/memory some avg10)"
          mem_some="''${mem_some:-0}"
          if float_ge "$mem_some" ${toString cfg.pressureSome.criticalPct}; then
            bump critical
            add_breach "host-some-pressure CRITICAL: $mem_some% (limit ${toString cfg.pressureSome.criticalPct}%) over the last 10s."
          elif float_ge "$mem_some" ${toString cfg.pressureSome.warnPct}; then
            bump warn
            add_breach "host-some-pressure WARN: $mem_some% (limit ${toString cfg.pressureSome.warnPct}%)"
          fi

          # --- per-agent cgroup attribution: discover once, reuse for scope-pressure + checkpoint prompts ---
          agents_tsv=""
          if command -v herdr >/dev/null 2>&1; then
            agents_tsv="$(herdr agent list 2>/dev/null | jq -r '.result.agents[]? | [(.name // .pane_id), .pane_id] | @tsv' 2>/dev/null || true)"
          fi

          scope_crit="" scope_warn="" scope_max="0"
          if [ -n "$agents_tsv" ]; then
            while IFS=$'\t' read -r target pane; do
              [ -n "$pane" ] || continue
              safe_pane="''${pane//:/-}"
              pane_max="0"
              for f in /sys/fs/cgroup/user.slice/user-"$(id -u)".slice/user@"$(id -u)".service/herdr.slice/herdr-"$safe_pane"-*.scope/memory.pressure; do
                [ -r "$f" ] || continue
                v="$(psi_field "$f" some avg10)"
                pane_max="$(max_float "$pane_max" "''${v:-0}")"
              done
              scope_max="$(max_float "$scope_max" "$pane_max")"
              if float_ge "$pane_max" ${toString cfg.pressureSome.criticalPct}; then
                scope_crit="$scope_crit $target=$pane_max%"
              elif float_ge "$pane_max" ${toString cfg.pressureSome.warnPct}; then
                scope_warn="$scope_warn $target=$pane_max%"
              fi
            done <<< "$agents_tsv"
          fi

          if [ -n "$scope_crit" ]; then
            bump critical
            add_breach "agent-scope CRITICAL:$scope_crit (limit ${toString cfg.pressureSome.criticalPct}%) — a specific agent pane is thrashing, not just the host aggregate."
          elif [ -n "$scope_warn" ]; then
            bump warn
            add_breach "agent-scope WARN:$scope_warn (limit ${toString cfg.pressureSome.warnPct}%)"
          fi

          # --- decide whether to alert, honoring cooldown + severity-change ---
          now_epoch="$(date +%s)"
          summary="full_avg300=$mem_full% some_avg10=$mem_some% swap_used=$swap_pct% tasks=$tasks agent_scope_max_avg10=$scope_max%"

          should_alert=0
          if [ "$severity" != "ok" ]; then
            if [ "$severity" != "$last_severity" ] || [ $((now_epoch - last_alert_epoch)) -ge ${toString cfg.cooldownSeconds} ]; then
              should_alert=1
            fi
          fi

          nori_alert="$(command -v nori-alert || true)"
          if [ -z "$nori_alert" ] && [ -x /run/current-system/sw/bin/nori-alert ]; then
            nori_alert=/run/current-system/sw/bin/nori-alert
          fi

          if [ "$should_alert" -eq 1 ]; then
            # Route by tier. `phone` gates the ntfy push; warn stays on the
            # desktop so a routine `nix build` cannot page the operator.
            phone=1
            ${lib.optionalString cfg.phoneOnCriticalOnly ''
              [ "$severity" = "critical" ] || phone=0
            ''}

            ${lib.optionalString cfg.desktopNotify ''
              if command -v herdr >/dev/null 2>&1; then
                herdr notification show "saturation $severity" \
                  --body "$summary" >/dev/null 2>&1 || true
              fi
            ''}

            if [ "$phone" -eq 1 ] && [ -n "$nori_alert" ]; then
              sev_word="warning"
              [ "$severity" = "critical" ] && sev_word="urgent"
              "$nori_alert" \
                --audience operator \
                --severity "$sev_word" \
                --category saturation \
                --title "$(uname -n): saturation $severity ($summary)" \
                --body "$(uname -n) is saturation-$severity.

          $summary
          $breach_lines" || true
            elif [ "$phone" -eq 1 ]; then
              echo "saturation-alert: nori-alert not found; skipping alert (severity=$severity $summary)" >&2
            fi
            last_alert_epoch="$now_epoch"

            ${lib.optionalString cfg.checkpointPrompt.enable ''
              if [ "$severity" = "critical" ]; then
                if [ -n "$agents_tsv" ] && command -v herdr >/dev/null 2>&1; then
                  while IFS=$'\t' read -r target pane; do
                    [ -n "$target" ] || continue
                    herdr agent prompt "$target" \
                      "[saturation-alert] Host memory pressure is critical ($summary). Finish the current atomic edit, make the smallest safe verification, and commit or otherwise checkpoint coherent work now." \
                      >/dev/null 2>&1 || true
                  done <<< "$agents_tsv"
                fi
              fi
            ''}
          elif [ "$severity" = "ok" ] && [ "$last_severity" != "ok" ]; then
            ${lib.optionalString cfg.desktopNotify ''
              if command -v herdr >/dev/null 2>&1; then
                herdr notification show "saturation recovered" \
                  --body "$summary" >/dev/null 2>&1 || true
              fi
            ''}
            # Recovery follows the tier that raised it: only a cleared CRITICAL
            # earns a phone notice, otherwise a build finishing would page too.
            recovery_phone=1
            ${lib.optionalString cfg.phoneOnCriticalOnly ''
              [ "$last_severity" = "critical" ] || recovery_phone=0
            ''}
            if [ "$recovery_phone" -eq 1 ] && [ -n "$nori_alert" ]; then
              "$nori_alert" \
                --audience operator \
                --severity info \
                --category saturation \
                --title "$(uname -n): saturation recovered" \
                --body "$(uname -n) dropped back below every saturation-alert warn threshold.

          $summary" || true
            fi
          fi

          {
            printf 'last_severity=%s\n' "$severity"
            printf 'last_alert_epoch=%s\n' "$last_alert_epoch"
          } > "$state_file"
        '';
      };
    };

    systemd.user.timers.saturation-alert = {
      Unit.Description = "Periodic saturation-alert check";
      Timer = {
        /*
          Same cadence as the system-unit predecessor: the 2026-07-26 leak
          went from healthy to unusable in roughly 25 minutes, 5min bounds
          discovery well inside that window. Coarser than
          clamor-manager-monitor.sh's 20s loop, which traded periodic-timer
          simplicity for near-real-time response in one operator session;
          this stays on the declarative timer shape every other periodic
          check here uses (disk-alert, the predecessor).
        */
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
        AccuracySec = "30s";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
