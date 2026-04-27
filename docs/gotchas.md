# Gotchas

Lessons learned the hard way during Phase 5. Read before doing anything that touches these areas.

## NVMe `/dev` enumeration is unstable

Same physical drive can appear at different `/dev/nvmeNn1` paths between boots. On nori-station: at install time the WD Black SN750 was `/dev/nvme0n1` and the Corsair Force MP510 (Windows) was `/dev/nvme1n1`. After the first reboot they swapped — SN750 is now `nvme1n1`, MP510 is now `nvme0n1`.

**Implication**: never reference `/dev/nvmeN` directly in disko configs or destructive commands. Use `/dev/disk/by-id/<model>-<serial>` paths. They follow the hardware. The disko configs in this repo are by-id-pinned for this reason — a re-run with the original `/dev/nvme0n1` config today would wipe Windows.

Re-derive the current mapping any time you're unsure: `ls /dev/disk/by-id/`.

## Caddy: `acmeCA = "internal"` is wrong

Looks like the right knob, isn't. NixOS module's `services.caddy.acmeCA` takes an ACME directory URL — Caddy will literally try to `dial tcp: lookup internal` and fail.

The right way to switch every vhost to Caddy's internal CA:

```nix
services.caddy.globalConfig = "local_certs";
```

## Caddy: "failed to install root certificate" is non-fatal

When Caddy generates its internal CA, it tries to install the root cert into `/etc/ssl/certs/...` via `tee`. The systemd-hardened service can't write there. You get a noisy error log like:

```
pki.ca.local | failed to install root certificate | error: failed to execute tee: exit status 1
```

Caddy continues serving certs anyway from its own store. Ignore the error. We install the root CA on devices manually + add it to the system trust store via `security.pki.certificateFiles`.

## Python doesn't trust the system CA — `certifi` ships its own

`security.pki.certificateFiles` adds your CA to `/etc/ssl/certs/ca-bundle.crt` — Go, curl, openssl, libcurl all pick it up. **Python doesn't.** httpx / requests / urllib3 default to certifi's bundled trust store, which doesn't include local CAs.

Symptom: `[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: unable to get local issuer certificate`.

Fix: set `SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt"` (and optionally `REQUESTS_CA_BUNDLE` for older requests-based libs) in the service's environment.

## sops env-file format: `=`, not `:`

sops stores everything as YAML, which uses `key: value`. systemd's `EnvironmentFile=` expects env-file syntax: `KEY=VALUE`. When putting an env file into sops as a block string:

```yaml
gatus-env: |
  NTFY_CHANNEL=nori-claude-jhiugyfthgcv     # CORRECT
  NTFY_CHANNEL: nori-claude-jhiugyfthgcv    # WRONG — looks like YAML, won't be loaded
  NTFY-CHANNEL=...                          # WRONG — env vars must be UPPERCASE_WITH_UNDERSCORES
```

Cost us 4 iteration cycles when first wiring Gatus. systemd silently drops unparseable lines — no error, just env vars never appear in the process.

## sops block-string indentation matters

When using `|` for multi-line YAML values, the indent depth is significant. Tabs don't work — use 2 spaces:

```yaml
authelia-oidc-issuer-private-key: |
  -----BEGIN PRIVATE KEY-----
  MIIE...
  -----END PRIVATE KEY-----
```

If indent is wrong (or the value lands on the same line as the key), sops decrypts to an empty string. `sops -d secrets/secrets.yaml | grep <key>` is the fastest way to verify a value is non-empty.

## DynamicUser services: ownership trickery

NixOS services using `DynamicUser=yes` (open-webui, ollama, ntfy-sh, gatus, beszel-hub) get a fresh ephemeral UID at each session. From outside the service namespace, files appear owned `nobody:nogroup`. Implications:

- `chown ollama:ollama /var/lib/ollama` fails — that user doesn't exist statically. Use `chown --reference=<existing-file>` to copy ownership from a sibling.
- StateDirectory= mechanism makes `/var/lib/<name>` appear externally; actual storage is `/var/lib/private/<name>` (bind mount).
- To grant a DynamicUser service read access to /run/secrets files (mode 0440 root:keys), set `SupplementaryGroups = [ "keys" ]` in the systemd unit override.

