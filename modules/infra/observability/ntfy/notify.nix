{
  config,
  lib,
  pkgs,
  ...
}:

{
  /*
    Both knobs default to production shape; the e2e nixosTest
    (tests/e2e-pi-smoke.nix) overrides them to point at a stub
    receiver in-VM with a sub-second recovery window. Production
    keeps the 120s window + ntfy.sh URL.
  */
  options.nori.observability.ntfyNotify = {
    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.sh";
      description = ''
        Base URL the notify@ template POSTs to. Channel name from
        sops is appended as a path segment. Override to redirect
        alerts to a local stub in tests, or to a self-hosted ntfy
        in environments where ntfy.sh isn't reachable.
      '';
    };
    recoveryWindowSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = ''
        Seconds to wait after OnFailure triggers before alerting.
        Most transient failures self-heal during the systemd
        restart backoff; alerting immediately produces stale
        notifications. Production default of 120s covers the
        early backoff tier (1s+2s+4s+8s+15s+30s+1min ≈ 2min).
        Tests override to ~3s for fast iteration.
      '';
    };
  };

  config = lib.mkMerge [
    {
      nori.services.ntfy-notify.tags = [
        "observability"
        "alerting"
      ];

      /*
        Caddy-gated so the Pi (no Caddy, runs the ntfy server itself)
        doesn't register a route pointing at its own backend. Host coupling
        lives in nori.hosts (see modules/infra/hosts.nix).
      */
      nori.lanRoutes = lib.mkIf config.services.caddy.enable {
        alert = {
          port = 8081;
          runsOn = "pi";
          monitor.path = "/v1/health";
          audience = "operator";
        };
      };
    }
    (lib.mkIf config.nori.services.ntfy-notify.enabled {
      /**
        notify@ — OnFailure handler used by any unit that should alert on
        failure (restic backups, btrbk snapshots, …). Imported by every host
        so each host's own units can wire `OnFailure = "notify@%n.service"`.

        Posts directly to ntfy.sh (public) — that's where the user's mobile
        app is already subscribed; the alert path through ntfy.sh stays
        alive even when the local ntfy on Pi is down. The local server in
        ./server.nix is for future internal-only alerts (services that
        shouldn't traverse public internet), not used by this template.

        Test from any tailnet host (after the secret is in place):
          curl -H "Title: test" -d "hello" \
            "https://ntfy.sh/$(cat /run/secrets/ntfy-channel)"
      */

      sops.secrets.ntfy-channel = {
        mode = "0444";
      };

      systemd.services."notify@" = {
        description = "Send ntfy urgent alert for failed unit %i (after recovery window)";
        scriptArgs = "%i";
        script = ''
                UNIT="$1"

                # Wait through the system-wide restart cycle before alerting. # multi-line: ok
                # modules/infra/restart-policy.nix sets RestartSec=1s with
                # backoff ramping to 5min over 9 steps, then gives up at
                # StartLimitBurst=15 in 1h. Most transient failures self-heal in
                # well under a minute — alerting immediately produces "service
                # down" notifications that are stale by the time the operator
                # opens the phone.
                #
                # Recovery window comes from nori.observability.ntfyNotify.
                # recoveryWindowSeconds — 120 in prod, ~3 in tests. Both
                # tiers exercise the same code path; only the wait differs.
                sleep ${toString config.nori.observability.ntfyNotify.recoveryWindowSeconds}

                if systemctl is-active "$UNIT" --quiet; then
                  # Unit recovered during the window — quiet.
                  exit 0
                fi

                # Last 8 lines / 800 chars fits ntfy's body limit without truncation.
                TAIL="$(journalctl -u "$UNIT" -n 8 --no-pager 2>&1 | tail -c 800)"

                CHANNEL=$(cat ${config.sops.secrets.ntfy-channel.path})
                ${pkgs.curl}/bin/curl -fsS \
                  -H "Title: ${config.networking.hostName}: $UNIT still failed after recovery window" \
                  -H "Priority: urgent" \
                  -H "Tags: warning,rotating_light" \
                  --data-binary "$UNIT is still in failed state on ${config.networking.hostName} after the OnFailure recovery window. Recent journal:

          $TAIL

          Diagnose: journalctl -u $UNIT" \
                  "${config.nori.observability.ntfyNotify.baseUrl}/$CHANNEL" || true
        '';
        serviceConfig = {
          Type = "oneshot";
          # Sleep MUST run uninterrupted — generous timeout so systemd
          # doesn't kill the alert before it fires. Slack of 60s over
          # the configured window covers curl + journalctl overhead.
          TimeoutStartSec = "${toString (config.nori.observability.ntfyNotify.recoveryWindowSeconds + 60)}s";
        };
      };

      nori.backups.notify.skip = "Stateless — ntfy-channel from sops, alerts POSTed to ntfy.sh on demand.";
    })
  ];
}
