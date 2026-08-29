{ config, pkgs, ... }:

{
  packages = with pkgs; [
    ansible
    ansible-lint
    cloud-utils
    curl
    dig
    jq
    nix
    openssh
    qemu
    secretspec
    shellcheck
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
      roles \
      tests/vm
    ansible-lint playbooks/pi.yml
    shellcheck scripts/*.sh ../.githooks/pre-commit
    roles/pihole/tests/test_contract.sh
    roles/authelia/tests/test_contract.sh
    roles/ddns/tests/test-contract.sh
    roles/gatus/tests/test_contract.sh
    roles/ntfy/tests/test_contract.sh
    roles/beszel/tests/test_contract.sh
    roles/victoriametrics/tests/test_contract.sh
    roles/victorialogs/tests/test_contract.sh
    roles/vector/tests/test_contract.sh
    roles/backup/tests/test_contract.sh
    generated_inventory="$(generate-inventory)"
    jq --exit-status \
      '(.pi_appliances.hosts | keys) == ["pi"]
       and .pi_appliances.hosts.pi.pi_domain == "home.phibkro.org"
       and .pi_appliances.hosts.pi.pihole_lan_address == "192.168.1.225"
       and .pi_appliances.hosts.pi.pihole_tailnet_address == "100.100.71.3"
       and .pi_appliances.hosts.pi.pi_routes == [{
         name: "pihole",
         hostname: "pihole.home.phibkro.org",
         upstream_address: "192.168.1.225",
         upstream_port: 8081,
         reachability: "internal"
       }]' \
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
      --watch roles \
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
