_: {
  /**
    Private implementation modules for the reusable Hyprland session.
    The public composition boundary is src/profiles/home/desktop/hyprland-session.nix.
  */
  imports = [
    ./action-model.nix
    ./component-model.nix
    ./hypr-lock.nix
    ./hypr-rice
    ./hyprsunset.nix
    ./persona-quickshell
    ./settings-quickshell
    ./settings-service
    ./vicinae
    ./steady-state-resource-alert.nix
    ./waybar-component.nix
    ./waybar.nix
    ./wayland-pipewire-idle-inhibit.nix
  ];

  /*
    Plasma shares graphical-session.target, so Hyprland-only Wayland daemons
    belong to hyprland-session.target. UWSM's Hyprland session starts and
    stops that target (hypr-rice/runtime.nix), giving every dependent one
    lifecycle root that ends at logout.
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
