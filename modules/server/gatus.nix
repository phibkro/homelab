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
  # Two-host pattern: each host runs its own Gatus instance with its
  # own probe list, alerting directly to ntfy.sh (no local-ntfy
  # dependency — local ntfy on station is convenience for OnFailure
  # webhooks; the alert path through ntfy.sh stays alive even when
  # the local ntfy is down). When station's Gatus dies (host hung,
  # the 2026-04-28 case), Pi's Gatus catches it. Vice versa for Pi
  # outages.
  #
  # Per-host probe lists are declared at the host level — station
  # probes its own services + Pi; Pi probes station + itself. The
  # `services.gatus.settings.endpoints` attribute is open and gets
  # both auto-generated entries (from nori.lanRoutes via
  # lib/lan-route.nix on hosts that have lanRoutes) and host-side
  # additions (TCP probes for non-HTTP services).
  #
  # Web UI at port 8082 (8080 collides with Open WebUI). Tailnet-only
  # exposure via Caddy is opt-in via `nori.gatus.exposeViaCaddy`
  # (default true; Pi sets false because it has no Caddy).
  #
  # Storage = memory (no persistence; recent results are in RAM only,
  # which is fine — alerts go to ntfy.sh, history isn't load-bearing).
  #
  # Channel name for ntfy.sh comes from a sops env-file at runtime —
  # gatus's YAML uses ${NTFY_CHANNEL} which it substitutes from env.
  # The secret is in env-file format because gatus's `environmentFile`
  # systemd directive needs `KEY=VALUE` lines, not bare values.

  options.nori.gatus.exposeViaCaddy = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether to register the Gatus web UI in nori.lanRoutes (which
      creates a Caddy vhost at status.nori.lan). Set false on hosts
      that don't run Caddy (nori-pi).
    '';
  };

  config.sops.secrets.gatus-env = {
    mode = "0440";
  };

  config.services.gatus = {
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

      # `endpoints` is the open list. lib/lan-route.nix appends
      # auto-generated entries from `nori.lanRoutes.<n>.monitor`;
      # host config files append manual TCP/HTTP probes for
      # non-lanRoute services (blocky on :53, samba on :445, the
      # other host's services for mutual observation). See
      # hosts/<host>/default.nix.
      endpoints = [ ];
    };
  };

  config.nori.harden.gatus = { };

  # Caddy vhost at https://status.nori.lan — only on hosts that run
  # Caddy. No self-monitor (Gatus can't usefully probe itself —
  # would always pass while alive and silently disappear when dead).
  config.nori.lanRoutes = lib.mkIf config.nori.gatus.exposeViaCaddy {
    status = {
      port = 8082;
    };
  };

  # Memory-only storage (settings.storage.type = "memory") — no
  # on-disk state to preserve. DynamicUser as well.
  config.nori.backups.gatus.skip = "Memory-only storage; no on-disk state.";
}
