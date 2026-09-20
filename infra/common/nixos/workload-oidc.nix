{ config, lib, ... }:

/**
  Host-local OIDC client credentials for Nix-managed workloads.

  The pure inventory owns client metadata and workload placement. This adapter
  materializes only the raw client secret needed by workloads on the current
  NixOS host. Authelia's hashed client secrets are owned by the Pi Ansible
  projection.
*/
let
  routes = config.nori.inventory.routes;
  localOidcRoutes = lib.filterAttrs (
    _: route: route.host == config.nori.inventory.currentHost && route.oidc != null
  ) routes;
in
{
  config = lib.mkIf (localOidcRoutes != { }) {
    sops.secrets = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "oidc-${name}-client-secret" {
        mode = "0440";
        group = "keys";
      }
    ) localOidcRoutes;

    sops.templates = lib.mapAttrs' (
      name: route:
      lib.nameValuePair "oidc-${name}-env" {
        mode = "0440";
        group = "keys";
        content = ''
          ${route.oidc.secretEnvName}=${config.sops.placeholder."oidc-${name}-client-secret"}
        '';
      }
    ) localOidcRoutes;
  };
}
