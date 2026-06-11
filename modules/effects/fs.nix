{ config, lib, ... }:

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
  #
  # Optional `samba` block — when set, the share follows the drive: any
  # host whose nori.fs declares `samba = { … }` for an entry emits the
  # corresponding Samba share via the generator below. When a drive
  # physically moves between hosts (OneTouch → aurora 2026-06-11; future
  # IronWolf moves), the share moves with it automatically because the
  # `nori.fs.<X>.samba` declaration lives next to the disko entry.

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
      types.submodule (
        { name, ... }:
        {
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
            samba = mkOption {
              default = null;
              description = ''
                Optional Samba export. When set, the host emits a
                corresponding share via the generator below — the
                share follows the drive across hosts because the
                declaration lives next to the disko entry. The share's
                global hardening (tailnet-only firewall, hosts allow
                CIDRs, vfs objects for macOS interop) lives in
                modules/services/samba.nix; per-share fields here.

                Defaults are picked for the homelab's single-user
                operator + family case: writable, valid user `nori`,
                force ownership to `nori:users`, 0664/0775 masks.
              '';
              type = types.nullOr (
                types.submodule {
                  options = {
                    shareName = mkOption {
                      type = types.str;
                      default = name;
                      description = ''
                        SMB share name (the path after `\\host\` or
                        `smb://host/`). Defaults to the nori.fs entry
                        name. Override when the on-the-wire name should
                        differ from the registry key (e.g. a renamed
                        share that family bookmarks still use).
                      '';
                    };
                    readOnly = mkOption {
                      type = types.bool;
                      default = false;
                    };
                    validUsers = mkOption {
                      type = types.listOf types.str;
                      default = [ "nori" ];
                    };
                    forceUser = mkOption {
                      type = types.str;
                      default = "nori";
                    };
                    forceGroup = mkOption {
                      type = types.str;
                      default = "users";
                    };
                    createMask = mkOption {
                      type = types.str;
                      default = "0664";
                    };
                    directoryMask = mkOption {
                      type = types.str;
                      default = "0775";
                    };
                    vetoFiles = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      example = "/.*/";
                      description = ''
                        Samba `veto files` pattern (slash-delimited).
                        Used by the operator's `nori` share for the
                        recursive dotfile veto — `/.*/` denies SMB
                        access to any dot-prefixed entry at every depth
                        to keep nested .env / .git-credentials / .ssh
                        material off the tailnet. Per `veto files`(5)
                        the pattern is matched against names, NOT full
                        paths — non-dot secrets (credentials.json, *.key)
                        won't be hidden by this and shouldn't be stored
                        in vetoed shares.
                      '';
                    };
                    deleteVetoFiles = mkOption {
                      type = types.bool;
                      default = false;
                      description = ''
                        When true, lets a directory be removed even
                        though it contains vetoed dotfiles inside.
                        Pair with `vetoFiles` for the operator-share
                        UX (delete a folder over SMB without manually
                        removing its .git first).
                      '';
                    };
                    ownerTmpfilesRule = mkOption {
                      type = types.bool;
                      default = true;
                      description = ''
                        Whether to emit a systemd-tmpfiles rule asserting
                        the share's mount-point ownership matches
                        forceUser/forceGroup at 0775. Default true. Turn
                        off for paths owned by another module (e.g. arr/
                        shared.nix already owns /mnt/media/{downloads,
                        library} as root:media 02775; a samba share over
                        those would set `ownerTmpfilesRule = false` to
                        avoid conflict).
                      '';
                    };
                  };
                }
              );
            };
          };
        }
      )
    );
  };

  # Writer half of nori.fs: hosts that declare any `nori.fs.<X>.samba`
  # entries emit the corresponding share + ownership tmpfiles. The
  # samba globals (workgroup, hosts allow, vfs objects, the firewall
  # rule) live in modules/services/samba.nix on the host that imports it.
  config =
    let
      withSamba = lib.filterAttrs (_: f: f.samba != null) config.nori.fs;
    in
    lib.mkIf (withSamba != { }) {
      services.samba.settings = lib.mapAttrs' (
        _: f:
        lib.nameValuePair f.samba.shareName (
          {
            inherit (f) path;
            browseable = "yes";
            "read only" = if f.samba.readOnly then "yes" else "no";
            "valid users" = lib.concatStringsSep " " f.samba.validUsers;
            "force user" = f.samba.forceUser;
            "force group" = f.samba.forceGroup;
            "create mask" = f.samba.createMask;
            "directory mask" = f.samba.directoryMask;
          }
          // lib.optionalAttrs (f.samba.vetoFiles != null) {
            "veto files" = f.samba.vetoFiles;
            "delete veto files" = if f.samba.deleteVetoFiles then "yes" else "no";
          }
        )
      ) withSamba;

      systemd.tmpfiles.rules = lib.mapAttrsToList (
        _: f: "d ${f.path} 0775 ${f.samba.forceUser} ${f.samba.forceGroup} -"
      ) (lib.filterAttrs (_: f: f.samba.ownerTmpfilesRule) withSamba);
    };
}
