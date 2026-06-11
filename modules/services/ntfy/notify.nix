{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkMerge [
  {
    nori.services.ntfy-notify.tags = [
      "observability"
      "alerting"
    ];
  }
  (lib.mkIf config.nori.services.ntfy-notify.enabled {
    # notify@ — OnFailure handler used by any unit that should alert on
    # failure (restic backups, btrbk snapshots, …). Imported by every host
    # so each host's own units can wire `OnFailure = "notify@%n.service"`.
    #
    # Posts directly to ntfy.sh (public) — that's where the user's mobile
    # app is already subscribed; the alert path through ntfy.sh stays
    # alive even when the local ntfy on Pi is down. The local server in
    # ./server.nix is for future internal-only alerts (services that
    # shouldn't traverse public internet), not used by this template.
    #
    # Test from any tailnet host (after the secret is in place):
    #   curl -H "Title: test" -d "hello" \
    #     "https://ntfy.sh/$(cat /run/secrets/ntfy-channel)"

    sops.secrets.ntfy-channel = {
      mode = "0444";
    };

    systemd.services."notify@" = {
      description = "Send ntfy urgent alert for failed unit %i (after recovery window)";
      scriptArgs = "%i";
      script = ''
              UNIT="$1"

              # Wait through the system-wide restart cycle before alerting.
              # modules/effects/restart-policy.nix sets RestartSec=1s with
              # backoff ramping to 5min over 9 steps, then gives up at
              # StartLimitBurst=15 in 1h. Most transient failures self-heal in
              # well under a minute — alerting immediately produces "service
              # down" notifications that are stale by the time the operator
              # opens the phone.
              #
              # 2 minutes covers the early backoff tier (1s+2s+4s+8s+15s+30s+
              # 1min ≈ 2min). If the unit is back up by then, suppress the
              # alert; if it's still failed, the failure is real and the
              # notification is worth surfacing. The operator can still see
              # the original failure in `journalctl -u <unit>` either way.
              sleep 120

              if systemctl is-active "$UNIT" --quiet; then
                # Unit recovered during the window — quiet.
                exit 0
              fi

              # Last 8 lines / 800 chars fits ntfy's body limit without truncation.
              TAIL="$(journalctl -u "$UNIT" -n 8 --no-pager 2>&1 | tail -c 800)"

              CHANNEL=$(cat ${config.sops.secrets.ntfy-channel.path})
              ${pkgs.curl}/bin/curl -fsS \
                -H "Title: ${config.networking.hostName}: $UNIT still failed after 2min" \
                -H "Priority: urgent" \
                -H "Tags: warning,rotating_light" \
                --data-binary "$UNIT is still in failed state on ${config.networking.hostName} 2 minutes after the OnFailure trigger. Recent journal:

        $TAIL

        Diagnose: journalctl -u $UNIT" \
                "https://ntfy.sh/$CHANNEL" || true
      '';
      serviceConfig = {
        Type = "oneshot";
        # The 120s sleep MUST run uninterrupted — generous timeout so
        # systemd doesn't kill the alert before it fires.
        TimeoutStartSec = "180s";
      };
    };

    # Caddy-gated so the Pi (no Caddy, runs the ntfy server itself)
    # doesn't register a route pointing at its own backend. Host coupling
    # lives in nori.hosts (see modules/effects/hosts.nix).
    nori.lanRoutes = lib.mkIf config.services.caddy.enable {
      alert = {
        port = 8081;
        host = config.nori.hosts.pi.tailnetIp;
        monitor.path = "/v1/health";
        audience = "operator";
      };
    };

    nori.backups.notify.skip = "Stateless — ntfy-channel from sops, alerts POSTed to ntfy.sh on demand.";
  })
]
