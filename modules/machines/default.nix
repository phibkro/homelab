{
  lib,
  inputs,
}:

/**
  Machine registry + `nixosConfigurations` factory.

  Four persistent NixOS hosts on a single residential network plus a
  Mac on standalone home-manager. Roles are typed; placement assertions
  enforce them (see `modules/infra/backup/default.nix`); cross-host refs
  go through `nori.hosts` registry — never IP literals.

  ## Topology

  ```mermaid
  graph TB
    subgraph "appliance tier"
      P[pi<br/>entry plane: Caddy + Authelia + Blocky<br/>+ observability + alert + Tailscale]
    end
    subgraph "workhorse tier"
      A[aurora<br/>family vault + family-tier backends]
      W[workstation<br/>GPU + arr stack + downloads<br/>+ cold replica of /mnt/family]
    end
    subgraph "agent tier"
      V[pavilion<br/>quarantined agents]
    end
    M[macbook<br/>daily-driver]
    P -- "*.${nori.domain} proxy" --> A
    P -- "*.${nori.domain} proxy" --> W
    W -- "nightly btrfs send/receive" --> W
    A -- "scraped by" --> P
    W -- "scraped by" --> P
    V -- "scraped by" --> P
    P -- "ntfy.sh public<br/>heartbeat to hc.io" --> Internet[Internet]
    M -. "SSH" .-> P
    M -. "SSH" .-> A
    M -. "SSH" .-> W
  ```

  Failure domain independence: each host shares no storage, no PSU, no
  critical boot-path dependency with the others. Any single failure does
  not block the rest.

  ## Service-implicit-until-lan-route'd (the tier principle)

  A service has three concerns: registration (it exists), state (it
  persists data), location (it runs on host X). For services confined to
  one host, **location is implicit from the import site**:

  ```
  modules/machines/aurora/default.nix imports modules/services/vaultwarden.nix
                              ⇒ vaultwarden runs on aurora
  ```

  The service doesn't declare a host. The fact that aurora's module list
  pulls it in IS the location declaration. No explicit `runsOn`, no
  cross-host wiring.

  **Location becomes explicit when a service crosses machines.** That
  happens through `nori.lanRoutes.<X>.runsOn`, which names the host
  backing a route. `runsOn` lives on lan-route not by convenience — but
  because the act of exposing a service via HTTP IS the act of declaring
  location-needs-resolving. Pre-exposure, location is implicit; at
  exposure, location is the cross-machine answer the proxy needs.

  ```
    declaration      state      location          cross-machine?
    ─────────────────────────────────────────────────────────────────
    packages         none       anywhere          N/A (stateless)
    services         local      implicit (import) opt-in via lan-route
    distributed      local +    EXPLICIT —        N/A (already is)
    services         binding    runsOn host(s)
  ```

  Today `runsOn` is a single host string. Forward shape (not in tree
  yet but pre-named): a list with a semantic tag — `failover` (sum),
  `loadbalance` (product), `sequential` (ordered sum). Rule of three:
  extract when a second service genuinely needs multi-host routing.

  ## How this module works

  Two explicit maps form the single source of truth:

   - `nixosMachines`     — NixOS hosts the flake builds, name → folder path
   - `standaloneHomes`   — non-NixOS machines (Mac) that ride home-manager
                           standalone, name → home.nix path
   - `identityFor`       — per-host identity facts (tailnet/lan IPs, role,
                           hardware, primaryJob); keys MUST equal those of
                           `nixosMachines`. Asserted eval-time below.

  Adding a NixOS host: add the entry to BOTH `nixosMachines` AND
  `identityFor`. The key-set assertion fails eval if one is missing,
  preserving the "no parallel identifier to keep in sync" property the
  old readDir-driven enumeration had — but explicit instead of magic.

  Schema: `modules/infra/hosts.nix`.

  Consumers (cross-host refs):

   - `modules/infra/networking/default.nix`     — `nori.lanIp` default
   - `modules/infra/backup/default.nix`         — host-aware appliance assertion
   - `modules/infra/observability/beszel/agent.nix` — metrics route backend
   - `modules/infra/observability/ntfy/notify.nix`  — alert route backend
   - `modules/machines/workstation/default.nix` — Pi probe URLs
*/

let
  nixosMachines = {
    workstation = ./workstation;
    pi = ./pi;
    pavilion = ./pavilion;
    aurora = ./aurora;
  };

  standaloneHomes = {
    macbook = ./macbook/home.nix;
  };

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
      `modules/machines/pavilion/default.nix` for the impermanence /
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

  /*
    Key-set assertion: every key in nixosMachines must have a matching
    identityFor entry and vice versa. Replaces the readDir-driven
    eval-fail behaviour with an explicit, single-line check.
  */
  machineKeys = lib.attrNames nixosMachines;
  identityKeys = lib.attrNames identityFor;
  missingIdentity = lib.subtractLists identityKeys machineKeys;
  missingMachine = lib.subtractLists machineKeys identityKeys;

  hostRegistry = lib.mapAttrs (_: id: id) identityFor;

  /**
    Build a `nixosSystem` for a host entry.

    Wraps `lib.nixosSystem` with three injections every host needs:

     - `specialArgs.inputs` so machine modules can reach flake
       inputs without re-importing.
     - `networking.hostName` set from the registry key — keys,
       hostnames, and module imports all derive from the same
       string. No parallel identifier to keep in sync.
     - `nori.hosts = hostRegistry` so cross-host references
       (`config.nori.hosts.<other>.tailnetIp`) resolve on every
       host's eval.
  */
  mkHost =
    name: path:
    lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        path
        {
          config.networking.hostName = name;
          config.nori.hosts = hostRegistry;
        }
      ];
    };
in
assert (
  lib.assertMsg (missingIdentity == [ ])
    "modules/machines/default.nix: nixosMachines has key(s) ${toString missingIdentity} with no identityFor entry"
);
assert (
  lib.assertMsg (missingMachine == [ ])
    "modules/machines/default.nix: identityFor has key(s) ${toString missingMachine} with no nixosMachines entry"
);
{
  nixosConfigurations = lib.mapAttrs mkHost nixosMachines;
  inherit standaloneHomes;
}
