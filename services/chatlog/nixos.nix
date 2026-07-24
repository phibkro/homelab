{
  config,
  pkgs,
  ...
}:

let
  tailnetIp = config.nori.hosts.${config.networking.hostName}.tailnetIp;
in
{
  /*
    Workbench intentionally binds only to 127.0.0.1:4789. Pi's Caddy runs on
    another host, so systemd exposes a socket exclusively on workstation's
    tailnet address and proxies it back to loopback. FreeBind lets the socket
    exist before Tailscale restores the address during boot; the generated
    lanRoute firewall rule opens 4790 only on tailscale0.
  */
  systemd.sockets.chatlog-relay = {
    description = "Tailnet socket for Chatlog Workbench";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "${tailnetIp}:4790";
      FreeBind = true;
    };
  };

  systemd.services.chatlog-relay = {
    description = "Tailnet relay to loopback-only Chatlog Workbench";
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:4789";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  nori.harden.chatlog-relay = { };

  nori.backups.chatlog.skip = "The relay is stateless; Chatlog's corpus lives under /home and is covered by the user-data backup.";
}
