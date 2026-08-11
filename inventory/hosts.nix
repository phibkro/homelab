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
      "log-forwarder"
      "media-compute"
      "observability-agent"
    ];
    workloads = [
      "blocky"
      "btrbk-replica-target"
      "clamor"
      "disk-alert"
      "gatus"
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
      roleOneLiner = "sleep-friendly compute";
      codename = "emperor";
      hardware = "Ryzen 5600X · 32 GB DDR4 · RTX 5060 Ti 16 GB (Blackwell) · WD SN750 1 TB NVMe + Corsair MP510 960 GB NVMe + Seagate IronWolf Pro 4 TB (USB)";
      primaryJob = ''
        GPU services (Ollama / Jellyfin NVENC), `*arr` stack +
        qBittorrent, `@downloads` + `@streaming` on the IronWolf,
        daily-driver desktop. Cold replica of `/mnt/family/*` on
        MP510 (btrbk receive endpoint). WoL-wake when media access
        happens.
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

  pavilion = {
    kind = "nixos";
    systemModule = ../modules/machines/pavilion;
    homeModule = ../modules/machines/pavilion/home.nix;
    profiles = [
      "base"
      "agent-host"
      "log-forwarder"
      "observability-agent"
    ];
    workloads = [ ];
    identity = {
      tailnetIp = "100.93.230.66";
      lanIp = null;
      role = "agent";
      roleOneLiner = "";
      codename = "pavilion";
      hardware = "HP Pavilion g6 · AMD Athlon II · BIOS+GRUB · btrfs-rollback root (impermanence)";
      primaryJob = ''
        Agent quarantine — nixpkgs-agent / sandboxed Claude and
        Codex work, headless. Planned weekly tertiary replica
        of `/mnt/family/*` (P16).
      '';
    };
  };

  aurora = {
    kind = "nixos";
    systemModule = ../modules/machines/aurora;
    homeModule = ../modules/machines/aurora/home.nix;
    profiles = [
      "base"
      "family-vault"
      "log-forwarder"
      "research"
      "observability-agent"
    ];
    workloads = [
      "ntfy-notify"
      "nvidia-gpu-exporter"
    ];
    identity = {
      tailnetIp = "100.101.67.111";
      lanIp = null;
      role = "workhorse";
      roleOneLiner = "always-on family vault";
      codename = "aurora";
      hardware = "Asus N552V · Intel Skylake-H i7-6700HQ · 12 GB DDR4 · NVIDIA GTX 950M (legacy_535) · Toshiba HDD + OneTouch USB";
      primaryJob = ''
        Family vault: `/mnt/family/{photos,home-videos,projects,library,archive}`
        on the Toshiba HDD + family-tier service backends
        (Vaultwarden, Radicale, Miniflux, Immich full stack + ML,
        Calibre-web, Komga, Navidrome, Glance, Heim, Filmder,
        Grafana). Samba shares for `/mnt/family/*`. OneTouch
        restic vault. Always-on so it survives workstation's
        sleep / outage.
      '';
    };
  };
}
