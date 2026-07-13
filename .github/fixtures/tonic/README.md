# Tonic CI contract fixture

The real `tonic` flake is private and intentionally pinned to the operator's
local checkout. Public GitHub runners cannot fetch it.

CI overrides that input with this fixture. It exposes only the package
contract consumed by homelab modules:

- `packages.<system>.backend`, with a default executable;
- `packages.<system>.pwa`, containing `share/tonic-pwa`.

This lets CI evaluate every NixOS configuration and run every homelab check
without publishing tonic or silently skipping workstation evaluation. Local
`just check` and deployments continue to use and validate the real checkout.
