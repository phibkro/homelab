---
generated: true
source: flake.nix § packages.docs-topology
regenerate: nix build .#docs-topology
---

# Topology — generated reference

Auto-derived from the `nori.inventory.hosts` schema + values in
`inventory/hosts.nix`. Do not hand-edit; the hand-curated overview
lives at `docs/reference/topology.md` (kept parallel for the
generated-vs-handwritten coverage experiment).

Typed, read-only projection of the pure pre-evaluation inventory.

Values are injected by `lib/machines.nix`; modules consume this
interface but cannot use it to select imports. Compiler-private module paths
and future artifact handles never enter the projection.

# Inventory host registry — overview {#sec-functions-library-inventory-hosts}




## Per-host hardware posture

## workstation — hardware inventory: `inventory/hosts.nix`

Desktop, media, GPU, and attached storage host:

 - **WD SN750 1 TB NVMe** — root + service and user state (`@`, `@home`,
   `@nix`, `@var-lib`, `@srv-share`, `@srv-nori`, `@snapshots`). disko at `./disko.nix`.
 - **Corsair MP510 960 GB NVMe** — cache and preserved archives at
   `/mnt/backup-local`. disko at `./disko-mp510.nix`.
 - **Seagate IronWolf Pro 4 TB (SATA)** — downloads plus canonical family
   datasets under `/mnt/media/*`. disko at `./disko-media.nix`.

## NVMe enumeration warning

`nvme0n1` was NixOS root at install time; post-reboot the drives
swapped. Disko configs target `/dev/disk/by-id/...` paths because of
this. **Never touch `nvme0n1` without verifying the model and serial against
`/dev/disk/by-id/`.**

## Service posture

Media services, GPU workloads, research tools, and the operator desktop
stay here. Adelie owns the SSD-local application tier. Pi remains the
always-on entry and observability plane. IronWolf stores cold media.
OneTouch stores independent Restic history from both workhorses.

## Sleep + GPU constraint

NVIDIA Blackwell + `suspend-then-hibernate` hangs upstream (systemd
#27559). Workstation uses manual `super+P` lock-then-suspend with
the VRAM-preserve kernel param fix; PipeWire-aware idle inhibit
prevents idle-sleep during ambient sound. Full debt note in
`docs/roadmap.md § Architectural debt`.


## Hosts at a glance

| Host | Managed by | Codename | Role | Tailnet | LAN | Hardware | Primary job |
|---|---|---|---|---|---|---|---|
| **adelie** | `nixos` | adelie | `workhorse` (SSD-local application host) | `100.107.90.3` | — | Node 304 · Ryzen 5 5600X · 16 GB DDR4 · RTX 2060 Super · Samsung 990 Pro 1 TB NVMe | SSD-local application backends: Attic, Grafana, Miniflux, Radicale, Stremio, and Vaultwarden. Each stateful service backs up to its own restricted repository on the workstation-attached OneTouch disk. Media and portable disks remain on workstation. |
| **pi** | `ansible` | fairy | `appliance` (always-on entry plane) | `100.100.71.3` | `192.168.1.225` | Raspberry Pi 4 8 GB · aarch64 · 32 GB SD boot | HTTP entry plane (Caddy + Authelia + Pi-hole and the site wildcard certificate), Glance home page, observability hub, alert plane, and Tailscale subnet router and exit node. |
| **workstation** | `nixos` | emperor | `workhorse` (desktop, media, and storage host) | `100.81.5.122` | `192.168.1.181` | Ryzen 9 5950X · 64 GB DDR4 · RTX 5060 Ti 16 GB (Blackwell) · WD SN750 1 TB NVMe + Corsair MP510 960 GB NVMe + Seagate IronWolf Pro 4 TB SATA | Graphical workstation, GPU services, media acquisition and playback, and Samba shares on the attached IronWolf disk. It publishes re-derivable Nix paths to Adelie's Attic cache. OneTouch receives independent Restic history from both workhorses; same-disk snapshots provide local rollback for workstation datasets. |

## Registry schema (`nori.inventory.hosts.<name>.*`)

What an `inventory/hosts.nix` identity entry must declare to
satisfy the schema. Schema lives in `infra/common/nixos/inventory.nix`.

## nori.inventory.hosts

Public-safe host identity, profile, and resolved workload inventory.



*Type:*
attribute set of (submodule) *(read only)*

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.codename



Human-readable host codename.



*Type:*
string

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.hardware



Human-readable hardware summary.



*Type:*
string

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.kind



Deployment backend selected for the host.



*Type:*
one of “ansible”, “nixos”

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.lanIp



Stable LAN IPv4 address, or null when the host is tailnet-only.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.primaryJob



Primary responsibility of the host.



*Type:*
string

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.profiles



Resolved reusable profiles selected for the host.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.role



Host role used by workload placement constraints.



*Type:*
one of “workhorse”, “appliance”, “agent”, “client”

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.roleOneLiner



Short operator-facing summary of the host role.



*Type:*
string

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.tags



Stable placement capabilities declared by the host.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.tailnetIp



Stable Tailscale IPv4 address, or null when the host is not enrolled.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)



## nori.inventory.hosts.<name>.workloads



Resolved workloads selected for the host.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [<nixpkgs/infra/common/nixos/inventory.nix>](https://github.com/NixOS/nixpkgs/blob//infra/common/nixos/inventory.nix)


