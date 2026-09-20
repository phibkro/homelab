/*
  Physical host inventory.

  Platform realization and deployment commands are compiler-private. `identity`,
  profile selection, and placement tags form the public-safe control-plane input.
*/
{
  adelie = {
    kind = "nixos";
    managementRoot = "infra/adelie";
    additionalSourceRoots = [ ];
    systemModule = ../infra/adelie;
    homeModule = ../users/nori/adelie.nix;
    profiles = [
      "base"
      "log-forwarder"
      "remote-backup-source"
      "observability-agent"
    ];
    tags = [
      "application-service-host"
      "gpu-host"
      "nas"
      "nixos"
    ];
    identity = {
      tailnetIp = "100.107.90.3";
      lanIp = null;
      role = "workhorse";
      roleOneLiner = "SSD-local application host";
      codename = "adelie";
      hardware = "Node 304 · Ryzen 5 5600X · 16 GB DDR4 · RTX 2060 Super · Samsung 990 Pro 1 TB NVMe";
      primaryJob = ''
        SSD-local application backends: Attic, Filmder, Grafana, Heim,
        Miniflux, Radicale, Stremio, and Vaultwarden. Each stateful service
        backs up to its own restricted repository on the workstation-attached
        OneTouch disk. Media and portable disks remain on workstation.
      '';
    };
    capabilities = {
      "nori.capabilities.Compute" = {
        architecture = "x86_64";
        cores = 6;
        memoryBytes = 17179869184;
      };
      "nori.capabilities.GpuCompute" = {
        backend = "cuda";
        vendor = "nvidia";
        vramBytes = 8589934592;
      };
      "nori.capabilities.PersistentStorage" = {
        class = "local";
      };
    };
  };

  workstation = {
    kind = "nixos";
    managementRoot = "infra/workstation";
    additionalSourceRoots = [
      "services/bazarr"
      "services/jellyseerr"
      "services/lidarr"
      "services/prowlarr"
      "services/qbittorrent"
      "services/radarr"
      "services/recyclarr"
      "services/sonarr"
    ];
    systemModule = ../infra/workstation;
    homeModule = ../users/nori/home.nix;
    profiles = [
      "base"
      "backup-source"
      "desktop"
      "family-vault"
      "log-forwarder"
      "media-compute"
      "observability-agent"
      "research"
    ];
    tags = [
      "desktop"
      "large-gpu"
      "nixos"
      "primary-service-host"
    ];
    identity = {
      tailnetIp = "100.81.5.122";
      lanIp = "192.168.1.181";
      role = "workhorse";
      roleOneLiner = "desktop, media, and storage host";
      codename = "emperor";
      hardware = "Ryzen 9 5950X · 64 GB DDR4 · RTX 5060 Ti 16 GB (Blackwell) · WD SN750 1 TB NVMe + Corsair MP510 960 GB NVMe + Seagate IronWolf Pro 4 TB SATA";
      primaryJob = ''
        Graphical workstation, GPU services, media acquisition and playback,
        and Samba shares on the attached IronWolf disk. It publishes
        re-derivable Nix paths to Adelie's Attic cache. OneTouch receives
        independent Restic history from both workhorses; same-disk snapshots
        provide local rollback for workstation datasets.
      '';
    };
    capabilities = {
      "nori.capabilities.Compute" = {
        architecture = "x86_64";
        cores = 16;
        memoryBytes = 68719476736;
      };
      "nori.capabilities.GpuCompute" = {
        backend = "cuda";
        vendor = "nvidia";
        vramBytes = 17179869184;
      };
      "nori.capabilities.PersistentStorage" = {
        class = "local";
      };
    };
  };

  pi = {
    kind = "ansible";
    managementRoot = "infra/pi";
    additionalSourceRoots = [
      "infra/common/ansible"
      "services/authelia/ansible"
      "services/beszel/ansible/agent"
      "services/beszel/ansible/hub"
      "services/caddy/ansible"
      "services/cloudflare-ddns/ansible"
      "services/gatus/ansible"
      "services/glance/ansible"
      "services/heartbeat/ansible"
      "services/ntfy/ansible"
      "services/pihole/ansible"
      "services/restic-backup/ansible"
      "services/tailscale/ansible"
      "services/vector/ansible"
      "services/victorialogs/ansible"
      "services/victoriametrics/ansible"
    ];
    deployment = {
      planCommand = "just pi::plan";
      applyCommand = "just pi::deploy";
      verifyCommand = "just pi::check";
    };
    profiles = [
      "base"
      "entry-plane"
      "log-forwarder"
    ];
    tags = [ "entry-plane" ];
    identity = {
      tailnetIp = "100.100.71.3";
      lanIp = "192.168.1.225";
      role = "appliance";
      roleOneLiner = "always-on entry plane";
      codename = "fairy";
      hardware = "Raspberry Pi 4 8 GB · aarch64 · 32 GB SD boot";
      primaryJob = ''
        HTTP entry plane (Caddy + Authelia + Pi-hole and the LE wildcard
        certificate on `*.''${nori.domain}`), Glance home page, observability
        hub, alert plane, and Tailscale subnet router and exit node.
      '';
    };
    capabilities = {
      "nori.capabilities.Compute" = {
        architecture = "aarch64";
        cores = 4;
        memoryBytes = 8589934592;
      };
      "nori.capabilities.PersistentStorage" = {
        class = "local";
      };
    };
  };

}
