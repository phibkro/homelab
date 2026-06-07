{ pkgs, ... }:
{
  # System-level wiring for desktop apps. The user-tier package list
  # (browsers, editors, Wayland CLI utilities, etc.) lives in
  # home/desktop/apps.nix — only NixOS-module-only things stay here:
  # the file-manager xdg-mime registration + the thumbnail daemon.

  # Thunar — lightweight GUI file manager. Enabling via programs.thunar
  # (rather than just adding the package) registers it as the default
  # file:// handler so other apps' "open file manager" buttons land here,
  # plus loads its plugin set in-process.
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin # right-click extract / compress (menu only)
      thunar-volman # auto-mount USB / removable media
    ];
  };

  # Thumbnail daemon — Thunar (and other XDG file managers) talk to it
  # over D-Bus to render image/PDF/video thumbnails in place instead of
  # generic mime icons. Without this, folder views look "low-res" even
  # with a proper icon theme — Stylix paints chrome but the file tiles
  # stay as scaled-up mime symbols.
  services.tumbler.enable = true;
}
