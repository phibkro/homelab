# Sunshine Remote-Desktop Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Sunshine on the workstation so the MacBook (Moonlight) can remote-drive the live Hyprland session over the tailnet for DaVinci Resolve editing.

**Architecture:** A workstation-only NixOS module (`modules/desktop/sunshine.nix`) enables `services.sunshine` with an NVENC-capable package override and KMS capture, scopes its ports to `tailscale0`, and is wired in via `modules/desktop/default.nix`. The MacBook gets Moonlight as a documented Homebrew cask. Pairing and capture are verified at runtime.

**Tech Stack:** NixOS (flake), `services.sunshine` (nixpkgs), NVIDIA NVENC via CUDA, Hyprland/Wayland, Tailscale, Homebrew (Darwin client).

**Note on "TDD" here:** this is declarative config, not a test-suite codebase. The per-task verification is `nix-instantiate --parse` (syntax), `nh os build` / `nix flake check` (eval + build), and runtime checks after `just rebuild` — substituting for unit tests. Commit after each green step.

**Spec deviation (intentional):** the spec mentioned `nori.backups.sunshine.skip`. Dropped — the `every-service-has-{backup-intent,fs-hardening}` flake checks scan `modules/services/*.nix` only; Sunshine is a `modules/desktop/` user service with no homelab state, matching `gaming.nix`/`virt.nix` which carry neither declaration.

**Reference:** design doc `docs/specs/2026-05-22-sunshine-remote-host-design.md`.

---

### Task 1: Create the Sunshine module

**Files:**
- Create: `modules/desktop/sunshine.nix`

- [ ] **Step 1: Write the module**

```nix
{ pkgs, ... }:
{
  # Sunshine — game-stream host for remote desktop over the tailnet.
  # Moonlight (MacBook) connects to drive the workstation's live
  # Hyprland session, primarily for remote DaVinci Resolve editing; the
  # GPU does all encode/render work, the client is thin.
  #
  # Workstation-only by construction: imported via
  # modules/desktop/default.nix, which the darwin MacBook never imports
  # (it pulls only ../../home/pc.nix). Design + rationale:
  # docs/specs/2026-05-22-sunshine-remote-host-design.md.
  services.sunshine = {
    enable = true;

    # NVENC hardware encode on the NVIDIA GPU. cudaSupport pulls CUDA
    # (large closure; unfree, already permitted for davinci-resolve).
    # Without it Sunshine falls back to CPU x264 — high latency + load.
    package = pkgs.sunshine.override { cudaSupport = true; };

    # CAP_SYS_ADMIN for DRM/KMS screen capture — the reliable path on
    # NVIDIA + Wayland (the module adds a setuid-capability wrapper).
    # The usual caveat (apps launched *by* Sunshine run as root) does
    # not apply: we stream the already-running desktop via Sunshine's
    # built-in "Desktop" entry, which launches nothing. If capture
    # black-screens, fall back to wlr capture (capSysAdmin = false) —
    # Hyprland is wlroots-based. See Task 6 fallback.
    capSysAdmin = true;

    # systemd user unit started with graphical-session.target. Needs a
    # logged-in Hyprland session — the greetd prompt is not a session it
    # can attach to (scenario "a": log in once per boot).
    autoStart = true;

    # Ports scoped to tailscale0 below, not opened on all interfaces.
    openFirewall = false;
  };

  # Tailnet-only exposure — mirrors the beszel/ntfy/samba pattern;
  # nothing on LAN/WAN. Ports are Sunshine's default base port (47989)
  # plus the module's own offsets: TCP {-5,0,1,21}, UDP {9,10,11,13,21}.
  # Hardcoded here because openFirewall = false; keep in sync if the
  # base port is ever changed via services.sunshine.settings.port.
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      47984
      47989
      47990 # Sunshine web UI (pairing/config)
      48010
    ];
    allowedUDPPorts = [
      47998
      47999
      48000
      48002
      48010
    ];
  };
}
```

