{ config, lib, ... }:

# P15 receiver — workstation accepts btrfs send streams from aurora's
# btrbk into `/mnt/family-replica/<X>`. Sibling to btrbk-replication.nix
# (which is the sender, aurora-side). The split mirrors the
# restic-target / restic split.
#
# The local `services.btrbk` instance on workstation (snapshotting
# workstation's own subvols, see modules/infra/backup/btrbk.nix)
# already declares the `btrbk` user, group, shell, home, AND the
# NOPASSWD sudoers for `btrfs` / `mkdir` / `readlink` — which is
# exactly what aurora's `sudo btrfs receive` flow needs on this side.
# This module only ADDS the aurora-side ssh key to the existing user;
# module merging concatenates the `authorizedKeys.keys` list.

lib.mkMerge [
  { nori.services.btrbk-replica-target.tags = [ "backup-infra" ]; }

  (lib.mkIf
    (config.networking.hostName == "workstation" && config.nori.services.btrbk-replica-target.enabled)
    {
      users.users.btrbk.openssh.authorizedKeys.keys = [
        # aurora→workstation btrbk replication. Private half lives in
        # aurora's sops at secrets/secrets.yaml under
        # `btrbk-replication-ssh-key` (consumed via the aurora-side
        # `btrbk-replication.nix` ssh_identity option).
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPgBj+u+on5dpwCmH3QQPjbbVsNfHP9jL4NLLPZcc34O aurora→workstation btrbk replication"
      ];

      nori.backups.btrbk-replica-target.skip = "Auth-only module; replica payload backup intent is on aurora-side btrbk-replication.";
      nori.harden.btrbk-replica-target = { };
    }
  )
]
