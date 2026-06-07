{
  config,
  lib,
  pkgs,
  ...
}:

# Off-host dead-man-switch for the pi appliance.
#
# Pi centralises observability (VictoriaMetrics, VictoriaLogs, Gatus,
# Beszel hub) AND alert delivery (ntfy server). If pi dies, the
# evidence-of-failure exists on workstation's gatus, but the
# delivery channel dies with the host — so the operator wouldn't
# know.
#
# Mitigation: pi pings an external healthchecks.io check every 60s.
# When the pings stop for ~3 min (period 60s + grace 2min), the
# external service alerts via channels configured at hc.io
# (email/Telegram/etc.) — totally independent of this LAN.
#
# The ping URL is the secret (anyone with it can spoof "I'm alive"),
# stored in sops. The systemd timer reads it from the rendered
# secret path at runtime; nothing on disk references the URL plain.
#
# Failure mode coverage:
#   pi powered off / kernel panic / SD-card death / network gone →
#   pings stop → hc.io alerts off-host.
#
# What this does NOT catch:
#   - Service-level failures while pi itself is healthy (workstation
#     gatus + pi ntfy still cover those).
#   - hc.io itself being unreachable from pi (false positive — operator
#     pings, finds pi fine; rare enough to live with).

{
  sops.secrets.heartbeat-pi-url = {
    mode = "0440";
    group = "keys";
  };

  systemd.services.heartbeat = {
    description = "Ping healthchecks.io to prove pi is alive";
    # No OnFailure handler — silence at hc.io IS the alert.
    serviceConfig = {
      Type = "oneshot";
      # Allow the curl to read the sops-rendered URL file.
      SupplementaryGroups = [ "keys" ];
      # Hardening — process needs nothing beyond network egress.
      DynamicUser = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      NoNewPrivileges = true;
      LockPersonality = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
    };
    script = ''
      url=$(cat ${config.sops.secrets.heartbeat-pi-url.path})
      ${pkgs.curl}/bin/curl -fsS --max-time 10 --retry 2 --retry-delay 5 "$url" >/dev/null
    '';
  };

  systemd.timers.heartbeat = {
    description = "Dead-man-switch heartbeat to healthchecks.io";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Ping every 60s; hc.io is configured with period=60s + grace=2min,
      # so 3 missing pings (~3 min silence) trigger the off-host alert.
      OnBootSec = "30s";
      OnUnitActiveSec = "60s";
      AccuracySec = "5s";
      Unit = "heartbeat.service";
    };
  };
}
