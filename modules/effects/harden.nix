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
  # nori.harden — default-deny filesystem-namespace hardening.
  #
  # `/mnt` and `/srv` are tmpfs-overlaid read-only; services see only
  # the subpaths they explicitly bind. Variation across services is just
  # `binds` / `readOnlyBinds` / `protectHome`; the rest is constant
  # serviceConfig that every server module used to rewrite by hand.
  #
  # Attribute name MUST match the systemd unit name. Multi-unit services
  # declare separate entries (immich-server + immich-machine-learning).
  #
  # Composition: services needing extra serviceConfig keys
  # (PrivateDevices, SupplementaryGroups, EnvironmentFile, …) declare
  # them in a sibling `systemd.services.<name>.serviceConfig` block —
  # NixOS module merging combines them with this abstraction's output.

  options.nori.harden = mkOption {
    default = { };
    description = ''
      Filesystem-namespace hardening for systemd services. Each entry
      maps a service unit name to a hardening profile; the generator
      emits `systemd.services.<name>.serviceConfig`.
    '';
    example = lib.literalExpression ''
      {
        sonarr = { binds = [ "/mnt/media/downloads" ]; };
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

          # Universal baseline: stricter than NixOS systemd defaults;
          # verified no-impact against the live service set 2026-05-08.
          # Promote any of these to a per-entry option on the third
          # concrete need (rule of three).
          #
          # ProtectSystem=strict deliberately NOT here: would block
          # state-dir writes for services that don't list their state
          # path in `binds` (bazarr's StateDirectory output is empty;
          # several *arr services rely on upstream-module writability
          # semantics). Promote per-entry if a service needs it.
          PrivateTmp = lib.mkDefault true;
          NoNewPrivileges = lib.mkDefault true;
          LockPersonality = lib.mkDefault true;
          RestrictRealtime = lib.mkDefault true;
          RestrictSUIDSGID = lib.mkDefault true;
          ProtectKernelTunables = lib.mkDefault true;
          ProtectKernelLogs = lib.mkDefault true;
          ProtectClock = lib.mkDefault true;
          # AF_NETLINK is required: libuv's getifaddrs needs it, which
          # Node + Bun depend on. Still blocks AF_PACKET, AF_BLUETOOTH,
          # AF_VSOCK, and friends.
          RestrictAddressFamilies = lib.mkDefault [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
          ];
        }
        // optionalAttrs (cfg.protectHome != null) {
          ProtectHome = lib.mkForce cfg.protectHome;
        };
      }
    ) config.nori.harden;
  };
}
