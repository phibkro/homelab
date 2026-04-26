{ pkgs, ... }:
{
  # greetd: minimal login manager. tuigreet is a small Rust TUI greeter
  # that fits the keyboard-driven, terminal-leaning aesthetic of the rest
  # of the system (no Qt/KDE pull-in like sddm).
  #
  # Default flow: boot → tty1 → tuigreet (asks for username/password) →
  # exec Hyprland. --remember + --remember-user-session pre-fill the prior
  # username + session at next login.
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --asterisks --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  # greetd's unit is `WantedBy = graphical.target`. Without flipping the
  # system default target, the boot path stops at multi-user.target and
  # greetd never starts (getty@tty1 keeps tty1). Pin default.target to
  # graphical so the desktop comes up automatically.
  systemd.defaultUnit = "graphical.target";

  # tuigreet writes its remembered session/user state here. greetd's NixOS
  # module manages the directory but documenting the path is useful when
  # debugging "why does it keep forgetting my username".
  #   /var/cache/tuigreet/lastuser
  #   /var/cache/tuigreet/lastsession
}