## Authelia 4.39 requires HTTPS for `authelia_url`

You can't set `authelia_url = "http://..."` in the cookies config — Authelia rejects it at config-validation time as "does not have a secure scheme". Need real HTTPS.

For tailnet-only access, two paths:
1. **`tailscale serve` with HTTPS termination** (auto-LE certs for tailnet hostname): one-time imperative `sudo tailscale serve --bg --https=PORT http://localhost:9091`. Persists in tailscaled state.
2. **Caddy reverse proxy** with internal CA (current setup): `https://auth.nori.lan` via Caddy.

Either works. We chose (2) for consistency with the rest of the *.nori.lan services.

## Tailscale Serve / HTTPS Certs need to be enabled in admin first

`tailscale serve --https=...` returns "Serve is not enabled on your tailnet" until you toggle it in the Tailscale admin console. The CLI gives you the link to click. One-time action per tailnet.

## macOS rsync is openrsync, not GNU rsync

`/usr/bin/rsync` on Sequoia+ is `openrsync` (BSD reimplementation). Many GNU flags missing: `-A` (ACLs), `-X` (xattrs), `--info=stats2`. Worse: openrsync may exit 0 after dumping usage to stderr, so `set -e` doesn't catch it.

For Mac→host rsync, stick to BSD-supported subset: `-aH --no-owner --no-group --stats --partial`. Or install GNU rsync via `brew install rsync` (lands at `/opt/homebrew/bin/rsync`, ahead of `/usr/bin/rsync` on PATH).

## Blocky needs `bootstrapDns` when serving its own host

If nori-station's `/etc/resolv.conf` points at Tailscale's stub (`100.100.100.100`) AND Tailscale's global nameserver is set to nori-station's Blocky (via admin DNS push), there's a self-loop on Blocky restart: Blocky needs DNS to download blocklists, but its own DNS isn't serving yet.

Fix: configure `services.blocky.settings.bootstrapDns` with direct upstream IPs. Used only for Blocky's own outbound URL resolution, bypasses `/etc/resolv.conf`.

```nix
bootstrapDns = [
  { upstream = "1.1.1.1"; }
  { upstream = "9.9.9.9"; }
];
```

Symptom of missing bootstrap: blocklist download times out, denylist ends up empty (count=0), services like doubleclick.net resolve to real CDN IPs instead of 0.0.0.0.

## PocketBase 0.36 OAuth2: per-collection, not global

PocketBase moved OAuth provider configuration from system-wide settings to per-collection (each auth-type collection has its own OAuth config). For Beszel, the auth collection is `users`. Path: Collections (database icon) → users → ⚙ Options → OAuth2 tab. Or via the "Auth with OAuth2" overlay menu (which is greyed out until OAuth2 is enabled for the collection).

## `services.beszel.hub.openFirewall` doesn't exist

The Beszel module doesn't expose `openFirewall`. Use `networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8090 ];` instead. Other NixOS service modules vary; trust `nixos-option` over assumption.

## `services.ollama.acceleration = "cuda"` is deprecated

Removed in current nixpkgs. Use `package = pkgs.ollama-cuda` instead. First build of `ollama-cuda` is slow (~30 min) — nvcc compiles GGML for many CUDA arches and binary cache often misses.

## Gatus ntfy provider: `topic` and `url` are separate

Easy mistake: putting topic in URL like `https://ntfy.sh/<channel>`. Gatus's ntfy provider expects them as separate fields:

```nix
alerting.ntfy = {
  url = "https://ntfy.sh";
  topic = "\${NTFY_CHANNEL}";  # via env substitution
  priority = 4;
};
```

If you put topic in URL, Gatus silently disables the provider (`Ignoring provider=ntfy due to error=topic not set`) — no errors at runtime, alerts just don't send.

## greetd doesn't auto-start at boot without `systemd.defaultUnit = "graphical.target"`

