{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.steadyStateResourceAlert;

  /*
    This detector observes resource stocks that should settle: cgroup working
    set plus swap, descriptors, and tasks. CPU is deliberately absent.
    Distinguishing useful CPU work from churn requires a workload-owned
    monotonic progress counter; service uptime or log volume would only measure
    activity. The sole adapter here is a steady desktop surface whose useful
    output is fixed once active.
  */

  targetType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        unit = lib.mkOption {
          type = lib.types.str;
          default = "${name}.service";
          description = "Systemd user service whose cgroup owns the observed resources.";
        };
        progressEvidence = lib.mkOption {
          type = lib.types.str;
          description = ''
            Why useful output is steady after warm-up. This is a human
            assertion, not a machine-measured productivity counter.
          '';
        };
        warmupSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 600;
          description = "Time allowed for caches and working sets to settle before establishing a baseline.";
        };
        memoryGrowthBytes = lib.mkOption {
          type = lib.types.ints.positive;
          default = 268435456;
          description = "Minimum cgroup working-set-plus-swap growth above the steady baseline.";
        };
        memoryGrowthPercent = lib.mkOption {
          type = lib.types.ints.positive;
          default = 50;
          description = "Minimum percentage growth above the steady baseline.";
        };
        fdGrowth = lib.mkOption {
          type = lib.types.ints.positive;
          default = 128;
          description = "Minimum file-descriptor growth above the steady baseline.";
        };
        taskGrowth = lib.mkOption {
          type = lib.types.ints.positive;
          default = 16;
          description = "Minimum cgroup task growth above the steady baseline.";
        };
      };
    }
  );

  targetCalls = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (key: target: ''
      check_target \
        ${lib.escapeShellArg key} \
        ${lib.escapeShellArg target.unit} \
        ${toString target.warmupSeconds} \
        ${toString target.memoryGrowthBytes} \
        ${toString target.memoryGrowthPercent} \
        ${toString target.fdGrowth} \
        ${toString target.taskGrowth} \
        ${lib.escapeShellArg target.progressEvidence}
    '') cfg.targets
  );

  checkScript = pkgs.writeShellScript "steady-state-resource-alert-check" ''
    set -eu

    state_dir="''${STATE_DIRECTORY:-$HOME/.local/state/steady-state-resource-alert}"
    mkdir -p "$state_dir"
    cgroup_root="''${RESOURCE_EFFICIENCY_CGROUP_ROOT:-/sys/fs/cgroup}"

    if [ "''${RESOURCE_EFFICIENCY_ALERT_COMMAND+x}" = x ]; then
      # Explicit test/diagnostic authority boundary. An empty override records
      # the transition without producing an external notification.
      nori_alert="$RESOURCE_EFFICIENCY_ALERT_COMMAND"
    else
      nori_alert="$(command -v nori-alert || true)"
      if [ -z "$nori_alert" ] && [ -x /run/current-system/sw/bin/nori-alert ]; then
        nori_alert=/run/current-system/sw/bin/nori-alert
      fi
    fi

    sum_fds() {
      cgroup="$1"
      total=0
      while IFS= read -r pid; do
        [ -d "/proc/$pid/fd" ] || continue
        count="$(find "/proc/$pid/fd" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | wc -l)"
        total=$((total + count))
      done < "$cgroup/cgroup.procs"
      printf '%s\n' "$total"
    }

    persist() {
      state_file="$1"
      shift
      tmp="$state_file.tmp"
      printf '%s\n' "$*" > "$tmp"
      mv "$tmp" "$state_file"
    }

    check_target() {
      key="$1"
      unit="$2"
      warmup_seconds="$3"
      memory_growth_bytes="$4"
      memory_growth_percent="$5"
      fd_growth="$6"
      task_growth="$7"
      progress_evidence="$8"
      state_file="$state_dir/$key.state"

      active="$(systemctl --user show "$unit" --property ActiveState --value 2>/dev/null || true)"
      invocation="$(systemctl --user show "$unit" --property InvocationID --value 2>/dev/null || true)"
      cgroup_rel="$(systemctl --user show "$unit" --property ControlGroup --value 2>/dev/null || true)"
      if [ "$active" != active ] || [ -z "$invocation" ] || [ -z "$cgroup_rel" ]; then
        printf 'resource-efficiency target=%s unit=%s observation=inactive\n' "$key" "$unit"
        return
      fi

      cgroup="$cgroup_root$cgroup_rel"
      if
        [ ! -r "$cgroup/memory.current" ] \
          || [ ! -r "$cgroup/memory.swap.current" ] \
          || [ ! -r "$cgroup/memory.stat" ]
      then
        printf 'resource-efficiency target=%s unit=%s observation=rejected reason=missing-cgroup-accounting cgroup=%s\n' \
          "$key" "$unit" "$cgroup" >&2
        return
      fi

      now="$(date +%s)"
      memory="$(cat "$cgroup/memory.current")"
      swap="$(cat "$cgroup/memory.swap.current")"
      inactive_file=0
      while read -r stat_name stat_bytes; do
        if [ "$stat_name" = inactive_file ]; then
          inactive_file="$stat_bytes"
          break
        fi
      done < "$cgroup/memory.stat"
      working_set=$((memory - inactive_file))
      [ "$working_set" -ge 0 ] || working_set=0
      footprint=$((working_set + swap))
      tasks="$(cat "$cgroup/pids.current")"
      fds="$(sum_fds "$cgroup")"

      saved_invocation=""
      first_epoch=0
      baseline_footprint=0
      baseline_fds=0
      baseline_tasks=0
      streak=0
      alerted=0
      if [ -r "$state_file" ]; then
        IFS=' ' read -r \
          saved_invocation first_epoch baseline_footprint baseline_fds baseline_tasks streak alerted \
          < "$state_file" || true
      fi

      if [ "$saved_invocation" != "$invocation" ] || [ "$first_epoch" -le 0 ]; then
        persist "$state_file" "$invocation $now $footprint $fds $tasks 0 0"
        printf 'resource-efficiency target=%s unit=%s observation=accepted phase=warmup footprint_bytes=%s fds=%s tasks=%s invocation=%s\n' \
          "$key" "$unit" "$footprint" "$fds" "$tasks" "$invocation"
        return
      fi

      age=$((now - first_epoch))
      if [ "$age" -lt "$warmup_seconds" ]; then
        persist "$state_file" "$invocation $first_epoch $footprint $fds $tasks 0 0"
        printf 'resource-efficiency target=%s unit=%s observation=accepted phase=warmup age_seconds=%s footprint_bytes=%s fds=%s tasks=%s\n' \
          "$key" "$unit" "$age" "$footprint" "$fds" "$tasks"
        return
      fi

      # The minimum post-warm-up observation is the steady-state reference.
      # This tolerates transient cache growth but never ratchets a leak into the
      # baseline merely because it persisted.
      [ "$footprint" -ge "$baseline_footprint" ] || baseline_footprint="$footprint"
      [ "$fds" -ge "$baseline_fds" ] || baseline_fds="$fds"
      [ "$tasks" -ge "$baseline_tasks" ] || baseline_tasks="$tasks"

      memory_delta=$((footprint - baseline_footprint))
      fd_delta=$((fds - baseline_fds))
      task_delta=$((tasks - baseline_tasks))

      memory_breach=0
      if [ "$memory_delta" -ge "$memory_growth_bytes" ] \
        && [ $((footprint * 100)) -ge $((baseline_footprint * (100 + memory_growth_percent))) ]; then
        memory_breach=1
      fi

      breach=0
      reasons=""
      if [ "$memory_breach" -eq 1 ]; then
        breach=1
        reasons="memory+swap_growth=$memory_delta"
      fi
      if [ "$fd_delta" -ge "$fd_growth" ]; then
        breach=1
        reasons="''${reasons:+$reasons,}fd_growth=$fd_delta"
      fi
      if [ "$task_delta" -ge "$task_growth" ]; then
        breach=1
        reasons="''${reasons:+$reasons,}task_growth=$task_delta"
      fi

      if [ "$breach" -eq 1 ]; then
        streak=$((streak + 1))
      else
        streak=0
      fi

      if [ "$breach" -eq 1 ] && [ "$streak" -ge ${toString cfg.consecutiveSamples} ] && [ "$alerted" -eq 0 ]; then
        alerted=1
        message="unit=$unit suspected steady-state resource leak: $reasons after $age seconds; working_set_plus_swap=$footprint memory_current=$memory inactive_file=$inactive_file swap=$swap baseline=$baseline_footprint fds=$fds baseline_fds=$baseline_fds tasks=$tasks baseline_tasks=$baseline_tasks. Progress evidence (human assertion): $progress_evidence"
        printf 'resource-efficiency target=%s observation=suspected-leak evidence=%s\n' "$key" "$message" >&2
        if [ -n "$nori_alert" ]; then
          "$nori_alert" \
            --audience operator \
            --severity warning \
            --category resource-efficiency \
            --title "$(uname -n): suspected resource leak in $unit" \
            --body "$message" || true
        fi
      elif [ "$breach" -eq 0 ] && [ "$alerted" -eq 1 ]; then
        alerted=0
        printf 'resource-efficiency target=%s unit=%s observation=recovered footprint_bytes=%s baseline_bytes=%s\n' \
          "$key" "$unit" "$footprint" "$baseline_footprint"
      else
        printf 'resource-efficiency target=%s unit=%s observation=accepted phase=steady footprint_bytes=%s baseline_bytes=%s fds=%s baseline_fds=%s tasks=%s baseline_tasks=%s breach=%s streak=%s\n' \
          "$key" "$unit" "$footprint" "$baseline_footprint" "$fds" "$baseline_fds" "$tasks" "$baseline_tasks" "$breach" "$streak"
      fi

      persist "$state_file" "$invocation $first_epoch $baseline_footprint $baseline_fds $baseline_tasks $streak $alerted"
    }

    ${targetCalls}
  '';
