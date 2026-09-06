{ lib }:

{
  mkService =
    {
      name,
      unit ? name,
      port,
      sops ? { },
      tailnetOpen ? true,
      harden ? { },
      extraConfig ? { },
    }:
    lib.mkMerge [
      {
        sops.secrets = builtins.listToAttrs (
          map (secret: lib.nameValuePair secret { }) (sops.secrets or [ ])
        );
        networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.optional tailnetOpen port;
        nori.harden.${unit} = harden;
      }
      extraConfig
    ];
}