- [ ] **Step 2: Parse-check the file**

Run: `cd /srv/share/projects/homelab && nix-shell -p nix --run 'nix-instantiate --parse modules/desktop/sunshine.nix >/dev/null && echo PARSE OK'`
Expected: `PARSE OK`

- [ ] **Step 3: Commit**

```bash
cd /srv/share/projects/homelab
git add modules/desktop/sunshine.nix
git commit -m "feat(sunshine): workstation remote-desktop host module

NVENC (cudaSupport), KMS capture (capSysAdmin), autostart on graphical
session, ports scoped to tailscale0. Not yet imported — wired in next.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Wire the module into the desktop import set

**Files:**
- Modify: `modules/desktop/default.nix`

- [ ] **Step 1: Add the import**

Add `./sunshine.nix` to the `imports` list. The full list becomes:

```nix
_: {
  imports = [
    ./hyprland.nix
    ./greetd.nix
    ./audio.nix
    ./apps.nix
    ./fonts.nix
    ./waybar.nix
    ./mako.nix
    ./hypr-lock.nix
    ./gaming.nix
    ./virt.nix
    ./stylix.nix
    ./hyprsunset.nix
    ./sunshine.nix
  ];
}
```

- [ ] **Step 2: Parse-check**

Run: `cd /srv/share/projects/homelab && nix-shell -p nix --run 'nix-instantiate --parse modules/desktop/default.nix >/dev/null && echo PARSE OK'`
Expected: `PARSE OK`

- [ ] **Step 3: Commit**

```bash
cd /srv/share/projects/homelab
git add modules/desktop/default.nix
git commit -m "feat(sunshine): import sunshine module into desktop set

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Evaluate + build the workstation config (no switch)

This is the real "test": it proves the module evaluates, the NVENC
package override resolves, and the closure builds — without activating.

**Files:** none (build-only)

- [ ] **Step 1: Build the workstation system**

Run: `cd /srv/share/projects/homelab && just build`
(Justfile `build` = `nh os build . -H $(hostname)`.)
Expected: build succeeds; `nh` summary shows `sunshine` (and CUDA deps) in the ADDED list. First build is slow (CUDA closure).

- [ ] **Step 2: Run flake check**

