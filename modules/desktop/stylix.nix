{
  inputs,
  pkgs,
  ...
}:

{
  # Stylix — declarative Material You theming. One image input,
  # palette derived via Material You from-image generation, applied
  # across GTK / Qt / Hyprland / Kitty / btop / fuzzel / etc.
  #
  # Replaces the per-target manual config that lived in
  # machines/workstation/home.nix (gtk = { ... }, qt = { ... },
  # home.pointerCursor, dconf, Hyprland env XCURSOR / GTK_THEME).
  # Stylix's NixOS module also extends home-manager when home-manager
  # runs as a NixOS module (the workstation case), so per-user theming
  # comes through the same wire automatically.
  #
  # ── Swapping the wallpaper ───────────────────────────────────────
  # Change `stylix.image` to any local image path. Material You
  # regenerates the palette from the new image at next rebuild;
  # everything restyles in lockstep. To use a downloaded image:
  #   stylix.image = pkgs.fetchurl {
  #     url = "https://...";
  #     hash = "sha256-...";
  #   };
  #
  # ── Opting an app out ────────────────────────────────────────────
  # Stylix is opinionated by default (autoEnable = true). For an app
  # whose Stylix integration fights its own theme, opt out:
  #   stylix.targets.<app>.enable = false;
  # Targets list: https://stylix.danth.me/options/hm.html
  #
  # ── Polarity ─────────────────────────────────────────────────────
  # `dark` forces dark variant regardless of image brightness. Useful
  # when the image is bright but you still want dark UI.

  imports = [ inputs.stylix.nixosModules.stylix ];

  stylix = {
    enable = true;
    polarity = "dark";

    # Starter wallpaper from nixos-artwork. Swap to your own image
    # path or a fetchurl block when you have one you prefer; the
    # whole palette refreshes from whatever you point this at.
    image = "${pkgs.nixos-artwork.wallpapers.nineish-dark-gray}/share/backgrounds/nixos/nix-wallpaper-nineish-dark-gray.png";

    # Cursor — keep Bibata. Stylix would otherwise default to its own
    # cursor pick; this preserves the existing choice. Swap freely.
    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    # Fonts — JetBrainsMono Nerd Font matches the rest of the lab
    # (terminal, code editors). Sans/serif left at Stylix defaults.
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
      };
      sizes = {
        applications = 11;
        terminal = 12;
      };
    };

    # Per-target opt-outs at NixOS scope go here when needed. Targets
    # that live at home-manager scope (hyprlock, alacritty, etc.) opt
    # out from the home-manager config instead — see
    # machines/workstation/home.nix `stylix.targets.<X>.enable`.
  };
}
