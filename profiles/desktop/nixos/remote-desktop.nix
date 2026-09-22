{
  imports = [ ../../../services/sunshine/nixos.nix ];

  /*
    RustDesk's direct-IP listener is runtime user state: the operator enables it
    in each graphical session and owns its credentials. Reserve only its default
    TCP port on the tailnet; do not enable the public rendezvous server or open
    any LAN/WAN listener.

    Contract: docs/specs/2026-09-22-peer-remote-desktops.md
  */
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 21118 ];
}
