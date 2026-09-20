{
  config,
  pkgs,
  ...
}:
let
  # Remove when nixpkgs carries ansible-lint with upstream commit ed1e94e.
  ansibleLint = pkgs.ansible-lint.overridePythonAttrs (old: {
    dependencies = map (
      dependency: if (dependency.pname or "") == "yamllint" then yamlLint else dependency
    ) old.dependencies;
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/ansiblelint/utils.py \
        --replace-fail \
        'from ansible.module_utils._text import to_bytes' \
        'try:
          from ansible.module_utils.common.text.converters import to_bytes
      except ImportError:  # pragma: no branch
          from ansible.module_utils._text import to_bytes'
    '';
  });

  # Upstream 9dc506b supports pathspec 1.x without deprecated gitwildmatch.
  yamlLint = pkgs.yamllint.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (pkgs.fetchurl {
        url = "https://github.com/adrienverge/yamllint/commit/9dc506b5a1e22a728a95321a7cdb829ba17de0e0.patch";
        hash = "sha256-cPUDZKwHL48Mpc/pSxTP0B8exo44X5Qk7dSNJ/dZ0o8=";
      })
    ];
  });
in
{
  packages = with pkgs; [
    ansible
    ansibleLint
    caddy
    cloud-utils
    curl
    dig
    git
    jq
    iproute2
    nix
    openssh
    qemu
    secretspec
    shellcheck
    util-linux
    watchexec
  ];

  env = {
    ANSIBLE_CONFIG = "${config.devenv.root}/ansible.cfg";
    ANSIBLE_COLLECTIONS_PATH = "${config.devenv.state}/ansible/collections";
  };

  scripts.install-ansible-collections.exec = ''
    ansible-galaxy collection install -r requirements.yml
  '';

  scripts.generate-inventory.exec = ''
    exec bash scripts/generate-inventory.sh "$@"
  '';

  scripts.check.exec = ''
    set -euo pipefail
    install-ansible-collections
    yamllint \
      devenv.yaml \
      inventory \
      playbooks \
      requirements.yml \
      ansible/roles \
      ../common/ansible/roles \
      ../../services/*/ansible \
      tests/vm
    ansible-lint playbooks/pi.yml
    shellcheck scripts/*.sh scripts/tests/*.sh scripts/tests/fixtures/nix \
      ansible/roles/firewall/tests/*.sh \
      ../../services/*/ansible/tests/*.sh ../../.githooks/pre-commit
    ../../services/cloudflare-ddns/ansible/tests/test-contract.sh
    ansible/roles/firewall/tests/test_contract.sh
    ../../services/restic-backup/ansible/tests/test_state_identity.sh
    ../../services/caddy/ansible/tests/test_render.sh
    ../../services/authelia/ansible/tests/test_render.sh
    scripts/tests/generate-inventory.test.sh
    scripts/tests/run-production-inspect.test.sh
    scripts/tests/test-vm-lifecycle.test.sh
    generated_inventory="$(generate-inventory)"
    jq --exit-status \
      '(.pi_appliances.hosts | keys) == ["pi"]
       and .pi_appliances.hosts.pi.pi_domain == "home.phibkro.org"
       and .pi_appliances.hosts.pi.pihole_lan_address == "192.168.1.225"
       and .pi_appliances.hosts.pi.pihole_tailnet_address == "100.100.71.3"
       and .pi_appliances.hosts.pi.pi_backup_enabled == true
       and .pi_appliances.hosts.pi.pi_backup_target_address == "100.81.5.122"
       and .pi_appliances.hosts.pi.pi_backup_target_host == "workstation.saola-matrix.ts.net"
       and ([.pi_appliances.hosts.pi.pi_backup_jobs[].name] | sort)
         == ["authelia", "beszel", "caddy", "ntfy", "pihole", "vector", "victorialogs", "victoriametrics"]
       and (.pi_appliances.hosts.pi.pi_routes | any(.name == "pihole"))
       and (.pi_appliances.hosts.pi.pi_routes | any(.name == "auth"))
       and (.pi_appliances.hosts.pi.pi_routes
         | any(.name == "cache"
               and .upstream_address == "100.107.90.3"
               and .upstream_port == 5000))
       and (.pi_appliances.hosts.pi.pi_routes
         | any(.name == "home"
               and .upstream_address == "192.168.1.225"
               and .upstream_port == 8086))
       and (.pi_appliances.hosts.pi.pi_routes
         | any(.name == "news"
               and .upstream_address == "100.107.90.3"
               and .upstream_port == 8087))
       and (.pi_appliances.hosts.pi.pi_routes
         | any(.name == "vault"
               and .upstream_address == "100.107.90.3"
               and .upstream_port == 8222))
       and ([.pi_appliances.hosts.pi.pi_routes[]
             | select(.upstream_address == "100.107.90.3")
             | .name] | sort)
         == ["cache", "calendar", "filmder", "heim", "news", "ops", "stremio", "vault"]
       and .pi_appliances.hosts.pi.glance_enabled == true
       and .pi_appliances.hosts.pi.pi_tailnet_workload_ports == [8082, 8086]
       and (.pi_appliances.hosts.pi.glance_bookmark_groups | length == 5)
       and (.pi_appliances.hosts.pi.pi_routes | length > 1)
       and ([.pi_appliances.hosts.pi.authelia_oidc_clients[].client_id] | sort)
         == ["metrics", "news", "photos", "vault"]
       and (.pi_appliances.hosts.pi.gatus_endpoints | length > 7)
       and (.pi_appliances.hosts.pi.gatus_endpoints | any(.name == "media"))
       and .pi_appliances.hosts.pi.beszel_systems == [
         {name: "adelie", host: "100.107.90.3", port: 45876},
         {name: "pi", host: "192.168.1.225", port: 45876},
         {name: "workstation", host: "100.81.5.122", port: 45876}
       ]
       and ([.pi_appliances.hosts.pi.victoriametrics_scrape_jobs[].job_name] | sort)
         == ["gatus", "node", "nvidia-gpu", "process", "victoriametrics"]
       and .pi_appliances.hosts.pi.ddns_hostnames == [
         "audio.home.phibkro.org",
         "media.home.phibkro.org",
         "requests.home.phibkro.org"
       ]' \
      "$generated_inventory" >/dev/null
    ansible-inventory --inventory "$generated_inventory" --list \
      | jq --exit-status \
        '.pi_appliances.hosts == ["pi"]
         and ._meta.hostvars.pi.ansible_host != null' >/dev/null
    secretspec schema --profile production >/dev/null
    PI_VM_SSH_KEY=/tmp/not-used \
      PIHOLE_WEB_PASSWORD=syntax-only-password \
      CLOUDFLARE_ACME_TOKEN=syntax-only-cloudflare-token \
      ansible-playbook --syntax-check playbooks/pi.yml
    PI_VM_SSH_KEY=/tmp/not-used \
      ansible-playbook --syntax-check \
        -i inventory/test.yml \
        -e '{"pi_backup_enabled":false}' \
        tests/vm/disable-backups.yml
  '';

  scripts.fix.exec = ''
    set -euo pipefail
    install-ansible-collections
    ansible-lint --fix playbooks/pi.yml
  '';

  scripts.test.exec = ''
    exec bash scripts/test-vm.sh
  '';

  scripts.secrets.exec = ''
    exec secretspec check --profile production "$@"
  '';

  processes.quality.exec = ''
    exec watchexec \
      --postpone \
      --debounce 500ms \
      --clear \
      --watch inventory \
      --watch playbooks \
      --watch ansible/roles \
      --watch ../common/ansible/roles \
      --watch ../../services \
      --watch tests/vm \
      --watch scripts/test-vm.sh \
      --exts yml,yaml,j2,sh,nix \
      --shell bash \
      -- 'fix && check'
  '';

  enterTest = ''
    check
  '';
}