NixOS's greetd unit is `WantedBy = graphical.target`. On a fresh install (or any host that came up without a display manager), the system's `default.target` points at `multi-user.target`, so the boot path never reaches `graphical.target` and greetd just sits enabled-but-inactive. Symptom: boot completes, getty@tty1 stays running, monitor shows the TTY login prompt instead of tuigreet.

```nix
# modules/desktop/greetd.nix — pin the default target
systemd.defaultUnit = "graphical.target";
```

`systemctl start greetd.service` works manually, which is the diagnostic giveaway: the unit is fine, just nothing pulls it in at boot. Enabling a "real" display manager (sddm, lightdm) would also bump the default target as a side effect; greetd doesn't, so we set it explicitly.

## home-manager refuses to clobber pre-existing files in $HOME

Hyprland writes an autogenerated `~/.config/hypr/hyprland.conf` on first launch if no config exists. If a user logs in via tuigreet → Hyprland *before* home-manager has activated their profile (e.g. on first nixos-rebuild that adds Hyprland), the autogen file lands first. home-manager's activation then errors:

```
Existing file '/home/nori/.config/hypr/hyprland.conf' would be clobbered
```

Net effect: HM symlink never lands; SUPER bindings dead; "AUTOGENERATED CONFIG" banner visible in Hyprland. Set:

```nix
home-manager.backupFileExtension = "hm-backup";
```

HM then moves any pre-existing file aside (`<path>.hm-backup`) instead of bailing. Same applies to anything else that auto-generates config under XDG_CONFIG_HOME on first run — fish shell history, gtk settings, etc.

## Wireplumber promotes the wrong sink as default for USB streaming mics

USB streaming mics (Svive Leo, RØDE NT-USB, etc.) expose a playback sink as a sidetone monitor — not real speakers. Wireplumber's "highest capability" heuristic ranks USB devices ahead of onboard analog, so the mic's monitor sink ends up default. Anything plugged into the motherboard 3.5mm jacks plays into the void; volume sliders move but nothing comes out of the headphones.

`wpctl set-default <id>` writes a per-user override (`~/.local/state/wireplumber/default-nodes`) that survives reboots, but a wireplumber rule belt-and-suspenders the priority for fresh users / wiped state:

```nix
environment.etc."wireplumber/wireplumber.conf.d/51-prefer-onboard-analog.conf".text = ''
  monitor.alsa.rules = [
    {
      matches = [
        {
          alsa.mixer_name = "Realtek ALC892"
          media.class = "Audio/Sink"
        }
      ]
      actions = {
        update-props = {
          priority.driver  = 2000
          priority.session = 2000
        }
      }
    }
  ]
'';
```

Match by `alsa.mixer_name` (the codec ID), not `node.name` or PCI path — the codec name is hardware-stable while PCI paths shift with USB device ordering.

## Hyprland 0.55 will deprecate hyprlang in favor of Lua

Heads-up for future `nix flake update` runs. As of April 2026, the latest stable Hyprland is **0.54.3** and uses hyprlang — the format home-manager's `wayland.windowManager.hyprland.settings = { ... }` emits. The Hyprland wiki "Latest git" pages already document an upcoming 0.55 that switches the config language to Lua. The 0.55 binary is not yet tagged on GitHub, and home-manager (master as of 2026-04-26) has no Lua-Hyprland code.

Nix insulates us: the Nix attrset is the source of truth. The break point is when nixpkgs ships Hyprland 0.55 *before* home-manager grows a Lua emitter — at that point the generated hyprland.conf is hyprlang and the binary expects Lua.

**Within-hyprlang change**: `windowrulev2` was unified into `windowrule` in 0.54. The new keyword takes the v2-style matcher syntax with multiple effects on one line:

```
windowrule = match:class ^(com\.saivert\.pwvucontrol)$, float, size 700 500, center
```

See https://wiki.hypr.land/0.54.0/Configuring/Window-Rules/ for the full effect/prop list.

**Mitigations when 0.55 lands in nixpkgs:**
- Pin: `programs.hyprland.package = pkgs.hyprland_0_54;` (nixpkgs typically keeps versioned attrs for major transitions, like `legacy_580` for nvidia drivers)
- Or hold nixpkgs back: don't update the `nixpkgs` flake input past the revision that bumps Hyprland to 0.55, until home-manager catches up

