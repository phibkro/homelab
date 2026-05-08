{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    ;
in
{
  # nori.publicRoutes — internet-public routes via cloudflared tunnel,
  # served under phibkro.org. Each entry maps a hostname segment to a
  # local backend port; modules/server/cloudflared.nix assembles the
  # tunnel ingress rules from this attrset.
  #
  # Peer of nori.lanRoutes (which serves *.nori.lan via Caddy on the
  # tailnet-only LAN IP). Most apps want both: lanRoutes for tailnet-
  # internal access, publicRoutes for internet-public exposure under
  # the operator's portfolio domain. Backends listen once on
  # 127.0.0.1:<port>; the two route effects are the two views.
  #
  # Apex: declare host = "@" to map to phibkro.org itself (no
  # subdomain). modules/server/phibkro-index.nix uses this for the
  # auto-generated sitemap landing page.
  #
  # Sitemap metadata: routes with `sitemap != null` appear on the
  # phibkro.org apex landing page as cards. Backend-only routes
  # (e.g. drinks-api, the GraphQL endpoint behind drinks.phibkro.org's
  # SPA) leave it null and stay off the sitemap.
  options.nori.publicRoutes = mkOption {
    default = { };
    description = ''
      Internet-public routes via cloudflared tunnel under phibkro.org.
    '';
    example = lib.literalExpression ''
      {
        filmder = {
          host = "filmder";
          port = 9092;
          sitemap = {
            title = "Filmder";
            description = "TMDB-backed movie browser.";
          };
        };
      }
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          host = mkOption {
            type = types.str;
            description = ''
              Subdomain segment. The full hostname becomes
              `<host>.phibkro.org`, except `host = "@"` which maps to
              the apex `phibkro.org` directly.
            '';
          };
          port = mkOption {
            type = types.port;
            description = ''
              Local backend port the tunnel forwards to (always
              127.0.0.1:<port>).
            '';
          };
          sitemap = mkOption {
            default = null;
            description = ''
              If set, this route appears on the phibkro.org apex
              landing page. Backend-only routes (e.g. an API endpoint
              consumed by another route's frontend) leave this null.
            '';
            type = types.nullOr (
              types.submodule {
                options = {
                  title = mkOption {
                    type = types.str;
                    description = "Display name on the sitemap card.";
                  };
                  description = mkOption {
                    type = types.str;
                    description = "One-line blurb under the card title.";
                  };
                };
              }
            );
          };
        };
      }
    );
  };

  config = lib.mkIf (config.nori.publicRoutes != { }) {
    assertions = [
      {
        assertion =
          let
            ports = lib.mapAttrsToList (_: r: r.port) config.nori.publicRoutes;
          in
          lib.length ports == lib.length (lib.unique ports);
        message = ''
          nori.publicRoutes have duplicate backend ports. Each route
          must point at a unique local port — cloudflared can't ingress
          two hostnames to the same backend.
        '';
      }
      {
        assertion = lib.all (n: builtins.match "[a-z][a-z0-9-]*" n != null) (
          lib.attrNames config.nori.publicRoutes
        );
        message = ''
          nori.publicRoutes names must be DNS-safe: lowercase, must
          start with a letter, only [a-z0-9-] thereafter.
        '';
      }
      {
        assertion =
          let
            apexCount = lib.length (lib.filter (r: r.host == "@") (lib.attrValues config.nori.publicRoutes));
          in
          apexCount <= 1;
        message = ''
          More than one nori.publicRoutes entry sets host = "@". The
          apex (phibkro.org without subdomain) can have at most one
          backend.
        '';
      }
    ];
  };
}
