{
  lib,
  inputs,
}:

/**
  NixOS configuration factory backed by the pure homelab inventory.

  `inventory/default.nix` evaluates before the NixOS module fixed point.
  Host inventory owns identity, profiles, and placement tags. Workload
  manifests own ordered selectors. The compiler resolves explicit realization
  instances, then selects profile and workload modules for each NixOS host.

  ## Topology

  ```mermaid
  graph TB
    subgraph "appliance tier"
      P[pi · Ansible<br/>entry plane + observability hub]
    end
    subgraph "workhorse tier"
      A[adelie<br/>SSD application tier]
      W[workstation<br/>desktop + GPU + media + storage]
    end
    P -- "*.${nori.domain} proxy" --> A
    P -- "*.${nori.domain} proxy" --> W
    A -- "Restic to OneTouch" --> W
    A -- "scraped by" --> P
    W -- "scraped by" --> P
  ```

  Cross-host references continue through the compatibility `nori.hosts`
  registry. New architecture consumers use the typed, public-safe
  `nori.inventory` projection. Both derive from the same pure source; there is
  no parallel identity map.
*/

let
  inventory = import ../inventory { inherit lib; };
  hosts = inventory.internal.hosts;
  nixosHosts = lib.filterAttrs (_: host: host.kind == "nixos") hosts;

  # Cross-host topology is independent of deployment ownership: NixOS hosts
  # still need the Ansible-managed Pi's addresses for DNS and metrics.
  hostRegistry = lib.mapAttrs (_: host: host.identity) hosts;

  mkHost =
    name: host:
    lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules =
        inventory.internal.systemModulesFor name
        ++ [
          inputs.home-manager.nixosModules.home-manager
          host.systemModule
        ]
        ++ inventory.internal.runtimeModulesFor name
        ++ [
          {
            config.networking.hostName = name;
            config.nori.hosts = hostRegistry;
            config.nori.inventory = inventory.forHost name;
            config.nori.lanRoutes = inventory.internal.lanRoutes;
            config.home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              backupFileExtension = "hm-backup";
              users.nori.imports = [ host.homeModule ];
            };
          }
        ];
    };
in
{
  nixosConfigurations = lib.mapAttrs mkHost nixosHosts;
  inherit inventory;
}
