_:

{
  /*
    Root login is disabled over SSH. Wheel without password keeps the
    SSH key as the single gate to root: no install-time password to set,
    no rescue-chroot needed for first login. Tradeoff is acceptable on a
    tailnet-only host with key-only SSH.
  */
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
