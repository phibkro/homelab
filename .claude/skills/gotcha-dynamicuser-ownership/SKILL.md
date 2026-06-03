---
name: gotcha-dynamicuser-ownership
description: USE WHEN touching NixOS services that use `DynamicUser=yes` (ollama, ntfy-sh, open-webui, gatus, beszel-hub, jellyseerr, prowlarr) — fresh ephemeral UID per session means files appear owned `nobody:nogroup` externally; `chown <svc>:<svc>` fails; StateDirectory at `/var/lib/<n>` is a bind mount, actual storage at `/var/lib/private/<n>`. To grant /run/secrets read, set `SupplementaryGroups = [ "keys" ]`.
---

# DynamicUser services: ownership trickery

NixOS services using `DynamicUser=yes` (open-webui, ollama, ntfy-sh, gatus, beszel-hub) get a fresh ephemeral UID at each session. From outside the service namespace, files appear owned `nobody:nogroup`. Implications:

- `chown ollama:ollama /var/lib/ollama` fails — that user doesn't exist statically. Use `chown --reference=<existing-file>` to copy ownership from a sibling.
- StateDirectory= mechanism makes `/var/lib/<name>` appear externally; actual storage is `/var/lib/private/<name>` (bind mount).
- To grant a DynamicUser service read access to /run/secrets files (mode 0440 root:keys), set `SupplementaryGroups = [ "keys" ]` in the systemd unit override.

See also [[gotcha-dynamicuser-statedirectory-symlink]] for the restic-with-symlinks variant.
