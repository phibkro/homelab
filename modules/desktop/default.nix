_: {
  /**
    System-level concerns of the workstation graphical session.
    Per-user HM-only modules (waybar, mako, hypr-lock, hyprsunset, the
    GUI app package list) live in `home/desktop/` and are imported by
    `machines/workstation/home.nix`.
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
