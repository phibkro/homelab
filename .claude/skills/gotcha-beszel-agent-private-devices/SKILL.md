---
name: gotcha-beszel-agent-private-devices
description: USE WHEN Beszel agent dashboard's GPU panel is empty, agent logs `WARN nvidia-smi found no valid GPU data, stopping` — upstream `services.beszel.agent` sets `PrivateDevices = !cfg.smartmon.enable`; with smartmon off (default), `/dev/nvidia*` is hidden. Override `systemd.services.beszel-agent.serviceConfig.PrivateDevices = lib.mkForce false;`.
---

# Beszel agent under DynamicUser hides `/dev/nvidia*`

The upstream `services.beszel.agent` module sets `PrivateDevices = !cfg.smartmon.enable`. With smartmon off (the default), `PrivateDevices = true` creates a private `/dev` namespace that omits `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm`. The agent's bundled `nvidia-smi` invocation finds nothing and logs `WARN nvidia-smi found no valid GPU data, stopping` — and the Beszel dashboard's GPU panel stays empty.

Override locally:

```nix
systemd.services.beszel-agent.serviceConfig.PrivateDevices = lib.mkForce false;
```

Loosens just the device namespace; the rest of the upstream hardening (PrivateUsers, ProtectKernel*, SystemCallFilter, RestrictSUIDSGID) stays. See `modules/services/beszel/agent.nix` for the live config.
