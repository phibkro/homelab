---
generated: true
source: flake.nix § packages.docs-topology
regenerate: nix build .#docs-topology
---

# Topology — generated reference

Auto-derived from `nori.hosts` schema + `identityFor` values
in `modules/machines/default.nix`. Do not hand-edit; the
hand-curated overview + diagram + invariants live in
`docs/reference/topology.md`.

## Hosts at a glance

| Host | Codename | Role | Tailnet | LAN | Hardware | Primary job |
|---|---|---|---|---|---|---|
| **aurora** | aurora | `workhorse` (always-on family vault) | `100.101.67.111` | — | Asus N552V · Intel Skylake-H i7-6700HQ · 12 GB DDR4 · NVIDIA GTX 950M (legacy_535) · Toshiba HDD + OneTouch USB | Family vault: `/mnt/family/{photos,home-videos,projects,library,archive}` on the Toshiba HDD + family-tier service backends (Vaultwarden, Radicale, Miniflux, Immich full stack + ML, Calibre-web, Komga, Navidrome, Glance, Heim, Filmder, Grafana). Samba shares for `/mnt/family/*`. OneTouch restic vault. Always-on so it survives workstation's sleep / outage. |
| **pavilion** | pavilion | `agent` | `100.93.230.66` | — | HP Pavilion g6 · AMD Athlon II · BIOS+GRUB · btrfs-rollback root (impermanence) | Agent quarantine — hermes / nixpkgs-agent / sandboxed claude work, headless. Planned weekly tertiary replica of `/mnt/family/*` (P16). |
| **pi** | fairy | `appliance` (always-on entry plane) | `100.100.71.3` | `192.168.1.225` | Raspberry Pi 4 8 GB · aarch64 · USB-boot from Samsung FIT 128 GB | HTTP entry plane (Caddy + Authelia + Blocky-authoritative, LE wildcard cert on `*.${nori.domain}`), observability hub, alert plane, Tailscale subnet router + exit node. |
| **workstation** | emperor | `workhorse` (sleep-friendly compute) | `100.81.5.122` | `192.168.1.181` | Ryzen 5600X · 32 GB DDR4 · RTX 5060 Ti 16 GB (Blackwell) · WD SN750 1 TB NVMe + Corsair MP510 960 GB NVMe + Seagate IronWolf Pro 4 TB (USB) | GPU services (Ollama / Jellyfin NVENC), `*arr` stack + qBittorrent, `@downloads` + `@streaming` on the IronWolf, daily-driver desktop. Cold replica of `/mnt/family/*` on MP510 (btrbk receive endpoint). WoL-wake when media access happens. |

## Registry schema (`nori.hosts.<name>.*`)

What an `identityFor` entry must declare to satisfy the schema.
Schema lives in `modules/infra/hosts.nix`; values live in
`modules/machines/default.nix`.

## nori\.hosts

