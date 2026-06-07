---
summary: Implementation plan for `snowy` — Rust + libadwaita "settings panel"
  for Stylix-backed home-manager desktop config. Companion to the design doc.
status: ready to execute
created: 2026-06-07
---

# Snowy — implementation plan

Companion to `docs/superpowers/specs/2026-06-07-hm-settings-panel-design.md`.

Ten milestones, each with a concrete deliverable and a "done when" gate.
Designed for ~weekend-each cadence, sequentially executable. Each landing
milestone unblocks the next.

## Layout

```
/srv/share/projects/snowy/
├── flake.nix             # nixpkgs unstable + rust-overlay + ferris-flake or naersk
├── Cargo.toml            # gtk4, libadwaita, serde, anyhow, tokio (for nh shell-out)
├── src/
│   ├── main.rs           # Adw.Application bootstrap
│   ├── ui/
│   │   ├── window.rs     # Adw.PreferencesWindow shell
│   │   ├── icon_page.rs
│   │   ├── cursor_page.rs
│   │   ├── font_page.rs
│   │   └── scheme_page.rs
│   ├── backend/
│   │   ├── mod.rs        # ConfigBackend trait
│   │   └── stylix.rs     # StylixBackend impl
│   ├── runtime/
│   │   ├── gsettings.rs  # preview shims
│   │   ├── hyprctl.rs
│   │   └── editor.rs     # nix-editor shell-out wrapper
│   └── apply.rs          # commit flow: preview → nix-edit → just preview → just rebuild
└── README.md
```

## Milestones

### M0 — Project skeleton + hello-libadwaita

**Goal:** prove the stack compiles + renders + themes correctly under
current Stylix.

**Deliverable:**
- `cargo new snowy` inside `/srv/share/projects/snowy/`
- `flake.nix` with rust-overlay + dev shell (gtk4 + libadwaita + pkg-config)
- `src/main.rs` opens an empty `Adw.ApplicationWindow` titled "Snowy"
- Window inherits Stylix's GTK theme (Adwaita-dark with Material accents)

**Done when:** `just run` (or `cargo run`) opens a window in the current
Hyprland session, theme matches the rest of the desktop. Single screenshot
in `README.md`.

**Risk:** libadwaita-rs version skew vs nixpkgs's gtk4. Pin via `flake.lock`.

---

### M1 — Read current Stylix config

**Goal:** parse `modules/desktop/stylix.nix` and surface the current
icon theme, cursor, font, and base16 scheme as a `ConfigSnapshot`.

**Deliverable:**
- `src/backend/mod.rs` — `ConfigBackend` trait
- `src/backend/stylix.rs` — `StylixBackend`; uses `nix eval --raw
  /srv/share/projects/homelab#nixosConfigurations.workstation.config.stylix.<path>`
  to read evaluated values (NOT regex-parse the .nix file — that's
  brittle; eval is canonical)
- Unit test: snapshot matches what `just option stylix.iconTheme.package`
  reports

**Done when:** `cargo test backend::stylix` passes; CLI debug prints the
current ConfigSnapshot.

**Risk:** `nix eval` cold-cache is slow (~5s). Cache the snapshot once
at app startup; refresh on `Apply`.

---

### M2 — `Adw.PreferencesWindow` shell + page navigation

**Goal:** the four-card layout exists; navigation works; no functionality yet.

**Deliverable:**
- `src/ui/window.rs` — `Adw.PreferencesWindow` with four
  `Adw.PreferencesPage` instances (Icon Theme, Cursor, Font, Colour Scheme)
- Each page is empty but titled + iconned

**Done when:** click each tab, the title changes; window resizes
cleanly; Stylix-aware chrome stays consistent.

---

### M3 — Icon Theme page (the hardest one; lessons cascade)

**Goal:** end-to-end vertical slice for ONE card. Subsequent cards
clone the pattern.

**Deliverable:**
- `src/ui/icon_page.rs` — `Adw.FlowBox` of icon-theme tiles
- Each tile: 4 sample mime icons (folder, image, archive, executable)
  rendered at 48px, label below
- Enumerate available themes by globbing `/run/current-system/sw/share/icons/*/`
- Click a tile → `src/runtime/gsettings.rs` runs `gsettings set
  org.gnome.desktop.interface icon-theme '<name>'` (instant preview)
- "Apply" button (Adw.HeaderBar action) → triggers commit flow (M7)

**Done when:**
- Tiles render correctly with sample icons
- Clicking a tile changes Thunar's icons live (verify in adjacent window)
- "Apply" no-ops cleanly (until M7)

**Risk:** sample-icon rendering may not pick up the previewed theme;
may need to render via `GdkPixbuf::from_file` with explicit icon-theme
lookup. Fallback: just render the theme name + a "preview by hovering"
hint.

---

### M4 — Cursor page

**Goal:** clone M3 pattern for cursors.

**Deliverable:**
- `src/ui/cursor_page.rs` — `Adw.FlowBox` of cursor-theme tiles
- Each tile: cursor render (default + hover state) + label
- Size slider (Adw.SpinRow): 16 / 20 / 24 / 28 / 32 / 48 / 64
- Preview: `gsettings set ... cursor-theme` + `hyprctl setcursor <name> <size>`

**Done when:** swap cursor and size live in Hyprland.

