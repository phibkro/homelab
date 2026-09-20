{
  config,
  inputs,
  lib,
  ...
}:

/**
  adelie — SSD-local application host

  IronWolf Pro and OneTouch remain attached to workstation. Adelie owns only
  its Samsung system disk, SSD-local applications, and the cache directory.

  The base profile supplies shared Nix, SOPS, SSH, Tailscale, and Norwegian
  console-keymap policy. Workload placement supplies application modules.
*/
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware.nix
    ./disko.nix
  ];

  # Keep Ethernet and Wi-Fi available so maintenance does not depend on moving
  # the workstation's cable. Adelie decrypts only its narrow network secret.
  networking.useDHCP = lib.mkDefault true;
  nori.wifi = {
    enable = true;
    interface = "wlp5s0";
  };

  # RTL8852CE firmware 0.27.129.4 triggered rtw89 SER recovery on this host.
  # Disable the firmware low-power path first; keep PCIe power management enabled.
  boot.extraModprobeConfig = "options rtw89_core disable_ps_mode=Y";

  # Adelie receives only the credentials consumed by its selected workloads.
  # The workstation host identity is not a recipient for this file.
  sops.defaultSopsFile = lib.mkForce (inputs.self + "/secrets/adelie-runtime.yaml");

  # Attic cache chunks are re-derivable and stay on Adelie's local NVMe.
  nori.fs.cache = {
    path = "/var/lib/attic/chunks";
    tier = "re-derivable";
  };

  # Prefer the local entry-plane DNS while DHCP still advertises the router.
  networking.nameservers = [
    config.nori.inventory.hosts.pi.lanIp
    "1.1.1.1"
  ];

  # First activation creates users and state directories but cannot start a
  # writable target before its authoritative state arrives. The operator adds
  # each root-owned gate only after that service's transfer and restore pass.
  systemd.tmpfiles.rules = [ "d /var/lib/nori/migration 0700 root root -" ];
  systemd.services = lib.mkMerge [
    (lib.genAttrs
      [
        "miniflux"
        "radicale"
        "stremio"
        "vaultwarden"
      ]
      (service: {
        unitConfig.ConditionPathExists = "/var/lib/nori/migration/${service}-ready";
      })
    )
    (lib.genAttrs
      [
        "restic-backups-miniflux-onetouch"
        "restic-backups-radicale-onetouch"
        "restic-backups-stremio-onetouch"
        "restic-backups-vaultwarden-onetouch"
        "restic-check-monthly"
        "restic-check-weekly"
      ]
      (_: {
        unitConfig.ConditionPathExists = "/var/lib/nori/migration/backups-ready";
      })
    )
  ];

  # Media and portable-disk policy remains on workstation.
  services.tailscale.extraSetFlags = [ "--accept-dns=true" ];
}
