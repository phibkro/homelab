/**
  Disposable proof for the self-hosted Firecracker daemon/client boundary.
*/
{
  pkgs,
  lib,
  inputs,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "e2e-self-hosted-firecracker";
  node.specialArgs = { inherit inputs; };
  nodes.workstation = { ... }: {
    imports = [ ../infra/workstation/firecracker-environment.nix ];
    users.groups.nori.gid = 1000;
    users.users.nori = {
      uid = 1000;
      group = "nori";
      isNormalUser = true;
    };
    nori.selfHostedFirecracker.enable = true;
    networking.hostName = "firecracker-test";
    documentation.enable = lib.mkForce false;
  };
  testScript = ''
    start_all()
    workstation.wait_for_unit("multi-user.target")
    with subtest("unprivileged client and root daemon are installed"):
        workstation.succeed("test -x /run/current-system/sw/bin/agent-engine-self-hosted-launcher")
        workstation.succeed("test -x /run/current-system/sw/bin/firecracker")
        workstation.succeed("test -x /run/current-system/sw/bin/jailer")
        workstation.succeed("systemctl is-active agent-engine-self-hosted-launcher.service")
        workstation.succeed("systemctl show agent-engine-self-hosted-launcher.service -p User | grep -q User=root")
        workstation.succeed("test -S /run/adlc-firecracker/launcher.sock")
        workstation.succeed("stat -c '%a:%g' /run/adlc-firecracker | grep -q '^750:418$'")
        workstation.succeed("stat -c '%a:%g' /run/adlc-firecracker/launcher.sock | grep -q '^660:418$'")
    with subtest("client keeps strict bounded protocol"):
        workstation.fail("printf '{}\\n' | agent-engine-self-hosted-launcher")
        workstation.fail("printf '{\\\"action\\\":\\\"probe\\\"}\\nextra\\n' | agent-engine-self-hosted-launcher")
    with subtest("nori reaches the root daemon through the group socket"):
        status, output = workstation.execute(
            "su -s /bin/sh nori -c 'printf \"{}\\n\" | agent-engine-self-hosted-launcher' 2>&1"
        )
        assert status != 0 and "request action is required" in output and "EACCES" not in output, output
    with subtest("daemon carries VMM isolation policy"):
        props = workstation.succeed("systemctl show agent-engine-self-hosted-launcher.service -p ProtectHome -p ProtectSystem -p RestrictAddressFamilies -p MemoryMax -p TasksMax -p Slice -p DelegateSubgroup")
        assert "ProtectHome=yes" in props and "ProtectSystem=strict" in props, props
        assert "MemoryMax=4294967296" in props and "TasksMax=256" in props, props
        assert "Slice=adlc-firecracker.slice" in props and "AF_NETLINK" in props and "DelegateSubgroup=launcher" in props, props
  '';
}
