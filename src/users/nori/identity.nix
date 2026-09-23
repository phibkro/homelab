{
  config,
  inputs,
  pkgs,
  ...
}:

{
  sops.secrets.nori-console-password-hash = {
    sopsFile = inputs.self + "/secrets/shared-runtime.yaml";
    neededForUsers = true;
  };

  # Both hosts derive the console credential from the same encrypted hash.
  users.mutableUsers = false;

  # --- users -------------------------------------------------------------

  users.users.nori = {
    hashedPasswordFile = config.sops.secrets.nori-console-password-hash.path;
    isNormalUser = true;
    uid = 1000;
    description = "nori";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      # Mac laptop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINZj3DMqIjSV04Yiafw4Td0lQAoQyITCdRS9V/78XrrO 71797726+phibkro@users.noreply.github"
      /*
        workstation — enables SSH-based host activation and operational
        checks over plain OpenSSH instead of Tailscale-SSH, which can
        block waiting for periodic browser authentication. The key
        comment is `nori-station@github`, stale from the pre-rename host;
        the key material remains valid.
      */
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgBC1J2CYrhdwFerwCa9GZD15I03vqS07bFtiYRl2FU nori-station@github"
      # Phone (Termius) — added 2026-06-07. Mobile review of git diffs
      # via `just show-pending-diff` over the tailnet.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOfkUP/F7MJUOL97azKmG2IQXQ+9iQggrpXJUk6LI/UA phone-termius"
    ];
  };
}
