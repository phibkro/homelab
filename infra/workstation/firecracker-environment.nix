{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  staticVersion = "1.16.1";
  staticRelease = pkgs.stdenv.mkDerivation {
    pname = "firecracker-static";
    version = staticVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/firecracker-microvm/firecracker/releases/download/v${staticVersion}/firecracker-v${staticVersion}-x86_64.tgz";
      hash = "sha256-OCoCqGnk1tXLFMQFd/lUXoRYAh6osLLT/BDsFNnCQuY=";
    };
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/bin
      install -Dm555 "$(find . -type f -name 'firecracker-v${staticVersion}-x86_64' -not -name '*.debug' | head -n1)" $out/bin/firecracker
      install -Dm555 "$(find . -type f -name 'jailer-v${staticVersion}-x86_64' -not -name '*.debug' | head -n1)" $out/bin/jailer
    '';
    preferLocalBuild = true;
    meta = {
      description = "Official static Firecracker and matching Jailer release";
      homepage = "https://github.com/firecracker-microvm/firecracker/releases/tag/v${staticVersion}";
      license = lib.licenses.asl20;
      platforms = [ "x86_64-linux" ];
    };
  };

  guest = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules = [
      inputs.microvm.nixosModules.microvm
      (
        { pkgs, ... }:
        {
          networking.hostName = "agent-engine-self-hosted-guest";
          networking.useDHCP = false;
          networking.firewall.enable = true;
          networking.interfaces = { };
          networking.defaultGateway = null;
          networking.nameservers = [ ];
          services.resolved.enable = false;
          services.openssh.enable = false;
          boot.kernelParams = [
            "ip=off"
            "ipv6.disable=1"
          ];
          microvm = {
            guest.enable = true;
            optimize.enable = true;
            hypervisor = "firecracker";
            storeOnDisk = true;
            shares = [ ];
            interfaces = [ ];
            volumes = [
              {
                image = "/var/lib/adlc-firecracker/state.img";
                mountPoint = "/var/lib/omp";
                size = 128;
                autoCreate = false;
                fsType = "ext4";
              }
            ];
            vsock.cid = 3;
          };
          environment.systemPackages = [
            inputs.llm-agents.packages.${system}.omp
            pkgs.bun
            pkgs.socat
            pkgs.iproute2
          ];
          environment.etc."agent-engine-self-hosted-omp/models.yml" = {
            text = ''
              providers:
                offline:
                  baseUrl: http://127.0.0.1:9/v1
                  api: openai-completions
                  auth: none
                  models:
                    - id: offline
                      name: Offline
                      contextWindow: 8192
                      maxTokens: 1024
            '';
            mode = "0444";
          };
          environment.etc."agent-engine-self-hosted-guest.ts" = {
            source = ./firecracker-environment-guest.ts;
            mode = "0555";
          };
          systemd.services.agent-engine-self-hosted-omp = {
            description = "Generation-bound OMP RPC service";
            wantedBy = [ "multi-user.target" ];
            after = [ "local-fs.target" ];
            unitConfig.ConditionPathIsMountPoint = "/var/lib/omp";
            serviceConfig = {
              StandardOutput = "journal+console";
              StandardError = "journal+console";
              ExecStartPre = [
                "${pkgs.coreutils}/bin/mkdir -p /var/lib/omp/.omp/agent"
                "${pkgs.coreutils}/bin/ln -sfn /etc/agent-engine-self-hosted-omp/models.yml /var/lib/omp/.omp/agent/models.yml"
              ];
              ExecStart = "${pkgs.socat}/bin/socat VSOCK-LISTEN:5000,fork EXEC:'${pkgs.bun}/bin/bun /etc/agent-engine-self-hosted-guest.ts'";
              Environment = [
                "HOME=/var/lib/omp"
                "PI_CODING_AGENT_DIR=/var/lib/omp/.omp/agent"
                "XDG_CONFIG_HOME=/var/lib/omp/.config"
                "XDG_DATA_HOME=/var/lib/omp/.local/share"
                "PATH=${inputs.llm-agents.packages.${system}.omp}/bin:${pkgs.bun}/bin:/run/current-system/sw/bin"
              ];
              NoNewPrivileges = false;
              PrivateDevices = true;
              ProtectHome = true;
              ProtectSystem = "strict";
              ReadWritePaths = [
                "/var/lib/omp"
                "/tmp"
              ];
              RestrictAddressFamilies = [
                "AF_UNIX"
                "AF_NETLINK"
                "AF_VSOCK"
              ];
              MemoryMax = "1G";
              TasksMax = 128;
            };
          };
        }
      )
    ];
  };

  launcher = pkgs.writeShellApplication {
    name = "agent-engine-self-hosted-launcher";
    runtimeInputs = [
      pkgs.bun
      pkgs.coreutils
      pkgs.socat
      pkgs.e2fsprogs
      pkgs.util-linux
      pkgs.iproute2
    ];
    text = ''
      export ADLC_FIRECRACKER=${lib.escapeShellArg "${staticRelease}/bin/firecracker"}
      export ADLC_JAILER=${lib.escapeShellArg "${staticRelease}/bin/jailer"}
      export ADLC_GUEST_KERNEL=${lib.escapeShellArg "${guest.config.microvm.kernel.dev}/vmlinux"}
      export ADLC_GUEST_INITRD=${lib.escapeShellArg "${guest.config.system.build.initialRamdisk}/${guest.config.system.boot.loader.initrdFile}"}
      export ADLC_GUEST_STORE=${lib.escapeShellArg (toString guest.config.microvm.storeDisk)}
      export ADLC_GUEST_BOOT_ARGS=${lib.escapeShellArg "console=ttyS0,115200 reboot=k panic=1 i8042.noaux i8042.nomux i8042.nopnp i8042.dumbkbd ${toString guest.config.microvm.kernelParams}"}
      export ADLC_STATE_ROOT=/var/lib/adlc-firecracker
      export ADLC_SOCKET=/run/adlc-firecracker/launcher.sock
      export ADLC_GUEST_UID=418
      export ADLC_GUEST_GID=418
      export ADLC_SOCKET_GID=418
      exec ${pkgs.bun}/bin/bun ${./firecracker-environment-launcher.ts} "$@"
    '';
  };

  cfg = config.nori.selfHostedFirecracker;
