{ config, pkgs, ... }:

{
  packages = with pkgs; [
    ansible
    ansible-lint
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
    yamllint
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
    ../../services/pihole/ansible/tests/test_contract.sh
    ../../services/authelia/ansible/tests/test_contract.sh
    ../../services/cloudflare-ddns/ansible/tests/test-contract.sh
    ansible/roles/firewall/tests/test_contract.sh
    ../../services/gatus/ansible/tests/test_contract.sh
    ../../services/ntfy/ansible/tests/test_contract.sh
    ../../services/beszel/ansible/hub/tests/test_contract.sh
    ../../services/beszel/ansible/agent/tests/test_contract.sh
    ../../services/heartbeat/ansible/tests/test_contract.sh
    ../../services/victoriametrics/ansible/tests/test_contract.sh
    ../../services/victorialogs/ansible/tests/test_contract.sh
    ../../services/vector/ansible/tests/test_contract.sh
    ../../services/restic-backup/ansible/tests/test_contract.sh
    ../../services/restic-backup/ansible/tests/test_state_identity.sh
    ../../services/caddy/ansible/tests/test_contract.sh
    ../../services/caddy/ansible/tests/test_render.sh
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
               and .upstream_address == "100.81.5.122"
               and .upstream_port == 5000))
       and (.pi_appliances.hosts.pi.pi_routes | length > 1)
       and ([.pi_appliances.hosts.pi.authelia_oidc_clients[].client_id] | sort)
         == ["metrics", "news", "photos", "vault"]
       and (.pi_appliances.hosts.pi.gatus_endpoints | length > 7)
       and (.pi_appliances.hosts.pi.gatus_endpoints | any(.name == "media"))
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
