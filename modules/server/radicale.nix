{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Radicale — CalDAV + CardDAV server. Replaces Google Calendar /
  # Contacts dependency for the household. Phones (iOS Calendar,
  # Android DAVx5) sync to https://calendar.nori.lan/ over the tailnet.
  #
  # Default port 5232. Backed by plain filesystem (one .ics / .vcf per
  # event/contact under /var/lib/radicale/collections) — restic Pattern
  # A backup picks it up via the existing user-data job once that path
  # is added (TODO).
  #
  # First-run setup:
  #   1. Create the htpasswd file (one-time, on the host):
  #        sudo nix run nixpkgs#apacheHttpd -- htpasswd -B -c \
  #          /var/lib/radicale/users nori
  #        sudo chown radicale:radicale /var/lib/radicale/users
  #        sudo chmod 0640 /var/lib/radicale/users
  #   2. Visit https://calendar.nori.lan, log in with the credentials
  #      set above. Create a default calendar + addressbook for nori.
  #   3. On the iPhone: Settings → Calendar → Accounts → Add Account →
  #      Other → CalDAV. Server: calendar.nori.lan, user/pass as set.
  #      Same shape for CardDAV.
  #   4. On Android: install DAVx5 (F-Droid), add account with the
  #      base URL https://calendar.nori.lan and creds.
  #
  # Multi-user: htpasswd file holds entries per user. Each user gets a
  # collections dir under /var/lib/radicale/collections/<user>/.
  services.radicale = {
    enable = true;
    settings = {
      server.hosts = [ "127.0.0.1:5232" ];
      auth = {
        type = "htpasswd";
        htpasswd_filename = "/var/lib/radicale/users";
        htpasswd_encryption = "bcrypt";
      };
      storage.filesystem_folder = "/var/lib/radicale/collections";
    };
  };

  # Bootstrap an empty htpasswd file so the service starts on first run.
  # Adding a user is `sudo htpasswd -B /var/lib/radicale/users <name>`
  # (see header comment).
  systemd.tmpfiles.rules = [
    "f /var/lib/radicale/users 0640 radicale radicale - "
  ];

  nori.harden.radicale = { };

  nori.lanRoutes.calendar = {
    port = 5232;
    monitor.path = "/.web/";
    dashboard = {
      title = "Radicale";
      icon = "sh:radicale";
      group = "Personal";
      description = "CalDAV / CardDAV — phone calendar + contacts";
    };
  };

  # Pattern A — calendars (CalDAV) and contacts (CardDAV) are
  # irreplaceable user data. Tiny (~8K) so daily restic is free.
  # Static `radicale` user, real /var/lib/radicale dir.
  nori.backups.radicale.paths = [ "/var/lib/radicale" ];
}
