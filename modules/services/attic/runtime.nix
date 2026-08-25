{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cachePath = config.nori.fs.cache.path;
  cacheHost = "cache.${config.nori.domain}";
  loopbackBaseUrl = "http://127.0.0.1:5000";
  publicBaseUrl = "https://${cacheHost}";
  cachePublicKey = "attic.nori.lan-1:3zt/aS8K1bSEjNvZQB9ga9OeZTxcRkvbb7aYRI/vobo=";
  bootstrapScript = pkgs.writeShellScript "attic-cache-bootstrap" ''
    set -euo pipefail

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    headers="$tmpdir/headers"
    post_body="$tmpdir/post.json"
    patch_body="$tmpdir/patch.json"
    post_response="$tmpdir/post.response"
    patch_response="$tmpdir/patch.response"
    verify_response="$tmpdir/verify.response"
    api_url="${loopbackBaseUrl}/_api/v1/cache-config/nori"

    # Keep all credential material in root-only runtime files. The curl
    # command line contains only paths to those files, never their contents.
    {
      printf '%s\n' 'Host: ${cacheHost}' 'Content-Type: application/json'
      printf '%s' 'Authorization: Bearer '
      cat ${config.sops.secrets.attic-admin-token.path}
      printf '\n'
    } > "$headers"
    chmod 0400 "$headers"

    # A missing cache returns 404 here; any HTTP response proves that atticd
    # is listening and has accepted the production Host header.
    ready=0
    for _ in $(seq 1 60); do
      status="$(
        curl --silent --show-error --output /dev/null \
          --write-out '%{http_code}' \
          --connect-timeout 1 --max-time 3 \
          --header "@$headers" \
          "${loopbackBaseUrl}/nori/nix-cache-info" 2>/dev/null || true
      )"
      case "$status" in
        000) sleep 1 ;;
        *) ready=1; break ;;
      esac
    done
    if [ "$ready" -ne 1 ]; then
      echo "attic cache bootstrap: atticd did not become ready" >&2
      exit 1
    fi

    # KeypairConfig is an externally tagged Rust enum. --rawfile reads the
    # sops-rendered keypair without putting its private payload in jq argv.
    jq -n \
      --rawfile keypair ${config.sops.secrets.attic-cache-keypair.path} \
      ' {
          keypair: { Keypair: ($keypair | rtrimstr("\n")) },
          is_public: true,
          store_dir: "/nix/store",
          priority: 50,
          upstream_cache_key_names: [
            "cache.nixos.org-1",
            "cache.nixos-cuda.org"
          ]
        }' > "$post_body"

    post_status="$(
      curl --silent --show-error --output "$post_response" \
        --write-out '%{http_code}' \
        --request POST \
        --header "@$headers" \
        --data-binary "@$post_body" \
        "$api_url" || true
    )"
    case "$post_status" in
      2??) ;;
      400)
        if ! jq -e '.error == "CacheAlreadyExists"' "$post_response" >/dev/null 2>&1; then
          echo "attic cache bootstrap: cache creation failed (HTTP $post_status)" >&2
          cat "$post_response" >&2
          exit 1
        fi
        ;;
      *)
        echo "attic cache bootstrap: cache creation failed (HTTP $post_status)" >&2
        cat "$post_response" >&2
        exit 1
        ;;
    esac

    jq -n \
      --rawfile keypair ${config.sops.secrets.attic-cache-keypair.path} \
      ' {
          keypair: { Keypair: ($keypair | rtrimstr("\n")) },
          is_public: true,
          upstream_cache_key_names: [
            "cache.nixos.org-1",
            "cache.nixos-cuda.org"
          ],
          retention_period: { Period: 2592000 }
        }' > "$patch_body"

    patch_status="$(
      curl --silent --show-error --output "$patch_response" \
        --write-out '%{http_code}' \
        --request PATCH \
        --header "@$headers" \
        --data-binary "@$patch_body" \
        "$api_url" || true
    )"
    case "$patch_status" in
      2??) ;;
      *)
        echo "attic cache bootstrap: cache convergence PATCH failed (HTTP $patch_status)" >&2
        cat "$patch_response" >&2
        exit 1
        ;;
    esac

    verify_status="$(
      curl --silent --show-error --output "$verify_response" \
        --write-out '%{http_code}' \
        --request GET \
        --header "@$headers" \
        "$api_url" || true
    )"
    if ! case "$verify_status" in 2??) true ;; *) false ;; esac; then
      echo "attic cache bootstrap: cache convergence read-back failed (HTTP $verify_status)" >&2
      cat "$verify_response" >&2
      exit 1
    fi
    if ! jq -e \
      --arg expected_public_key "${cachePublicKey}" \
      --arg expected_api_endpoint "${publicBaseUrl}/" \
      --arg expected_substituter_endpoint "${publicBaseUrl}/nori" \
      ' .public_key == $expected_public_key
        and .is_public == true
        and .store_dir == "/nix/store"
        and .upstream_cache_key_names == [
          "cache.nixos.org-1",
          "cache.nixos-cuda.org"
        ]
        and .retention_period == { Period: 2592000 }
        and .api_endpoint == $expected_api_endpoint
        and .substituter_endpoint == $expected_substituter_endpoint' \
      "$verify_response" >/dev/null; then
      echo "attic cache bootstrap: cache configuration did not converge" >&2
      cat "$verify_response" >&2
      exit 1
    fi
  '';
