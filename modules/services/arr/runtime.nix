/**
  Acquisition runtime — intentionally coupled.

  Each component retains its own inventory identity and endpoint, while this
  shared module keeps the storage, permissions, API, and lifecycle contract
  atomic. The inventory compiler deduplicates this module when resolving the
  eight colocated workload identities.
*/
_: {
  imports = [
    ./shared.nix
    ./bazarr.nix
    ./jellyseerr.nix
    ./lidarr.nix
    ./prowlarr.nix
    ./qbittorrent.nix
    ./radarr.nix
    ./recyclarr.nix
    ./sonarr.nix
  ];
}
