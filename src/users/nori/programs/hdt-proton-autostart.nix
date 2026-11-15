_:
let
  hdt = builtins.getFlake "github:phibkro/hdt-proton-hyprland/d545886cb980ba0d102ef7a6b4cca14b57017996";
in
{
  imports = [ hdt.homeManagerModules.default ];
  programs.hdt-proton = {
    enable = true;
    dataDirectory = "/srv/share/projects/reverse-engineering/hdt-proton";
  };
  # Adopt the project-owned unit until the next full Home Manager activation.
  xdg.configFile."systemd/user/hdt-proton-autostart.service".force = true;
}
