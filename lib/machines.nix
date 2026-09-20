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

  Every NixOS module receives the typed, public-safe `nori.inventory`
  projection generated from this pure source; there is no parallel identity
  map.
*/

let
  inventory = import ../inventory { inherit lib; };
  hosts = inventory.internal.hosts;
  nixosHosts = lib.filterAttrs (_: host: host.kind == "nixos") hosts;

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
            config.nori.inventory = inventory.forHost name;
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
