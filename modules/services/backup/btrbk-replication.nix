{
  config,
  lib,
  pkgs,
  ...
}:

# P15 — btrfs send/receive replication for aurora's family-vault →
# workstation's MP510 family-replica subvols. Closes the third copy
# of the 3-copy posture (aurora primary + workstation replica +
# OneTouch restic), leaving Hetzner off-site for a future ROADMAP
# round if appetite reverses.
#
# Sender lives on aurora: snapshots `/mnt/family/<X>`, btrfs-sends
# each snapshot over ssh to workstation. Receiver writes into
# `/mnt/family-replica/<X>` on workstation's MP510 (subvols already
# carved out by the P9 disko-mp510.nix layout).
#
# Verification: `modules/effects/replication.nix` (P5) provides
# `nori.replicas.<n>` registry + per-replica freshness verifier on
# the target host. This module populates the registry as it activates
# the send timer, so a stalled receive surfaces via the verifier
# automatically — no double-wiring needed.

let
  # Source subvols on aurora that get replicated. Derived from
  # `nori.fs` so the list stays single-sourced; the alternative
  # (hard-coded list here + parallel list in disko) would drift.
  irreplaceableFs = lib.filterAttrs (_: f: f.tier == "irreplaceable") config.nori.fs;

  # btrbk operates on subvol paths relative to a volume root. Strip
  # the `/mnt/family/` prefix to get the subvol names btrbk needs.
  # Each subvol gets its own `target` because workstation's MP510
  # mounts `@family-replica-<X>` at separate `/mnt/family-replica/<X>`
  # paths — there's no single parent btrfs filesystem btrbk could
  # use as a shared receive directory.
  subvolEntries = lib.mapAttrs' (
    _: f:
    let
      name = lib.removePrefix "/mnt/family/" f.path;
    in
    lib.nameValuePair name {
      target = "ssh://${config.nori.hosts.workstation.tailnetIp}${workstationReplicaRoot}/${name}";
    }
  ) irreplaceableFs;

  workstationReplicaRoot = "/mnt/family-replica";
in

