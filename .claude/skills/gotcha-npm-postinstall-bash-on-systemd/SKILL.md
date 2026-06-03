---
name: gotcha-npm-postinstall-bash-on-systemd
description: USE WHEN adding a systemd unit that runs `npm ci` / `npm install` / `pnpm install` with native modules (@swc/core, esbuild, node-gyp, anything with postinstall scripts) — postinstall spawns `sh`, systemd's minimal env has none. Add `bash` to the unit's `path`. Doesn't apply to bun-based builds.
---

# npm postinstall on systemd needs `bash` on the unit `path`

Several Node packages (`@swc/core`, `esbuild`, `node-gyp`, anything with native modules) have postinstall scripts that spawn `sh` for platform detection. NixOS systemd units inherit a minimal env without `/bin/sh`, so `npm ci` fails with:

```
npm error code ENOENT
npm error syscall spawn sh
npm error path /var/lib/<app>/src/node_modules/@swc/core
npm error errno -2
npm error enoent spawn sh ENOENT
```

Fix: add `bash` to the unit's `path`:

```nix
systemd.services.<app>-build = {
  path = with pkgs; [ bash git nodejs_22 ];
  # ...
};
```

Required for any Node-based deploy under systemd (filmder hit it; heim/drinks/finnbydel will too). Doesn't apply to bun-based builds since bun's postinstall scripts use bun's own JS runtime.
