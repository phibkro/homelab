{ config, ... }:

{
  /*
    First-boot auth is manual on a fresh node:
      sudo tailscale up --hostname=<canonical>
    Once authed, `extraUpFlags` is a no-op (the systemd-bundled
    `tailscaled-autoconnect` only runs `up` if the node isn't already
    logged in). To rename a live node, use:
      sudo tailscale set --hostname=<canonical>
    Later we move auth itself to services.tailscale.authKeyFile via
    sops-nix; until then `up` is hand-rolled at install time.

    Tailscale-SSH (`--ssh`) is intentionally NOT enabled here. The
    check-mode reauth cycle (browser visit every ~12h per ACL) wedges
    cross-host automation — `just remote pi rebuild` fails at the
    rsync stage when the cookie expires, with no remedy other than
    the operator visiting the auth URL by hand. Tailscale ACLs+keys
    already gate WHO can reach the node (tailnet membership = auth
    perimeter); OpenSSH with the per-user pubkey lists in
    users.users.<n>.openssh.authorizedKeys.keys handles the SSH
    handshake itself, no expiring browser session. For ad-hoc human
    SSH from phone/Mac, the Tailscale mobile app's MagicDNS pointer +
    the OpenSSH pubkey already on the device works without rituals.

    Disabling on EXISTING nodes also needs a live runtime command:
      sudo tailscale set --ssh=false
    (extraUpFlags only runs on first `tailscale up`.)
  */
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";

    /*
      Declared so that any future re-auth (logout + up) lands the node
      back on the canonical hostname. Per-host override via extraUpFlags
      in the host's own config if a host ever needs a different tailnet
      name.
    */
    extraUpFlags = [
      "--hostname=${config.networking.hostName}"
    ];
  };
}
