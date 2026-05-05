{
  config,
  lib,
  pkgs,
  ...
}:

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
  # nori.funnelRoutes — single source of truth for Tailscale Funnel
  # exposure. Each entry contributes a path-mounted handler on the
  # workstation's funnel hostname; the composer below assembles ONE
  # serve config covering all entries and applies it via
  # `tailscale serve set-config`.
  #
  # Why an aggregator (vs each app calling `tailscale serve` itself):
  # `tailscale serve set-config` REPLACES the entire serve config — if
  # two apps each ran their own `set-config`, the second would erase
  # the first. The aggregator collects, the single oneshot applies.
  #
  # Funnel exposure = INTERNET-public, not tailnet-public. The threat
  # model is materially different from `nori.lanRoutes.<n>.audience`:
  #   * lanRoutes audience = "operator|family|public" — all
  #     gated-by-tailnet; tailnet IS the auth perimeter
  #   * funnelRoutes — anyone on the public internet can reach this
  # Keeping them as separate effect surfaces lets call sites surface
  # the choice ("expose to tailnet" vs "expose to internet")
  # explicitly rather than inheriting it from a shared enum.
  #
  # ── Service distinct hostnames? ─────────────────────────────────
  # Tailscale's serve config ties handlers to a `<host>:443` key, and
  # the host is the machine's tailnet name (workstation.<tailnet>.ts.net).
  # `tailscale serve advertise` exists for advertising the machine as
  # a service-name proxy on the tailnet, but Funnel doesn't (yet)
  # honour distinct hostnames per service for public exposure. So:
  # all funnel entries today land at <workstation>.ts.net/<path>/.
  # When Tailscale ships per-service Funnel hostnames or we adopt a
  # custom domain (e.g. `<n>.phibkro.dev` CNAME), the composer
  # adapts; call sites stay unchanged.

  options.nori.funnelRoutes = mkOption {
    default = { };
    description = ''
      Tailscale Funnel exposure for self-deployed apps. Each attribute
      adds one path-mounted handler to the workstation funnel.
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = ''
              URL path on the funnel hostname where this app is
              mounted, e.g. "/filmder/". Trailing slash matters
              for sub-path asset resolution — keep it.
            '';
          };

          target = mkOption {
            type = types.str;
            description = ''
              Where Tailscale forwards requests:
                * `/var/lib/<n>/dist` for static-file serving
                * `http://127.0.0.1:<port>` for a local backend
                * `unix:/var/run/<n>.sock` for a Unix socket
              `targetType` below decides which serve handler this is
              passed to.
            '';
          };

          targetType = mkOption {
            type = types.enum [
              "Path"
              "Proxy"
            ];
            default = "Path";
            description = ''
              "Path" — Tailscale serves files directly from the
              `target` directory (good for fully-built static sites).
              "Proxy" — Tailscale reverse-proxies to the `target` URL
              (good for runtime-app backends like Next.js / GraphQL).
            '';
          };
        };
      }
    );
  };

  config = mkIf (config.nori.funnelRoutes != { }) (
    let
      # Funnel hostname. Hardcoded to workstation's tailnet name —
      # the only host with Funnel access at the moment. When a
      # second host gets Funnel, derive from `config.networking.hostName`
      # + the tailnet domain.
      funnelHost = "workstation.saola-matrix.ts.net";
      funnelKey = "${funnelHost}:443";

      handlers = mapAttrs' (
        _: cfg:
        nameValuePair cfg.path {
          ${cfg.targetType} = cfg.target;
        }
      ) config.nori.funnelRoutes;

      serveConfigJson = pkgs.writeText "tailscale-serve.json" (
        builtins.toJSON {
          TCP."443" = {
            HTTPS = true;
          };
          Web.${funnelKey} = {
            Handlers = handlers;
          };
          AllowFunnel.${funnelKey} = true;
        }
      );
    in
    {
      # Apply the assembled serve config to tailscaled. set-config
      # is idempotent (sets desired state from the JSON file) so
      # re-running on every activation is safe and free.
      systemd.services.tailscale-funnel-config = {
        description = "Apply Tailscale serve + funnel config (nori.funnelRoutes)";
        after = [ "tailscaled.service" ];
        wants = [ "tailscaled.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          # `--all` applies the config across all services hosted by
          # this node (workstation in this homelab). The alternative
          # `--service=svc:<n>` form is the newer per-service shape
          # that lets each app advertise a distinct hostname (e.g.
          # `filmder.<tailnet>.ts.net`) — pursue when we want
          # service-distinct URLs and have wired the Tailscale ACL
          # `nodeAttrs` to permit service advertisement. For now
          # (single-host, path-mounted), `--all` is the right scope.
          ${pkgs.tailscale}/bin/tailscale serve set-config --all ${serveConfigJson}
        '';
      };
    }
  );
}
