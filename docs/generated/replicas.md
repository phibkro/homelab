---
generated: true
source: flake-parts/packages/docs-replicas.nix
regenerate: nix build .#docs-replicas
---

# `nori.replicas` — generated reference

Two-section artifact: module overview (RFC 145 doc-comments
from the concern's `default.nix`) + per-option schema
(`nixosOptionsDoc` over the eval'd options tree). The
concern file's path is shown in the per-option "Declared by"
lines below.


# replicas concern — overview {#sec-functions-library-replicas}


## `homelab.replicas.options.nori.replicas` {#function-library-homelab.replicas.options.nori.replicas}

`nori.replicas` — declarative cross-host data-replication registry.

Each entry pairs a source dataset on one host with a target on
another, plus a mechanism + freshness budget. The Writer half
below emits a per-replica verifier oneshot on the *target* host
(where the snapshot must land): if the latest snapshot is older
than `maxAgeHours`, the unit fails → notify@ alerts via ntfy.

The replicator itself (e.g. btrfs send/receive timer aurora →
workstation MP510 for `/mnt/family/*`) lands in P15 — this
module only defines the registry + the verifier so the freshness
check is wired before any replicas actually exist. On hosts with
zero matching entries the writer is a clean no-op (no units
emitted) and `just test-replicas` exits 0 with "no replicas
declared".

### Examples

Service-tier shape:

```nix
nori.replicas.family-photos = {
  source       = { host = "aurora";      path = "/mnt/family/photos"; };
  target       = { host = "workstation"; path = "/mnt/family-replica/photos"; };
  mechanism    = "btrfs-send-receive";
  maxAgeHours  = 25;  # daily cadence + 1h slack
};
```

See `docs/plans/2026-06-11-aurora-migration.md` § P5/P15.

## `homelab.replicas.config` {#function-library-homelab.replicas.config}

Writer: per-replica verifier oneshot emitted on the target host.
Empty registry on this host → `mkIf` collapses to `{}` cleanly;
no units, no timers, no `test-replicas` false negatives.




## Option schema

## nori.replicas

Declarative cross-host dataset replicas. Each entry names a
source (host + path) and target (host + path), the replication
mechanism, and a freshness budget. The verifier emitted on the
target host alerts via ntfy when the latest snapshot at
` target.path ` is older than ` maxAgeHours `.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```

*Declared by:*
 - `modules/infra/storage/replication.nix`



## nori.replicas.<name>.maxAgeHours



Freshness budget on the target side. The verifier reads
the latest snapshot timestamp under ` target.path ` and
fails if older than this — triggering the OnFailure →
notify@ ntfy alert. Default 25h covers a daily cadence

 - 1h slack for the receive window.



*Type:*
positive integer, meaning >0



*Default:*

```nix
25
```

*Declared by:*
 - `modules/infra/storage/replication.nix`



## nori.replicas.<name>.mechanism



How the source is propagated. Only ` btrfs-send-receive `
is supported today (aurora HDD → workstation MP510, both
btrfs). Other mechanisms (zfs send, rsync) would extend
this enum when a use case arrives.



*Type:*
value “btrfs-send-receive” (singular enum)

*Declared by:*
 - `modules/infra/storage/replication.nix`



## nori.replicas.<name>.source



Host + path where the dataset originates.



*Type:*
submodule

*Declared by:*
 - `modules/infra/storage/replication.nix`



## nori.replicas.<name>.source.host



Source host name (key into ` nori.hosts `).



*Type:*
string

*Declared by:*
 - `modules/infra/storage/replication.nix`



## nori.replicas.<name>.source.path



Source filesystem path (typically a btrfs subvolume).



*Type:*
absolute path

*Declared by:*
 - `modules/infra/storage/replication.nix`



## nori.replicas.<name>.target



Host + path where the replica lands.



*Type:*
submodule

*Declared by:*
 - `modules/infra/storage/replication.nix`



## nori.replicas.<name>.target.host



Target host name (key into ` nori.hosts `).



*Type:*
string

*Declared by:*
 - `modules/infra/storage/replication.nix`



## nori.replicas.<name>.target.path



Target filesystem path (subvolume receiving the replica).



*Type:*
absolute path

*Declared by:*
 - `modules/infra/storage/replication.nix`


