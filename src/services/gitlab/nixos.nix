{
  config,
  lib,
  pkgs,
  ...
}:

let
  inventory = config.nori.inventory;
  cfg = config.services.gitlab;

  httpPort = inventory.workloads.gitlab.listeners.http.port;
  tailnetIp = inventory.hosts.${inventory.currentHost}.tailnetIp;

  # The nixpkgs module serves Workhorse on this unix socket only.
  workhorseSocket = "/run/gitlab/gitlab-workhorse.socket";

  # Every secret is a key in the host's default SOPS file. GitLab reads each
  # one through `gitlab-config.service`, which runs as the `gitlab` user.
  secretNames = {
    initialRootPassword = "gitlab-initial-root-password";
    secretKeyBase = "gitlab-secret-key-base";
    otpKeyBase = "gitlab-otp-key-base";
    dbKeyBase = "gitlab-db-key-base";
    openidConnectSigningKey = "gitlab-openid-connect-signing-key";
    activeRecordPrimaryKey = "gitlab-active-record-encryption-primary-key";
    activeRecordDeterministicKey = "gitlab-active-record-encryption-deterministic-key";
    activeRecordKeyDerivationSalt = "gitlab-active-record-encryption-key-derivation-salt";
  };
  secretPath = name: config.sops.secrets.${name}.path;

  proxyConfig = pkgs.writeText "gitlab-proxy.Caddyfile" ''
    {
      admin off
      auto_https off
    }

    # Loopback and the tailnet address are the only listeners. Workhorse
    # itself has no TCP socket.
    http://:${toString httpPort} {
      bind 127.0.0.1 ${tailnetIp}
      reverse_proxy unix/${workhorseSocket}
    }
  '';