**Risk:** cursor theme samples are tricky to render in GTK (cursors
aren't standard SVG icons). May fall back to text label only.

---

### M5 — Font page

**Goal:** sans + mono pickers with text-preview rendering, size slider.

**Deliverable:**
- `src/ui/font_page.rs` — two `Adw.ActionRow`s opening a font chooser
  (`gtk::FontDialog`) for sans + mono
- Live preview area: a paragraph of lorem in current sans, a code
  snippet in current mono
- Size sliders (sans + mono separately, matching Stylix's
  `fonts.sizes.{applications, terminal}`)
- Preview: `gsettings set ... font-name <name>` for sans; mono is
  mostly cosmetic-only since GTK apps respect system mono via Stylix

**Done when:** font dialog opens, selection updates preview area;
sliders move; sample text re-renders.

**Risk:** Stylix's font target may not respond to runtime gsettings —
preview may be approximate-only with a "fully visible after Apply" hint.

---

### M6 — Colour Scheme (base16 swatch grid)

**Goal:** browse + preview base16 schemes.

**Deliverable:**
- `src/ui/scheme_page.rs` — `Adw.FlowBox` of scheme tiles
- Each tile: 16-swatch grid (8x2) showing scheme colours, scheme name below
- Enumerate from `${pkgs.base16-schemes}/share/themes/*.yaml` via
  `nix eval` (cached at startup)
- **No runtime preview** for this card — base16 schemes ripple through
  too many apps to fake; "Preview" button instead runs `nh os test`
  with the proposed change and prompts to commit or revert
- The "no instant preview" exception worth documenting in-card

**Done when:** scheme grid renders; clicking a swatch + "Preview" runs
`just preview` with the scheme change spliced in.

**Risk:** the slowest card by far — every scheme preview is a full
rebuild. May want a "decide from swatches alone, preview only the
finalist" UX. Worth iterating.

---

### M7 — Apply / Preview / Commit flow

**Goal:** end-to-end commit semantics shared by all four cards.

**Deliverable:**
- `src/apply.rs` — state machine: `Pristine → Previewing → Applied →
  Committed | Reverted`
- "Apply" button triggers:
  1. `src/runtime/editor.rs` shells out `nix-editor -i -v <value>
     modules/desktop/stylix.nix <attr>` + `nix fmt -- ...`
  2. Banner: "Change written. Run `just preview` to test, `just
     rebuild` to commit, or click Revert."
  3. "Revert" runs `git checkout modules/desktop/stylix.nix`
- "Commit" button (only after Apply) runs `nh os switch` in a thread,
  shows progress, success/failure toast.

**Done when:** all four cards drive the same flow; failure modes
(nix-editor error, build failure) surface clean toast messages.

**Risk:** running `nh os switch` from a GUI requires elevation. On
NixOS the user is in `trusted-users` already; `nh` works without sudo
in the user's session. Verify.

---

### M8 — Stylix opt-out for snowy's own chrome

**Goal:** snowy itself should look polished; current Stylix GTK target
may produce surprises.

**Deliverable:**
- Test under live Stylix — if window decoration / accent colours look
  off, add `stylix.targets.<snowy-app-id>.enable = false` to homelab's
  stylix config and apply our own Adwaita defaults
- Or — keep Stylix on but override specific properties via `gtk_css`

**Done when:** snowy's window looks like a polished, deliberate app —
not a half-themed accident.

**Risk:** this is "polish, see what happens" — can defer until M3+ shows
problems.

---

### M9 — Wrap

**Deliverable:**
- `README.md` with screenshots, install instructions (`nix run
  github:phibkro/snowy`), feature list, scope limits
- `flake.nix` exports binary as default package
- Tag `v0.1.0`

**Done when:** fresh clone + `nix run` produces a working snowy. README
is honest about Stylix-only scope.

---

## Slice 2 ideas (parked)

- Wallpaper picker (Stylix `image` input)
- Hyprland keybind editor (touches different write-back target — separate
  ConfigBackend impl)
- Per-monitor cursor size
- Font weight + variant pickers
- Live colour-scheme generator from a chosen image (Stylix already has
  Material You from-image; snowy could let you preview the palette
  before committing)

## Top three risks to watch

1. **`nix-editor` value-type coverage.** Works for scalars (string, int,
   bool, package literals). Untested for attrset literals and lambdas.
   If a card hits one, fall back to in-place file rewrite via
   `tree-sitter-nix`.

2. **Stylix's eval surface vs the actual .nix structure.** `nix eval`
   sees the *resolved* value (e.g., a fully-realised derivation
   reference); `nix-editor` writes to the *source* attribute (e.g.,
   `pkgs.papirus-icon-theme` as syntax). Need a clean
   resolution-vs-syntax mapping per attribute.

3. **`nh os switch` failure surface.** Errors are multi-page. Surface
   only the last error block; full log on demand via a Details
   expander. Don't try to parse — let the user read what failed.

## What this plan deliberately does NOT cover

- Tests beyond M1 unit tests. Snowy is GUI-heavy; integration testing
  is via "open it, use it." If something breaks, write a test then.
- CI. Push to a remote, run `nix flake check` locally before pushing.
- Cross-distro packaging. Stylix-only assumption is the gate.
- Telemetry, error reporting, crash logs. Single-user tool.
