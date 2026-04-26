{ config, lib, pkgs, ... }:

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
    TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
    BindReadOnlyPaths = [ ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8081 ];

  # Notification template — used as `OnFailure = "notify@%n.service"`
  # by any unit that should alert on failure (restic backups, btrbk
  # snapshots, etc.). The %i instance parameter expands to the failed
  # unit's name; the template POSTs an urgent ntfy message.
  #
  # Subscribe from your phone / mac:
  #   ntfy mobile app → add subscription → server
  #     http://nori-station.saola-matrix.ts.net:8081
  #     topic: urgent
  #
  # Test from any tailnet host:
  #   curl -H "Title: test" -d "hello" http://nori-station.saola-matrix.ts.net:8081/urgent
  systemd.services."notify@" = {
    description = "Send ntfy urgent alert for failed unit %i";
    scriptArgs = "%i";
    script = ''
      ${pkgs.curl}/bin/curl -fsS \
        -H "Title: nori-station: $1 failed" \
        -H "Priority: urgent" \
        -H "Tags: warning,rotating_light" \
        -d "Unit $1 failed on nori-station. Check journalctl -u $1." \
        http://127.0.0.1:8081/urgent || true
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };
}
