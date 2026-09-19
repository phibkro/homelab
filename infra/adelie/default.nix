{
  inputs,
  lib,
  ...
}:

/**
  adelie — staged storage and media host

  Phase one intentionally owns only the Samsung 990 Pro system disk. The
  IronWolf Pro and OneTouch are not attached yet, so declaring either would
  turn a physical-migration decision into a boot dependency. Their eventual
  storage and backup roles will be introduced together with a verified
  migration plan.

  The base profile supplies the shared Nix, SOPS, SSH, Tailscale and Norwegian
  console-keymap policy. `users/nori/identity.nix` supplies the existing
  Emperor automation key as an authorized key, so first boot is reachable
  without a one-off installer exception.
*/
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware.nix
    ./disko.nix
  ];

  # First admission uses wired DHCP. Wi-Fi would require host-scoped secret
  # enrollment and belongs to the later physical activation milestone.
  networking.useDHCP = lib.mkDefault true;

  # Prefer the local entry-plane DNS while DHCP still advertises the router.
  networking.nameservers = [
    "192.168.1.225"
    "1.1.1.1"
  ];

  # Keep the first boot a light, headless host. GPU/media policy comes with
  # the data-drive and workload placement decision, not before it.
  services.tailscale.extraSetFlags = [ "--accept-dns=true" ];
}
