---
generated: true
source: flake.nix § packages.docs-capabilities
regenerate: nix build .#docs-capabilities
---

# Capabilities — generated reference

Module overviews + per-option schema for `nori.harden` and
`nori.gpu`. Hand-curated cross-module synthesis (which
services consume which capability, per-host driver
choices) lives in the file-level doc-comments at
`modules/infra/capabilities/{default,gpu}.nix`.

Capabilities concern — what services can DO on the machine.

Distinct from "access" (who can REACH the service): capabilities
covers the outbound / local direction — filesystem visibility, GPU
device allocation, system capabilities, shared group memberships.
PaaS analogue: sidecar permissions, volume mounts, device
allocations.

`default.nix` carries the `nori.harden` schema + systemd
FS-namespace adapter. `gpu.nix` carries `nori.gpu.nvidiaDevices`
registry (the device-path SoT services read from).

Shared `media` group declarations live in
`modules/services/arr/shared.nix` + `modules/machines/aurora/default.nix`
(declared by each host that uses it; idempotent merge). A future
`media-group.nix` could centralize this.

# Capabilities concern — overview {#sec-functions-library-capabilities}


## `homelab.capabilities.options.nori.harden` {#function-library-homelab.capabilities.options.nori.harden}

`nori.harden` — default-deny filesystem-namespace hardening.

`/mnt` and `/srv` are tmpfs-overlaid read-only; services see only
the subpaths they explicitly bind. Variation across services is
just `binds` / `readOnlyBinds` / `protectHome`; the rest is
constant `serviceConfig` that every server module used to
rewrite by hand.

Attribute name MUST match the systemd unit name. Multi-unit
services declare separate entries (`immich-server` +
`immich-machine-learning`).

Composition: services needing extra `serviceConfig` keys
(PrivateDevices, SupplementaryGroups, EnvironmentFile, …)
declare them in a sibling `systemd.services.<name>.serviceConfig`
block — NixOS module merging combines them with this
abstraction's output.



## GPU access pattern

Services that need the GPU set `accelerationDevices` (or systemd
`DeviceAllow`) from `config.nori.gpu.nvidiaDevices` — single source
of truth, declared per host in that host's `hardware.nix`.

| Service | Status | Resource |
|---|---|---|
| Ollama (CUDA) | live | 14+ GiB VRAM at idle with model loaded |
| Immich (CUDA ML + NVENC) | live | NVENC encode, ML inference (on aurora's GTX 950M) |
| Jellyfin (NVENC) | OS-level live | Web-UI flag still off (ROADMAP item) |

Driver split:

 - **workstation** (RTX 5060 Ti, Blackwell) — `hardware.nvidia.package =
   config.boot.kernelPackages.nvidiaPackages.production`. 595.58.03+
   on 26.05; Blackwell support landed.
 - **aurora** (GTX 950M, Maxwell) — `legacy_535` branch (Maxwell GPUs
   are out of the production branch's supported list).
 - **pavilion, pi** — no GPU; `nori.gpu.nvidiaDevices = [ ]` default.

Fallback ladder if production breaks: `production` → `beta` →
`latest` → explicit `mkDriver` pin.

## Why the registry shape

Same Reader+Writer shape as `nori.lanRoutes` and `nori.harden`. Each
host's `hardware.nix` is the Reader (sets `nori.gpu.nvidiaDevices`);
each service that needs the GPU is the Writer (reads
`config.nori.gpu.nvidiaDevices` for its `accelerationDevices` /
`DeviceAllow` setting). GPU swap = edit one host's hardware.nix;
every consuming service follows.

Compute-only by design: `nvidia-modeset` (display) and
`nvidia-uvm-tools` (profiling) aren't in the registry. Add them if
a future workload needs display access or profiling.

# GPU access pattern {#sec-functions-library-capabilities-gpu}


## `homelab.capabilities-gpu.options.nori.gpu.nvidiaDevices` {#function-library-homelab.capabilities-gpu.options.nori.gpu.nvidiaDevices}

`nori.gpu.nvidiaDevices` — single source of truth for NVIDIA
device nodes. Services that need GPU access read this rather
than hardcode paths, so a GPU swap is a one-line change.

Compute-only by design: `nvidia-modeset` (display) and
`nvidia-uvm-tools` (profiling) aren't in this set.




## Option schema

## nori.gpu.nvidiaDevices

NVIDIA device nodes exposed to GPU-opted-in services
(services.immich.accelerationDevices, future DeviceAllow-style
consumers). Empty default lets GPU-less hosts pass through cleanly;
GPU hosts set this in their hardware.nix.



*Type:*
list of string



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "/dev/nvidia0"      # GPU compute
  "/dev/nvidiactl"    # driver control node
  "/dev/nvidia-uvm"   # unified virtual memory (required for CUDA)
]

```

*Declared by:*
 - `modules/infra/capabilities/gpu.nix`



## nori.harden



Filesystem-namespace hardening for systemd services. Each entry
maps a service unit name to a hardening profile; the generator
emits ` systemd.services.<name>.serviceConfig `.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  sonarr = { binds = [ "/mnt/media/downloads" ]; };
  jellyfin = { readOnlyBinds = [ "/mnt/media" "/srv/share" ]; };
  syncthing = { protectHome = null; };
}

```

*Declared by:*
 - `modules/infra/capabilities`



## nori.harden.<name>.binds



Writable bind-mount paths to expose to the service.
Maps to systemd ` BindPaths `. Use for state-bearing
service-specific subtrees the service must write to
(e.g. /mnt/media/photos for Immich).



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - `modules/infra/capabilities`



## nori.harden.<name>.protectHome



Whether to set ` ProtectHome ` (with mkForce). Default
true; the abstraction’s whole point is default-deny.
Set false explicitly to allow /home access, or null to
leave the upstream NixOS module’s setting intact (use
when upstream’s value is opinionated and our override
would regress).



*Type:*
null or boolean



*Default:*

```nix
true
```

*Declared by:*
 - `modules/infra/capabilities`



## nori.harden.<name>.readOnlyBinds



Read-only bind-mount paths to expose to the service.
Maps to systemd ` BindReadOnlyPaths `. Use for paths the
service consumes but must not modify (e.g. /mnt/media
for Jellyfin which streams existing files).



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - `modules/infra/capabilities`


