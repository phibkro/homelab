{
  config,
  pkgs,
  lib,
  ...
}:

{
  # --- users -------------------------------------------------------------

  users.users.nori = {
    isNormalUser = true;
    description = "Philip";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      # Mac laptop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINZj3DMqIjSV04Yiafw4Td0lQAoQyITCdRS9V/78XrrO 71797726+phibkro@users.noreply.github"
    ];
  };

  # Root login is disabled over SSH. Wheel without password keeps the
  # SSH key as the single gate to root: no install-time password to set,
  # no rescue-chroot needed for first login. Tradeoff is acceptable on a
  # tailnet-only host with key-only SSH.
  security.sudo.wheelNeedsPassword = false;

  # --- ssh ---------------------------------------------------------------

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };
}
