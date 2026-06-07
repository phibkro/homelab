{ lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  # nori.hosts — topology registry.
  #
  # Collapses cross-host IP literals (was 6+ grep hits for 100.x.y.z
  # across service modules and probes) into one declaration site:
  # `identityFor` in flake.nix. Cross-host refs read
  # `config.nori.hosts.<n>.tailnetIp`. Enforced by the
  # `forbidden-patterns` flake check (no `100.x.y.z` outside identityFor).
  #
  # `role` is typed (enum, not free-form) because it's the key for
  # placement assertions in modules/effects/backup.nix (appliance ≠
  # paths-backups; agent ≠ `nori.backups` at all). A new constraint
  # = a new enum value, document below, add the assertion.

  options.nori.hosts = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          tailnetIp = mkOption {
            type = types.str;
            description = ''
              Tailnet (100.x.y.z) IP. Stable per device once authed —
              survives reboots and re-IPs. The canonical address for
              cross-host references in this flake.
            '';
          };
          lanIp = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Static-DHCP LAN IP, or null. Used by ops tooling (Justfile
              rsync targets) when the tailnet hostname doesn't resolve —
              e.g., `workstation.saola-matrix.ts.net` from Mac without
              tailnet DNS.
            '';
          };
          codename = mkOption {
            type = types.str;
            description = ''
              Aesthetic codename for MOTD / dashboards / casual reference.
              The hostname (not the codename) stays the identifier that
              SSH / Tailscale / nix flakes know — codename is decoration.

              Theme: cold / polar / penguin.
            '';
          };
          role = mkOption {
            type = types.enum [
              "workhorse"
              "appliance"
              "agent"
            ];
            description = ''
              Structural role driving placement assertions:

              * `workhorse` — heavy compute, state, GPU, large disks.
                Caddy + Authelia + media + DBs. Backed up to local restic.

              * `appliance` — observability + alerting + DNS + network
                plumbing. Survives workhorse failure. Anti-write storage
                (no swap, volatile journald, flash) → paths-based
                backups are a build error (assertion in
                modules/effects/backup.nix).

              * `agent` — untrusted-compute quarantine. Stateless by
                design: tmpfs root + impermanence /persist. No GPU
                (inference offloaded to workhorse), no GH credential.
                `nori.backups.<X>` declarations are a build error —
                anything escaping the box sandbox vanishes on reboot.

              Adding a role = extend the enum + document its constraints
              + add the assertions that key off it.
            '';
          };
        };
      }
    );
    default = { };
    description = ''
      Topology registry. Single source of truth for cross-host
      references. Populated in flake.nix's `identityFor` (driven by
      readDir over ./hosts/).
    '';
  };
}
