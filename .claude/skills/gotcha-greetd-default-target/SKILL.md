---
name: gotcha-greetd-default-target
description: USE WHEN greetd doesn't autostart at boot (monitor shows TTY login prompt instead of tuigreet) — NixOS's greetd unit is `WantedBy=graphical.target` but the system's default.target is multi-user.target. Set `systemd.defaultUnit = "graphical.target";`. Diagnostic giveaway: `systemctl start greetd.service` works manually.
---

# greetd doesn't auto-start at boot without `systemd.defaultUnit = "graphical.target"`

NixOS's greetd unit is `WantedBy = graphical.target`. On a fresh install (or any host that came up without a display manager), the system's `default.target` points at `multi-user.target`, so the boot path never reaches `graphical.target` and greetd just sits enabled-but-inactive. Symptom: boot completes, getty@tty1 stays running, monitor shows the TTY login prompt instead of tuigreet.

```nix
# modules/machines/desktop/greetd.nix — pin the default target
systemd.defaultUnit = "graphical.target";
```

`systemctl start greetd.service` works manually, which is the diagnostic giveaway: the unit is fine, just nothing pulls it in at boot. Enabling a "real" display manager (sddm, lightdm) would also bump the default target as a side effect; greetd doesn't, so we set it explicitly.
