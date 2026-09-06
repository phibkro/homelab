{
  pkgs,
  ...
}:

{
  # --- users -------------------------------------------------------------

  users.users.nori = {
    isNormalUser = true;
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
        workstation — enables cross-host automation (`just remote pi
        <recipe>`) over plain OpenSSH instead of Tailscale-SSH, which
        periodically wedges silently waiting for browser auth. See
        Mnemopi recall: gotcha-tailscale-ssh-browser-auth. Comment
        in the key is `nori-station@github`, stale from the pre-rename
        host name; key material is the same.
      */
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgBC1J2CYrhdwFerwCa9GZD15I03vqS07bFtiYRl2FU nori-station@github"
      # Phone (Termius) — added 2026-06-07. Mobile review of git diffs
      # via `just show-pending-diff` over the tailnet.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOfkUP/F7MJUOL97azKmG2IQXQ+9iQggrpXJUk6LI/UA phone-termius"
    ];
  };
}
