/*
  Physical host inventory.

  `systemModule` is compiler-private. `identity`, profile selection, and direct
  workload additions form the public-safe control-plane input. Direct additions
  represent genuine host deviations from a reusable profile; they are not an
  escape hatch for implicit tag activation.
*/
{
  workstation = {
    kind = "nixos";
    systemModule = ../modules/machines/workstation;
    homeModule = ../modules/machines/workstation/home.nix;
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
    workloads = [
      "clamor"
      "disk-alert"
      "herdr-projects-mcp"
      "hindsight"
      "mcp-origin-tunnel"
      "ntfy-notify"
      "nvidia-gpu-exporter"
    ];
    identity = {
      tailnetIp = "100.81.5.122";
      lanIp = "192.168.1.181";
      role = "workhorse";
      roleOneLiner = "always-on converged desktop/server";
      codename = "emperor";
      hardware = "Ryzen 5600X · 32 GB DDR4 · RTX 5060 Ti 16 GB (Blackwell) · WD SN750 1 TB NVMe + Corsair MP510 960 GB NVMe + Seagate IronWolf Pro 4 TB USB";
      primaryJob = ''
        Always-on graphical workstation and homelab server:
        GPU services (Ollama / Jellyfin NVENC), `*arr` stack +
        qBittorrent, family services and Samba shares on the attached
        IronWolf disk. Backups write locally to the MP510 and
        off-host to Aurora's OneTouch restic vault.
      '';
    };
  };

  pi = {
    kind = "nixos";
    systemModule = ../modules/machines/pi;
    homeModule = ../modules/machines/pi/home.nix;
    profiles = [
      "base"
      "entry-plane"
      "log-forwarder"
    ];
    workloads = [
      "beszel-agent"
      "ntfy-notify"
    ];
    identity = {
      tailnetIp = "100.100.71.3";
      lanIp = "192.168.1.225";
      role = "appliance";
      roleOneLiner = "always-on entry plane";
      codename = "fairy";
      hardware = "Raspberry Pi 4 8 GB · aarch64 · USB-boot from Samsung FIT 128 GB";
      primaryJob = ''
        HTTP entry plane (Caddy + Authelia + Blocky-authoritative,
        LE wildcard cert on `*.''${nori.domain}`), observability
        hub, alert plane, Tailscale subnet router + exit node.
      '';
    };
  };

  aurora = {
    kind = "nixos";
    systemModule = ../modules/machines/aurora;
    homeModule = ../modules/machines/aurora/home.nix;
    profiles = [
      "base"
      "log-forwarder"
      "observability-agent"
    ];
    workloads = [
      "attic"
      "restic-target"
    ];
    identity = {
      tailnetIp = "100.101.67.111";
      lanIp = null;
      role = "workhorse";
      roleOneLiner = "off-host backup vault";
      codename = "aurora";
      hardware = "Asus N552V · Intel Skylake-H i7-6700HQ · 12 GB DDR4 · NVIDIA GTX 950M (legacy_535) · OneTouch USB";
      primaryJob = ''
        Off-host backup appliance. The chrooted restic SFTP target
        stores workstation backups on the OneTouch HDD, preserving a
        second chassis and power-failure domain.
      '';
    };
  };
}
