{ config, lib, pkgs, ... }:

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

      endpoints = [
        {
          name = "open-webui";
          url = "http://127.0.0.1:8080";
          interval = "60s";
          conditions = [ "[STATUS] == 200" ];
          alerts = [{
            type = "ntfy";
            failure-threshold = 3;
            send-on-resolved = true;
          }];
        }
        {
          name = "jellyfin";
          url = "http://127.0.0.1:8096";
          interval = "60s";
          conditions = [ "[STATUS] == 200" ];
          alerts = [{
            type = "ntfy";
            failure-threshold = 3;
            send-on-resolved = true;
          }];
        }
        {
          name = "ollama";
          url = "http://127.0.0.1:11434/api/tags";
          interval = "60s";
          conditions = [ "[STATUS] == 200" ];
          alerts = [{
            type = "ntfy";
            failure-threshold = 3;
            send-on-resolved = true;
          }];
        }
        {
          name = "blocky-dns";
          url = "tcp://127.0.0.1:53";
          interval = "60s";
          conditions = [ "[CONNECTED] == true" ];
          alerts = [{
            type = "ntfy";
            failure-threshold = 3;
            send-on-resolved = true;
          }];
        }
        {
          name = "samba-smb";
          url = "tcp://127.0.0.1:445";
          interval = "60s";
          conditions = [ "[CONNECTED] == true" ];
          alerts = [{
            type = "ntfy";
            failure-threshold = 3;
            send-on-resolved = true;
          }];
        }
        {
          name = "ntfy-local";
          url = "http://127.0.0.1:8081/v1/health";
          interval = "300s";
          conditions = [ "[STATUS] == 200" ];
          alerts = [{
            type = "ntfy";
            failure-threshold = 3;
            send-on-resolved = true;
          }];
        }
      ];
    };
  };

  systemd.services.gatus.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
    BindReadOnlyPaths = [ ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8082 ];

  # Exposed at https://gatus.nori.lan via Caddy.
  nori.lanRoutes.gatus = { port = 8082; };
}
