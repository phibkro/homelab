{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    mkIf
    mapAttrs'
    nameValuePair
    optionalAttrs
    ;
in
{
  # nori.harden — single source of truth for default-deny filesystem
  # namespace hardening. Each entry generates the systemd serviceConfig
  # baseline that every server module currently rewrites by hand:
  #
  #   {
  #     ProtectHome = lib.mkForce true;
  #     TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
  #     BindReadOnlyPaths = [...];
  #     BindPaths = [...];
  #   }
  #
  # The variation across services is just `binds` (writable paths) and
  # `readOnlyBinds` (read-only paths); the rest is constant. Service
  # modules now declare their hardening inline alongside lanRoutes and
  # backups:
  #
  #   nori.harden.sonarr = { binds = [ "/mnt/media/streaming" ]; };
  #   nori.harden.jellyfin = { readOnlyBinds = [ "/mnt/media" "/srv/share" ]; };
  #   nori.harden.syncthing = { protectHome = null; };  # opt out
  #
  # The attribute name MUST match the systemd service unit name, so
  # multi-unit services declare separate entries (immich-server +
  # immich-machine-learning).
  #
  # ── Composition with extra serviceConfig ────────────────────────────
  # Services that need additional hardening keys (PrivateDevices,
  # SupplementaryGroups, EnvironmentFile, resource caps, …) declare them
  # in a sibling `systemd.services.<name>.serviceConfig` block. NixOS
  # module merging combines them with the abstraction's output.
  #
  # ── ProtectHome semantics ───────────────────────────────────────────
  # `protectHome = true`  → emits `ProtectHome = lib.mkForce true`
  # `protectHome = false` → emits `ProtectHome = lib.mkForce false`
  # `protectHome = null`  → does not touch ProtectHome at all (keeps
  #                         upstream NixOS module's value, e.g. syncthing
  #                         which the upstream module already sets to a
  #                         specific value). Use this when the upstream
  #                         module is opinionated and our forced override
  #                         would regress.

  options.nori.harden = mkOption {
    default = { };
    description = ''
      Filesystem-namespace hardening for systemd services. Each entry
      maps a service unit name to a hardening profile; the generator
      emits the corresponding `systemd.services.<name>.serviceConfig`.

      Default-deny: services see no `/mnt` or `/srv` content unless
      they explicitly bind a subpath. The `/mnt:ro` and `/srv:ro`
      tmpfs overlays make the rest invisible.
    '';
    example = lib.literalExpression ''
      {
        sonarr = { binds = [ "/mnt/media/streaming" ]; };
        jellyfin = { readOnlyBinds = [ "/mnt/media" "/srv/share" ]; };
        syncthing = { protectHome = null; };
      }
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          binds = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Writable bind-mount paths to expose to the service.
              Maps to systemd `BindPaths`. Use for state-bearing
              service-specific subtrees the service must write to
              (e.g. /mnt/media/photos for Immich).
            '';
          };
          readOnlyBinds = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Read-only bind-mount paths to expose to the service.
              Maps to systemd `BindReadOnlyPaths`. Use for paths the
              service consumes but must not modify (e.g. /mnt/media
              for Jellyfin which streams existing files).
            '';
          };
          protectHome = mkOption {
            type = types.nullOr types.bool;
            default = true;
            description = ''
              Whether to set `ProtectHome` (with mkForce). Default
              true; the abstraction's whole point is default-deny.
              Set false explicitly to allow /home access, or null to
              leave the upstream NixOS module's setting intact (use
              when upstream's value is opinionated and our override
              would regress).
            '';
          };
        };
      }
    );
  };

  config = mkIf (config.nori.harden != { }) {
    systemd.services = mapAttrs' (
      name: cfg:
      nameValuePair name {
        serviceConfig = {
          TemporaryFileSystem = [
            "/mnt:ro"
            "/srv:ro"
          ];
          BindReadOnlyPaths = cfg.readOnlyBinds;
          BindPaths = cfg.binds;
        }
        // optionalAttrs (cfg.protectHome != null) {
          ProtectHome = lib.mkForce cfg.protectHome;
        };
      }
    ) config.nori.harden;
  };
}
