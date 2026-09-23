# Service changes

Start with [the shared guide](../../AGENTS.md). A service directory owns its
metadata and backend implementations:

- `manifest.nix` is pure inventory metadata and endpoint policy.
- `nixos.nix` is the NixOS implementation when the service runs on a NixOS host.
- `ansible/` is the Pi implementation when the service runs there.
- `implementation/` holds service-owned templates and static assets.

Placement, datasets, backup facts and host roles are declared in `src/inventory/`;
profiles compose reusable modules. Read callers and both manifest/runtime sides
before editing a cross-host service. Preserve explicit authentication, backup,
hardening and deployment behavior, then run the focused checks appropriate to
the changed backend.
