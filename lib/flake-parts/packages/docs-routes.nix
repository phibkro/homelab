/*
  Generated reference for the compiler-owned active route projection.

  Build:      nix build .#docs-routes
  Output:     ./result (CommonMark file)
  Committed:  docs/generated/routes.md
*/
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      routes = inputs.self.lib.noriInventory.routes;
      routeRow =
        name: route:
        let
          monitor = if route.monitor == null then "no" else "yes";
          publicStatus = if route.publicStatus then "yes" else "no";
        in
        "| `${name}` | `${route.workload}` | `${route.host}` | `${toString route.port}` | `${route.reachability}` | `${route.audience}` | `${route.auth}` | ${monitor} | ${publicStatus} |";
      rows = lib.concatStringsSep "\n" (lib.mapAttrsToList routeRow routes);
    in
    {
      packages.docs-routes = pkgs.writeText "routes.md" ''
        ---
        generated: true
        source: flake.nix § packages.docs-routes
        regenerate: nix build .#docs-routes
        ---

        # Active HTTP routes

        This table is generated from `lib.noriInventory.routes`. Workload
        manifests own endpoint declarations. The inventory compiler resolves
        placement and policy before NixOS and Ansible adapters consume them.

        | Route | Workload | Host | Port | Reachability | Audience | Authentication | Monitor | Public status |
        |---|---|---:|---:|---|---|---|:---:|:---:|
        ${rows}
      '';
    };
}
