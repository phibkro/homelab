{ config, lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  # nori.fs — single source of truth for named filesystem locations
  # services consume by name + value-tier metadata that drives backup
  # and snapshot policy.
  #
  # ── Why this exists ─────────────────────────────────────────────────
  # Subvolume mount paths used to be magic strings scattered across:
  #   * arr/{sonarr,radarr,lidarr,bazarr,qbittorrent}.nix     binds
  #   * arr/shared.nix                                         tmpfiles
  #   * jellyfin.nix / immich.nix / calibre-web.nix / komga.nix
  #   * backup/restic.nix      media-irreplaceable.paths
  #   * backup/btrbk.nix       per-instance subvolume lists
  #
  # Plus the value-tier categorization from docs/DESIGN.md (re-derivable
  # / user / irreplaceable) lived only in prose. Adding a new media
  # subvolume meant editing ~5 places + remembering which restic repo
  # picks it up.
  #
  # nori.fs collapses both: hosts (alongside their disko config) declare
  # named filesystem locations + tier; services read by name; backup
  # generators filter by tier.
  #
  # Reader-shaped effect: hosts produce, services consume.
  # Plus Writer-shaped consequence: backup/btrbk generators in
  # modules/server/backup/ interpret the collected tier metadata.
  #
  # ── Tier semantics ──────────────────────────────────────────────────
  #   re-derivable  Auto-grabbed / re-downloadable. Not in any restic
  #                 repo. Snapshot weekly (cheap insurance against
  #                 accidental deletion mid-grab).
  #   user          /home, /srv/share — user-touched files. Goes in
  #                 the `user-data` restic repo. Daily snapshot.
  #   irreplaceable Photos / home-videos / projects / curated media
  #                 (books, comics). Goes in the `media-irreplaceable`
  #                 restic repo. Daily snapshot, long retention.
  #
  # ── Cross-host portability ──────────────────────────────────────────
  # Service modules read `config.nori.fs.<n>.path`, never literals.
  # A future second workhorse with media on a different mount becomes
  # a `nori.fs.streaming.path = "..."` change in *its* host config; no
  # service module changes.

  options.nori.fs = mkOption {
    default = { };
    description = ''
      Named filesystem locations declared by the host (typically
      alongside disko subvolume definitions) and consumed by service
      modules. Each entry pairs a path with a value tier; the tier
      drives membership in restic backup repos and snapshot retention.
    '';
    example = lib.literalExpression ''
      {
        streaming   = { path = "/mnt/media/streaming";   tier = "re-derivable"; };
        photos      = { path = "/mnt/media/photos";      tier = "irreplaceable"; };
        share       = { path = "/srv/share";             tier = "user"; };
      }
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          path = mkOption {
            type = types.path;
            description = ''
              Mountpoint or directory path. Single source of truth —
              service modules MUST read `config.nori.fs.<n>.path`
              rather than hardcoding the literal.
            '';
          };
          tier = mkOption {
            type = types.enum [
              "re-derivable"
              "user"
              "irreplaceable"
            ];
            description = ''
              Value tier per docs/DESIGN.md "Three value tiers".
              Drives which restic repo (if any) the path lands in
              and the snapshot retention class. Adding a tier:
              extend the enum, document the contract, update the
              filter generators in modules/server/backup/.
            '';
          };
        };
      }
    );
  };

  # No config block here — nori.fs is pure Reader. The Writer-shaped
  # consequences (filtering by tier into backup repo paths, btrbk
  # subvolume lists) live in modules/server/backup/ where the consumers
  # are. Keeps the effect schema separable from the consumer wiring.
}
