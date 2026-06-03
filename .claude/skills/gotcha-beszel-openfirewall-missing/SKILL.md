---
name: gotcha-beszel-openfirewall-missing
description: USE WHEN configuring `services.beszel.hub` firewall — the Beszel module doesn't expose `openFirewall`. Use `networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8090 ];` directly. Trust `nixos-option` over assumption for other modules' firewall toggles too.
---

# `services.beszel.hub.openFirewall` doesn't exist

The Beszel module doesn't expose `openFirewall`. Use `networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8090 ];` instead. Other NixOS service modules vary; trust `nixos-option` over assumption.

See also [[gotcha-per-interface-firewall-rules]] — opening on `tailscale0` only can become a latent constraint if DNS routes change.
