/**
  Disposable acceptance of the GitLab authority plane.

  The guest imports the real `nixos.nix` realization with the inventory
  projection, sops-nix decrypting the test fixture, and the shared hardening and
  backup modules. It boots GitLab and observes, in order:

    1. the readiness (also with dependency checks), health and liveness
       endpoints answer 200 on loopback;
    2. the only listeners outside loopback are the host's tailnet address on the
       HTTP port (the guest holds that address on `lo`, as tailscaled would hold
       it on `tailscale0`);
    3. the sealer journey of docs/runbooks/gitlab-authority.md works through
       the tailnet listener: a private project, a protected `main`, protected
       `kwyne/seal/*` tags, and a Maintainer project access token limited to
       `write_repository`. That token seals `main` and an annotated receipt tag
       in one atomic push. A Developer token, a force push, a receipt update and
       a receipt deletion are refused with GitLab's messages, and a refused
       receipt leaves `main` unchanged. The token cannot use the REST API;
    4. one Restic run exports a fresh archive of the database and repositories
       and copies it, and a second run exports again;
    5. a restore over the live instance undoes a later seal, an unprotected
       `main` and a revoked token, and the sealer seals again.

  This proves the module composition and the GitLab behavior it relies on in a
  guest. It does not prove Tailscale delivery, the firewall rule on
  `tailscale0`, the OneTouch SFTP path, or recovery of the real data; those stay
  operator observations.
*/
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  inventory = inputs.self.lib.noriInventory;
  # The manifest owns placement; the guest receives the projection of that host.
  hostName = lib.head inventory.workloads.gitlab.hosts;
  tailnetIp = inventory.hosts.${hostName}.tailnetIp;
  port = toString inventory.workloads.gitlab.listeners.http.port;
  backupTarget = inventory.backup.targetName;

  # Throwaway credential for a guest that is destroyed with the test.
  rootToken = "vm-test-root-token-0123456789";
