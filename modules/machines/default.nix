{
  lib,
  inputs,
  machinesPath,
}:

/**
  Machine-enumeration + `nixosConfigurations` factory.

  Reads `machinesPath` (currently `./machines/` at repo root; will be
  `./modules/machines/` after Phase 4 of the modules-as-root
  restructure) to derive the list of machines from the filesystem.
  NixOS machines are those with a `default.nix`; standalone
  home-manager machines (the Mac) only have `home.nix`.

  Identity metadata (tailnet/lan IPs, role, hardware, primaryJob) is
  indexed by NixOS host name in `identityFor` below — non-NixOS
  machines aren't in the registry because nothing in the NixOS
  module system references them. The `genAttrs` lookup forces every
  NixOS host folder to have an identity entry — a folder without
  identity fails eval; an identity entry without a folder is
  silently dead code (caught by code review).

  Schema: `modules/effects/hosts.nix`.

  Consumers (cross-host refs):

   - `modules/infra/networking/default.nix`     — `nori.lanIp` default
   - `modules/infra/backup/default.nix`  — host-aware appliance assertion
   - `modules/infra/observability/beszel/agent.nix` — metrics route backend
   - `modules/infra/observability/ntfy/notify.nix`  — alert route backend
   - `machines/workstation/default.nix`  — Pi probe URLs

  Topology change = edit `identityFor`, redeploy. Adding a NixOS
  host = `mkdir machines/<n> && touch machines/<n>/{default,hardware}.nix`
  plus an `identityFor` entry — eval errors on either omission.
  Adding a non-NixOS machine = `mkdir machines/<n> && touch
  machines/<n>/home.nix` (no `default.nix`; not in `identityFor`).
*/

let
  machineNames = lib.attrNames (
    lib.filterAttrs (_: t: t == "directory") (builtins.readDir machinesPath)
  );

  # NixOS machines are those with a default.nix. Drives both
  # nixosConfigurations enumeration and the host registry.
  nixosMachineNames = lib.filter (
    n: builtins.pathExists (machinesPath + "/${n}/default.nix")
  ) machineNames;

  identityFor = {
    workstation = {
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
    pi = {
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
    /**
      Pavilion — HP g6 retasked as the agent quarantine host.
      Tailnet IP fills in after first `tailscale up`; lan stays null
      since the device roams (no static DHCP reservation). See
      `machines/pavilion/default.nix` for the impermanence /
      agent-role posture. Sits under `tag:agent` in the Tailscale
      ACL — can reach workhorse :11434 (ollama) only; cannot SSH
      any privileged-tier host.
    */
    pavilion = {
      tailnetIp = "100.93.230.66";
      lanIp = null; # roams; no static DHCP lease
      role = "agent";
      roleOneLiner = "";
      codename = "pavilion"; # hostname-equal — "pavilion" already evokes the polar/exploration theme
      hardware = "HP Pavilion g6 · AMD Athlon II · BIOS+GRUB · btrfs-rollback root (impermanence)";
      primaryJob = ''
        Agent quarantine — hermes / nixpkgs-agent / sandboxed
        claude work, headless. Planned weekly tertiary replica
        of `/mnt/family/*` (P16).
      '';
    };
    /**
      Aurora — retired Asus N552V gaming laptop (i7-6700HQ, 12 GB
      RAM, GTX 950M, dead battery). Repurposed as a single-role
      immich machine-learning offload host so workstation's 5060 Ti
      stays dedicated to ollama. Classified workhorse — has GPU,
      has compute, hosts a service — but it's a *minimal* workhorse;
      if a second compute-offload host ever appears, that's the
      rule-of-three signal to extract a dedicated `compute` role.
    */
    aurora = {
      tailnetIp = "100.101.67.111";
      lanIp = null; # wifi-only, no static lease
      role = "workhorse";
      roleOneLiner = "always-on family vault";
      codename = "aurora"; # already polar
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

  hostRegistry = lib.genAttrs nixosMachineNames (n: identityFor.${n});

  /**
    Build a `nixosSystem` for a host folder.

    Wraps `lib.nixosSystem` with three injections every host needs:

     - `specialArgs.inputs` so machine modules can reach flake
       inputs without re-importing.
     - `networking.hostName` set from the folder name — the
       folder is the SoT; registry keys, hostnames, and module
       imports all derive from the same string. No parallel
       identifier to keep in sync.
     - `nori.hosts = hostRegistry` so cross-host references
       (`config.nori.hosts.<other>.tailnetIp`) resolve on every
       host's eval.

    Called once per entry in `nixosMachineNames` via `genAttrs`;
    not exported for external consumers.

    # Inputs

    `name`

    : Host folder name under `machinesPath`. Must exist as a
      directory with a `default.nix`. Drives both the module
      import path and `config.networking.hostName`.

    # Type

    ```
    mkHost :: String -> nixosSystem
    ```
  */
  mkHost =
    name:
    lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        (machinesPath + "/${name}")
        {
          config.networking.hostName = name;
          config.nori.hosts = hostRegistry;
        }
      ];
    };
in
{
  nixosConfigurations = lib.genAttrs nixosMachineNames mkHost;
}
