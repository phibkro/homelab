/**
  Acquisition runtime — intentionally coupled.

  The stack shares storage and permissions, so one module owns its import
  graph. Each child still gates its own realization from the compiler's
  `currentWorkloads` projection. Disabling or moving one workload cannot start
  it through an active sibling.
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
