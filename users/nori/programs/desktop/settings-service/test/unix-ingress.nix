{ pkgs, lib }:
pkgs.testers.runNixOSTest {
  name = "desktop-settings-unix-ingress";
  nodes.machine = { ... }: {
    users.users.nori = {
      isNormalUser = true;
      uid = 1000;
    };
    users.users.other = {
      isNormalUser = true;
      uid = 1001;
    };
    environment.systemPackages = [ pkgs.gcc pkgs.socat pkgs.coreutils pkgs.util-linux ];
    environment.etc."nori-test/unix-ingress.c".source = ../src/unix-ingress.c;
  };
  testScript = ''
    start_all()
    machine.succeed("install -d -m 0700 -o nori -g users /run/nori-ingress")
    machine.succeed("gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -o /run/nori-ingress/ingress /etc/nori-test/unix-ingress.c")
    machine.succeed("chown nori:users /run/nori-ingress/ingress")
    machine.succeed("runuser -u nori -- socat UNIX-LISTEN:/run/nori-ingress/backend.sock,mode=0600,fork EXEC:'${pkgs.coreutils}/bin/echo allowed' >/tmp/backend.log 2>&1 &")
    machine.wait_until_succeeds("test -S /run/nori-ingress/backend.sock")
    machine.succeed("runuser -u nori -- /run/nori-ingress/ingress /run/nori-ingress/public.sock /run/nori-ingress/backend.sock 1000 >/tmp/ingress.log 2>&1 &")
    machine.wait_until_succeeds("test -S /run/nori-ingress/public.sock")
    machine.succeed("stat -c %a /run/nori-ingress/public.sock | grep -x 600")
    machine.succeed("runuser -u nori -- sh -c 'printf \"\" | socat - UNIX-CONNECT:/run/nori-ingress/public.sock' | grep -x allowed")

    # Deliberately relax only this disposable test socket. A different UID can
    # connect, but the ingress must reject it before the backend reads bytes.
    machine.succeed("chmod 0711 /run/nori-ingress && chmod 0666 /run/nori-ingress/public.sock")
    machine.fail("timeout 2 runuser -u other -- sh -c 'printf \"\" | socat - UNIX-CONNECT:/run/nori-ingress/public.sock' | grep -x allowed")
  '';
}
