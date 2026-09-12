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
    environment.systemPackages = [
      pkgs.gcc
      pkgs.socat
      pkgs.coreutils
      pkgs.util-linux
      pkgs.procps
    ];
    environment.etc."nori-test/unix-ingress.c".source = ../src/unix-ingress.c;
  };
  testScript = ''
    start_all()
    machine.succeed("install -d -m 0700 -o nori -g users /run/nori-ingress")
    machine.succeed("gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -o /run/nori-ingress/ingress /etc/nori-test/unix-ingress.c")
    machine.succeed("runuser -u nori -- socat UNIX-LISTEN:/run/nori-ingress/backend.sock,mode=0600,fork EXEC:'${pkgs.coreutils}/bin/cat' >/tmp/backend.log 2>&1 &")
    machine.wait_until_succeeds("test -S /run/nori-ingress/backend.sock")
    machine.succeed("runuser -u nori -- /run/nori-ingress/ingress /run/nori-ingress/public.sock /run/nori-ingress/backend.sock 1000 >/tmp/ingress.log 2>&1 &")
    machine.wait_until_succeeds("test -S /run/nori-ingress/public.sock")
    machine.succeed("stat -c %a /run/nori-ingress/public.sock | grep -x 660")
    machine.succeed("printf '\\000\\000\\000\\007allowed' | runuser -u nori -- socat - UNIX-CONNECT:/run/nori-ingress/public.sock | tail -c 7 | grep -x allowed")

    # Deliberately relax only this disposable test socket. A different UID can
    # connect, but the ingress must reject it before the backend reads bytes.
    machine.succeed("chmod 0711 /run/nori-ingress && chmod 0666 /run/nori-ingress/public.sock")
    machine.fail("timeout 2 runuser -u other -- sh -c 'printf \"\" | socat - UNIX-CONNECT:/run/nori-ingress/public.sock' | grep -x allowed")

    # The ingress accepts only one bounded frame. A second complete frame is
    # rejected before it can become a second backend request.
    machine.fail("printf '\\000\\000\\000\\007allowed\\000\\000\\000\\007allowed' | timeout 2 runuser -u nori -- socat - UNIX-CONNECT:/run/nori-ingress/public.sock | grep -a allowed")

    # Eight incomplete same-UID requests reach the fixed child cap. The ninth
    # cannot reach the backend; after relay timeout reaps the children, a
    # normal request succeeds again.
    machine.succeed("for i in $(seq 1 8); do runuser -u nori -- sh -c 'tail -f /dev/null | socat - UNIX-CONNECT:/run/nori-ingress/public.sock >/dev/null' & done; sleep 1")
    machine.fail("printf '\\000\\000\\000\\007allowed' | timeout 2 runuser -u nori -- socat - UNIX-CONNECT:/run/nori-ingress/public.sock | grep -x allowed")
    machine.succeed("sleep 6; printf '\\000\\000\\000\\007allowed' | runuser -u nori -- socat - UNIX-CONNECT:/run/nori-ingress/public.sock | tail -c 7 | grep -x allowed")
  '';
}
