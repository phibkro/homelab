{
  config,
  lib,
  ...
}:

let
  cfg = config.nori.wifi;
in
{
  options.nori.wifi = {
    enable = lib.mkEnableOption "the shared Akkar WPA2/WPA3 wireless network";
    interface = lib.mkOption {
      type = lib.types.str;
      example = "wlo1";
      description = "The host-specific wireless interface name.";
    };
  };

  config = lib.mkIf cfg.enable {
    /*
      SOPS decrypts the raw passphrase only to /run/secrets-rendered. The
      wpa_supplicant configuration carries an external reference, so the
      passphrase cannot enter a world-readable Nix store path.
    */
    sops.secrets.wifi-akkar-psk = { };
    sops.templates."wireless-Akkar.conf" = {
      # NixOS runs wpa_supplicant as this dedicated, sandboxed account. It is
      # the sole reader of the runtime file; root retains administrative access.
      owner = "wpa_supplicant";
      group = "wpa_supplicant";
      mode = "0400";
      content = ''
        psk_akkar=${config.sops.placeholder.wifi-akkar-psk}
      '';
    };

    networking.wireless = {
      enable = true;
      interfaces = [ cfg.interface ];
      secretsFile = config.sops.templates."wireless-Akkar.conf".path;
      networks.Akkar.pskRaw = "ext:psk_akkar";
    };

    # sops-nix renders this template during system activation. The service's
    # generated BindReadOnlyPaths declaration makes a missing file a loud
    # startup error, never a silent fallback to a plaintext Nix-store password.
  };
}
