---
name: gotcha-blocky-bootstrap-dns
description: USE WHEN configuring a Blocky module that serves as its own host's resolver — there's a self-loop on restart (Blocky needs DNS to download blocklists, its own DNS isn't up yet). Configure `services.blocky.settings.bootstrapDns = [{ upstream = "1.1.1.1"; } { upstream = "9.9.9.9"; }];`. Symptom: blocklist count=0, ads still resolve.
---

# Blocky needs `bootstrapDns` when serving its own host

If workstation's `/etc/resolv.conf` points at Tailscale's stub (`100.100.100.100`) AND Tailscale's global nameserver is set to workstation's Blocky (via admin DNS push), there's a self-loop on Blocky restart: Blocky needs DNS to download blocklists, but its own DNS isn't serving yet.

Fix: configure `services.blocky.settings.bootstrapDns` with direct upstream IPs. Used only for Blocky's own outbound URL resolution, bypasses `/etc/resolv.conf`.

```nix
bootstrapDns = [
  { upstream = "1.1.1.1"; }
  { upstream = "9.9.9.9"; }
];
```

Symptom of missing bootstrap: blocklist download times out, denylist ends up empty (count=0), services like doubleclick.net resolve to real CDN IPs instead of 0.0.0.0.
