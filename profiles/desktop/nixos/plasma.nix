{ pkgs, ... }:
{
  # Plasma contributes its Wayland session and KDE portal policy, not a login manager.
  services.desktopManager.plasma6.enable = true;
  environment.systemPackages = [ pkgs.kdePackages.plasma-bigscreen ];
  # Remote desktop is intentionally outside this profile's scope.
  environment.plasma6.excludePackages = [ pkgs.kdePackages.krdp ];

  # Greetd remains the sole display manager for both graphical hosts.
  services.displayManager.sddm.enable = false;
  services.displayManager.plasma-login-manager.enable = false;
}
