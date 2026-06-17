---
name: gotcha-tailscale-ssh-browser-auth
description: USE WHEN automation script / justfile recipe hangs silently doing `tailscale ssh` or `ssh` to a tailnet host — Tailscale SSH periodically wedges on a browser-auth re-check (URL in stderr that non-interactive shells never see). Fix order — (1) add station's pubkey to Pi's `authorized_keys` in `modules/machines/base/users.nix`, then use regular OpenSSH via LAN IP; (2) re-auth via the URL; (3) drive from Mac (already keyed).
---

# Tailscale SSH browser-auth wedges cross-host automation

`tailscale ssh nori@pi.saola-matrix.ts.net` (or any SSH to a tailnet IP when Tailscale SSH is enabled on the destination) periodically requires a browser auth check — `Tailscale SSH requires an additional check. To authenticate, visit: https://login.tailscale.com/a/...`. Non-interactive shells (justfile recipes, automation scripts) hang silently waiting for the browser flow.

Workarounds, in order of preference:

1. **Add station's pubkey to Pi's `authorized_keys` via `users.users.nori.openssh.authorizedKeys.keys`** in `modules/machines/base/users.nix`. Cross-host automation then uses regular OpenSSH auth (LAN IP path), bypassing tailscale-SSH entirely. Bootstrap chicken-and-egg: needs SSH to deploy, so initially copy the key manually or run from a host that already has working SSH.
2. **Re-auth interactively** via the URL in the wedge message — keeps Tailscale-SSH working but the next expiry hits again.
3. **Drive cross-host work from Mac** — Mac's pubkey is already in Pi's authorized_keys, so `just remote pi rebuild` from there works.

Diagnostic: `ps -ef | grep ssh` shows the stuck SSH process; output file from `run_in_background` is empty.
