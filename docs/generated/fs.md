---
generated: true
source: flake-parts/packages/docs-fs.nix
regenerate: nix build .#docs-fs
---

# `nori.fs` — generated reference

Two-section artifact: module overview (RFC 145 doc-comments
from the concern's `default.nix`) + per-option schema
(`nixosOptionsDoc` over the eval'd options tree). The
concern file's path is shown in the per-option "Declared by"
lines below.

Storage concern — `nori.fs` (subvol / value-tier policy) +
`nori.replicas` (cross-host replication registry).

`default.nix` carries the `nori.fs` schema + generators;
`replication.nix` carries the cross-host replication verifier.

Both schemas are part of "where data lives + how it's protected"
(the storage half of the PaaS lens). Adapters that ACT on these
schemas live elsewhere:

 - btrfs subvol creation: disko configs per host
 - btrbk send/receive timers: `modules/infra/backup/btrbk*.nix`

# fs concern — overview {#sec-functions-library-fs}


## `homelab.fs.options.nori.fs` {#function-library-homelab.fs.options.nori.fs}

`nori.fs` — named filesystem locations + value-tier metadata.

Collapses subvolume paths that used to be magic strings across
arr binds, jellyfin/immich/komga consumers, and the
restic+btrbk generators. Reader-shaped effect: hosts declare
(alongside disko), services consume by name; backup generators
in `modules/infra/backup/` filter by tier (the Writer-shaped
consequence).

Optional `samba` block — when set, the share follows the drive:
any host whose `nori.fs` declares `samba = { … }` for an entry
emits the corresponding Samba share via the generator below.
When a drive physically moves between hosts (OneTouch → aurora
2026-06-11; future IronWolf moves), the share moves with it
automatically because the `nori.fs.<X>.samba` declaration lives
next to the disko entry.

## `homelab.fs.config` {#function-library-homelab.fs.config}

Writer half of `nori.fs`: hosts that declare any
`nori.fs.<X>.samba` entries emit the corresponding share +
ownership tmpfiles. The samba globals (workgroup, hosts allow,
vfs objects, the firewall rule) live in
`modules/services/samba.nix` on the host that imports it.




## Option schema

## nori.fs

Named filesystem locations declared by the host (typically
alongside disko subvolume definitions) and consumed by service
modules. Each entry pairs a path with a value tier; the tier
drives membership in restic backup repos and snapshot retention.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  downloads   = { path = "/mnt/media/downloads";   tier = "re-derivable"; };
  photos      = { path = "/mnt/media/photos";      tier = "irreplaceable"; };
  share       = { path = "/srv/share";             tier = "user"; };
}

```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.path



Mountpoint or directory path. Single source of truth —
service modules MUST read ` config.nori.fs.<n>.path `
rather than hardcoding the literal.



*Type:*
absolute path

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba



Optional Samba export. When set, the host emits a
corresponding share via the generator below — the
share follows the drive across hosts because the
declaration lives next to the disko entry. The share’s
global hardening (tailnet-only firewall, hosts allow
CIDRs, vfs objects for macOS interop) lives in
modules/services/samba.nix; per-share fields here.

Defaults are picked for the homelab’s single-user
operator + family case: writable, valid user ` nori `,
force ownership to ` nori:users `, 0664/0775 masks.



*Type:*
null or (submodule)



*Default:*

```nix
null
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.createMask



Octal mask applied to newly created files (Samba ` create mask `).



*Type:*
string



*Default:*

```nix
"0664"
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.deleteVetoFiles



When true, lets a directory be removed even
though it contains vetoed dotfiles inside.
Pair with ` vetoFiles ` for the operator-share
UX (delete a folder over SMB without manually
removing its .git first).



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.directoryMask



Octal mask applied to newly created directories (Samba ` directory mask `).



*Type:*
string



*Default:*

```nix
"0775"
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.forceGroup



All file operations execute as this UNIX group (Samba ` force group `).



*Type:*
string



*Default:*

```nix
"users"
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.forceUser



All file operations execute as this UNIX user (Samba ` force user `).



*Type:*
string



*Default:*

```nix
"nori"
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.ownerTmpfilesRule



Whether to emit a systemd-tmpfiles rule asserting
the share’s mount-point ownership matches
forceUser/forceGroup at 0775. Default true. Turn
off for paths owned by another module (e.g. arr/
shared.nix already owns /mnt/media/{downloads,
library} as root:media 02775; a samba share over
those would set ` ownerTmpfilesRule = false ` to
avoid conflict).



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.readOnly



Mount the share read-only (Samba ` read only `). Default false.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.shareName



SMB share name (the path after ` \\host\ ` or
` smb://host/ `). Defaults to the nori.fs entry
name. Override when the on-the-wire name should
differ from the registry key (e.g. a renamed
share that family bookmarks still use).



*Type:*
string



*Default:*

```nix
"‹name›"
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.validUsers



Samba users permitted to mount this share.



*Type:*
list of string



*Default:*

```nix
[
  "nori"
]
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.samba.vetoFiles



Samba ` veto files ` pattern (slash-delimited).
Used by the operator’s ` nori ` share for the
recursive dotfile veto — ` /.*/ ` denies SMB
access to any dot-prefixed entry at every depth
to keep nested .env / .git-credentials / .ssh
material off the tailnet. Per ` veto files `(5)
the pattern is matched against names, NOT full
paths — non-dot secrets (credentials.json, \*.key)
won’t be hidden by this and shouldn’t be stored
in vetoed shares.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/.*/"
```

*Declared by:*
 - `modules/infra/storage`



## nori.fs.<name>.tier



Value tier per docs/reference/storage.md “Value tiers”.
Drives which restic repo (if any) the path lands in
and the snapshot retention class. Adding a tier:
extend the enum, document the contract, update the
filter generators in modules/infra/backup/.



*Type:*
one of “re-derivable”, “user”, “irreplaceable”

*Declared by:*
 - `modules/infra/storage`


