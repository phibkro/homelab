{ pkgs, ... }:
{
  /*
    greetd: minimal login manager. tuigreet is a small Rust TUI greeter
    that fits the keyboard-driven, terminal-leaning aesthetic of the rest
    of the system (no Qt/KDE pull-in like sddm).

    Default flow: boot → tty1 → tuigreet (asks for username/password) →
    uwsm starts Hyprland with proper systemd-user session integration.
    --remember + --remember-user-session pre-fill the prior username +
    session at next login.

    `uwsm start hyprland-uwsm.desktop`: UWSM wraps Hyprland with a
    systemd-user-session bootstrap that activates graphical-session.target
    (and friends) so user units like waybar/mako/hypridle auto-start
    cleanly. See programs.hyprland.withUWSM in modules/machines/desktop/hyprland.nix.
  */
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --asterisks --cmd 'uwsm start hyprland-uwsm.desktop'";
        user = "greeter";
      };
    };
  };

  /*
    greetd's unit is `WantedBy = graphical.target`. Without flipping the
    system default target, the boot path stops at multi-user.target and
    greetd never starts (getty@tty1 keeps tty1). Pin default.target to
    graphical so the desktop comes up automatically.
  */
  systemd.defaultUnit = "graphical.target";

  /*
    tuigreet writes its remembered session/user state here. greetd's NixOS
    module manages the directory but documenting the path is useful when
    debugging "why does it keep forgetting my username".
      /var/cache/tuigreet/lastuser
      /var/cache/tuigreet/lastsession
  */

  /*
    Secret-service daemon (libsecret backend). Zed and other apps that
    use the Secret Service API store auth tokens here; without it they
    fall back to in-memory only and lose credentials on restart (Zed
    GitHub auth was the trigger). gnome-keyring's NixOS module sets up
    both the daemon and the SSH/secrets/PKCS11 components.
  */
  services.gnome.gnome-keyring.enable = true;

  /*
    PAM hook for auto-unlock: when greetd authenticates the user, the
    login password is also handed to gnome-keyring to unlock the
    default keyring. Without this the keyring exists but stays locked
    until you type the password again — same UX failure as no keyring.
  */
  security.pam.services.greetd.enableGnomeKeyring = true;
}
