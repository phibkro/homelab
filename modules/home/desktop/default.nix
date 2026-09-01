_: {
  /**
    Private implementation modules for the Wayland/Hyprland session.
    The public composition boundary is profiles/desktop/default.nix.
  */
  imports = [
    ./hypr-lock.nix
    ./hypr-rice
    ./hyprsunset.nix
    ./persona-quickshell
    ./steady-state-resource-alert.nix
    ./waybar.nix
    ./wayland-pipewire-idle-inhibit.nix
  ];

  /*
    This desktop is Hyprland-only, so Wayland daemons belong to the
    compositor's session target rather than the generic graphical target.
    The user manager persists across logouts; graphical-session.target can
    therefore remain active at the greeter and leave failed services inert on
    the next login. hyprland-session.target is bounced after Hyprland imports
    its fresh display environment, giving every dependent one lifecycle root.
  */
  wayland.systemd.target = "hyprland-session.target";

  nori.hyprRice.enable = true;

  nori.steadyStateResourceAlert = {
    enable = true;
    targets = {
      persona-widgets = {
        unit = "persona-quickshell.service";
        progressEvidence = "The desktop widgets provide a fixed interactive surface after startup; useful output does not grow with heap, swap, descriptors, or tasks.";
        # First use of all three video-backed overlays establishes a measured
        # ~700 MiB QtMultimedia high-water mark; growth beyond 768 MiB is not warm-up.
        memoryGrowthBytes = 805306368;
        memoryGrowthPercent = 50;
      };
      persona-wallpaper = {
        unit = "persona-quickshell-wallpaper.service";
        progressEvidence = "The wallpaper provides one continuously available visual surface; useful output does not grow with heap, swap, descriptors, or tasks.";
        memoryGrowthBytes = 536870912;
        memoryGrowthPercent = 50;
      };
      waybar = {
        unit = "waybar.service";
        progressEvidence = "Waybar provides one fixed status surface; useful output does not grow with heap, swap, descriptors, or tasks.";
        warmupSeconds = 300;
        memoryGrowthBytes = 134217728;
        memoryGrowthPercent = 100;
      };
    };
  };
}
