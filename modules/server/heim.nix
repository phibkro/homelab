{
  config,
  lib,
  pkgs,
  ...
}:

# heim — operator's portfolio site. Turborepo monorepo with bun, Next.js
# 15-canary at apps/portfolio/, Payload CMS 3.x as the admin/data layer,
# Postgres-backed. Tailnet-only access at https://heim.nori.lan.
#
# ── Postgres: piggyback on the existing instance ─────────────────
# `services.postgresql` is already enabled in this homelab via Immich's
# `services.immich.database.enable = true` (uses the system instance,
# not a private one). v17.9 today. Adding heim's DB + role inline here
# rather than spinning a second postgres or extracting a `nori.app
# Databases` effect — rule of three: heim is the second app on
# postgres (immich the first), wait for a third before extracting.
#
# Auth: UNIX socket peer auth. The heim user runs the build + serve
# units as OS user `heim`; postgres trusts based on OS identity, no
# password-handling round-trip to sops. Connection URL therefore:
#   postgres:///heim?host=/var/run/postgresql
#
# ── Build/serve shape ────────────────────────────────────────────
# Same skeleton as filmder + finnbydel, scaled to a monorepo:
#   * heim-build.service — oneshot, manual via `just deploy-app heim`.
#     Clone → bun install at root (installs all workspace deps via
#     turbo) → bun run build (turbo delegates to next build for the
#     portfolio app, plus any package builds). Sentinel-skip on
#     unchanged commits. ExecStartPost restarts serve.
#   * heim-serve.service — long-running. `bun run start` from
#     apps/portfolio/ (Next.js production server) on 127.0.0.1:9094.
#     Restart-on-failure covers the boot-before-first-build gap.
#
# Caddy reverse-proxies heim.nori.lan → 127.0.0.1:9094.
#
# ── Sops secrets ─────────────────────────────────────────────────
#   payload-secret      Payload CMS encryption secret (random hex)
#   heim-revalidate     Next.js on-demand-ISR webhook secret
#                        (project-prefixed because it's specific to
#                         heim's revalidation route, no other app
#                         consumes it)
#
# To bootstrap (one-time, operator runs):
#   openssl rand -hex 32 | xargs -I{} echo "payload-secret: {}"
#   openssl rand -hex 32 | xargs -I{} echo "heim-revalidate: {}"
#   sops secrets/apps.yaml
#   # paste the two lines, save
#
# ── First-run wizard ─────────────────────────────────────────────
# Payload bootstraps itself on first DB connect (creates collections
# tables from payload.config.ts). After heim-serve is healthy, visit
# https://heim.nori.lan/admin and create the first admin user via the
# form. Subsequent users are managed in the Payload admin UI.

let
  heimRepo = "https://github.com/phibkro/heim.git";
  servePort = 9094;
  publicUrl = "https://heim.nori.lan";

  # UNIX socket peer-auth — heim user → heim DB.
  databaseUri = "postgres:///heim?host=/var/run/postgresql";
