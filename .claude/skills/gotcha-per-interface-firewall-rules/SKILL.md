---
name: gotcha-per-interface-firewall-rules
description: USE WHEN opening firewall ports with `networking.firewall.interfaces."<iface>".allowedTCPPorts` for services intended to be reachable from multiple route families (LAN + tailnet + cross-host subnet) — interface-scoped rules become latent constraints when DNS routes shift. Use `networking.firewall.allowedTCPPorts` global for ambiguous-route services. Symptom: `context deadline exceeded` from Gatus / Go-stdlib clients, loopback `curl` succeeds.
---

# Per-interface firewall rules become latent constraints when DNS routes change

`networking.firewall.interfaces."<iface>".allowedTCPPorts = [ ... ]` opens a port only on that interface. If `*.nori.lan` resolves to an IP reachable only via that interface, the rule "works" because traffic always arrives there. Change DNS to a different IP family (LAN vs tailnet) and the rule silently drops everything.

Hit during the 2026-05-05 LAN-IP migration: Caddy had `interfaces."tailscale0".allowedTCPPorts = [ 80 443 ]`, fine for as long as DNS pointed at the tailnet IP. After Blocky started returning the LAN IP, traffic arrived on `enp42s0` and got dropped. Pi's Gatus probe of `https://status.nori.lan` started timing out at the TCP layer; loopback `curl` from station succeeded (lo bypasses the interface match) so the failure looked weirder than it was.

For services intended to be reachable from any host route (LAN client + tailnet client + cross-host subnet route), open globally with `networking.firewall.allowedTCPPorts`. Same shape as Blocky's `:53` rule. The router doesn't forward inbound from WAN, so the host firewall is just the second layer.

Symptom keyword for grep: `context deadline exceeded (Client.Timeout exceeded while awaiting headers)` from a Go-stdlib HTTPS client probing a service that responds fine on loopback.