in
{
  options.nori.selfHostedFirecracker.enable = lib.mkEnableOption "the local net-off Firecracker Environment launcher";

  config = lib.mkIf cfg.enable {
    users.groups.adlc-firecracker = {
      gid = 418;
    };
    users.users.adlc-firecracker = {
      uid = 418;
      group = "adlc-firecracker";
      isSystemUser = true;
      description = "Unprivileged Firecracker VMM identity";
    };
    users.users.nori.extraGroups = lib.mkAfter [ "adlc-firecracker" ];

    systemd.tmpfiles.settings."10-adlc-firecracker" = {
      "/var/lib/adlc-firecracker".d = {
        user = "root";
        group = "root";
        mode = "0700";
      };
    };

    environment.systemPackages = [
      launcher
      staticRelease
    ];

    systemd.services.agent-engine-self-hosted-launcher = {
      description = "ADLC self-hosted Firecracker root daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "simple";
        Slice = "adlc-firecracker.slice";
        ExecStart = "${launcher}/bin/agent-engine-self-hosted-launcher --daemon";
        User = "root";
        Group = "adlc-firecracker";
        StandardInput = "null";
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = false;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/var/lib/adlc-firecracker"
          "/run/adlc-firecracker"
        ];
        RuntimeDirectory = "adlc-firecracker";
        RuntimeDirectoryMode = "0750";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_VSOCK"
          "AF_NETLINK"
        ];
        Delegate = "cpu io memory pids";
        DelegateSubgroup = "launcher";
        TasksAccounting = true;
        CPUQuota = "100%";
        CPUWeight = 100;
        MemoryHigh = "2G";
        MemoryMax = "4G";
        TasksMax = 256;
        LimitNOFILE = 1024;
        IOSchedulingClass = "best-effort";
      };
    };
  };
}