in
{
  sops.secrets.payload-secret = {
    sopsFile = ../../secrets/apps.yaml;
    owner = "heim";
    mode = "0400";
  };
  sops.secrets.heim-revalidate = {
    sopsFile = ../../secrets/apps.yaml;
    owner = "heim";
    mode = "0400";
  };

  users.users.heim = {
    isSystemUser = true;
    group = "heim";
    home = "/var/lib/heim";
    description = "heim build + serve user";
  };
  users.groups.heim = { };

  # Add heim to the existing postgres instance — DB + role with
  # ownership. Peer auth handles the connection (no password row
  # needed).
  services.postgresql = {
    ensureDatabases = [ "heim" ];
    ensureUsers = [
      {
        name = "heim";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.heim-build = {
    description = "Build heim (manual trigger via `just deploy-app heim`)";
    after = [
      "network-online.target"
      "postgresql.service"
    ];
    wants = [
      "network-online.target"
      "postgresql.service"
    ];

    path = with pkgs; [
      git
      bun
    ];

    environment = {
      DATABASE_URI = databaseUri;
      DATABASE_URL = databaseUri; # payload reads URI; some next code reads URL
      NEXT_PUBLIC_SERVER_URL = publicUrl;
      NODE_ENV = "production";
    };

    serviceConfig = {
      Type = "oneshot";
      User = "heim";
      Group = "heim";
      StateDirectory = "heim";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/heim";
      ExecStartPost = "+${pkgs.systemd}/bin/systemctl restart heim-serve.service";
    };

    # Inject sops secrets via two-line read (no EnvironmentFile —
    # the secrets are raw values, not key=value pairs, and we want
    # the env var names to be PAYLOAD_SECRET / REVALIDATE_SECRET
    # regardless of what sops keys them as).
    script = ''
      set -euo pipefail

      if [ ! -d src/.git ]; then
        rm -rf src
        git clone --depth 1 ${heimRepo} src
      else
        git -C src fetch --depth 1 origin main
        git -C src reset --hard origin/main
      fi

      cd src

      CURRENT_COMMIT=$(git rev-parse HEAD)
      SENTINEL="$STATE_DIRECTORY/.last-built-commit"
      if [ -f "$SENTINEL" ] \
         && [ "$(cat "$SENTINEL")" = "$CURRENT_COMMIT" ] \
         && [ -d "apps/portfolio/.next" ]; then
        echo "heim already built for $CURRENT_COMMIT — skipping"
        exit 0
      fi

      export PAYLOAD_SECRET="$(cat ${config.sops.secrets.payload-secret.path})"
      export REVALIDATE_SECRET="$(cat ${config.sops.secrets.heim-revalidate.path})"

      # Monorepo install (resolves all workspace deps).
      bun install

      # Turbo orchestrates package builds + portfolio's `next build`.
      bun run build

      echo "$CURRENT_COMMIT" > "$SENTINEL"
    '';
  };

  systemd.services.heim-serve = {
    description = "Serve heim portfolio via Next.js";
    after = [
      "network-online.target"
      "postgresql.service"
    ];
    wants = [
      "network-online.target"
      "postgresql.service"
    ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ bun ];

    environment = {
      DATABASE_URI = databaseUri;
      DATABASE_URL = databaseUri;
      NEXT_PUBLIC_SERVER_URL = publicUrl;
      NODE_ENV = "production";
      PORT = toString servePort;
      HOSTNAME = "127.0.0.1";
    };

    # Skip start until first deploy has produced .next/. Same
    # bootstrap-gap pattern as finnbydel-serve.
    unitConfig.ConditionPathExists = "/var/lib/heim/src/apps/portfolio/.next";

    serviceConfig = {
      Type = "simple";
      User = "heim";
      Group = "heim";

      # StateDirectory ensures /var/lib/heim exists for harden.binds
      # before mount-namespacing runs.
      StateDirectory = "heim";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/heim/src/apps/portfolio";

      # Read sops secrets at start time. systemd loads
      # /run/secrets/* before the unit runs (sops-nix activation
      # ordering), so the cat is safe even on cold boot.
      ExecStart = pkgs.writeShellScript "heim-serve" ''
        set -euo pipefail
        export PAYLOAD_SECRET="$(cat ${config.sops.secrets.payload-secret.path})"
        export REVALIDATE_SECRET="$(cat ${config.sops.secrets.heim-revalidate.path})"
        exec ${pkgs.bun}/bin/bun run start
      '';

      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  nori.lanRoutes.heim = {
    port = servePort;
    audience = "public";
    monitor = { };
    dashboard = {
      title = "Heim";
      icon = "si:nextdotjs";
      group = "Personal";
      description = "Operator's portfolio (Next.js + Payload CMS)";
    };
  };

  nori.harden.heim-build = {
    binds = [
      "/var/lib/heim"
      "/var/run/postgresql" # socket access for postgres CLI tools at build (none invoked today; future-proof)
    ];
  };
  nori.harden.heim-serve = {
    binds = [
      "/var/lib/heim"
      "/var/run/postgresql"
    ];
  };

  # Backup intent: Payload's data lives in postgres, not under
  # /var/lib/heim. The system postgres backup (already covered via
  # restic-backups-postgres if the operator has that route, OR via
  # the immich db backup which dumps the whole instance) handles
  # heim's DB. The /var/lib/heim/src clone is reproducible from
  # github — skip filesystem backup for the source dir.
  nori.backups.heim.skip = "data lives in postgres (covered separately); /var/lib/heim/src is reproducible from github";
}
