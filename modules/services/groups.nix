# Service groups — composable concerns, NOT a mutually-exclusive
# hierarchy. A service can appear in multiple groups; pick whichever
# slicing makes sense for the host you're composing.
#
# Usage from a host's default.nix:
#
#   let
#     groups = import ../../modules/services/groups.nix;
#   in {
#     imports =
#       [ ../../modules/common ../../modules/lib/lan-route.nix ]
#       ++ groups.networking ++ groups.auth ++ groups.observability
#       ++ groups.backup ++ groups.ai ++ groups.media ++ groups.arr
#       ++ [ ../../modules/desktop ./hardware.nix ./disko.nix
#            ./disko-media.nix ./disko-onetouch.nix ];
#   }
#
# Adding a new service: drop the file at modules/services/<name>.nix
# and append it to the relevant group(s) below. A service belongs to
# every group whose concern it supports — no "primary category"
# constraint, so e.g. ntfy can live in `observability` for the metric
# stack and a future `notifications` group for app integrations.
#
# Groups are evaluated as plain Nix lists by the host import; the
# module system de-duplicates if the same path appears more than once
# across groups, so overlap is safe.

{
  # AI / LLM stack — local inference + chat UI
  ai = [
    ./ollama.nix
    ./open-webui.nix
  ];

  # *arr media-acquisition stack — indexer + download client + the
  # *arrs themselves. arr-shared.nix is the cross-cutting `media`
  # group + tmpfiles for the shared library/download paths.
  arr = [
    ./arr-shared.nix
    ./prowlarr.nix
    ./qbittorrent.nix
    ./sonarr.nix
    ./radarr.nix
    ./lidarr.nix
    ./bazarr.nix
    ./jellyseerr.nix
  ];

  # Media serving — Jellyfin (video/music), Samba (SMB shares),
  # calibre-web (ebooks + OPDS), Komga (comics + OPDS).
  media = [
    ./jellyfin.nix
    ./samba.nix
    ./calibre-web.nix
    ./komga.nix
  ];

  # Metrics / monitoring / alert delivery. ntfy provides the notify@
  # template referenced by other modules' OnFailure handlers, so it
  # naturally pairs with this group.
  observability = [
    ./beszel.nix
    ./gatus.nix
    ./ntfy.nix
  ];

  # Data durability — local snapshots + encrypted off-host backup.
  backup = [
    ./btrbk.nix
    ./backup-restic.nix
  ];

  # Edge networking — HTTPS terminator + DNS adblock.
  networking = [
    ./caddy.nix
    ./blocky.nix
  ];

  # SSO / auth — currently just Authelia. Sized as its own group
  # because services that opt into OIDC reach across the others.
  auth = [
    ./authelia.nix
  ];
}