Either way: the Nix-side config doesn't change. Only the rendered output format does.

## mako "Failed to acquire service name" after home-manager restart

When you change `services.mako.settings` and rebuild, home-manager restarts the user unit. The old mako process can outlive the systemd-tracked PID briefly, holding `org.freedesktop.Notifications` on the user's dbus session. The new instance fails to acquire the name and exits:

```
mako: Failed to acquire service name: File exists
mako: Is a notification daemon already running?
```

Fresh boot: never sees this. Iterating on mako config without rebooting: `kill <stale-pid>; systemctl --user start mako.service`. `pkill mako` doesn't work cleanly because the process arg-vector is the unwrapped store path, not "mako" verbatim — kill by PID from `pgrep -af mako`.

## Beszel agent under DynamicUser hides `/dev/nvidia*`

The upstream `services.beszel.agent` module sets `PrivateDevices = !cfg.smartmon.enable`. With smartmon off (the default), `PrivateDevices = true` creates a private `/dev` namespace that omits `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm`. The agent's bundled `nvidia-smi` invocation finds nothing and logs `WARN nvidia-smi found no valid GPU data, stopping` — and the Beszel dashboard's GPU panel stays empty.

Override locally:

```nix
systemd.services.beszel-agent.serviceConfig.PrivateDevices = lib.mkForce false;
```

Loosens just the device namespace; the rest of the upstream hardening (PrivateUsers, ProtectKernel*, SystemCallFilter, RestrictSUIDSGID) stays. See `modules/services/beszel.nix` for the live config.

## NTFS read-only mounts: BitLocker + Fast Startup

Two independent failure modes when adding a `fileSystems."<path>".fsType = "ntfs3"` entry pointing at a Windows partition:

1. **BitLocker.** Win11 enables device encryption by default on supported hardware. `blkid` on a BitLocker-encrypted partition reports `crypto_LUKS` or no `TYPE` rather than `ntfs`. The `ntfs3` driver can't read encrypted partitions; mount fails with `wrong fs type`. Verify before declaring the mount: `blkid /dev/disk/by-id/...-part3` should report `TYPE="ntfs"`. If not, suspend BitLocker from Windows or use `dislocker`.

2. **Fast Startup dirty journal.** Win11's default Shutdown is actually a hibernation-to-disk; the NTFS volume is left with a dirty journal flag. `ntfs3` refuses to mount dirty volumes even read-only as of kernel 6.18. Symptom on first boot: mount fails with "wrong fs type" or "volume is dirty". Fix: boot Windows, choose Restart (not Shutdown) which forces a clean shutdown; OR uncheck "Turn on fast startup" in Power options for a permanent fix.

See `docs/runbooks/inspect-windows-drive.md` for the full procedure.

## Authelia OIDC clients require `X_AUTHELIA_CONFIG_FILTERS=template`

OIDC client `client_secret` values use `{{ secret "/run/secrets/oidc-<n>-client-secret-hash" }}` template syntax (see `modules/lib/lan-route.nix` + `modules/services/authelia.nix`). The substitution only happens when Authelia is invoked with the template config-filter enabled:

```nix
systemd.services.authelia-main.environment.X_AUTHELIA_CONFIG_FILTERS = "template";
```

Without it, Authelia parses the literal `{{ secret "..." }}` string as the client_secret and rejects every OIDC handshake with a hash mismatch. The legacy `_FILE` / `expand-env` substitution paths are explicitly **not** supported for list-typed config sections (which OIDC clients are); template filter is the only working path. `expand-env` is being removed in 4.40.

## Pre-Phase-5 backups (`scripts/backup.sh`) have no integrity verification

`scripts/backup.sh` writes a manifest from in-the-moment `du` of the destination directory. There's no post-write verification, no comparison on subsequent runs. Files can disappear between backup and restore (manual deletion, exfat corruption) and the manifest still claims success. Treat any pre-Phase-5 rsync-to-exfat backup as a snapshot of intent, not a guaranteed source of truth.

For Phase 5+, restic (`backup-restic.nix`) provides `restic check` + content-addressed integrity by design.
