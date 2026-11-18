_:
let
  hdt = builtins.getFlake "github:phibkro/hdt-proton-hyprland/53488df8a5ae0b0a7d2bdab16abb3c6da084b031";
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