lib.mkMerge [
  { nori.services.btrbk-replication.tags = [ "backup" ]; }

  # Aurora-only by direction-of-replication. Workstation receives via
  # the `btrbk` user's sudoers + authorized_keys (declared on the
  # workstation side; this module doesn't touch workstation config).
  # Also gated on the per-host `nori.services.btrbk-replication.enable`
  # flag because the module needs a sops secret to exist before it
  # can activate cleanly. Operator flips this true once the ssh key
  # bootstrap below is complete.
  (lib.mkIf (config.networking.hostName == "aurora" && config.nori.services.btrbk-replication.enabled)
    {
      # ── btrbk instance ─────────────────────────────────────────────
      # `family-replica` snapshots each `/mnt/family/<X>` daily and
      # sends incrementals to workstation. snapshot_dir under the
      # family vault keeps snapshots on the same btrfs filesystem (the
      # only way btrfs send works — snapshots are read-only btrfs
      # subvols on the source FS). target_preserve mirrors the source
      # retention so workstation's replica isn't a sliding window
      # different from aurora.
      services.btrbk.instances.family-replica = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = "7d 4w 6m";
          target_preserve_min = "2d";
          target_preserve = "7d 4w 6m";
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          stream_compress = "zstd";

          # ssh_user from the local btrbk service's perspective is the
          # remote user it connects AS (i.e. the `btrbk` user on
          # workstation). ssh_identity is the private key path here on
          # aurora; bootstrap via sops.
          ssh_user = "btrbk";
          ssh_identity = "/run/secrets/btrbk-replication-ssh-key";

          volume."/mnt/family".subvolume = subvolEntries;
        };
      };

      systemd.services.btrbk-family-replica.unitConfig.OnFailure = [
        "notify@btrbk-family-replica.service"
      ];

      # ── sops: aurora's ssh private key for the workstation `btrbk` user.
      # Operator bootstrap:
      #   1. On aurora: sudo -u btrbk-aurora ssh-keygen -t ed25519 \
      #        -f /tmp/btrbk-aurora -N ''  (no passphrase; sops protects at rest)
      #   2. Paste the private key into `sops secrets/secrets.yaml`:
      #        btrbk-replication-ssh-key: |
      #          -----BEGIN OPENSSH PRIVATE KEY-----
      #          …
      #   3. Paste the matching pubkey into machines/workstation/default.nix
      #      under users.users.btrbk.openssh.authorizedKeys.keys (see the
      #      workstation-side TODO below).
      #   4. Re-encrypt sops: `cd secrets && sops updatekeys secrets.yaml`
      #   5. just remote aurora rebuild + just rebuild on workstation.
      sops.secrets.btrbk-replication-ssh-key = {
        # The upstream `services.btrbk` runs the unit as User=btrbk (uid
        # set by NixOS' implicit-system-uid allocator); the key has to be
        # readable by that uid, not just root.
        owner = "btrbk";
        group = "btrbk";
        mode = "0400";
      };

      # ── nori.replicas: declare the cross-host intent so the P5 verifier
      # on the target host (workstation) picks up the freshness check.
      nori.replicas = lib.mapAttrs (
        _: f:
        let
          name = lib.removePrefix "/mnt/family/" f.path;
        in
        {
          source = {
            host = "aurora";
            inherit (f) path;
          };
          target = {
            host = "workstation";
            path = "${workstationReplicaRoot}/${name}";
          };
          mechanism = "btrfs-send-receive";
          maxAgeHours = 25; # daily cadence + 1h slack
        }
      ) irreplaceableFs;

      # ── Skip restic on the replica subvols.
      # The replica IS the backup — re-running restic over it would
      # double-spend backup budget. The `nori.replicas` registry above
      # is what catches stale receives; restic on aurora covers the
      # source data.
      nori.backups.btrbk-family-replica.skip = "Replica written by btrbk send/receive; source-data restic on aurora is the primary backup path.";

      # btrbk-replication is the SENDER unit. Defaults are fine — btrbk
      # mounts source subvols read-only and only writes the ssh control
      # socket + a state file under /var/lib/btrbk. Mirror of the
      # receiver-side declaration in btrbk-replica-target.nix.
      nori.harden.btrbk-replication = { };

      # ─────────────────────────────────────────────────────────────────
      # ── Workstation-side configuration this module does NOT carry ───
      # ─────────────────────────────────────────────────────────────────
      #
      # The workstation needs all of:
      #
      #   users.users.btrbk = {
      #     isSystemUser = true;
      #     group = "btrbk";
      #     home = "/var/lib/btrbk";
      #     createHome = true;
      #     openssh.authorizedKeys.keys = [
      #       "ssh-ed25519 AAAA… btrbk-replication"  # paste aurora's pubkey
      #     ];
      #     shell = pkgs.bashInteractive;
      #   };
      #   users.groups.btrbk = { };
      #
      #   security.sudo.extraRules = [{
      #     users = [ "btrbk" ];
      #     commands = [
      #       { command = "${pkgs.btrbk}/bin/btrbk"; options = [ "NOPASSWD" ]; }
      #       { command = "${pkgs.btrfs-progs}/bin/btrfs"; options = [ "NOPASSWD" ]; }
      #     ];
      #   }];
      #
      # And the MP510 `/mnt/family-replica/<X>` mountpoints must exist
      # and be writable by btrbk via sudo — disko-mp510.nix already
      # declares them (P9 commit `4acf8d2`), so the mounts are in place.
      #
      # NOT included in this module because the sender-side module
      # shouldn't reach across hosts to declare receiver-side state.
      # When wiring, add the workstation-side bits in a sibling module
      # `modules/services/backup/btrbk-replica-target.nix` gated on
      # `config.networking.hostName == "workstation"`, parallel to the
      # existing `restic-target.nix` pattern.
      #
      # First-run smoke test, after both sides land:
      #   1. On aurora: sudo systemctl start btrbk-family-replica.service
      #   2. tail -f /var/log on aurora + workstation; first send is full,
      #      subsequent runs are incremental.
      #   3. After success: ls /mnt/family-replica/photos/.snapshots/ on
      #      workstation should show the received snapshot.
      #   4. P5 verifier auto-fires hourly; first 25h after wiring should
      #      catch the freshness budget — if `restic-backups-…` style
      #      notifications fire instead of snapshot success, check the
      #      sudoers + key first.
    }
  )
]
