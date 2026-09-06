/**
  Acquisition runtime — intentionally coupled.

  Each component retains its own inventory identity and endpoint, while this
  shared module keeps the storage, permissions, API, and lifecycle contract
  atomic. The inventory compiler deduplicates this module when resolving the
  eight colocated workload identities.
*/
_: {
  imports = [
    ./resources.nix
    ../../services/bazarr/nixos.nix
    ../../services/jellyseerr/nixos.nix
    ../../services/lidarr/nixos.nix
    ../../services/prowlarr/nixos.nix
    ../../services/qbittorrent/nixos.nix
    ../../services/radarr/nixos.nix
    ../../services/recyclarr/nixos.nix
    ../../services/sonarr/nixos.nix
  ];
}
