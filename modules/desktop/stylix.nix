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

    # Material Design palette — base16-schemes/material-darker. Pinned
    # explicitly rather than image-derived because Material You from
    # nixos-artwork wallpapers (tried nineish-dark-gray + mosaic-blue)
    # produced flat washed-out palettes — the source images just
    # don't have enough chromatic variance. A curated palette gives
    # actual Material-Design colors deterministically.
    #
    # Options at /nix/store/<base16-schemes>/share/themes/material-*.yaml:
    #   material-darker    deep slate background, cyan/teal accents (default)
    #   material-lighter   light variant
    #   material-palenight blue-leaning dark
    #   material-vivid     more saturated dark
    #
    # Stylix still needs an `image` for the desktop wallpaper itself
    # (lock screen, login bg) — independent of the palette source.
    base16Scheme = "${pkgs.base16-schemes}/share/themes/material-darker.yaml";
    image = "${pkgs.nixos-artwork.wallpapers.mosaic-blue}/share/backgrounds/nixos/nix-wallpaper-mosaic-blue.png";

    # Cursor — keep Bibata. Stylix would otherwise default to its own
    # cursor pick; this preserves the existing choice. Swap freely.
    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    # Fonts — Material-aligned sans (Roboto) + JetBrainsMono Nerd for
    # mono. Noto covers fallback for missing glyphs; configured at
    # system level via modules/desktop/fonts.nix. Stylix wires these
    # into GTK / Qt / Hyprland chrome / terminal apps in lockstep.
    fonts = {
      sansSerif = {
        package = pkgs.roboto;
        name = "Roboto";
      };
      serif = {
        package = pkgs.roboto;
        name = "Roboto";
      };
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
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

    # Stylix's kmscon module still sets `services.kmscon.extraConfig`
    # and `services.kmscon.fonts`, both removed in nixpkgs unstable
    # (renamed to `services.kmscon.config` + `fonts.packages` +
    # `services.kmscon.config.font-name`). Stylix hasn't caught up yet
    # — the deprecated options trigger eval-time assertions. Disable
    # the integration until upstream Stylix follows. Cost: kmscon TTY
    # rendering doesn't get auto-themed; the rest of Stylix is fine.
    targets.kmscon.enable = false;
  };
}
