---
name: gotcha-tailscale-https-certs-toggle
description: USE WHEN `tailscale serve --https=...` returns "Serve is not enabled on your tailnet" — toggle HTTPS Certs in the Tailscale admin console first (one-time per tailnet). The CLI prints the link to click.
---

# Tailscale Serve / HTTPS Certs need to be enabled in admin first

`tailscale serve --https=...` returns "Serve is not enabled on your tailnet" until you toggle it in the Tailscale admin console. The CLI gives you the link to click. One-time action per tailnet.