Run: `cd /srv/share/projects/homelab && nix flake check --print-build-logs 2>&1 | tail -20`
Expected: no assertion failures. In particular, **no** `every-service-has-fs-hardening` / `every-service-has-backup-intent` error naming `sunshine` (it lives in `modules/desktop/`, out of those checks' scope). If one *does* fire, stop and reassess scope — do not silence it.

- [ ] **Step 3: Commit** — nothing to commit (build-only). Proceed.

---

### Task 4: Document Moonlight on the MacBook (Homebrew cask)

**Files:**
- Modify: `machines/macbook/home.nix`

- [ ] **Step 1: Add the inline comment block**

In `home.packages` (the `with pkgs; [ ... ]` list), alongside the
existing ghostty/handbrake/utm cask comments, add a Moonlight entry
matching that style (comment-only — the cask is installed via brew, not
nix). Insert near the other cask notes:

```nix
    # moonlight — game-stream client for the Sunshine host on the
    # workstation (remote DaVinci Resolve editing over the tailnet).
    # GUI cask, not in nixpkgs for Darwin in a usable form here.
    # Brew: `brew install --cask moonlight`. Pair via the Sunshine web
    # UI at https://workstation:47990 over the tailnet.
```

- [ ] **Step 2: Parse-check**

Run: `cd /srv/share/projects/homelab && nix-shell -p nix --run 'nix-instantiate --parse machines/macbook/home.nix >/dev/null && echo PARSE OK'`
Expected: `PARSE OK`

- [ ] **Step 3: Commit**

```bash
cd /srv/share/projects/homelab
git add machines/macbook/home.nix
git commit -m "docs(macbook): note Moonlight cask for Sunshine host

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Rebuild + activate on the workstation

**Files:** none (activation)

- [ ] **Step 1: Rebuild and switch**

Run: `cd /srv/share/projects/homelab && just rebuild`
Expected: exit 0; `nh` shows `sunshine` ADDED; "Activating configuration".

- [ ] **Step 2: Confirm the user service is registered**

Run: `systemctl --user list-unit-files sunshine.service`
Expected: `sunshine.service` listed (enabled/static). If "not found", the graphical-session generation hasn't reloaded — log out/in once.

- [ ] **Step 3: Commit** — nothing (activation only).

---

### Task 6: Pair + verify the live stream

**Files:** none (runtime verification). Manual; requires the MacBook.

- [ ] **Step 1: Confirm Sunshine is running in the session**

On the workstation (inside the Hyprland session): `systemctl --user status sunshine`
Expected: `active (running)`. If it failed: `journalctl --user -u sunshine -e` — look for capture-init errors (see fallback below).

- [ ] **Step 2: Reach the web UI from the MacBook**

On the MacBook over the tailnet, browse `https://workstation:47990`
(accept the self-signed cert). Set the admin username/password on first
load.
Expected: Sunshine dashboard loads. If it times out: verify the tailnet
port with `sudo tailscale status` and `nc -vz workstation 47990` from
the MacBook.

- [ ] **Step 3: Install + pair Moonlight**

On the MacBook: `brew install --cask moonlight`, launch it. Add the host
by tailnet hostname (`workstation`) if mDNS auto-discovery doesn't list
it (mDNS often doesn't traverse the tailnet). Moonlight shows a PIN →
enter it in the Sunshine web UI under "PIN".
Expected: host pairs, "Desktop" app appears in Moonlight.

- [ ] **Step 4: Start a session and verify capture + audio**

Ensure the workstation is logged in (unlock hyprlock if needed — you can
do this over the stream). In Moonlight, launch "Desktop".
Expected: live Hyprland desktop visible, motion smooth, and **audio**
present (play any sound on the workstation). Open DaVinci Resolve and
scrub a clip to confirm usable latency.

**Fallback — if the stream is a black screen (NVIDIA KMS capture fail):**
1. Set `capSysAdmin = false;` in `modules/desktop/sunshine.nix` (switches Sunshine to wlroots/`wlr` capture — Hyprland is wlroots-based).
2. `just rebuild`, then restart capture: `systemctl --user restart sunshine`.
3. Re-test Step 4. If wlr also black-screens, capture `journalctl --user -u sunshine -e` and the `WAYLAND_DISPLAY`/`XDG_SESSION_TYPE` env of the session, and reassess (KMS may need the session on the primary DRM node, or a Sunshine capture env override).

- [ ] **Step 5: Commit** — if the fallback edited the module, commit:

```bash
cd /srv/share/projects/homelab
git add modules/desktop/sunshine.nix
git commit -m "fix(sunshine): use wlr capture (KMS black-screened on NVIDIA)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```
Otherwise nothing to commit — implementation complete.

---

## Self-review notes

- **Spec coverage:** host module (T1) ✓, NVENC override (T1) ✓, capSysAdmin/KMS (T1) ✓, autoStart (T1) ✓, openFirewall=false + tailscale0 ports (T1) ✓, import wiring (T2) ✓, eval/build gate (T3) ✓, Moonlight cask on MacBook (T4) ✓, rebuild (T5) ✓, pairing + verification + black-screen fallback (T6) ✓. The spec's `nori.backups.skip` is intentionally dropped (documented above).
- **Port set:** TCP `[47984 47989 47990 48010]`, UDP `[47998 47999 48000 48002 48010]` — derived from the module's offsets against base 47989, used identically in T1 and verified in T6. Corrects the spec's port list, which omitted UDP 48010.
- **No placeholders:** every code/command step is concrete.
