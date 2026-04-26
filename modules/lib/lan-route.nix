{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    mkIf
    mapAttrs'
    nameValuePair
    ;
in
{
  # nori.lanRoutes — single source of truth for services exposed
  # under *.nori.lan. Each entry generates BOTH:
  #   * Caddy vhost: reverse proxy from <name>.nori.lan to the
  #     declared backend port
  #   * Blocky customDNS mapping: <name>.nori.lan → tailnet IP
  #
  # Service modules just declare their own routing inline:
  #
  #   nori.lanRoutes.chat = { port = 8080; };
  #
  # No more Caddy + Blocky edits per service. Adding a new service
  # later: one line in the module that owns the service.

  options.nori.lanIp = mkOption {
    type = types.str;
    default = "100.81.5.122";
    description = ''
      Tailnet IP that *.nori.lan names resolve to. Currently
      nori-station's tailnet IP. When nori-pi exists and runs its
      own subset of services, split into per-host route maps.
    '';
  };

  options.nori.lanRoutes = mkOption {
    default = { };
    description = ''
      Services to expose under *.nori.lan via Caddy reverse proxy +
      Blocky DNS. Attribute name = subdomain; value declares the
      backend.
    '';
    example = lib.literalExpression ''
      {
        jellyfin = { port = 8096; };
        chat = { port = 8080; };
        ai = { port = 11434; };
      }
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          port = mkOption {
            type = types.port;
            description = "Backend TCP port (validated 0-65535 at eval time).";
          };
          host = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = "Backend host for Caddy to proxy to.";
          };
          scheme = mkOption {
            type = types.enum [
              "http"
              "https"
            ];
            default = "http";
            description = "Backend scheme. Most services run plain HTTP; Caddy terminates TLS.";
          };
          exposeOnTailnet = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Open the backend port on the tailnet, bypassing Caddy.
              Default closed — Caddy on 443 is the canonical entry
              point. Opt in only when something needs direct port
              access (legacy clients, programmatic tools that don't
              handle Caddy's internal CA).
            '';
          };
          monitor = mkOption {
            default = null;
            description = ''
              If set, auto-generate a Gatus endpoint probing the route's
              backend directly (bypasses Caddy, tests just the service).
              Set to `{ }` to use defaults; override `path` for non-/
              health endpoints (e.g. ollama needs /api/tags).
            '';
            type = types.nullOr (
              types.submodule {
                options = {
                  path = mkOption {
                    type = types.str;
                    default = "/";
                    description = "Path appended to the backend URL for the probe.";
                  };
                  interval = mkOption {
                    type = types.str;
                    default = "60s";
                  };
                  failureThreshold = mkOption {
                    type = types.int;
                    default = 3;
                  };
                  conditions = mkOption {
                    type = types.listOf types.str;
                    default = [ "[STATUS] == 200" ];
                  };
                };
              }
            );
          };
        };
      }
    );
  };

  config = mkIf (config.nori.lanRoutes != { }) {
    services.caddy.virtualHosts = mapAttrs' (
      name: cfg:
      nameValuePair "${name}.nori.lan" {
        extraConfig = "reverse_proxy ${cfg.scheme}://${cfg.host}:${toString cfg.port}";
      }
    ) config.nori.lanRoutes;

    services.blocky.settings.customDNS.mapping = mapAttrs' (
      name: _: nameValuePair "${name}.nori.lan" config.nori.lanIp
    ) config.nori.lanRoutes;

    # Tailnet firewall: open backend ports for opt-in routes only.
    # Default-deny aligns with the rest of the network policy
    # (Caddy on :80 + :443 from caddy.nix is the canonical entry).
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.flatten (
      lib.mapAttrsToList (_: cfg: lib.optional cfg.exposeOnTailnet cfg.port) config.nori.lanRoutes
    );

    # Auto-generated Gatus endpoints for routes that opt in via
    # `monitor`. Manual entries in modules/services/gatus.nix
    # (blocky-dns, samba-smb) coexist via list concatenation.
    services.gatus.settings.endpoints = lib.mkAfter (
      lib.mapAttrsToList (name: cfg: {
        inherit name;
        url = "${cfg.scheme}://${cfg.host}:${toString cfg.port}${cfg.monitor.path}";
        inherit (cfg.monitor) interval conditions;
        alerts = [
          {
            type = "ntfy";
            failure-threshold = cfg.monitor.failureThreshold;
            send-on-resolved = true;
          }
        ];
      }) (lib.filterAttrs (_: cfg: cfg.monitor != null) config.nori.lanRoutes)
    );
  };
}
