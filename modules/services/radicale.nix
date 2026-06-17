{ config, lib, ... }:

lib.mkMerge [
  {
    nori.services.radicale.tags = [
      "family-tier"
      "stateful"
    ];

    nori.lanRoutes.calendar = {
      port = 5232;
      runsOn = "aurora";
      exposeOnTailnet = true;
      monitor.path = "/.web/";
      audience = "family";
      dashboard = {
        title = "Radicale";
        icon = "sh:radicale";
        group = "Personal";
        description = "CalDAV / CardDAV — phone calendar + contacts";
      };
    };
  }
  (lib.mkIf config.nori.services.radicale.enabled {
    /*
      Radicale — CalDAV + CardDAV server. Replaces Google Calendar /
      Contacts dependency for the household. Phones (iOS Calendar,
      Android DAVx5) sync to https://calendar.nori.lan/ over the tailnet.

      First-run setup:
        1. Create the htpasswd file (one-time, on the host):
             sudo nix run nixpkgs#apacheHttpd -- htpasswd -B -c \
               /var/lib/radicale/users nori
             sudo chown radicale:radicale /var/lib/radicale/users
             sudo chmod 0640 /var/lib/radicale/users
        2. Visit https://calendar.nori.lan, log in with the credentials
           set above. Create a default calendar + addressbook for nori.
        3. On the iPhone: Settings → Calendar → Accounts → Add Account →
           Other → CalDAV. Server: calendar.nori.lan, user/pass as set.
           Same shape for CardDAV.
        4. On Android: install DAVx5 (F-Droid), add account with the
           base URL https://calendar.nori.lan and creds.
    */
    services.radicale = {
      enable = true;
      settings = {
        server.hosts = [ "0.0.0.0:5232" ];
        auth = {
          type = "htpasswd";
          htpasswd_filename = "/var/lib/radicale/users";
          htpasswd_encryption = "bcrypt";
        };
        storage.filesystem_folder = "/var/lib/radicale/collections";
      };
    };

    # Bootstrap an empty htpasswd file so the service starts on first run
    # (operator runs `htpasswd -B -c` to seed the real entry — see header).
    systemd.tmpfiles.rules = [
      "f /var/lib/radicale/users 0640 radicale radicale - "
    ];

    nori.harden.radicale = { };

    # Pattern A — file-snapshot consistency is fine, radicale writes one
    # .ics / .vcf per event and the whole tree is tiny (~8K).
    nori.backups.radicale.include = [ "/var/lib/radicale" ];
  })
]
