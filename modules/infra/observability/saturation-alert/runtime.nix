{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.observability.saturationAlert;
in
{
  /*
    Thresholds are calibrated against MEASURED workstation values from the
    2026-07-26 incident, not guessed. Both the degraded and healthy readings
    are recorded on each option so a future reader can re-derive them.
  */
  options.nori.observability.saturationAlert = {
    memoryPressureFullPct = lib.mkOption {
      type = lib.types.ints.between 1 99;
      default = 10;
      description = ''
        Alert when `/proc/pressure/memory` full avg300 crosses this percent.

        "full" means EVERY non-idle task was stalled waiting on memory; a
        sustained non-zero value is thrashing, not load. Measured 2026-07-26:
        27.34% while the box was unusable, 0.29% healthy. 10% sits clear of
        both, and a legitimate heavy build does not full-stall unless it is
        genuinely OOM-thrashing — which is worth waking someone for.
      '';
    };

    taskCeiling = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4000;
      description = ''
        Alert when the kernel's total task count (`/proc/loadavg` field 4,
        after the slash) crosses this.

        The leak canary, and deliberately a SEPARATE signal from pressure: a
        process leak shows up here long before it costs enough memory to stall
        anything. Measured 2026-07-26: 4749 tasks at the peak (898 of them V8
        workers from 141 leaked harnesses), ~3300 healthy with the full agent
        fleet running.
      '';
    };
  };

  config = {
    /**
      saturation-alert — periodic pressure watchdog. The companion to
      disk-alert: that one catches a filesystem filling up, this one catches
      the machine itself being consumed.

      WHY: on 2026-07-26 a leaked agent harness accumulated 421 processes and
      4.1 GiB, driving load to 31.65 and stalling every task on the box 27% of
      wall-clock. Nothing alerted, because nothing FAILED — every unit stayed
      healthy while the machine became unusable. `notify@` and `agent-fix@`
      cover unit failure; this covers saturation, which is a different signal
      class entirely (SRE's fourth golden signal).

      Emits through nori.alerts (`operator` audience) — the same emit-point
      notify@ and disk-alert use. One delivery construct.

      DELIBERATELY NOT WATCHED:
      - `/proc/pressure/io` — measured unreliable on this box. During the same
        incident it read 60%+ "full" while the NVMe was 2% utilised and only
        one task was in D-state, because PSI attributes a lone blocked task on
        an otherwise-idle system as a total stall. It would be a false-positive
        generator.
      - `/proc/pressure/cpu` — fires on legitimate work. `nix flake check` with
        its VM tests pushes cpu "some" past 40% routinely; alerting on it would
        train the operator to ignore the channel.
    */

    systemd.services.saturation-alert = {
      description = "Check memory pressure + task count, alert via ntfy if saturated";
      serviceConfig = {
        Type = "oneshot";
        User = "root"; # nori-alert reads /run/secrets/ntfy-channel (mode 0444)
      };
      unitConfig.OnFailure = [ "notify@saturation-alert.service" ];
      path = [ pkgs.coreutils ];
      script = ''
        set -eu

        # PSI values are decimals ("27.34"), so the comparison lives in awk
        # rather than the shell. Prints the value only when it breaches.
        mem_breach="$(
          awk -v limit=${toString cfg.memoryPressureFullPct} '
            /^full/ {
              for (i = 1; i <= NF; i++) {
                if ($i ~ /^avg300=/) {
                  sub("avg300=", "", $i)
                  if ($i + 0 >= limit) print $i
                }
              }
            }
          ' /proc/pressure/memory
        )"

        if [ -n "$mem_breach" ]; then
          ${config.nori.alerts.command} \
            --audience operator \
            --severity urgent \
            --category saturation \
            --title "${config.networking.hostName}: memory saturated ($mem_breach% stalled)" \
            --body "Every task on ${config.networking.hostName} was stalled on memory $mem_breach% of the last 5 minutes (limit ${toString cfg.memoryPressureFullPct}%). The box is degrading even if no unit has failed.

        Triage: check for a process leak first —
          ps -eLf --no-headers | wc -l
          ps -eo pid,pcpu,pmem,rss,etime,comm --sort=-rss | head -20
          systemd-cgls --no-pager | head -40" || true
        fi

        # Field 4 of /proc/loadavg is running/total tasks; the total is what a
        # leak inflates. Integer, so plain shell comparison is fine.
        tasks="$(cut -d' ' -f4 /proc/loadavg | cut -d/ -f2)"
        if [ "$tasks" -ge ${toString cfg.taskCeiling} ]; then
          ${config.nori.alerts.command} \
            --audience operator \
            --severity urgent \
            --category saturation \
            --title "${config.networking.hostName}: task count $tasks" \
            --body "${config.networking.hostName} has $tasks kernel tasks (limit ${toString cfg.taskCeiling}). This usually means a process leak rather than real work.

        Triage:
          ps -eLo comm --no-headers | sort | uniq -c | sort -rn | head
          ps -eo pid,ppid,etimes,comm --sort=etimes | head -20" || true
        fi
      '';
    };

    systemd.timers.saturation-alert = {
      description = "Periodic saturation-alert check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        /*
          Tighter than disk-alert's 30min: a disk fills over hours, but the
          2026-07-26 leak went from healthy to unusable in roughly 25 minutes.
          5min bounds discovery well inside that window. Both reads are a
          couple of syscalls, so the cost is nil.
        */
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
        AccuracySec = "30s";
      };
    };

    nori.backups.saturation-alert.skip = "Stateless — reads /proc and POSTs to ntfy on threshold breach.";

    # Reads only world-readable /proc files; the baseline hardening needs no
    # widening for it.
    nori.harden.saturation-alert = { };
  };
}
