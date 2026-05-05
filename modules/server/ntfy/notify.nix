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
    description = "Send ntfy urgent alert for failed unit %i";
    scriptArgs = "%i";
    script = ''
      CHANNEL=$(cat ${config.sops.secrets.ntfy-channel.path})
      ${pkgs.curl}/bin/curl -fsS \
        -H "Title: ${config.networking.hostName}: $1 failed" \
        -H "Priority: urgent" \
        -H "Tags: warning,rotating_light" \
        -d "Unit $1 failed on ${config.networking.hostName}. Check journalctl -u $1." \
        "https://ntfy.sh/$CHANNEL" || true
    '';
    serviceConfig = {
      Type = "oneshot";
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
  # relocates, update modules/common/topology.nix instead of this file.
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
