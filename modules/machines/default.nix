{
  lib,
  inputs,
}:

/**
  NixOS configuration factory backed by the pure homelab inventory.

  `inventory/default.nix` is evaluated before the NixOS module fixed point and
  owns host enumeration, identity, profile selection, and intended workload
  placement. This factory still imports each legacy host realization unchanged
  during Phase 1; later phases replace its all-service imports with runtime
  modules selected from the same pure inventory.

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
      modules = [
        host.systemModule
      ]
      ++ inventory.internal.runtimeModulesFor name
      ++ [
        {
          config.networking.hostName = name;
          config.nori.hosts = hostRegistry;
          config.nori.inventory = inventory.forHost name;
          config.nori.lanRoutes = inventory.internal.lanRoutes;
        }
      ];
    };
in
{
  nixosConfigurations = lib.mapAttrs mkHost hosts;
  inherit standaloneHomes inventory;
}
