{ lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  # nori.fs — named filesystem locations + value-tier metadata.
  #
  # Collapses subvolume paths that used to be magic strings across arr
  # binds, jellyfin/immich/komga consumers, and the restic+btrbk
  # generators. Reader-shaped effect: hosts declare (alongside disko),
  # services consume by name; backup generators in modules/server/backup/
  # filter by tier (the Writer-shaped consequence).

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
        downloads   = { path = "/mnt/media/downloads";   tier = "re-derivable"; };
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
              Value tier per docs/STORAGE.md "Value tiers".
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

  # No config block: nori.fs is pure Reader. Tier-driven filtering and
  # btrbk subvolume lists live in modules/server/backup/ next to their
  # consumers.
}
