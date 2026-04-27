{
  config,
  lib,
  pkgs,
  ...
}:

{
  # ntfy — alert delivery for backup failures, drive issues, service
  # outages, etc. Per DESIGN.md L478-486:
  #   urgent topic  — sound, bypass DND (service down, drive failing,
  #                   backup job failed)
  #   default topic — silent warning (filesystem >80%, sustained CPU)
  #
  # Tailnet-only on port 8080 — wait, conflicts with Open WebUI's 8080.
  # Using 8081 instead. Browser/mobile-app subscribers must include
  # the port in the URL, e.g.:
  #   nori-station.saola-matrix.ts.net:8081/urgent
  #
  # Single-user tailnet → no auth (any tailnet host can publish/subscribe).
  # If multi-user later: flip auth-default-access to "deny" and issue
  # per-topic publish tokens via sops + Authorization headers.
  #
  # State (auth db, attachments) at /var/lib/ntfy-sh; small enough that
  # daily restic Pattern A is fine. Wire it up in backup-restic.nix once
  # this module's been live a few days and the schema is settled.

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "http://nori-station.saola-matrix.ts.net:8081";
      listen-http = ":8081";
      auth-default-access = "read-write";
      behind-proxy = false;
    };
  };

  # Default-deny FS access — ntfy only needs its own state dir.
  systemd.services.ntfy-sh.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
  };

  # Exposed at https://alert.nori.lan via Caddy. Monitored against
  # ntfy's /v1/health endpoint (returns 200 when ready).
  nori.lanRoutes.alert = {
    port = 8081;
    monitor.path = "/v1/health";
  };

  # Channel name for ntfy.sh (public service) — security-by-obscurity,
  # don't put in the public repo. Match the value in your .secrets.env
  # `NTFY_CHANNEL` so all your Claude/system alerts land in the same
  # mobile-app subscription you already use.
  sops.secrets.ntfy-channel = {
    mode = "0444";
    # readable by the notify@ service running as root,
    # but no special user — root reads everything anyway.
  };

  # Notification template — used as `OnFailure = "notify@%n.service"`
  # by any unit that should alert on failure (restic backups, btrbk
  # snapshots, etc.). The %i instance parameter expands to the failed
  # unit's name. POSTs an urgent message to the user's existing
  # ntfy.sh channel (sops-managed).
  #
  # Test from any tailnet host (after the secret is in place):
  #   curl -H "Title: test" -d "hello" \
  #     "https://ntfy.sh/$(cat /run/secrets/ntfy-channel)"
  #
  # The local self-hosted ntfy-sh instance above is kept running for
  # potential future internal-only alerts (services that shouldn't
  # traverse public internet) but the OnFailure template targets
  # ntfy.sh directly because that's where the user's mobile app is
  # already subscribed.
  systemd.services."notify@" = {
    description = "Send ntfy urgent alert for failed unit %i";
    scriptArgs = "%i";
    script = ''
      CHANNEL=$(cat ${config.sops.secrets.ntfy-channel.path})
      ${pkgs.curl}/bin/curl -fsS \
        -H "Title: nori-station: $1 failed" \
        -H "Priority: urgent" \
        -H "Tags: warning,rotating_light" \
        -d "Unit $1 failed on nori-station. Check journalctl -u $1." \
        "https://ntfy.sh/$CHANNEL" || true
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };

  # Pattern A — local ntfy state (auth db, attachments). DynamicUser
  # → /var/lib/private/ntfy-sh.
  nori.backups.ntfy.paths = [ "/var/lib/private/ntfy-sh" ];
}