in
{
  sops.secrets.attic-jwt-environment = {
    sopsFile = inputs.self + "/secrets/apps.yaml";
    key = "attic_jwt_environment";
    owner = "root";
    mode = "0400";
    restartUnits = [
      "atticd.service"
      "attic-cache-bootstrap.service"
    ];
  };
  sops.secrets.attic-cache-keypair = {
    sopsFile = inputs.self + "/secrets/apps.yaml";
    key = "attic_cache_keypair";
    owner = "root";
    mode = "0400";
    restartUnits = [ "attic-cache-bootstrap.service" ];
  };
  sops.secrets.attic-admin-token = {
    sopsFile = inputs.self + "/secrets/apps.yaml";
    key = "attic_admin_token";
    owner = "root";
    mode = "0400";
    restartUnits = [ "attic-cache-bootstrap.service" ];
  };

  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
    home = "/var/lib/atticd";
  };
  users.groups.atticd = { };

  systemd.tmpfiles.rules = [
    "d ${cachePath} 0750 atticd atticd -"
  ];

  services.atticd = {
    enable = true;
    user = "atticd";
    group = "atticd";
    mode = "monolithic";
    environmentFile = config.sops.secrets.attic-jwt-environment.path;
    settings = {
      listen = "0.0.0.0:5000";
      allowed-hosts = [ cacheHost ];
      api-endpoint = "${publicBaseUrl}/";
      substituter-endpoint = "${publicBaseUrl}/";
      database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      storage = {
        type = "local";
        path = cachePath;
      };
      compression.type = "zstd";
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "30 days";
      };
    };
  };

  # The upstream module defaults to DynamicUser=true. Stable ownership of the
  # OneTouch-backed cache path requires a declared static account instead.
  systemd.services.atticd.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "atticd";
    Group = "atticd";
  };

  systemd.services.attic-cache-bootstrap = {
    description = "Initialize and reconcile the Attic nori cache";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "atticd.service"
    ];
    requires = [ "atticd.service" ];
    path = with pkgs; [
      coreutils
      curl
      jq
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = bootstrapScript;
    };
  };

  nori.harden.atticd.binds = [ cachePath ];
  nori.harden.attic-cache-bootstrap = { };

  nori.backups.atticd.skip = "Attic cache chunks are re-derivable from upstream and local builds; the SQLite state is not backed up.";
  nori.backups.attic-cache-bootstrap.skip = "One-shot Attic cache reconciler has no persistent state.";
}
