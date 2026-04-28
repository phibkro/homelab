{
  lib,
  inputs,
  ...
}:

{
  # nori-station is a server + a desktop. Each `modules/<concern>`
  # import is one role this machine plays; the host is the sum of
  # its concerns plus its physical hardware.
  imports = [
    inputs.disko.nixosModules.disko

    ../../modules/common # base + users + sops + tailscale + lib options
    ../../modules/server # every server module (HTTP, *arr, backup, …)
    ../../modules/desktop # Hyprland + greetd + audio + bars + apps + gaming

    ./hardware.nix
    ./disko.nix
    ./disko-media.nix
    ./disko-onetouch.nix
    ./windows-mount.nix
  ];

  networking.hostName = "nori-station";
  networking.useDHCP = lib.mkDefault true;

  # Station-side Gatus probes for non-HTTP services (these don't fit
  # the lan-route auto-gen pattern). HTTP services behind Caddy are
  # auto-probed via nori.lanRoutes.<n>.monitor — see
  # modules/lib/lan-route.nix.
  #
  # When nori-pi joins the lab, add explicit probes for Pi here:
  # `tcp://<pi-tailnet-ip>:53` (Blocky), `tcp://<pi-tailnet-ip>:22`
  # (SSH). Until then, Pi's Gatus probes station; the reverse
  # direction stays out of this list.
  services.gatus.settings.endpoints = [
    {
      name = "blocky-dns";
      url = "tcp://127.0.0.1:53";
      interval = "60s";
      conditions = [ "[CONNECTED] == true" ];
      alerts = [
        {
          type = "ntfy";
          failure-threshold = 3;
          send-on-resolved = true;
        }
      ];
    }
    {
      name = "samba-smb";
      url = "tcp://127.0.0.1:445";
      interval = "60s";
      conditions = [ "[CONNECTED] == true" ];
      alerts = [
        {
          type = "ntfy";
          failure-threshold = 3;
          send-on-resolved = true;
        }
      ];
    }
  ];
}
