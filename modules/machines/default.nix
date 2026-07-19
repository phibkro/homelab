{
  lib,
  inputs,
}:

/**
  NixOS configuration factory backed by the pure homelab inventory.

  `inventory/default.nix` is evaluated before the NixOS module fixed point and
  owns host enumeration, identity, profile selection, intended workload
  placement, and reusable system-module composition. Host realizations carry
  only hardware/storage and genuine deviations; profiles and workload
  manifests select reusable modules before the NixOS fixed point.

  ## Topology

  ```mermaid
  graph TB
    subgraph "appliance tier"
      P[pi<br/>entry plane + observability hub]
    end
    subgraph "workhorse tier"
      A[aurora<br/>always-on family vault]
      W[workstation<br/>media compute + desktop]
    end
    subgraph "agent tier"
      V[pavilion<br/>quarantined agents]
    end
    M[macbook<br/>daily-driver]
    P -- "*.${nori.domain} proxy" --> A
    P -- "*.${nori.domain} proxy" --> W
    A -- "nightly btrfs send/receive" --> W
    A -- "scraped by" --> P
    W -- "scraped by" --> P
    V -- "scraped by" --> P
    M -. "SSH" .-> P
    M -. "SSH" .-> A
    M -. "SSH" .-> W
  ```

  Cross-host references continue through the compatibility `nori.hosts`
  registry. New architecture consumers use the typed, public-safe
  `nori.inventory` projection. Both derive from the same pure source; there is
  no parallel identity map.
*/

let
  inventory = import ../../inventory { inherit lib; };
  hosts = inventory.internal.hosts;

  hostRegistry = lib.mapAttrs (_: host: host.identity) hosts;

  standaloneHomes = {
    macbook = ./macbook/home.nix;
  };

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
  nixosConfigurations = lib.mapAttrs mkHost hosts;
  inherit standaloneHomes inventory;
}
