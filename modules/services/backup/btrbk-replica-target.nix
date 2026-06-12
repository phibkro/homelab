{
  config,
  lib,
  pkgs,
  ...
}:

# P15 receiver — workstation accepts btrfs send streams from aurora's
# btrbk into `/mnt/family-replica/<X>`. Sibling to btrbk-replication.nix
# (which is the sender, aurora-side). The split mirrors the
# restic-target / restic split: sender carries the schedule + the
# nori.replicas registry; receiver carries only the SSH user + sudoers
# that let aurora's btrbk write into MP510's subvols.

lib.mkMerge [
  { nori.services.btrbk-replica-target.tags = [ "backup-infra" ]; }

  (lib.mkIf
    (config.networking.hostName == "workstation" && config.nori.services.btrbk-replica-target.enabled)
    {
      users.users.btrbk = {
        isSystemUser = true;
        group = "btrbk";
        home = "/var/lib/btrbk";
        createHome = true;
        shell = pkgs.bashInteractive; # btrbk runs via ssh shell
        openssh.authorizedKeys.keys = [
          # aurora→workstation btrbk replication. Private half lives
          # in aurora's sops at secrets/secrets.yaml under
          # `btrbk-replication-ssh-key`. Bootstrap via the steps in
          # btrbk-replication.nix § sops; the pubkey lands here when
          # the key is generated.
          # TODO: paste the generated pubkey once the operator runs
          # the bootstrap steps. Until then, the receive side is
          # provisioned but reachable only via direct shell.
        ];
      };
      users.groups.btrbk = { };

      # btrbk needs btrfs + btrbk binaries via sudo because btrfs
      # subvolume create / receive require CAP_SYS_ADMIN. NOPASSWD so
      # aurora's non-interactive ssh session can run the receive flow.
      security.sudo.extraRules = [
        {
          users = [ "btrbk" ];
          commands = [
            {
              command = "${pkgs.btrbk}/bin/btrbk";
              options = [ "NOPASSWD" ];
            }
            {
              command = "${pkgs.btrfs-progs}/bin/btrfs";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      # No nori.backups for this module — declarative auth + sudoers
      # only; the replica payload itself is opted out of restic on
      # the aurora-side btrbk-replication.nix (replica IS the backup).
      nori.backups.btrbk-replica-target.skip = "Auth + sudoers only; replica payload backup intent is on aurora-side btrbk-replication.";

      # No systemd unit named `btrbk-replica-target` — the receive
      # service runs ad-hoc on each incoming ssh connection, no
      # long-running daemon. Hardening intent recorded against sshd
      # by services.openssh itself.
      nori.harden.btrbk-replica-target = { };
    })
]
