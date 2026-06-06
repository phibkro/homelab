{ lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  # nori.hosts — topology registry.
  #
  # ── Why this exists ─────────────────────────────────────────────────
  # Cross-host references used to be IP literals scattered through
  # service modules and host files: the Pi tailnet IP appeared in
  # beszel/agent.nix's metrics lanRoute, in ntfy/notify.nix's alert
  # lanRoute, in workstation/default.nix's Gatus probes for the Pi,
  # in modules/effects/lan-route.nix's nori.lanIp default. Six grep hits
  # for "100.100.71.3" and "100.81.5.122". A topology change (Pi swap,
  # tailnet re-auth, replacement device) was a fan-out edit.
  #
  # The registry collapses that into one declaration site. Cross-host
  # refs read `config.nori.hosts.<n>.tailnetIp`; the literal lives in
  # exactly one place (`identityFor` in flake.nix), tied to the
  # host folder structure under ./hosts/ via readDir.
  #
  # ── Why `role` is typed (not free-form) ─────────────────────────────
  # The enum constraint ("workhorse" | "appliance") isn't decoration —
  # it's the key for *placement assertions* elsewhere in the flake.
  # modules/effects/backup.nix asserts that appliance hosts can't have
  # paths-based backups (Pi's flash storage is anti-write; daily restic
  # snapshots to the FIT contradict that posture). Without a typed
  # role tag, that assertion would have to enumerate hostnames or
  # special-case strings — both fragile when a new host lands.
  #
  # The taxonomy:
  #   workhorse — runs heavy compute / state / GPU. State preserved on
  #               real disks. Caddy + Authelia + media + databases live
  #               here. workstation today.
  #   appliance — observability + alerting + DNS + network plumbing.
  #               Survives workhorse failure; alerts the operator when
  #               the workhorse hangs (the 2026-04-28 incident pattern).
  #               Anti-write storage; declarative reproducibility means
  #               losing state is recoverable. pi today.
  #
  # If a future host doesn't fit the binary, *that's the signal* — add
  # the role to the enum, document its constraints, and adjust the
  # assertions that key off role.
  #
  # ── Contract ────────────────────────────────────────────────────────
  # Cross-host references in modules/ and hosts/ MUST go through this
  # registry, not through IP literals. Topology change = edit
  # `identityFor` in flake.nix, redeploy. Adding a new host = create
  # the folder under ./hosts/ AND add an identityFor entry; either
  # omission fails eval.

  options.nori.hosts = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          tailnetIp = mkOption {
            type = types.str;
            description = ''
              Tailnet (100.x.y.z) IP. Stable per device once authed —
              survives reboots and re-IPs. The canonical address for
              cross-host references in this flake.
            '';
          };
          lanIp = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              LAN IP if a static DHCP lease exists; null otherwise.
              Used by ops tooling (Justfile rsync targets) when the
              tailnet hostname doesn't resolve from the operator's
              machine — e.g., `workstation.saola-matrix.ts.net` from
              Mac without tailnet DNS.
            '';
          };
          codename = mkOption {
            type = types.str;
            description = ''
              Aesthetic codename for the host. Used in MOTD, dashboard
              titles, and casual reference — the hostname stays the
              identifier that SSH / known_hosts / Tailscale / nix
              flakes know.

              Theme is cold / polar / penguin. The 2026-06-06 set:
                workstation → emperor   (Emperor penguin — the workhorse)
                macbook     → adelie    (Adélie penguin — small, agile)
                pi          → fairy     (Fairy / Little penguin — the smallest)
                pavilion    → pavilion  (already polar-evocative)
                aurora      → aurora    (polar light)

              Adding a host: pick a codename that fits the theme and
              hints at the host's role.
            '';
          };
          role = mkOption {
            type = types.enum [
              "workhorse"
              "appliance"
              "agent"
            ];
            description = ''
              The host's structural role in the lab:

              * `workhorse` — heavy compute, state-rich services, GPU,
                large disks. Caddy + Authelia + media + DBs live here.
                Backed up to local restic + (planned) off-site Hetzner.

              * `appliance` — observability + alerting + DNS forwarder
                + network plumbing. Designed to survive workhorse
                failure: alerts go out independently via ntfy.sh; DNS
                keeps resolving via the Tailscale push fallback. Has
                anti-write storage (no swap, volatile journald, FIT/SD
                card flash) so paths-based backups are a build error
                via the assertion in modules/effects/backup.nix.

              * `agent` — untrusted-compute quarantine host. Runs the
                nixpkgs-agent harness (pi + box + nix-build verification
                loop). Stateless by design: root on tmpfs via
                impermanence; only `/persist` (ssh host keys, tailscale
                state, machine-id) survives reboot. Worktrees live in
                /tmp and vanish on reboot. No GPU — inference is
                offloaded to the workhorse over tailnet. No claude-code,
                no GH credential, no SSH key inbound from
                appliance/agent tier (the tailscale ACL split). If
                anything were ever to escape the box sandbox, a reboot
                wipes the residue; backups-by-default would be the
                wrong posture, so `nori.backups.<X>` declarations are a
                build error (modules/effects/backup.nix assertion).

              Adding a role: extend the enum, document the constraints,
              and add the assertions that key off it. Don't reuse an
              existing role for a host whose constraints differ.
            '';
          };
        };
      }
    );
    default = { };
    description = ''
      Topology registry. Single source of truth for cross-host
      references. Populated in flake.nix's `identityFor` attrset
      (driven by readDir over ./hosts/).
    '';
  };
}
