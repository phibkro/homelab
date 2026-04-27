{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Gatus — synthetic uptime monitoring, fully declarative. Replaces
  # Uptime Kuma per the principle "if code-as-config becomes hard,
  # investigate alternatives." Gatus's entire config is YAML; no
  # admin user, no DB, no web-UI bootstrap. NixOS module renders the
  # `settings` attrset to the YAML file gatus consumes.
  #
  # Web UI at port 8082 (8080 collides with Open WebUI). Tailnet-only.
  # Storage = memory (no persistence; recent results are in RAM only,
  # which is fine — alerts go to ntfy.sh, history isn't load-bearing).
  #
  # Channel name for ntfy.sh comes from a sops env-file at runtime —
  # gatus's YAML uses ${NTFY_CHANNEL} which it substitutes from env.
  # The secret is in env-file format because gatus's `environmentFile`
  # systemd directive needs `KEY=VALUE` lines, not bare values.

  sops.secrets.gatus-env = {
    mode = "0440";
  };

  services.gatus = {
    enable = true;
    environmentFile = config.sops.secrets.gatus-env.path;
    settings = {
      metrics = false;
      storage.type = "memory";

      web = {
        address = "0.0.0.0";
        port = 8082;
      };

      alerting.ntfy = {
        # Gatus's ntfy provider takes url and topic as SEPARATE fields
        # — putting the topic in the URL silently disables alerting
        # ("topic not set" warning at startup, no failures emitted).
        url = "https://ntfy.sh";
        topic = "\${NTFY_CHANNEL}";
        priority = 4;
      };

      # HTTP endpoints behind Caddy auto-generate from each service's
      # `nori.lanRoutes.<name>.monitor` declaration — see
      # modules/lib/lan-route.nix. Only entries that don't fit the
      # lan-route pattern (TCP probes for non-HTTP services) live here.
      endpoints = [
        {
          name = "blocky-dns";
          url = "tcp://127.0.0.1:53";
          interval = "60s";
          conditions = [ "[CONNECTED] == true" ];
          alerts = [
            {
              type = "ntfy";
              failure-threshold = 3;
              send-on-resolved = true;
            }
          ];
        }
        {
          name = "samba-smb";
          url = "tcp://127.0.0.1:445";
          interval = "60s";
          conditions = [ "[CONNECTED] == true" ];
          alerts = [
            {
              type = "ntfy";
              failure-threshold = 3;
              send-on-resolved = true;
            }
          ];
        }
      ];
    };
  };

  systemd.services.gatus.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
  };

  # Exposed at https://status.nori.lan via Caddy. No monitor for self
  # (Gatus can't usefully probe itself — would always pass while alive
  # and silently disappear when dead).
  nori.lanRoutes.status = {
    port = 8082;
  };

  # Memory-only storage configured (settings.storage.type = "memory")
  # — no on-disk state to preserve. DynamicUser as well.
  nori.backups.gatus.skip = "Memory-only storage; no on-disk state.";
}