in
{
  options.nori.steadyStateResourceAlert = {
    enable = lib.mkEnableOption "steady-state cgroup resource-growth detection";
    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Systemd timer interval between observations.";
    };
    consecutiveSamples = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Consecutive expanded-resource samples required before alerting.";
    };
    targets = lib.mkOption {
      type = lib.types.attrsOf targetType;
      default = { };
      description = ''
        Long-lived services whose useful output is steady after warm-up.
        Batch jobs and agents require a separate adapter with a monotonic
        progress counter and are intentionally rejected by this model.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.steady-state-resource-alert = {
      Unit = {
        Description = "Detect sustained resource expansion in steady-state desktop services";
        OnFailure = [ "user-notify@steady-state-resource-alert.service" ];
      };
      Service = {
        Type = "oneshot";
        StateDirectory = "steady-state-resource-alert";
        Environment = "PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.findutils
            pkgs.systemd
          ]
        }:/run/current-system/sw/bin";
        ExecStart = checkScript;
      };
    };

    systemd.user.timers.steady-state-resource-alert = {
      Unit.Description = "Periodically sample steady-state desktop resource efficiency";
      Timer = {
        OnBootSec = cfg.interval;
        OnUnitActiveSec = cfg.interval;
        Unit = "steady-state-resource-alert.service";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
