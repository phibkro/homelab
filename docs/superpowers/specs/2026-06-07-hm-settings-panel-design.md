---
summary: Personal home-manager / desktop config "settings panel" — Rust + GTK4
  libadwaita, Stylix-first backend, ephemeral-preview / persistent-apply UX
  modelled on macOS System Preferences but scoped to theming and adjacent.
status: design draft, no implementation yet
created: 2026-06-07
---

# HM Settings Panel — design draft

A GUI for the `just option / set / preview / rebuild` loop, scoped initially
to desktop / theming configuration on this homelab's workstation.

## Why this and not generic `nix-gui` / `nixos-conf-editor`

Both prior attempts hit walls (see commit `06df96e` body — the LSP/option
research). The walls compound at full NixOS scope; **narrowing to
home-manager desktop config neutralises most of them**:

| Wall (prior projects) | Full NixOS | HM/desktop scope |
|---|---|---|
| Eval-rebuild speed | ~30s | ~5–10s, sometimes sub-second via runtime hooks |
| Type rendering complexity | 15k options, many `lambda` / `submodule` | A few hundred options, mostly `str` / `enum` / `package` / `int` |
| Write-back round-trip | Many files, custom helpers | 2–3 files (`stylix.nix`, `home.nix`, hyprland config) |
| Consequence reflection | Ripples to firewall, polkit, … | Themes ripple to themes — clean blast radius |

## Architecture (four decisions, locked)

1. **Personal-first.** Hard-codes paths in `/srv/share/projects/homelab/`. No
   user-facing config. Externalise later if/when the shape stabilises.
2. **Hybrid preview.** Runtime hooks (`gsettings`, `hyprctl`, `dconf`) for
   instant-feel; `just preview` (= `nh os test`) for the
   does-this-survive-rebuild truth-check before commit.
3. **Rust + GTK4 + libadwaita.** Native to Linux, themed by Stylix's
   `gtk` target so the tool is of-a-piece with the desktop. Bindings via
   `gtk4-rs` + `libadwaita-rs`. Single binary, no webview tax. Built into
   the system via nix flake.
4. **ConfigBackend trait, Stylix-only implementation to start.**
   Architectural lever for future generality (KDE, vanilla HM, etc.)
   without committing to the matrix today.

```rust
trait ConfigBackend {
    fn read_current(&self) -> Result<ConfigSnapshot>;
    fn preview_runtime(&self, change: &ConfigChange) -> Result<()>;
    fn write_persistent(&self, change: &ConfigChange) -> Result<()>;
    fn supported(&self) -> bool;
}

struct StylixBackend { config_path: PathBuf }
// future: PlainHmBackend, KdeBackend, …
```

## First slice (path 1 in the deliverable sequence)

**Theme + cursor + font browser with live preview.** Single window,
libadwaita `Adw.PreferencesWindow` shape. Cards for:

- Icon theme — visual grid of installed sets, click → `gsettings`
  preview → "Apply" calls `nix-editor` write to `stylix.iconTheme.package`
  → `just preview` to verify, "Persist" or "Revert" terminal step.
- Cursor — same shape.
- Font (sans / mono / size) — text rendering preview.
- Color scheme — base16 swatch grid.

Out of scope for slice 1: keybinds, panel layout, services, networking.

## Decisions locked 2026-06-07

- **Name:** `snowy`. Polar/penguin theme; ❄️ as visual mark.
- **Repo location:** `/srv/share/projects/snowy/`, sibling to homelab,
  separate flake. Keeps homelab focused; snowy gets its own iteration
  cadence.
- **Slice 1 scope:** four cards — Icon Theme, Cursor, Font, Colour
  Scheme (base16 swatch grid driving `stylix.base16Scheme`).
- **First commit:** `cargo new snowy` + libadwaita-rs hello-world that
  renders an `Adw.PreferencesWindow`, themes correctly under current
  Stylix — confidence spike before any config-reading code.

Implementation plan: see sibling `2026-06-07-snowy-implementation-plan.md`.

## What this is NOT

- Not a generic NixOS settings panel. Will refuse non-Stylix setups at
  the supported() check.
- Not a competitor to `home-manager switch` or `nh os switch`. Wraps
  them; does not replace them.
- Not a replacement for the `just option / set / preview / rebuild` CLI
  loop — the GUI consumes the same primitives via shell-out. Both
  layers must work; CLI is the source of truth.

## References

- Walls research: commit `06df96e` body — covers nix-gui,
  nixos-conf-editor, SnowflakeOS attempts and their specific failure
  modes.
- Memory: `[[iteration-trio-workflow]]` documents the CLI primitives
  this GUI consumes.
- Stylix targets reference: <https://stylix.danth.me/options/hm.html>
- libadwaita-rs: <https://gtk-rs.org/gtk4-rs/git/book/>