in
pkgs.testers.runNixOSTest {
  name = "gitlab-authority";

  node.specialArgs = { inherit inputs; };

  nodes.gitlab =
    { lib, pkgs, ... }:
    {
      imports = [
        inputs.sops-nix.nixosModules.sops
        ../../../infra/common/nixos/inventory.nix
        ../../../infra/common/nixos/service-hardening.nix
        ../../../infra/common/nixos/backup.nix
        ../nixos.nix
      ];

      networking.hostName = "gitlab";
      documentation.enable = lib.mkForce false;

      # The projection every real host receives, selected for the GitLab host.
      nori.inventory = inventory // {
        currentHost = hostName;
        currentWorkloads = inventory.hosts.${hostName}.workloads;
      };

      environment.etc."sops-test-age.txt".source = ../../../../tests/keys/test-age.txt;
      sops.age.keyFile = "/etc/sops-test-age.txt";
      sops.age.sshKeyPaths = lib.mkForce [ ];
      sops.defaultSopsFile = ../../../../tests/secrets/test.yaml;
      sops.secrets.restic-password = { };

      nori.backupTargets.${backupTarget} = {
        repository = "/var/lib/test-restic-repo";
        description = "Disposable guest repository";
      };
      systemd.tmpfiles.rules = [ "d /var/lib/test-restic-repo 0700 root root -" ];

      # tailscaled holds this address on tailscale0 in production. The guest
      # has no Tailscale; `lo` carries it so the listener can bind it.
      systemd.services.gitlab-test-tailnet-address = {
        wantedBy = [ "multi-user.target" ];
        before = [ "gitlab-proxy.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.iproute2}/bin/ip addr add ${tailnetIp}/32 dev lo";
        };
      };
      systemd.services.gitlab-proxy = {
        after = [ "gitlab-test-tailnet-address.service" ];
        requires = [ "gitlab-test-tailnet-address.service" ];
      };

      environment.systemPackages = with pkgs; [
        curl
        git
        gnutar
        iproute2
        jq
        restic
      ];

      # The upstream NixOS GitLab test sizes the guest this way.
      virtualisation = {
        memorySize = 6144;
        cores = 4;
        diskSize = 4096;
        useNixStoreImage = true;
        writableStore = false;
      };

      # One Sidekiq thread keeps the guest inside its memory; production keeps
      # the module default. A failing unit must stay failed so the test shows it.
      services.gitlab.sidekiq.concurrency = 1;
      systemd.services.gitlab.serviceConfig.Restart = lib.mkForce "no";
      systemd.services.gitlab-workhorse.serviceConfig.Restart = lib.mkForce "no";
      systemd.services.gitaly.serviceConfig.Restart = lib.mkForce "no";
      systemd.services.gitlab-sidekiq.serviceConfig.Restart = lib.mkForce "no";
    };

  testScript = ''
    import json
    import shlex

    PORT = "${port}"
    TAILNET_IP = "${tailnetIp}"
    LOOPBACK = "http://127.0.0.1:" + PORT
    TAILNET = "http://" + TAILNET_IP + ":" + PORT
    ROOT_TOKEN = "${rootToken}"
    PROJECT_PATH = "root/kwyne"
    ARCHIVE = "/var/lib/gitlab/backup/dump_gitlab_backup.tar"
    RESTIC = (
        "RESTIC_PASSWORD_FILE=/run/secrets/restic-password "
        "RESTIC_REPOSITORY=/var/lib/test-restic-repo/gitlab "
    )
    WORK = "/tmp/work"
    GIT = "git -C " + WORK + " "

    # What GitLab 19.3 answers when it refuses a push. These strings are the
    # enforcement docs/runbooks/gitlab-authority.md relies on; a GitLab upgrade
    # that changes one fails here instead of silently loosening the boundary.
    NOT_PUSH = "You are not allowed to push code to protected branches on this project."
    NOT_INITIAL = "You cannot push the initial commit"
    NOT_FORCE = "You are not allowed to force push code to a protected branch on this project."
    NOT_CREATE_TAG = "You are not allowed to create this tag as it is protected."
    NOT_UPDATE_TAG = "Protected tags cannot be updated."
    NOT_DELETE_TAG = "You can only delete protected tags using the web interface."

    def http_code(url):
        return gitlab.succeed("curl -s -o /dev/null -w '%{http_code}' " + shlex.quote(url)).strip()

    def api(method, path, payload=None, token=ROOT_TOKEN):
        parts = [
            "curl", "-sS", "-X", method,
            "-H", shlex.quote("Authorization: Bearer " + token),
            "-H", shlex.quote("Content-Type: application/json"),
            "-w", shlex.quote("\\n%{http_code}"),
        ]
        if payload is not None:
            parts += ["-d", shlex.quote(json.dumps(payload))]
        parts.append(shlex.quote(LOOPBACK + "/api/v4" + path))
        out = gitlab.succeed(" ".join(parts))
        body, _, status = out.rpartition("\n")
        return int(status), (json.loads(body) if body.strip() else None)

    def remote_url(user, token):
        return shlex.quote("http://" + user + ":" + token + "@" + TAILNET_IP + ":" + PORT + "/" + PROJECT_PATH + ".git")

    def commit(message):
        gitlab.succeed(GIT + "commit -q --allow-empty -m " + shlex.quote(message))
        return gitlab.succeed(GIT + "rev-parse HEAD").strip()

    def remote_refs(url):
        out = gitlab.succeed(GIT + "ls-remote " + url)
        return {ref: sha for sha, ref in (line.split("\t") for line in out.splitlines())}

    def rejected(command, message=None):
        # Merge stderr: GitLab's refusal arrives as "remote: GitLab: <reason>".
        status, output = gitlab.execute(command + " 2>&1")
        assert status != 0, ("accepted", command, output)
        if message is not None:
            assert message in output, (message, output)

    def diagnose():
        # Reached only when a wait below fails; the journal is the evidence.
        print(gitlab.execute(
            "journalctl --no-pager -n 400 -u gitlab-config -u gitlab-db-config -u gitlab-postgresql "
            "-u gitaly -u gitlab-workhorse -u gitlab -u gitlab-sidekiq -u gitlab-proxy"
        )[1])

    def wait_ready():
        for unit in [
            "gitaly.service",
            "gitlab-workhorse.service",
            "gitlab.service",
            "gitlab-sidekiq.service",
            "gitlab-proxy.service",
            "gitlab.target",
        ]:
            gitlab.wait_for_unit(unit)
        gitlab.wait_for_file("/var/lib/gitlab/tmp/sockets/gitlab.socket")
        for path in ["/-/readiness", "/-/readiness?all=1", "/-/health", "/-/liveness"]:
            gitlab.wait_until_succeeds(
                "[ \"$(curl -s -o /dev/null -w '%{http_code}' " + shlex.quote(LOOPBACK + path) + ")\" = 200 ]",
                timeout=600,
            )

    gitlab.start()
    try:
        with subtest("readiness, health and liveness answer 200 on loopback"):
            wait_ready()
    except Exception:
        diagnose()
        raise

    with subtest("only loopback and the tailnet address accept TCP connections"):
        listeners = [line.split()[3] for line in gitlab.succeed("ss -H -ltn").splitlines() if line.strip()]
        outside = [a for a in listeners if not (a.startswith("127.") or a.startswith("[::1]"))]
        assert outside == [TAILNET_IP + ":" + PORT], listeners
        assert sorted(a for a in listeners if a.endswith(":" + PORT)) == sorted(
            ["127.0.0.1:" + PORT, TAILNET_IP + ":" + PORT]
        ), listeners
        assert http_code(TAILNET + "/users/sign_in") == "200"
        # The monitoring allowlist is loopback only. The tailnet listener must not
        # serve the probes or the metrics to a client on the tailnet address.
        for path in ["/-/readiness", "/-/health", "/-/liveness", "/-/metrics"]:
            assert http_code(TAILNET + path) == "404", path

    with subtest("a private project with a protected main, protected seal tags and two tokens"):
        gitlab.succeed(
            "/run/wrappers/bin/sudo -u gitlab gitlab-rails runner \"token = User.find_by_username('root').personal_access_tokens.create(scopes: ['api'], name: 'Test Token', expires_at: 365.days.from_now); token.set_token('"
            + ROOT_TOKEN
            + "'); token.save!\""
        )
        # Runbook step 2: close sign-ups and limit Git to HTTP(S).
        status, settings = api("PUT", "/application/settings", {
            "signup_enabled": False, "enabled_git_access_protocol": "http",
        })
        assert status == 200, (status, settings)
        assert settings["signup_enabled"] is False, settings
        assert settings["enabled_git_access_protocol"] == "http", settings

        status, project = api("POST", "/projects", {
            "name": "kwyne", "visibility": "private", "initialize_with_readme": False,
        })
        assert status == 201, (status, project)
        assert project["path_with_namespace"] == PROJECT_PATH, project["path_with_namespace"]
        project_id = str(project["id"])

        status, rule = api("POST", "/projects/" + project_id + "/protected_branches", {
            "name": "main", "push_access_level": 40, "merge_access_level": 40, "allow_force_push": False,
        })
        assert status == 201, (status, rule)
        assert [level["access_level"] for level in rule["push_access_levels"]] == [40], rule
        assert rule["allow_force_push"] is False, rule

        status, rule = api("POST", "/projects/" + project_id + "/protected_tags", {
            "name": "kwyne/seal/*", "create_access_level": 40,
        })
        assert status == 201, (status, rule)
        assert [level["access_level"] for level in rule["create_access_levels"]] == [40], rule

        expires = gitlab.succeed("date -d '+30 days' +%F").strip()
        tokens = {}
        token_ids = {}
        for name, level in [("sealer", 40), ("reviewer", 30)]:
            status, issued = api("POST", "/projects/" + project_id + "/access_tokens", {
                "name": name, "scopes": ["write_repository"], "access_level": level, "expires_at": expires,
            })
            assert status == 201, (name, status, issued)
            assert issued["scopes"] == ["write_repository"], issued["scopes"]
            assert issued["access_level"] == level, issued
            tokens[name] = issued["token"]
            token_ids[name] = issued["id"]
        SEALER = remote_url("kwyne-sealer", tokens["sealer"])
        REVIEWER = remote_url("kwyne-reviewer", tokens["reviewer"])

        # Anonymous access to a private project fails before any rule matters.
        rejected("GIT_TERMINAL_PROMPT=0 git ls-remote " + shlex.quote(TAILNET + "/" + PROJECT_PATH + ".git"))

    def seal(seal_id, base, sha):
        # The sealer's commit point: main base -> sha with an exact lease, plus
        # an annotated receipt tag, in one atomic push (Spec 009).
        receipt = json.dumps({"sealId": seal_id, "baseSha": base, "sha": sha}, sort_keys=True)
        tag = "kwyne/seal/" + seal_id
        gitlab.succeed(GIT + "tag -a -m " + shlex.quote(receipt) + " " + tag + " " + sha)
        gitlab.succeed(
            GIT + "push --atomic --force-with-lease=refs/heads/main:" + base + " " + SEALER
            + " " + sha + ":refs/heads/main refs/tags/" + tag + ":refs/tags/" + tag
        )
        return receipt

    with subtest("only the Maintainer-level sealer token seeds main and seals it atomically"):
        gitlab.succeed("git config --global user.name sealer && git config --global user.email sealer@example.invalid")
        gitlab.succeed("git init -q -b main " + WORK)
        first = commit("first")

        # A Developer cannot create the protected main; the Maintainer can.
        rejected(GIT + "push " + REVIEWER + " HEAD:refs/heads/main", NOT_INITIAL)
        gitlab.succeed(GIT + "push " + SEALER + " HEAD:refs/heads/main")
        assert remote_refs(SEALER)["refs/heads/main"] == first

        second = commit("second")
        receipt_one = seal("test-1", first, second)
        refs = remote_refs(SEALER)
        assert refs["refs/heads/main"] == second, refs
        assert refs["refs/tags/kwyne/seal/test-1^{}"] == second, refs
        assert refs["refs/tags/kwyne/seal/test-1"] != second, "the receipt must be an annotated tag object"

        # Anyone who can read the repository can read the receipt back.
        gitlab.succeed("git clone -q " + REVIEWER + " /tmp/clone")
        shown = gitlab.succeed("git -C /tmp/clone for-each-ref --format='%(contents)' refs/tags/kwyne/seal/test-1")
        assert shown.strip() == receipt_one, shown

    with subtest("a Developer token moves neither main nor a seal tag"):
        third = commit("third")
        # Controls: the same credential still pushes what protection leaves open.
        gitlab.succeed(GIT + "push " + REVIEWER + " " + third + ":refs/heads/feature")
        gitlab.succeed(GIT + "tag v1 " + third + " && " + GIT + "push " + REVIEWER + " refs/tags/v1")

        rejected(GIT + "push " + REVIEWER + " " + third + ":refs/heads/main", NOT_PUSH)
        gitlab.succeed(GIT + "tag -a -m forged kwyne/seal/forged " + third)
        rejected(GIT + "push " + REVIEWER + " refs/tags/kwyne/seal/forged", NOT_CREATE_TAG)
        rejected(
            GIT + "push --atomic " + REVIEWER + " " + third + ":refs/heads/main refs/tags/kwyne/seal/forged"
        )
        refs = remote_refs(SEALER)
        assert refs["refs/heads/main"] == second, refs
        assert "refs/tags/kwyne/seal/forged" not in refs, refs

    with subtest("the sealer cannot rewrite main or alter and delete receipts"):
        gitlab.succeed(GIT + "checkout -q -b rewrite " + first)
        commit("rewrite")
        rejected(GIT + "push --force " + SEALER + " HEAD:refs/heads/main", NOT_FORCE)
        rejected(GIT + "push " + SEALER + " HEAD:refs/heads/main", "non-fast-forward")
        gitlab.succeed(GIT + "checkout -q main")

        # A receipt is immutable, and a refused receipt takes main down with it.
        gitlab.succeed(GIT + "tag -f -a -m moved kwyne/seal/test-1 " + third)
        rejected(
            GIT + "push --atomic --force " + SEALER + " " + third + ":refs/heads/main refs/tags/kwyne/seal/test-1",
            NOT_UPDATE_TAG,
        )
        rejected(GIT + "push " + SEALER + " :refs/tags/kwyne/seal/test-1", NOT_DELETE_TAG)
        refs = remote_refs(SEALER)
        assert refs["refs/heads/main"] == second, refs
        assert refs["refs/tags/kwyne/seal/test-1^{}"] == second, refs

        # The sealer keeps working: the next seal advances main and adds a receipt.
        seal("test-2", second, third)
        refs = remote_refs(SEALER)
        assert refs["refs/heads/main"] == third, refs
        assert refs["refs/tags/kwyne/seal/test-2^{}"] == third, refs
        assert refs["refs/tags/kwyne/seal/test-1^{}"] == second, refs

    with subtest("a write_repository token cannot call the REST API"):
        status, body = api("GET", "/projects/" + project_id, token=tokens["sealer"])
        assert status == 403, (status, body)
        assert body["error"] == "insufficient_scope", body

    with subtest("one Restic run exports a fresh archive of the database and repositories"):
        gitlab.succeed("systemctl start restic-backups-gitlab-${backupTarget}.service")
        result = gitlab.succeed("systemctl show -p Result --value restic-backups-gitlab-${backupTarget}.service").strip()
        assert result == "success", result
        # The export unit returns to inactive, so the next run exports again.
        state = gitlab.succeed("systemctl show -p ActiveState --value gitlab-backup.service").strip()
        assert state == "inactive", state

        listing = gitlab.succeed("tar -tf " + ARCHIVE).splitlines()
        assert "db/database.sql.gz" in listing, listing
        assert any(entry.startswith("repositories/") and not entry.endswith("/") for entry in listing), listing
        first_run = int(gitlab.succeed("stat -c %Y " + ARCHIVE))

        snapshots = json.loads(gitlab.succeed(RESTIC + "restic snapshots --json"))
        assert len(snapshots) == 1, snapshots
        assert "/var/lib/gitlab/backup" in snapshots[0]["paths"], snapshots[0]["paths"]
        assert "dump_gitlab_backup.tar" in gitlab.succeed(RESTIC + "restic ls latest")

    with subtest("a second Restic run exports again instead of reusing the first archive"):
        gitlab.succeed("systemctl start restic-backups-gitlab-${backupTarget}.service")
        second_run = int(gitlab.succeed("stat -c %Y " + ARCHIVE))
        assert second_run > first_run, (first_run, second_run)
        assert len(json.loads(gitlab.succeed(RESTIC + "restic snapshots --json"))) == 2

    with subtest("a restore over the live instance brings back main, its rules and the tokens"):
        # Change what the archive holds: seal one more commit, unprotect main and
        # revoke the reviewer token. The restore must undo all three.
        fourth = commit("fourth")
        seal("test-3", third, fourth)
        assert remote_refs(SEALER)["refs/heads/main"] == fourth
        status, _ = api("DELETE", "/projects/" + project_id + "/protected_branches/main")
        assert status == 204, status
        status, _ = api("DELETE", "/projects/" + project_id + "/access_tokens/" + str(token_ids["reviewer"]))
        assert status == 204, status
        rejected(GIT + "ls-remote " + REVIEWER)

        # The documented restore. Stopping the target stops every GitLab unit
        # (they are PartOf it), including Gitaly; PostgreSQL and Redis keep
        # running. The restore needs only Gitaly and the configuration unit.
        gitlab.succeed("systemctl stop gitlab.target")
        gitlab.succeed("systemctl start gitlab-config.service gitaly.service gitlab-postgresql.service")
        gitlab.wait_for_file("/var/lib/gitlab/tmp/sockets/gitaly.socket")
        gitlab.succeed("sudo -u gitlab -H gitlab-rake gitlab:backup:restore RAILS_ENV=production BACKUP=dump force=yes")
        gitlab.succeed("systemctl start gitlab.target")
        wait_ready()

        refs = remote_refs(SEALER)
        assert refs["refs/heads/main"] == third, refs
        assert refs["refs/tags/kwyne/seal/test-2^{}"] == third, refs
        assert not any(ref.startswith("refs/tags/kwyne/seal/test-3") for ref in refs), refs
        status, rule = api("GET", "/projects/" + project_id + "/protected_branches/main")
        assert status == 200, (status, rule)
        assert [level["access_level"] for level in rule["push_access_levels"]] == [40], rule
        gitlab.succeed(GIT + "ls-remote " + REVIEWER)

        # The restored instance accepts the sealer's next seal.
        seal("test-4", third, fourth)
        assert remote_refs(SEALER)["refs/heads/main"] == fourth
  '';
}
