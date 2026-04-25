{ config, lib, ... }:

{
  # First-boot auth is manual on a fresh node:
  #   sudo tailscale up --ssh --hostname=<canonical>
  # Once authed, `extraUpFlags` is a no-op (the systemd-bundled
  # `tailscaled-autoconnect` only runs `up` if the node isn't already
  # logged in). To rename a live node, use:
  #   sudo tailscale set --hostname=<canonical>
  # Later we move auth itself to services.tailscale.authKeyFile via
  # sops-nix; until then `up` is hand-rolled at install time.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";

    # Declared so that any future re-auth (logout + up) lands the node
    # back on the canonical hostname with SSH-over-tailscale enabled.
    # The hostname here matches networking.hostName per host; if a host
    # ever needs a different tailnet name, override extraUpFlags there.
    extraUpFlags = [
      "--ssh"
      "--hostname=${config.networking.hostName}"
    ];
  };
}
