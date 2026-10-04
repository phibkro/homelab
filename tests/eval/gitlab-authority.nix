{ inputs, lib }:

/**
  GitLab is the canonical Git store ("authority plane"). This contract pins
  the properties its operator approved: one placement, no public or LAN
  projection, every secret a key of the host's own SOPS file, and backup
  and hardening intent for every unit. Runtime behavior (health endpoint,
  bind addresses, a push through the listener, a backup run, a restore) is the
  `e2e-gitlab` VM check.

  The host is not named here. The manifest owns placement, and this check
  follows `workload.hosts`, so moving GitLab changes the manifest and the
  secrets, not the contract.
*/
let
  inventory = inputs.self.lib.noriInventory;
  nixosHosts = inputs.self.nixosConfigurations;
  workload = inventory.workloads.gitlab;

  gitlabHost = lib.head workload.hosts;
  host = nixosHosts.${gitlabHost}.config;
  otherHosts = lib.filterAttrs (name: _: name != gitlabHost) nixosHosts;
  port = workload.listeners.http.port;
  inRanges = ranges: lib.any (range: range.from <= port && port <= range.to) ranges;
  tailnetIp = inventory.hosts.${gitlabHost}.tailnetIp;
  otherSecretFiles = lib.filter builtins.pathExists (
    map (name: inputs.self + "/secrets/${name}-runtime.yaml") (lib.attrNames otherHosts)
  );

  secretsFile = inputs.self + "/secrets/${gitlabHost}-runtime.yaml";
  encryptedKeys = "\n" + builtins.readFile secretsFile;
  secretNames = [
    "gitlab-active-record-encryption-deterministic-key"
    "gitlab-active-record-encryption-key-derivation-salt"
    "gitlab-active-record-encryption-primary-key"
    "gitlab-db-key-base"
    "gitlab-initial-root-password"
    "gitlab-openid-connect-signing-key"
    "gitlab-otp-key-base"
    "gitlab-secret-key-base"
  ];
  gitlabFiles = with host.services.gitlab; [
    initialRootPasswordFile
    secrets.secretFile
    secrets.otpFile
    secrets.dbFile
    secrets.jwsFile
    secrets.activeRecordPrimaryKeyFile
    secrets.activeRecordDeterministicKeyFile
    secrets.activeRecordSaltFile
  ];
  units = [
    "gitlab"
    "gitlab-workhorse"
    "gitaly"
    "gitlab-sidekiq"
    "gitlab-config"
    "gitlab-db-config"
    "gitlab-postgresql"
    "gitlab-backup"
    "gitlab-proxy"
  ];
  backupTarget = host.nori.backupTargets.${inventory.backup.targetName};
  restic = host.systemd.services."restic-backups-gitlab-${inventory.backup.targetName}";

  # The one cloudflared tunnel in the repository lists its ingress in this
  # file. GitLab must not appear in it.
  tunnelSource = builtins.readFile (inputs.self + "/src/services/mcp-origin-tunnel/nixos.nix");
  runbook = builtins.readFile (inputs.self + "/docs/runbooks/gitlab-authority.md");

  # Placement: one host. Every other host stays free of the service.
  placedOnOneHost =
    lib.length workload.hosts == 1
    && host.services.gitlab.enable
    && lib.all (other: !other.config.services.gitlab.enable) (lib.attrValues otherHosts)
    && !(lib.elem "gitlab" inventory.hosts.pi.workloads);

  # No endpoint means no Pi route, Pi-hole record, Gatus probe or DDNS name, and
  # nothing that could reach the LAN or the internet. The listener is private.
  noProjection =
    workload.endpoints == { }
    && !(lib.any (route: route.workload == "gitlab") (lib.attrValues inventory.routes))
    && !(lib.hasInfix "gitlab" (builtins.toJSON inputs.self.lib.noriPiInventory))
    && port == 8929
    && !(host.services.cloudflared.enable or false)
    && !(lib.hasInfix "gitlab" tunnelSource)
    && !(lib.hasInfix (toString port) tunnelSource);

  # The port opens on tailscale0 only; the global list holds SSH alone. No
  # firewall range, global or per interface, may cover the port either.
  tailnetOnlyFirewall =
    lib.elem port host.networking.firewall.interfaces."tailscale0".allowedTCPPorts
    && !(lib.elem port host.networking.firewall.allowedTCPPorts)
    && !(inRanges host.networking.firewall.allowedTCPPortRanges)
    &&
      lib.all
        (
          interface:
          !(lib.elem port host.networking.firewall.interfaces.${interface}.allowedTCPPorts)
          && !(inRanges host.networking.firewall.interfaces.${interface}.allowedTCPPortRanges)
        )
        (
          lib.filter (interface: interface != "tailscale0") (
            lib.attrNames host.networking.firewall.interfaces
          )
        )
    && host.services.redis.servers.gitlab.port == 0
    && !host.services.gitlab.registry.enable
    && !host.services.gitlab.pages.enable
    && !host.services.gitlab.smtp.enable
    && !host.services.gitlab.https
    && lib.elem "gitlab" host.services.openssh.settings.DenyUsers;

  # Secrets: each one is a key of the host's own encrypted file, readable only
  # by the gitlab account, and reaches GitLab as a /run/secrets path. No other
  # host receives them.
  secretsBoundary =
    lib.all (
      name:
      lib.hasInfix "\n${name}: ENC[" encryptedKeys
      && host.sops.secrets.${name}.sopsFile == secretsFile
      && host.sops.secrets.${name}.owner == "gitlab"
      && host.sops.secrets.${name}.mode == "0400"
      && host.sops.secrets.${name}.restartUnits == [ ]
    ) secretNames
    && lib.all (path: lib.hasPrefix "/run/secrets/" path) gitlabFiles
    && lib.length (lib.unique gitlabFiles) == lib.length secretNames
    && lib.all (other: !(lib.any (lib.hasPrefix "gitlab-") (lib.attrNames other.config.sops.secrets))) (
      lib.attrValues otherHosts
    )
    && lib.all (file: !(lib.hasInfix "\ngitlab-" ("\n" + builtins.readFile file))) otherSecretFiles
    && host.services.gitlab.extraConfig.gitlab.usage_ping_enabled == false;

  # Backup: the recovery contract names an active job whose archive holds the
  # database and repositories, is refreshed by every restic run, and is checked.
  backupBoundary =
    workload.recovery == {
      model = "application-export";
      backupJob = "gitlab";
    }
    && host.nori.backups.${workload.recovery.backupJob}.include == [ host.services.gitlab.backup.path ]
    && host.nori.backups.gitlab.tier == "irreplaceable"
    && host.systemd.services.gitlab-backup.environment.BACKUP == "dump"
    && host.systemd.services.gitlab-backup.serviceConfig.RemainAfterExit == false
    && host.systemd.services.gitlab-backup.unitConfig.OnFailure == [ "notify@gitlab-backup.service" ]
    && lib.elem "gitlab-backup.service" restic.requires
    && lib.elem "gitlab-backup.service" restic.after
    && lib.hasInfix "${backupTarget.repository}/gitlab" host.systemd.services.restic-check-weekly.script
    && lib.all (other: !(other.config.nori.backups ? gitlab)) (lib.attrValues otherHosts);

  # Hardening: every unit the module defines carries the shared baseline.
  hardened = lib.all (unit: host.nori.harden ? ${unit}) units;

  # PostgreSQL 17 is GitLab 19's minimum; the shared instance must satisfy it.
  databaseVersion = lib.versionAtLeast host.services.postgresql.package.version "17";

  /*
    GitLab must be upgraded through documented stops (19.2, 19.5, 19.8, 19.11:
    https://docs.gitlab.com/19.3/update/upgrade_paths/). A nixpkgs bump moves
    the minor version silently and can skip a stop, which corrupts migrations
    on a populated database. A new minor fails here until the operator has read
    docs/runbooks/gitlab-authority.md § Upgrades and records it. Patch releases
    pass.
  */
  acknowledgedMinor = "19.3";
  installedVersion = host.services.gitlab.packages.gitlab.version;
  upgradePathAcknowledged = lib.versions.majorMinor installedVersion == acknowledgedMinor;

  # The runbook names the host, listener and secrets file of the placement. Moving
  # GitLab fails here until those three rows follow. The activation and backup
  # transport rows are prose that nothing checks.
  runbookStatesPlacement =
    lib.hasInfix "| Host | `${gitlabHost}` |" runbook
    && lib.hasInfix "| Listener | `${tailnetIp}:${toString port}` |" runbook
    && lib.hasInfix "| Secrets file | `secrets/${gitlabHost}-runtime.yaml` |" runbook;

  # The NixOS-typed projection must accept every workload the compiler
  # publishes. A manifest attribute without an option (as `recovery` once was)
  # only fails when a module reads that workload.
  projectionAcceptsEveryWorkload = lib.all (
    name:
    (builtins.tryEval (builtins.deepSeq nixosHosts.${name}.config.nori.inventory.workloads true))
    .success
  ) (lib.attrNames nixosHosts);
