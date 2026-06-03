---
name: gotcha-sops-env-file-format
description: USE WHEN writing sops-encrypted secrets that become `EnvironmentFile=` for a systemd unit — the file body must be env-file syntax (KEY=VALUE), NOT YAML (key: value). systemd silently drops unparseable lines. Cost 4 iteration cycles wiring Gatus.
---

# sops env-file format: `=`, not `:`

sops stores everything as YAML, which uses `key: value`. systemd's `EnvironmentFile=` expects env-file syntax: `KEY=VALUE`. When putting an env file into sops as a block string:

```yaml
gatus-env: |
  NTFY_CHANNEL=nori-claude-jhiugyfthgcv     # CORRECT
  NTFY_CHANNEL: nori-claude-jhiugyfthgcv    # WRONG — looks like YAML, won't be loaded
  NTFY-CHANNEL=...                          # WRONG — env vars must be UPPERCASE_WITH_UNDERSCORES
```

Cost us 4 iteration cycles when first wiring Gatus. systemd silently drops unparseable lines — no error, just env vars never appear in the process.
