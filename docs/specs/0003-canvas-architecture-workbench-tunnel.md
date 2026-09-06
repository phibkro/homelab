# Canvas architecture workbench tunnel

> Superseded by `0004-general-dev-share.md`. The requested two-label hostname
> exposed a paid multi-level TLS dependency, so the implementation moved to a
> first-level, Access-protected sharing adapter reusable by every dev server.

## User journey

While the Rust semantic explorer development server is running on the
workstation, the operator can open
`https://canvas-plugin.architecture.phibkro.org` from a MacBook or phone,
authenticate through Cloudflare Access with the existing operator identity,
and use the Dioxus workbench. When the development server stops, no workstation
port remains publicly reachable.

## Goal

Project the loopback-only Dioxus development server through the homelab's
existing named Cloudflare Tunnel and protect the entire hostname with an
identity-specific Access policy.

## Constraints

- The hostname follows `{system}.{subsystem}.phibkro.org`.
- The origin remains bound to `127.0.0.1:8788`.
- The existing shared `cloudflared` connector remains the only connector for
  its named tunnel.
- Alchemy owns the public DNS record and Access application.
- Nix owns the connector ingress rule.
- Only the existing operator email is allowed; an OTP/login-method-only rule is
  forbidden because it would allow any valid email identity.
- Canvas credentials and Cloudflare credentials do not enter the Canvas repo.

## Falsifiers / definition of done

- An unauthenticated request to the public hostname is redirected to
  Cloudflare Access rather than reaching Dioxus.
- The Access application covers the exact hostname and its allow policy names
  only the operator email.
- The tunnel routes the hostname to `http://127.0.0.1:8788` and retains a final
  `http_status:404` catch-all.
- The Dioxus task listens on loopback, not a LAN or wildcard address.
- The authenticated browser journey renders the architecture workbench from a
  device outside the workstation.
- Homelab checks and the Canvas Rust checks pass from committed content.
