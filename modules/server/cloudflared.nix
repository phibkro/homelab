{ config, lib, ... }:

# cloudflared — Cloudflare Tunnel daemon. Outbound-only: workstation
# initiates a tunnel to Cloudflare's edge; public DNS for *.phibkro.org
# resolves to Cloudflare which forwards via the tunnel to local
# 127.0.0.1:<port> backends. No inbound ports opened on the home
# network.
#
# Pairs with the nori.publicRoutes effect (modules/effects/public-route.nix).
# Each app's module declares `nori.publicRoutes.<n>` next to its
# existing `nori.lanRoutes.<n>`; this module assembles the tunnel
# ingress rules from the collected attrset.
#
# ── Tunnel ID ────────────────────────────────────────────────────
# Single tunnel for the homelab's public exposure, created once via
#   cloudflared tunnel login
#   cloudflared tunnel create phibkro
# and pinned by UUID below. Credentials JSON encrypted at
# secrets/apps.yaml#cloudflared-tunnel-credentials. Re-creating the
# tunnel (e.g. after credential leak) means rerouting DNS records;
# don't churn this UUID without intent.
#
# ── DNS routing (operator-side) ──────────────────────────────────
# Adding a new hostname to the tunnel requires a one-time CNAME at
# Cloudflare. Run from the operator's shell (uses ~/.cloudflared/cert.pem
# from the original `tunnel login`):
#   cloudflared tunnel route dns phibkro phibkro.org      # apex
#   cloudflared tunnel route dns phibkro me.phibkro.org   # heim
#   cloudflared tunnel route dns phibkro filmder.phibkro.org
#   ... etc.
# Each command writes one CNAME entry in Cloudflare DNS pointing
# `<host>` → `<tunnel-uuid>.cfargotunnel.com`. The just recipe
# `cloudflared-route-all` runs all of them at once.

let
  tunnelId = "9fc33815-3e6c-41dc-9858-8e01fe79ecda";

  # Build the cloudflared ingress map from publicRoutes. Each entry
  # becomes `<hostname> → http://localhost:<port>`. Apex entries
  # (host = "@") get the bare domain; everything else gets a
  # subdomain. cloudflared also wants a default `*` catch-all that
  # returns 404 — not declarable via the NixOS module's `ingress`
  # attrset, so configured separately as `default`.
  ingressFor =
    cfg:
    let
      hostname = if cfg.host == "@" then "phibkro.org" else "${cfg.host}.phibkro.org";
    in
    lib.nameValuePair hostname "http://localhost:${toString cfg.port}";

  ingress = lib.listToAttrs (lib.mapAttrsToList (_: ingressFor) config.nori.publicRoutes);
in
{
  sops.secrets.cloudflared-tunnel-credentials = {
    sopsFile = ../../secrets/apps.yaml;
    # cloudflared upstream module runs as DynamicUser; static owner=
    # would fail eval. Use the standard `keys` group (sops-nix
    # primitive) and grant it as a supplementary group on the
    # cloudflared service unit below.
    group = "keys";
    mode = "0440";
  };

  services.cloudflared = {
    enable = true;
    tunnels.${tunnelId} = {
      credentialsFile = config.sops.secrets.cloudflared-tunnel-credentials.path;
      default = "http_status:404";
      inherit ingress;
    };
  };

  # The NixOS cloudflared module names the unit after the tunnel id.
  nori.harden."cloudflared-tunnel-${tunnelId}" = { };

  # Grant the dynamic-user cloudflared service access to the keys
  # group so it can read the sops-rendered credentials file.
  systemd.services."cloudflared-tunnel-${tunnelId}".serviceConfig.SupplementaryGroups = [
    "keys"
  ];

  # No state worth saving — the credential is sops-managed (recoverable
  # from the sops file or by re-running `cloudflared tunnel create`),
  # and the daemon's runtime state is just the live connection set.
  nori.backups.cloudflared.skip = "stateless — credentials are sops-managed; runtime state is just live tunnel connections";
}
