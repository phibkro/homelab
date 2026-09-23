{ config, pkgs, ... }:
let
  sessionChooser = pkgs.linkFarm "nori-greetd-sessions" [
    {
      name = "plasma.desktop";
      path = "${pkgs.kdePackages.plasma-workspace.sessions}/share/wayland-sessions/plasma.desktop";
    }
    {
      name = "hyprland-uwsm.desktop";
      path = "${config.programs.hyprland.package}/share/wayland-sessions/hyprland-uwsm.desktop";
    }
    {
      name = "plasma-bigscreen-wayland.desktop";
      path = "${pkgs.kdePackages.plasma-bigscreen}/share/wayland-sessions/plasma-bigscreen-wayland.desktop";
    }
  ];
  emptyXSessionDirectory = pkgs.runCommand "nori-greetd-empty-xsessions" { } ''
    mkdir -p "$out"
  '';
in
{
  /*
    Greetd is the only login manager. Tuigreet scans the generated chooser,
    which exposes only Plasma, Plasma Bigscreen, and UWSM-managed Hyprland;
    the empty X11 directory keeps raw X11 desktop files out of its menu.
  */
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --asterisks --sessions /etc/greetd/sessions --xsessions /etc/greetd/xsessions --cmd 'uwsm start hyprland-uwsm.desktop'";
        user = "greeter";
      };
    };
  };

  environment.etc."greetd/sessions".source = sessionChooser;
  environment.etc."greetd/xsessions".source = emptyXSessionDirectory;

  /*
    Gnome Keyring serves Secret Service consumers. Greetd's PAM password is
    forwarded to both keyring implementations so neither needs a second prompt.
  */
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd = {
    enableGnomeKeyring = true;
    kwallet = {
      enable = true;
      # Tuigreet starts from tty1 before the Wayland session exists.
      forceRun = true;
    };
  };
}