Topology registry\. Single source of truth for cross-host
references\. Populated in flake\.nix’s ` identityFor ` (driven by
readDir over \./hosts/)\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```

*Declared by:*
 - [/nix/store/\[^/]\*-source/modules/infra/hosts\.nix](file:///nix/store/[^/]*-source/modules/infra/hosts.nix)



## nori\.hosts\.\<name>\.codename



Aesthetic codename for MOTD / dashboards / casual reference\.
The hostname (not the codename) stays the identifier that
SSH / Tailscale / nix flakes know — codename is decoration\.

Theme: cold / polar / penguin\.



*Type:*
string

*Declared by:*
 - [/nix/store/\[^/]\*-source/modules/infra/hosts\.nix](file:///nix/store/[^/]*-source/modules/infra/hosts.nix)



## nori\.hosts\.\<name>\.hardware



One-line hardware identification — chassis · CPU · RAM · GPU
· notable storage\. Drives the hosts-at-a-glance table in
the generated topology doc; not consumed by evaluation\.

Format guidance: model · CPU family · RAM · GPU (if any) ·
storage notes\. Keep terse — the field is a table cell, not
a spec sheet\. Detailed posture lives in modules/machines/\<n>/default\.nix
header comments (anti-write posture, impermanence, etc\.)\.



*Type:*
string

*Declared by:*
 - [/nix/store/\[^/]\*-source/modules/infra/hosts\.nix](file:///nix/store/[^/]*-source/modules/infra/hosts.nix)



## nori\.hosts\.\<name>\.lanIp



Static-DHCP LAN IP, or null\. Used by ops tooling (Justfile
rsync targets) when the tailnet hostname doesn’t resolve —
e\.g\., ` workstation.saola-matrix.ts.net ` from Mac without
tailnet DNS\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [/nix/store/\[^/]\*-source/modules/infra/hosts\.nix](file:///nix/store/[^/]*-source/modules/infra/hosts.nix)



## nori\.hosts\.\<name>\.primaryJob



Multi-clause prose describing what this host does — the
“Primary job” cell in the topology table\. CommonMark
permitted (bullets, inline code, links)\. Keep to a
paragraph; deeper rationale belongs in modules/machines/\<n>/default\.nix
or the relevant ADR\.

Drift policy: when a host’s job changes materially (gains
or loses a service tier), update this string in the same
commit\. The generator surfaces it; the prose-only
topology\.md no longer carries it\.



*Type:*
string

*Declared by:*
 - [/nix/store/\[^/]\*-source/modules/infra/hosts\.nix](file:///nix/store/[^/]*-source/modules/infra/hosts.nix)



## nori\.hosts\.\<name>\.role



Structural role driving placement assertions:

 - ` workhorse ` — heavy compute, state, GPU, large disks\.
   Backed up to local restic\. Today this covers two
   distinct shapes — workstation (GPU + desktop +
   bulk media) and aurora (always-on family vault +
   family-tier backends) — which still share the
   “owns state, can take paths-based backups” properties
   workhorse implies\. **Rule of three**: if a third host
   matches aurora’s always-on-no-desktop shape, extract
   a dedicated ` vault ` (or ` compute `) role then\.

 - ` appliance ` — observability + alerting + DNS + network
   plumbing + HTTP entry plane (Caddy + Authelia +
   Blocky-authoritative)\. Survives workhorse failure\.
   Anti-write storage (no swap, volatile journald, flash)
   → paths-based backups are a build error (assertion in
   modules/infra/backup/default\.nix)\.

 - ` agent ` — untrusted-compute quarantine\. Stateless by
   design: tmpfs root + impermanence /persist\. No GPU
   (inference offloaded to workhorse), no GH credential\.
   ` nori.backups.<X> ` declarations are a build error —
   anything escaping the box sandbox vanishes on reboot\.

Adding a role = extend the enum, document its constraints,
and add the assertions that key off it\.



*Type:*
one of “workhorse”, “appliance”, “agent”

*Declared by:*
 - [/nix/store/\[^/]\*-source/modules/infra/hosts\.nix](file:///nix/store/[^/]*-source/modules/infra/hosts.nix)



## nori\.hosts\.\<name>\.roleOneLiner



Short qualifier appended to the ` role ` cell in the topology
table — disambiguates the role for hosts that share a typed
role but differ in shape (e\.g\. workstation “sleep-friendly
compute” vs aurora “always-on family vault”; both are
` workhorse `)\. Empty string when the role itself is the
full story (pavilion: ` agent `)\.



*Type:*
string

*Declared by:*
 - [/nix/store/\[^/]\*-source/modules/infra/hosts\.nix](file:///nix/store/[^/]*-source/modules/infra/hosts.nix)



## nori\.hosts\.\<name>\.tailnetIp



Tailnet (100\.x\.y\.z) IP\. Stable per device once authed —
survives reboots and re-IPs\. The canonical address for
cross-host references in this flake\.



*Type:*
string

*Declared by:*
 - [/nix/store/\[^/]\*-source/modules/infra/hosts\.nix](file:///nix/store/[^/]*-source/modules/infra/hosts.nix)


