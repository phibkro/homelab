---
name: gotcha-chromecast-hardcoded-dns
description: USE WHEN ads slip through Blocky on Chromecast / Google Home / Google TV / Android TV but blocked everywhere else — those devices hardcode 8.8.8.8 and ignore DHCP + Tailscale DNS push. Per-device fix is full static-IP config in Google Home app pointing DNS at pi (.225) + workstation (.181). Network-level fix needs bridge-mode Genexis + a real router.
---

# Chromecast / Google appliances hardcode `8.8.8.8` and ignore DHCP/Tailscale DNS push

Chromecast, Google Home, Google TV, and Android TV ship with `8.8.8.8` baked in. They ignore both router DHCP DNS and Tailscale's global-nameserver push. Result: ads show through Blocky on these devices even when every other client on the network is filtered.

The Blocky module's design notes already flag the broader case: "LAN-only devices (smart TV, guest phones) are NOT covered" — they keep using whatever the router pushes. Google appliances make it worse because they ignore the router too.

**Per-device fix** (works on most current Chromecast firmware): Google Home app → device → Settings → Network → Use static IP → fill all fields:

```
IP address:    192.168.1.<free>     # outside the Genexis DHCP pool
Subnet mask:   255.255.255.0
Gateway:       192.168.1.1          # Genexis EG400 default
DNS 1:         192.168.1.225        # pi (Blocky in forwarder mode)
DNS 2:         192.168.1.181        # workstation (Blocky self-hosted; fallback)
```

Setting only "static DNS" without the rest of the config isn't an option in Google Home; the UI forces full IP config. Pick a static IP outside Genexis's DHCP range to avoid lease collisions.

Verify: tell the Chromecast to reboot (Google Home → device → restart). Cast YouTube. First video may still show one ad from cached DNS (~1-5 min TTL); subsequent videos should be ad-free.

**Network-level fix** (covers all LAN devices including Google appliances): bridge-mode the Genexis (phone call to Altibox) + put a real router/firewall (pfSense, OpenWRT, or just iptables on Pi as the gateway) in the path. Two things become possible:

- Push Blocky as DHCP DNS to all LAN clients
- NAT-redirect outbound `:53` traffic to Blocky — catches devices that hardcode `8.8.8.8`

**Caveat**: newer Chromecast firmware can fall back to DNS-over-HTTPS on `:443`, which sails through any port-53 interception. Block known DoH endpoints by IP if you see ads recur after applying the fix above.
