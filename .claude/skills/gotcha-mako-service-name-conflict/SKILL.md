---
name: gotcha-mako-service-name-conflict
description: USE WHEN mako fails to start after a home-manager rebuild with "Failed to acquire service name: File exists / Is a notification daemon already running?" — old mako outlived the systemd-tracked PID, still holds org.freedesktop.Notifications on dbus. Kill by PID from `pgrep -af mako` (NOT `pkill mako` — process arg-vector is the store path), then `systemctl --user start mako`.
---

# mako "Failed to acquire service name" after home-manager restart

When you change `services.mako.settings` and rebuild, home-manager restarts the user unit. The old mako process can outlive the systemd-tracked PID briefly, holding `org.freedesktop.Notifications` on the user's dbus session. The new instance fails to acquire the name and exits:

```
mako: Failed to acquire service name: File exists
mako: Is a notification daemon already running?
```

Fresh boot: never sees this. Iterating on mako config without rebooting: `kill <stale-pid>; systemctl --user start mako.service`. `pkill mako` doesn't work cleanly because the process arg-vector is the unwrapped store path, not "mako" verbatim — kill by PID from `pgrep -af mako`.
