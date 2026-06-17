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
  # placement assertions in modules/infra/backup/default.nix (appliance ≠
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
          hardware = mkOption {
            type = types.str;
            description = ''
              One-line hardware identification — chassis · CPU · RAM · GPU
              · notable storage. Drives the hosts-at-a-glance table in
              the generated topology doc; not consumed by evaluation.

              Format guidance: model · CPU family · RAM · GPU (if any) ·
              storage notes. Keep terse — the field is a table cell, not
              a spec sheet. Detailed posture lives in machines/<n>/default.nix
              header comments (anti-write posture, impermanence, etc.).
            '';
          };
          primaryJob = mkOption {
            type = types.str;
            description = ''
              Multi-clause prose describing what this host does — the
              "Primary job" cell in the topology table. CommonMark
              permitted (bullets, inline code, links). Keep to a
              paragraph; deeper rationale belongs in machines/<n>/default.nix
              or the relevant ADR.

              Drift policy: when a host's job changes materially (gains
              or loses a service tier), update this string in the same
              commit. The generator surfaces it; the prose-only
              topology.md no longer carries it.
            '';
          };
          roleOneLiner = mkOption {
            type = types.str;
            description = ''
              Short qualifier appended to the `role` cell in the topology
              table — disambiguates the role for hosts that share a typed
              role but differ in shape (e.g. workstation "sleep-friendly
              compute" vs aurora "always-on family vault"; both are
              `workhorse`). Empty string when the role itself is the
              full story (pavilion: `agent`).
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
                Backed up to local restic. Today this covers two
                distinct shapes — workstation (GPU + desktop +
                bulk media) and aurora (always-on family vault +
                family-tier backends) — which still share the
                "owns state, can take paths-based backups" properties
                workhorse implies. **Rule of three**: if a third host
                matches aurora's always-on-no-desktop shape, extract
                a dedicated `vault` (or `compute`) role then.

              * `appliance` — observability + alerting + DNS + network
                plumbing + HTTP entry plane (Caddy + Authelia +
                Blocky-authoritative). Survives workhorse failure.
                Anti-write storage (no swap, volatile journald, flash)
                → paths-based backups are a build error (assertion in
                modules/infra/backup/default.nix).

              * `agent` — untrusted-compute quarantine. Stateless by
                design: tmpfs root + impermanence /persist. No GPU
                (inference offloaded to workhorse), no GH credential.
                `nori.backups.<X>` declarations are a build error —
                anything escaping the box sandbox vanishes on reboot.

              Adding a role = extend the enum, document its constraints,
              and add the assertions that key off it.
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
