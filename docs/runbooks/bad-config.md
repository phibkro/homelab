# Bad config

**RTO**: <15 min. NixOS rollback is atomic; this should be the cheapest recovery.

## Symptom

`nixos-rebuild switch` activated a config that broke something — service won't start, network unreachable, can't log in, kernel panic at boot.

## If you can SSH

```bash
sudo nixos-rebuild switch --rollback
```

That activates the previous generation. Symlink-only swap; takes seconds.

## If SSH is dead but graphical session works

Open a terminal in the running session, run the command above.

## If the host is unreachable entirely

Reboot to the systemd-boot menu. Pick the "previous generation" entry — they're listed by date+hash. Boot that, log in, then optionally make it the default:

```bash
# from the recovered session
sudo nixos-rebuild switch --rollback   # makes prev gen the default
```

## After recovery

1. `git log` to see what changed and which commit was activated when it broke.
2. Iterate on the config locally; do not deploy again until tests/checks pass.
3. If the bad config was pushed to `origin/main`, revert the offending commit so other hosts pulling the flake don't trip the same trap.

## What you can rely on

- `/.snapshots/` btrbk snapshots are independent of the NixOS generation — drop a recovered config can't hurt them.
- `/nix/store` GC is gated by `--delete-older-than 30d`; rollback works for any generation younger than 30 days that hasn't been GC'd.

## What this won't recover

- Stateful service data corrupted by the bad config (e.g. a migration that wrote schema changes). For that → `service-corruption.md`.
- Disk-level damage. For that → `drive-failure-*.md`.
