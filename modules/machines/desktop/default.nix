_: {
  /**
    System-level concerns of the workstation graphical session.
    Per-user HM-only modules (Persona, mako, hypr-lock, hyprsunset, the
    rice implementation) live in `modules/home/desktop/`; user-facing app
    groups compose through `modules/home/profiles/desktop/`.
  */
  imports = [
    ./hyprland.nix
    ./greetd.nix
    ./audio.nix
    ./apps.nix
    ./fonts.nix
    ./gaming.nix
    ./virt.nix
    ./stylix.nix
    ./sunshine.nix
  ];
}
