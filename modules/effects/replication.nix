{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    mkIf
    mapAttrs'
    nameValuePair
    filterAttrs
    ;
in
{
  # nori.replicas — declarative cross-host data-replication registry.
  #
  # Each entry pairs a source dataset on one host with a target on
  # another, plus a mechanism + freshness budget. The Writer half
  # below emits a per-replica verifier oneshot on the *target* host
  # (where the snapshot must land): if the latest snapshot is older
  # than `maxAgeHours`, the unit fails → notify@ alerts via ntfy.
  #
  # The replicator itself (e.g. btrfs send/receive timer aurora →
  # workstation MP510 for `/mnt/family/*`) lands in P15 — this module
  # only defines the registry + the verifier so the freshness check
  # is wired before any replicas actually exist. On hosts with zero
  # matching entries the writer is a clean no-op (no units emitted)
  # and `just test-replicas` exits 0 with "no replicas declared".
  #
  # Service-tier shape:
  #
  #   nori.replicas.family-photos = {
  #     source       = { host = "aurora";      path = "/mnt/family/photos"; };
  #     target       = { host = "workstation"; path = "/mnt/family-replica/photos"; };
  #     mechanism    = "btrfs-send-receive";
  #     maxAgeHours  = 25;  # daily cadence + 1h slack
  #   };
  #
  # See docs/superpowers/plans/2026-06-11-aurora-migration.md § P5/P15.

  options.nori.replicas = mkOption {
    default = { };
    description = ''
      Declarative cross-host dataset replicas. Each entry names a
      source (host + path) and target (host + path), the replication
      mechanism, and a freshness budget. The verifier emitted on the
      target host alerts via ntfy when the latest snapshot at
      `target.path` is older than `maxAgeHours`.
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          source = mkOption {
            description = "Host + path where the dataset originates.";
            type = types.submodule {
              options = {
                host = mkOption { type = types.str; };
                path = mkOption { type = types.path; };
              };
            };
          };
          target = mkOption {
            description = "Host + path where the replica lands.";
            type = types.submodule {
              options = {
                host = mkOption { type = types.str; };
                path = mkOption { type = types.path; };
              };
            };
          };
          mechanism = mkOption {
            type = types.enum [ "btrfs-send-receive" ];
            description = ''
              How the source is propagated. Only `btrfs-send-receive`
              is supported today (aurora HDD → workstation MP510, both
              btrfs). Other mechanisms (zfs send, rsync) would extend
              this enum when a use case arrives.
            '';
          };
          maxAgeHours = mkOption {
            type = types.ints.positive;
            default = 25;
            description = ''
              Freshness budget on the target side. The verifier reads
              the latest snapshot timestamp under `target.path` and
              fails if older than this — triggering the OnFailure →
              notify@ ntfy alert. Default 25h covers a daily cadence
              + 1h slack for the receive window.
            '';
          };
        };
      }
    );
  };

  # Writer: per-replica verifier oneshot emitted on the target host.
  # Empty registry on this host → mkIf collapses to {} cleanly; no
  # units, no timers, no test-replicas false negatives.
  config =
    let
      mine = filterAttrs (_: r: r.target.host == config.networking.hostName) config.nori.replicas;
    in
    mkIf (mine != { }) {
      systemd.services = mapAttrs' (
        name: r:
        nameValuePair "replication-verifier-${name}" {
          description = "Replication freshness verifier — ${name} (${r.source.host} → ${r.target.host})";
          unitConfig.OnFailure = [ "notify@replication-verifier-${name}.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "root";
          };
          # Latest snapshot mtime under target.path. btrfs receive
          # lands subvols as direct children (snapshot dir convention
          # is `<n>-YYYYMMDD-HHMMSS` per btrbk); take the newest by
          # mtime. Failure = alert, which is the right behavior
          # whenever the registry claims a replica but nothing's
          # actually been received yet (the verifier's whole job is
          # to catch silent receive-stalls).
          script = ''
            set -uo pipefail
            target=${r.target.path}
            if [ ! -d "$target" ]; then
              echo "✗ target path missing: $target"
              exit 1
            fi
            latest=$(find "$target" -maxdepth 1 -mindepth 1 -printf '%T@\n' 2>/dev/null \
              | sort -n | tail -1)
            if [ -z "$latest" ]; then
              echo "✗ no snapshots under $target"
              exit 1
            fi
            now=$(date +%s)
            age_s=$(( now - ''${latest%.*} ))
            age_h=$(( age_s / 3600 ))
            budget=${toString r.maxAgeHours}
            if [ "$age_h" -gt "$budget" ]; then
              echo "✗ latest snapshot is ''${age_h}h old (>''${budget}h)"
              exit 1
            fi
            echo "✓ latest snapshot ''${age_h}h old (≤''${budget}h)"
          '';
        }
      ) mine;

      systemd.timers = mapAttrs' (
        name: _:
        nameValuePair "replication-verifier-${name}" {
          description = "Hourly replication freshness check — ${name}";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
            RandomizedDelaySec = "5m";
          };
        }
      ) mine;
    };
}
