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
  # Mutual observability: station probes Pi's Blocky + SSH via
  # tailnet IP. Pi has matching probes for station — see
  # hosts/nori-pi/default.nix. Each host's Gatus alerts via ntfy.sh
  # directly (no local-ntfy dependency), so when one host wedges
  # the other catches it.
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
    {
      # nori-pi's Blocky on tailnet IP — catches Pi outage even if
      # Pi's Gatus is down (same incident pattern in reverse).
      name = "pi-blocky-dns";
      url = "tcp://100.100.71.3:53";
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
      # nori-pi's SSH — full host-down detection (sshd dead = host
      # effectively gone from operator's perspective).
      name = "pi-ssh";
      url = "tcp://100.100.71.3:22";
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