in
{
  /*
    GitLab CE as the canonical Git store ("authority plane"). It has no public
    projection: no Cloudflare ingress, no public DNS, no Pi Caddy route. HTTP
    listens on loopback and the tailnet address; Git over SSH is off.

    === Bootstrap (after the first activation) ===
    Follow docs/runbooks/gitlab-authority.md: sign in as `root` with the value
    stored under `gitlab-initial-root-password`, close sign-ups, create the
    project, protect `main` and the `kwyne/seal/*` tags, and issue the
    sealer's project access token.

    === Secrets ===
    The eight values below are generated once and live in SOPS. The Rails keys
    encrypt columns in the database: never regenerate them for an instance
    that holds data. Restoring a backup needs the same values.

    === PostgreSQL ===
    `databaseCreateLocally` reuses the host's PostgreSQL instance and adds a
    `gitlab` role and database beside the other applications. GitLab 19 needs
    PostgreSQL 17 or newer; the module asserts that.
  */

  sops.secrets = lib.mapAttrs' (
    _: name:
    lib.nameValuePair name {
      owner = cfg.user;
      mode = "0400";
    }
  ) secretNames;

  services.gitlab = {
    enable = true;
    statePath = "/var/lib/gitlab";

    # Copy-paste URLs use the MagicDNS name, as Sunshine's origin does.
    host = "${config.networking.hostName}.saola-matrix.ts.net";
    port = httpPort;
    https = false;

    initialRootPasswordFile = secretPath secretNames.initialRootPassword;
    secrets = {
      secretFile = secretPath secretNames.secretKeyBase;
      otpFile = secretPath secretNames.otpKeyBase;
      dbFile = secretPath secretNames.dbKeyBase;
      jwsFile = secretPath secretNames.openidConnectSigningKey;
      activeRecordPrimaryKeyFile = secretPath secretNames.activeRecordPrimaryKey;
      activeRecordDeterministicKeyFile = secretPath secretNames.activeRecordDeterministicKey;
      activeRecordSaltFile = secretPath secretNames.activeRecordKeyDerivationSalt;
    };

    /*
      GitLab sends Service Ping to GitLab Inc. unless disabled. The setting is
      documented under "Through the configuration file" in
      https://docs.gitlab.com/administration/settings/usage_statistics/
    */
    extraConfig.gitlab.usage_ping_enabled = false;
  };

  /*
    Resource reasoning. GitLab's requirements page (19.3) names 8 vCPU and
    16 GB as the single-node baseline and 8 GB as the floor for a
    memory-constrained node, and says not to rely on swap. Adelie has 6 cores
    and 32 GB, and its other tenants (Grafana, Miniflux, Radicale, Vaultwarden)
    are small. It also carries the graphical-desktop profile, so a remote
    Plasma or Hyprland session can take memory from GitLab. This instance
    serves two identities and a few pushes a day: Puma (2 workers) and Sidekiq
    keep the module defaults. Read per-process RSS from process-exporter
    before capping system-gitlab.slice (the MemoryHigh item of docs/roadmap.md
    describes the method).
  */

  /*
    Workhorse listens on a unix socket only, so this Caddy instance is the one
    network listener. It mirrors the Hindsight origin proxy: loopback plus the
    tailnet address, nothing else. The bind fails until tailscale0 holds its
    address; the shared restart policy retries it with backoff.
  */
  systemd.services.gitlab-proxy = {
    description = "GitLab HTTP listener on loopback and the tailnet address";
    wantedBy = [ "gitlab.target" ];
    partOf = [ "gitlab.target" ];
    wants = [ "tailscaled.service" ];
    after = [
      "tailscaled.service"
      "gitlab-workhorse.service"
    ];
    environment = {
      XDG_CONFIG_HOME = "/run/gitlab-proxy";
      XDG_DATA_HOME = "/run/gitlab-proxy";
    };
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      RuntimeDirectory = "gitlab-proxy";
      ExecStart = "${pkgs.caddy}/bin/caddy run --config ${proxyConfig} --adapter caddyfile";
      Restart = "on-failure";
      ProtectSystem = "strict";
    };
  };

  # Open the port on the tailnet interface only; LAN and WAN stay closed.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ httpPort ];

  /*
    GitLab writes SSH keys of its users into the `gitlab` account's
    authorized_keys. The host's sshd listens on every interface, so a key added
    in the UI would expose Git over SSH to the LAN. The authority plane pushes
    over HTTP with a token; refuse SSH logins for the account.
  */
  services.openssh.settings.DenyUsers = [ cfg.user ];

  nori.harden.gitlab = { };
  nori.harden.gitlab-workhorse = { };
  nori.harden.gitaly = { };
  nori.harden.gitlab-sidekiq = { };
  nori.harden.gitlab-config = { };
  nori.harden.gitlab-db-config = { };
  nori.harden.gitlab-postgresql = { };
  nori.harden.gitlab-backup = { };
  nori.harden.gitlab-proxy = { };

  /*
    Pattern B (application-native export). `gitlab:backup:create` writes the
    database and every repository into one archive while GitLab runs (the unit
    binds to gitlab.service). It does not back up Redis, so the export is
    consistent when no Sidekiq job is pending or running (backup guide, "Other
    data"); a daily run beside one automated writer meets that. A fixed name
    keeps one file that every run replaces; restic keeps the history. The
    archive does not contain the secrets above, which live in SOPS.

    The nixpkgs unit is a oneshot with RemainAfterExit, so it would run once
    per boot and then ignore later starts. Without that flag every start runs,
    like postgresqlBackup. The restic unit depends on it, so every Restic run
    copies a fresh export and fails when the export fails.
  */
  systemd.services.gitlab-backup = {
    environment.BACKUP = "dump";
    serviceConfig.RemainAfterExit = lib.mkForce false;
    # A oneshot gets no shared OnFailure default, and a failed export only
    # blocks the restic unit that requires it. Alert on the export itself.
    unitConfig.OnFailure = [ "notify@gitlab-backup.service" ];
  };

  systemd.services."restic-backups-gitlab-${inventory.backup.targetName}" =
    lib.mkIf config.nori.backupDelivery.enable
      {
        requires = [ "gitlab-backup.service" ];
        after = [ "gitlab-backup.service" ];
      };

  nori.backups.gitlab = {
    include = [ cfg.backup.path ];
    tier = "irreplaceable";
    timer = "*-*-* 04:00:00";
  };
}
