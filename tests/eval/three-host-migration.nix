{
  inputs,
  lib,
  ...
}:

/**
  Post-admission boundary for the three-host service migration.

  Runtime journeys and state-copy evidence remain deployment checks. This file
  proves the source placement, authority, storage, and backup boundaries.
*/
let
  inventory = inputs.self.lib.noriInventory;
  adelie = inputs.self.nixosConfigurations.adelie.config;
  workstation = inputs.self.nixosConfigurations.workstation.config;
  movedServices = [
    "attic"
    "filmder"
    "grafana"
    "heim"
    "miniflux"
    "radicale"
    "stremio"
    "vaultwarden"
  ];
  expectedAdelieSecrets = [
    "attic-admin-token"
    "attic-cache-keypair"
    "attic-jwt-environment"
    "attic-push-token"
    "grafana-secret-key"
    "miniflux-admin-password"
    "ntfy-channel"
    "oidc-news-client-secret"
    "oidc-vault-client-secret"
    "restic-password"
    "restic-ssh-key"
    "tmdb-token"
    "wifi-akkar-psk"
  ];
  sharedAdelieSecrets = [
    "attic-push-token"
    "ntfy-channel"
  ];
  statefulBackupNames = [
    "miniflux"
    "radicale"
    "stremio"
    "vaultwarden"
  ];
  activeAdelieBackups = lib.attrNames (
    lib.filterAttrs (_: backup: backup.include != null) adelie.nori.backups
  );

  placementCorrect =
    inventory.workloads.glance.hosts == [ "pi" ]
    && lib.all (name: inventory.workloads.${name}.hosts == [ "adelie" ]) movedServices
    &&
      inventory.workloads."attic-publisher".hosts == [
        "adelie"
        "workstation"
      ]
    &&
      inventory.workloads."ntfy-notify".hosts == [
        "adelie"
        "pi"
        "workstation"
      ];

  runtimeCorrect =
    adelie.services.atticd.enable
    && adelie.services.grafana.enable
    && adelie.services.miniflux.enable
    && adelie.services.radicale.enable
    && adelie.services.vaultwarden.enable
    && lib.all (
      name:
      adelie.systemd.services.${name}.unitConfig.ConditionPathExists
      == "/var/lib/nori/migration/${name}-ready"
    ) statefulBackupNames
    && builtins.hasAttr "filmder-serve" adelie.systemd.services
    && builtins.hasAttr "filmder-static" adelie.systemd.services
    && builtins.hasAttr "heim-serve" adelie.systemd.services
    && builtins.hasAttr "stremio" adelie.systemd.services
    && adelie.systemd.services.filmder-build.serviceConfig.User == "filmder-builder"
    && adelie.systemd.services.filmder-static.serviceConfig.User == "filmder-static"
    && adelie.systemd.services.filmder-serve.serviceConfig.User == "filmder-proxy"
    && lib.elem "d /var/lib/filmder/dist 0750 filmder-builder filmder-static -" adelie.systemd.tmpfiles.rules
    && lib.any (
      command: lib.hasSuffix "/bin/systemctl restart filmder-static.service" command
    ) adelie.systemd.services.filmder-build.serviceConfig.ExecStartPost
    && builtins.hasAttr "attic-cache-watch" adelie.systemd.services
    && builtins.hasAttr "attic-cache-watch" workstation.systemd.services
    && !(workstation.services.atticd.enable or false)
    && !(builtins.hasAttr "filmder-serve" workstation.systemd.services)
    && !(builtins.hasAttr "heim-serve" workstation.systemd.services)
    && !(builtins.hasAttr "stremio" workstation.systemd.services)
    && !(workstation.services.grafana.enable or false)
    && !(workstation.services.miniflux.enable or false)
    && !(workstation.services.radicale.enable or false)
    && !(workstation.services.vaultwarden.enable or false);

  secretBoundaryCorrect =
    lib.attrNames adelie.sops.secrets == expectedAdelieSecrets
    && lib.all (
      name:
      if name == "wifi-akkar-psk" then
        adelie.sops.secrets.${name}.sopsFile == inputs.self + "/secrets/network.yaml"
      else if lib.elem name sharedAdelieSecrets then
        adelie.sops.secrets.${name}.sopsFile == inputs.self + "/secrets/shared-runtime.yaml"
      else
        adelie.sops.secrets.${name}.sopsFile == inputs.self + "/secrets/adelie-runtime.yaml"
    ) expectedAdelieSecrets
    && workstation.sops.secrets.ntfy-channel.sopsFile == inputs.self + "/secrets/shared-runtime.yaml"
    &&
      workstation.sops.secrets.attic-push-token.sopsFile == inputs.self + "/secrets/shared-runtime.yaml"
    && adelie.sops.secrets.ntfy-channel.mode == "0400"
    && adelie.sops.secrets.tmdb-token.owner == "filmder-proxy"
    && adelie.sops.templates.filmder-env.owner == "filmder-proxy"
    && adelie.sops.secrets.ntfy-channel.owner == "nori"
    && adelie.sops.templates.filmder-env.mode == "0400"
    && adelie.sops.templates.miniflux-env.group == "miniflux-secrets"
    && adelie.sops.templates."oidc-news-env".group == "miniflux-secrets"
    && adelie.systemd.services.miniflux.serviceConfig.SupplementaryGroups == [ "miniflux-secrets" ]
    && adelie.sops.templates."oidc-vault-env".owner == "vaultwarden"
    && adelie.sops.templates."oidc-vault-env".mode == "0400"
    && (adelie.systemd.services.vaultwarden.serviceConfig.SupplementaryGroups or [ ]) == [ ]
    && lib.all (secret: secret.restartUnits == [ ]) (lib.attrValues adelie.sops.secrets)
    && lib.elem adelie.sops.secrets.attic-jwt-environment.sopsFile adelie.systemd.services.atticd.restartTriggers
    && lib.elem adelie.sops.secrets.attic-cache-keypair.sopsFile adelie.systemd.services.attic-cache-bootstrap.restartTriggers
    && lib.elem adelie.sops.secrets.attic-push-token.sopsFile adelie.systemd.services.attic-cache-watch.restartTriggers
    && lib.elem workstation.sops.secrets.attic-push-token.sopsFile workstation.systemd.services.attic-cache-watch.restartTriggers;

  storageBoundaryCorrect =
    lib.attrNames adelie.disko.devices.disk == [ "main" ]
    &&
      adelie.disko.devices.disk.main.device
      == "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_1TB_S7HDNU0L409926V"
    && lib.attrNames adelie.nori.fs == [ "cache" ]
    && adelie.nori.fs.cache.path == "/var/lib/attic/chunks"
    && !(builtins.hasAttr "/mnt/media" adelie.fileSystems)
    && !(builtins.hasAttr "/mnt/backup" adelie.fileSystems);

  backupBoundaryCorrect =
    activeAdelieBackups == statefulBackupNames
    &&
      adelie.nori.backupTargets.onetouch.repository
      == "sftp:restic-adelie@workstation.saola-matrix.ts.net:/repos"
    && adelie.nori.backupTargets.onetouch.tailnetPeer == "workstation.saola-matrix.ts.net"
    && workstation.nori.backupTargets.onetouch.repository == "/mnt/backup"
    &&
      workstation.systemd.services.restic-target-directories.serviceConfig.BindPaths == [ "/mnt/backup" ]
    && builtins.hasAttr "restic-adelie" workstation.users.users
    &&
      lib.elem "postgresqlBackup-miniflux.service"
        adelie.systemd.services."restic-backups-miniflux-onetouch".requires
    && lib.all (
      name:
      adelie.systemd.services."restic-backups-${name}-onetouch".unitConfig.ConditionPathExists
      == "/var/lib/nori/migration/backups-ready"
    ) statefulBackupNames
    &&
      lib.all
        (
          name:
          adelie.systemd.services.${name}.unitConfig.ConditionPathExists
          == "/var/lib/nori/migration/backups-ready"
        )
        [
          "restic-check-monthly"
          "restic-check-weekly"
        ];
in
if
  placementCorrect
  && runtimeCorrect
  && secretBoundaryCorrect
  && storageBoundaryCorrect
  && backupBoundaryCorrect
then
  "ok — three-host service placement, authority, storage, and backup boundaries hold"
else
  throw ''
    Three-host migration contract failed.
    Placement: ${toString placementCorrect}
    Runtime:   ${toString runtimeCorrect}
    Secrets:   ${toString secretBoundaryCorrect}
    Storage:   ${toString storageBoundaryCorrect}
    Backups:   ${toString backupBoundaryCorrect}
  ''
