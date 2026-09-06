_: {
  /**
    System-level concerns of the workstation graphical session.
    Per-user HM-only modules (Persona, hypr-lock, hyprsunset, the
    rice implementation) live in `users/nori/programs/desktop/`; user-facing app
    groups compose through `profiles/home/desktop/`.
  */
  imports = [
    ./hyprland.nix
    ../../../services/greetd/nixos.nix
    ./audio.nix
    ./apps.nix
    ./fonts.nix
    ./gaming.nix
    ./virt.nix
    ./stylix.nix
    ../../../services/sunshine/nixos.nix
  ];
}
