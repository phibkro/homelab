{
  config,
  lib,
  pkgs,
  ...
}:

{
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
  # The hostname comes from config.networking.hostName so each host's
  # alert reads "<unit> failed on <host>" correctly.
  #
  # Test from any tailnet host (after the secret is in place):
  #   curl -H "Title: test" -d "hello" \
  #     "https://ntfy.sh/$(cat /run/secrets/ntfy-channel)"

  sops.secrets.ntfy-channel = {
    mode = "0444";
    # Readable by the notify@ service running as root.
    # No user/group set: root reads everything anyway.
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

      # Pull the recent journal tail so the ntfy push has useful
      # debugging context, not just the unit name. Stripped to the
      # last 8 lines to fit ntfy's body limits without truncation.
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

  # Cross-host alert URL: this Caddy host (if running) reverse-proxies
  # https://alert.nori.lan to the Pi-hosted ntfy at port 8081. Gated on
  # Caddy presence so hosts running notify@ without Caddy (the Pi
  # itself) don't pollute their lanRoutes registry — Pi's Blocky stays
  # in pure forwarder mode.
  #
  # The ntfy-host coupling lives in the nori.hosts registry (single
  # source of truth — see modules/effects/hosts.nix). If ntfy ever
  # relocates, update flake.nix `identityFor` instead of this file.
  nori.lanRoutes = lib.mkIf config.services.caddy.enable {
    alert = {
      port = 8081;
      host = config.nori.hosts.pi.tailnetIp;
      monitor.path = "/v1/health";
      audience = "operator";
    };
  };

  # No on-disk state owned by this module — notify@ is a oneshot script,
  # ntfy-channel sops secret is rendered at activation.
  nori.backups.notify.skip = "Stateless — ntfy-channel from sops, alerts POSTed to ntfy.sh on demand.";
}
