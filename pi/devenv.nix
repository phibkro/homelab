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
    generated_inventory="$(generate-inventory)"
    jq --exit-status '.pi_appliances.hosts == ["pi"]' "$generated_inventory" >/dev/null
    secretspec schema --profile production >/dev/null
    PI_VM_SSH_KEY=/tmp/not-used \
      PIHOLE_WEB_PASSWORD=syntax-only-password \
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
