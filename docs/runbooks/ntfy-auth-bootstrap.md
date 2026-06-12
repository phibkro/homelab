# ntfy auth tightening

Switch pi's ntfy hub from `auth-default-access = read-write` (current) to `deny` + per-publisher tokens. Wave-2 deep-clean output: prevent alert spoofing from agentic tailnet workloads.

## Why

Today any tailnet device can `POST https://alert.home.phibkro.org/<topic>` with arbitrary body and the operator's phone trusts the alert (because the topic on ntfy.sh side is one the operator subscribes to). Two compounding risks:

1. **Pavilion runs agents in sandboxes** — claude-code, hermes worktrees. A compromised dependency in that scope can publish convincing-looking alerts ("RAID degraded — please run `<malicious command>` to recover"), conditioning the operator to act on spoofed instructions.
2. **The local ntfy hub is on pi, on the tailnet** — the deny-by-default posture documented in NETWORK.md isn't load-bearing here; ntfy is the explicit exception.

Today's two real publishers:

- **Gatus** — uptime probe failure alerts → ntfy.sh directly (sees its token via env-file).
- **`notify@.service` template** — OnFailure hook on systemd units → also ntfy.sh.

Both publish to ntfy.sh (public), not the local hub. The local hub is pre-positioned for future internal-only alerts. Tightening its auth posture closes the spoofing surface even before anything depends on it.

## Bootstrap

### 1. Define the publisher token in sops

```sh
sops secrets/secrets.yaml
```

Generate a strong opaque token:

```yaml
ntfy-publisher-token: 'ntfy_<32-char base64 random>'
```

You can generate with: `nix shell nixpkgs#openssl -c openssl rand -base64 24 | tr -d '/+=' | head -c 32 | sed 's/^/ntfy_/'`.

### 2. Edit `modules/services/ntfy/server.nix`

Replace the auth-default-access line and add the imperative user setup:

```nix
sops.secrets.ntfy-publisher-token = {
  owner = "ntfy-sh";
  mode = "0400";
};

services.ntfy-sh = {
  enable = true;
  settings = {
    base-url = "https://alert.${config.nori.domain}";
    listen-http = ":8081";
    auth-default-access = "deny";    # was "read-write"
    behind-proxy = false;
    auth-file = "/var/lib/ntfy-sh/user.db";
  };
};

# Imperative user provisioning — ntfy doesn't have a NixOS-declarative
# users option (upstream tracks #150). Runs once per generation; idempotent
# (`ntfy user add` is a no-op if the user exists).
systemd.services.ntfy-sh-bootstrap = {
  description = "Provision ntfy publisher user from sops";
  after = [ "ntfy-sh.service" ];
  wantedBy = [ "ntfy-sh.service" ];
  serviceConfig.Type = "oneshot";
  serviceConfig.User = "ntfy-sh";
  serviceConfig.LoadCredential = "token:${config.sops.secrets.ntfy-publisher-token.path}";
  script = ''
    token=$(cat $CREDENTIALS_DIRECTORY/token)
    ${pkgs.ntfy-sh}/bin/ntfy user add --role=admin publisher "$token" || true
  '';
};
```

### 3. Wire publishers to send the Authorization header

**Gatus** (`modules/services/gatus.nix`) — add the env-file consumption and the `Authorization` header to the ntfy provider config:

```nix
sops.secrets.ntfy-publisher-token = { /* already declared in ntfy server module */ };

services.gatus.settings.alerting.ntfy = {
  url = "https://alert.${config.nori.domain}";   # was https://ntfy.sh
  topic = "\${NTFY_CHANNEL}";
  token = "\${NTFY_PUBLISHER_TOKEN}";            # NEW
  priority = 4;
};

systemd.services.gatus.serviceConfig.LoadCredential = [
  "token:${config.sops.secrets.ntfy-publisher-token.path}"
];
# Splice NTFY_PUBLISHER_TOKEN into the existing environmentFile via wrapper.
```

**`notify@` template** (`modules/services/notify.nix`) — add the bearer header to its curl call:

```nix
script = ''
  curl -sf \
    -H "Authorization: Bearer $(cat $CREDENTIALS_DIRECTORY/token)" \
    -H "Title: %i failed" \
    -d "@${journal output}" \
    "https://alert.${config.nori.domain}/${topic}"
'';
serviceConfig.LoadCredential = [
  "token:${config.sops.secrets.ntfy-publisher-token.path}"
];
```

### 4. Rebuild pi

```sh
just remote pi rebuild
```

First boot of the new generation: the bootstrap unit creates the `publisher` user with the operator-supplied token. Subsequent rebuilds are no-ops.

### 5. Verify

```sh
# Should now require the token:
curl -d "test" https://alert.home.phibkro.org/test
# → 401 Unauthorized

# With token:
curl -d "test" \
  -H "Authorization: Bearer ntfy_..." \
  https://alert.home.phibkro.org/test
# → 200 OK
```

Then trigger a deliberate gatus failure (stop a watched service for >3 probe intervals) and confirm the alert lands on the operator's phone as before.

## Rollback

Revert the ntfy/server.nix changes. The sops secret can stay (harmless).

Live ntfy user database (`/var/lib/ntfy-sh/user.db`) persists across rebuilds — you may need to `sudo systemctl stop ntfy-sh && sudo rm /var/lib/ntfy-sh/user.db && sudo systemctl start ntfy-sh` to fully revert to no-auth.

## Future direction

Move from one shared `publisher` token to per-publisher tokens (`gatus-publisher`, `notify-publisher`, `pavilion-publisher`, etc.) when a third publisher arrives. Today's single-token model collapses cleanly into per-publisher via the same bootstrap unit — add more `ntfy user add` lines, declare more sops secrets.