in
if
  placedOnOneHost
  && noProjection
  && tailnetOnlyFirewall
  && secretsBoundary
  && backupBoundary
  && hardened
  && databaseVersion
  && upgradePathAcknowledged
  && runbookStatesPlacement
  && projectionAcceptsEveryWorkload
then
  "ok — GitLab runs on ${gitlabHost} only, has no public or LAN projection, and its secrets, backup and hardening are declared"
else
  throw ''
    GitLab authority-plane contract failed (host ${gitlabHost}).
    Placement:       ${toString placedOnOneHost}
    No projection:   ${toString noProjection}
    Tailnet-only:    ${toString tailnetOnlyFirewall}
    Secrets:         ${toString secretsBoundary}
    Backup:          ${toString backupBoundary}
    Hardening:       ${toString hardened}
    PostgreSQL >=17: ${toString databaseVersion}
    Upgrade path:    ${toString upgradePathAcknowledged} (installed ${installedVersion}, acknowledged minor ${acknowledgedMinor}; see docs/runbooks/gitlab-authority.md § Upgrades)
    Runbook:         ${toString runbookStatesPlacement} (the placement table of docs/runbooks/gitlab-authority.md must name the host, listener and secrets file)
    Projection:      ${toString projectionAcceptsEveryWorkload}
  ''
