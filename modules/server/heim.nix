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

  # Sharp (image-processing dep pulled in by Payload CMS) ships a
  # native binary that loads libstdc++.so.6 at runtime via dlopen.
  # NixOS systemd's minimal env doesn't have libstdc++ on the
  # dynamic-linker path, so the build crashes during page-data
  # collection with `ERR_DLOPEN_FAILED: libstdc++.so.6: cannot open
  # shared object file`. Pointing LD_LIBRARY_PATH at the C++ stdlib
  # from pkgs.stdenv resolves it. Required for both build (sharp
  # loads during Next.js page-data collection) and serve (sharp
  # called per image-transform request at runtime).
  ldLibraryPath = lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
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

  # Postgres dependency declared explicitly even though Immich
  # already enables the system instance — local reasoning. Reading
  # heim.nix should answer "what does heim need?" without chasing
  # side effects from sibling modules. NixOS module merging is
  # idempotent on `enable = true`, so multiple declarants are fine.
  # If heim ever lands on a host without immich (split-stack later,
  # or a future deploy environment), this still works.
  services.postgresql = {
    enable = true;
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
      # nodejs_24 needed for `npx payload` — bun's `bunx payload`
      # fails with `Cannot find module 'tsx://...'` because Payload's
      # CLI uses tsx's URL-scheme loader which bun's resolver doesn't
      # support (bun-tsx-payload known incompat). Falling back to
      # node+npx for the migrate step works since bun's install layer
      # already populated node_modules/.bin/ in npm-compatible shape.
      nodejs_24
      # bash for npm/npx postinstall + child-spawn — same gotcha
      # that filmder hit (docs/gotchas.md "npm postinstall on systemd
      # needs bash on the unit path"). Surfaces here as
      # `npm error enoent spawn sh ENOENT`.
      bash
    ];

    environment = {
      DATABASE_URI = databaseUri;
      DATABASE_URL = databaseUri; # payload reads URI; some next code reads URL
      NEXT_PUBLIC_SERVER_URL = publicUrl;
      NODE_ENV = "production";
      LD_LIBRARY_PATH = ldLibraryPath;
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

      # Schema sync handled at runtime by postgresAdapter's
      # `push: true` (see apps/portfolio/payload.config.ts) —
      # heim-serve's first connect creates the tables via Drizzle
      # push. Build skips DB queries entirely because every
      # Payload-using route declares `export const dynamic =
      # "force-dynamic"`, which makes Next.js render per-request
      # instead of pre-generating at build time.
      #
      # No `payload migrate:push` step here because that route
      # tripped on bun + tsx + Payload-CLI ESM-resolution incompat
      # (extensionless TS imports in payload.config.ts). Pushing
      # the schema-management responsibility to runtime simplifies
      # the build pipeline + keeps it pure-bun.

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
      LD_LIBRARY_PATH = ldLibraryPath;
    };

    # Skip start until a *complete* Next.js build exists. BUILD_ID
    # is the file Next writes only on successful build — pointing
    # at the directory itself would match a half-failed build that
    # left a corrupt .next/ on disk, which then trips
    # `Could not find a production build in the '.next' directory`
    # at start time and infinite-restart-loops.
    unitConfig.ConditionPathExists = "/var/lib/heim/src/apps/portfolio/.next/BUILD_ID";

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
