{ pkgs, lib }:
pkgs.testers.runNixOSTest {
  name = "desktop-settings-unix-ingress";
  nodes.machine = _: {
    users.groups.nori-desktop-settings = { };
    users.groups.nori-desktop-settings-authority = { };
    users.users.nori-desktop-settings = {
      isSystemUser = true;
      group = "nori-desktop-settings";
      extraGroups = [ "nori-desktop-settings-authority" ];
    };
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
    environment.etc."nori-test/backend".text = ''
      #!${pkgs.runtimeShell}
      ${pkgs.coreutils}/bin/dd bs=1 count=11 status=none >/dev/null
      printf 1 >> /tmp/backend-count
      printf '\000\000\000\007allowed'
    '';
  };
  testScript = ''
    start_all()
    machine.succeed("install -d -m 0711 -o nori-desktop-settings -g nori-desktop-settings /run/nori-desktop-settings")
    machine.succeed("stat -c %U:%G:%a /run/nori-desktop-settings | grep -x nori-desktop-settings:nori-desktop-settings:711")
    machine.succeed("install -m 0640 -o root -g nori-desktop-settings-authority /dev/null /run/lock/nori-desktop-settings-activation.lock")
    machine.succeed("stat -c %U:%G:%a /run/lock/nori-desktop-settings-activation.lock | grep -x root:nori-desktop-settings-authority:640")
    machine.succeed("runuser -u nori-desktop-settings -- flock -xn /run/lock/nori-desktop-settings-activation.lock true")
    machine.fail("runuser -u nori -- flock -xn /run/lock/nori-desktop-settings-activation.lock true")
    machine.succeed("runuser -u nori-desktop-settings -- sh -c 'touch /run/nori-desktop-settings/service-file && rm /run/nori-desktop-settings/service-file'")
    machine.fail("runuser -u nori -- touch /run/nori-desktop-settings/nori-file")
    machine.succeed("runuser -u nori-desktop-settings -- sh -c 'touch /run/nori-desktop-settings/service-file'")
    machine.fail("runuser -u nori -- rm -f /run/nori-desktop-settings/service-file")
    machine.succeed("rm /run/nori-desktop-settings/service-file")
    machine.succeed("gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -o /run/nori-desktop-settings/ingress /etc/nori-test/unix-ingress.c")
    machine.succeed("runuser -u nori-desktop-settings -- socat UNIX-LISTEN:/run/nori-desktop-settings/backend.sock,mode=0600,fork EXEC:'${pkgs.runtimeShell} /etc/nori-test/backend' >/tmp/backend.log 2>&1 &")
    machine.wait_until_succeeds("test -S /run/nori-desktop-settings/backend.sock")
    machine.succeed("runuser -u nori-desktop-settings -- /run/nori-desktop-settings/ingress /run/nori-desktop-settings/public.sock /run/nori-desktop-settings/backend.sock 1000 >/tmp/ingress.log 2>&1 &")
    machine.wait_until_succeeds("test -S /run/nori-desktop-settings/public.sock")
    machine.succeed("stat -c %a /run/nori-desktop-settings/public.sock | grep -x 666")
    machine.succeed("printf '\\000\\000\\000\\007allowed' | runuser -u nori -- socat - UNIX-CONNECT:/run/nori-desktop-settings/public.sock | tail -c 7 | grep -x allowed")
    machine.succeed("rm -f /tmp/full-duplex-response; timeout 1 sh -c '(printf \"\\000\\000\\000\\007allowed\"; sleep 2) | runuser -u nori -- socat - UNIX-CONNECT:/run/nori-desktop-settings/public.sock > /tmp/full-duplex-response' || test $? -eq 124")
    machine.succeed("tail -c 7 /tmp/full-duplex-response | grep -x allowed")
    machine.fail("runuser -u nori -- touch /run/nori-desktop-settings/nori-file")
    machine.fail("runuser -u nori -- rm /run/nori-desktop-settings/public.sock")

    # The public socket is reachable by design. The ingress rejects a different
    # peer UID before it can dispatch a request to the protected backend.
    machine.fail("timeout 2 runuser -u other -- sh -c 'printf \"\" | socat - UNIX-CONNECT:/run/nori-desktop-settings/public.sock' | grep -x allowed")

    # The ingress buffers and verifies the complete client half before opening
    # a backend connection. Two frames therefore dispatch zero requests.
    machine.succeed("rm -f /tmp/backend-count")
    machine.fail("printf '\\000\\000\\000\\007allowed\\000\\000\\000\\007allowed' | timeout 2 runuser -u nori -- socat - UNIX-CONNECT:/run/nori-desktop-settings/public.sock | grep -a allowed")
    machine.succeed("test ! -e /tmp/backend-count")

    # Eight incomplete same-UID requests reach the fixed child cap. The ninth
    # cannot reach the backend; after relay timeout reaps the children, a
    # normal request succeeds again.
    machine.succeed("for i in $(seq 1 8); do runuser -u nori -- sh -c 'tail -f /dev/null | socat - UNIX-CONNECT:/run/nori-desktop-settings/public.sock >/dev/null' & done; sleep 1")
    machine.fail("printf '\\000\\000\\000\\007allowed' | timeout 2 runuser -u nori -- socat - UNIX-CONNECT:/run/nori-desktop-settings/public.sock | grep -x allowed")
    machine.succeed("sleep 6; printf '\\000\\000\\000\\007allowed' | runuser -u nori -- socat - UNIX-CONNECT:/run/nori-desktop-settings/public.sock | tail -c 7 | grep -x allowed")
  '';
}
