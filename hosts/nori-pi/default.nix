{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  ...
}:

{
  # nori-pi is a Raspberry Pi 4 (8 GiB) appliance — DNS adblock,
  # observability redundancy (Gatus + ntfy probing nori-station so
  # alerts still fire when station's down), Tailscale subnet
  # router + opt-in exit node, and eventually the local restic
  # backup target for fast restores.
  #
  # Per the "flat imports" decision (CLAUDE.md), this host does NOT
  # import modules/server/default.nix (the nori-station bundle).
  # Pi-specific service modules will be added file-by-file once they're
  # refactored to be role-parametric.
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4

    # The aarch64 sd-image installer module gives us
    # `system.build.sdImage` so we can build a flashable .img on
    # nori-station via aarch64 binfmt and dd it to the FIT, instead
    # of running an interactive installer.
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

    ../../modules/common
    ./hardware.nix
  ];

  networking.hostName = "nori-pi";
  networking.useDHCP = lib.mkDefault true;

  # Tailscale routing role — Pi advertises the LAN subnet + offers
  # exit-node service. Both opt-in per-device in the Tailscale admin
  # console after first auth. First-boot auth is manual (CLAUDE.md
  # gotcha: services.tailscale.authKeyFile via sops-nix is the
  # eventual path; for now: `sudo tailscale up --ssh
  # --advertise-routes=192.168.1.0/24 --advertise-exit-node
  # --hostname=nori-pi`).
  services.tailscale.useRoutingFeatures = lib.mkForce "server";

  # Required for any tailscale node advertising routes.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # No service modules yet — those land in a follow-up commit once
  # blocky.nix / gatus.nix / beszel.nix are refactored to be role-
  # parametric (Pi runs primary Blocky, a second Gatus instance
  # probing station, beszel-agent only). Skeleton commits first so
  # eval can be validated before adding behavior.
}
