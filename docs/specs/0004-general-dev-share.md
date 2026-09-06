# General dev share

## User journey

From any workstation project, the operator starts a loopback development
server and runs one command. The command prints an HTTPS URL and terminal QR
code that opens the server from a phone or MacBook outside the LAN. The share
exists only while the foreground command is running.

## Goal

Provide an Expo-like sharing adapter with a disposable public mode and a stable,
identity-protected mode, without teaching individual applications about
Cloudflare.

## Constraints

- `dev-share quick <origin>` creates a random TryCloudflare URL and clearly
  reports that possession of the URL grants access.
- `dev-share secure <origin>` uses `https://dev.phibkro.org`, protected by the
  existing operator-only Cloudflare Access policy.
- Origins must be explicit HTTP URLs using literal `127.0.0.1` or `[::1]` and
  an explicit non-zero port. Hostnames, LAN addresses, credentials, paths,
  queries, and fragments are rejected.
- Secure mode supports exactly one active share. The foreground reverse proxy
  owns the fixed loopback gateway port, making concurrent ownership fail loud.
- Process lifetime is the lease; no registry, daemon state, or cleanup job is
  introduced.
- Alchemy owns Access and DNS once. Nix owns the named-tunnel ingress and the
  installed CLI. Per-share operation performs no Cloudflare account mutation.
- Quick and secure modes reuse Cloudflare's HTTP/WebSocket proxy behavior and
  do not proxy arbitrary private-network destinations.

## Falsifiers / definition of done

- Parser tests reject non-loopback and ambiguous origin forms.
- Quick mode obtains a live `trycloudflare.com` URL and renders its QR code.
- An unauthenticated request to `https://dev.phibkro.org` reaches Cloudflare
  Access rather than the local origin.
- With secure mode running, an authenticated browser renders the real Dioxus
  workbench through the public hostname.
- Stopping the foreground command closes the local gateway port and the public
  endpoint no longer reaches the dev server.
- Alchemy converges to no changes after deployment and Nix evaluation passes.
