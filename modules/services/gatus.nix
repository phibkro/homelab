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
  # Web UI at port 8082 (8080 collides with Open WebUI).
  #
  # Channel name for ntfy.sh comes from a sops env-file at runtime —
  # gatus's YAML uses ${NTFY_CHANNEL} which it substitutes from env.
  # The secret is in env-file format because gatus's `environmentFile`
  # systemd directive needs `KEY=VALUE` lines, not bare values.

  config = lib.mkMerge [
    {
      nori.services.gatus.tags = [ "observability" ];

      # Caddy vhost at https://status.${nori.domain} — `runsOn` points
      # at the workstation instance (the canonical UI surface); pi's
      # Caddy reverse-proxies cross-host over tailnet. No self-monitor
      # (Gatus can't usefully probe itself — would always pass while
      # alive and silently disappear when dead).
      nori.lanRoutes.status = {
        port = 8082;
        runsOn = "workstation";
        exposeOnTailnet = true;
        audience = "public";
        dashboard = {
          title = "Gatus";
          icon = "sh:gatus";
          group = "Admin";
          description = "Service uptime + alerts";
        };
      };
    }
    (lib.mkIf config.nori.services.gatus.enabled {
      sops.secrets.gatus-env = {
        mode = "0440";
      };

      services.gatus = {
        enable = true;
        environmentFile = config.sops.secrets.gatus-env.path;
        settings = {
          # Exposes /metrics at the top level (NOT /api/v1/metrics — Gatus's
          # API sits under /api/v1/ but Prom endpoint follows standard
          # convention). Scraped by Pi's VictoriaMetrics.
          metrics = true;
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

      nori.harden.gatus = { };

      nori.backups.gatus.skip = "Memory-only storage; no on-disk state.";

      # 60s warmup before probing resumes after a (re)start. Suppresses
      # the false-positive alert window where Gatus comes up faster than
      # the services it monitors — most commonly after a `just rebuild`
      # restarts both Gatus AND its probe targets. Applies to crash
      # recovery too; the 60s monitoring gap on unexpected restarts is
      # the right trade vs. spurious alerts every rebuild.
      #
      # Was previously attempted in Justfile via `systemctl mask` around
      # nh os switch — failed because NixOS-managed units live at
      # /etc/systemd/system/<n>.service as nix-store symlinks and
      # systemctl refuses to overwrite those. Encoding the warmup at
      # the unit level avoids the wrapper coupling entirely. Cross-host
      # gap (other hosts' Gatus probing the rebuilding one) tracked as
      # G3 in docs/ROADMAP.md.
      systemd.services.gatus.serviceConfig.ExecStartPre = [
        "${pkgs.coreutils}/bin/sleep 60"
      ];
    })
  ];
}
