# Declared service and workstation process inventory

Read-only design evidence from `/srv/share/projects/homelab/.worktrees/two-host-migration`, HEAD `06de3381bbe307c08a7ee8524f652a314965cb41` plus the current uncommitted agent-friendliness/domain work. This is source inspection, not live process observation, evaluation of every merged option, or a claim that any service is healthy. No builds, deployment, network probes or credentials were used. A read-only `getFlake` evaluation identified the locked nixpkgs source as `/nix/store/dgl0m61l12l94psyr98mlyz7r48mkjnx-source` (abbreviated **N** below); nested units were read there where the repository delegates them upstream.

**Notation:** P = persistent procedure instantiated by a unit/session; R = triggered run that terminates; D = declared data/message flow; S = state feedback (prior state influences later output); H = hosting; A = access/authority; L = lifecycle/start dependency. A systemd `after` edge is L, not evidence of a D edge. Shared filesystem permissions are A; two processes seeing a directory does not prove they exchange files. Package installation does not prove a process runs.

Selection: [inventory/hosts.nix](../../../inventory/hosts.nix) selects workstation family-vault/media-compute plus explicit Hindsight, Attic, Clamor, Herdr MCP and tunnel workloads; [inventory/profiles.nix](../../../inventory/profiles.nix) resolves the selected groups. Their manifests and [inventory/default.nix](../../../inventory/default.nix) own metadata/runtime selection. These group names are selection mechanisms, not a process calculus. Pi's entry plane is a separate hosting boundary; same-host claims in old service comments are not authoritative.

## Family and research services

Each service below cites its local declaration; the paired `manifest.nix` owns route metadata and access audience. All are declared on workstation. Each process boundary can later be refined without changing its external wires.

### Immich

Source: [runtime](../../../nix/modules/services/immich/runtime.nix#L45), [manifest](../../../nix/modules/services/immich/manifest.nix), [upstream module](/nix/store/dgl0m61l12l94psyr98mlyz7r48mkjnx-source/nixos/modules/services/web-apps/immich.nix:289).

- P `immich-server`: HTTP on `0.0.0.0:2283`; photo-management request/response boundary. D: managed media at `${nori.fs.photos.path}/_immich-managed`; database socket/config, Redis socket, and ML HTTP endpoint. Source commentary names upload, recognition and scheduled DB dumps, but this repository does not specify the individual application job transitions or dump schedule. Do not invent a per-job worker graph.
- P `immich-machine-learning`: separately enabled, loopback port 3003, cache `/var/cache/immich`; server is configured to call it. Both units have PostgreSQL target lifecycle dependencies. GPU device access is declared; how each request consumes GPU memory is not measured here.
- P shared PostgreSQL: Immich enables the shared service and its database/user, pgvector and VectorChord extensions. Extensions are in-process capabilities, not separate services. R `postgresql-setup` extension SQL is augmented by the upstream Immich module.
- P `redis-immich`: separately enabled Unix-socket service, with socket group access granted to server. Protocol-level queue/cache contents and persistence semantics are an upstream boundary not traced here.
- S: photo tree, live DB, ML cache, and app-generated dump files feed future requests. A: static immich user, media supplementary group and explicit photo-tree bind. H: storage and all backing processes on workstation. Family route includes declared OIDC metadata; actual user/account state remains runtime state.
- Gate: `services.immich.enable`, database/Redis/ML all explicitly true when its selected runtime is imported. Backup declaration delegates photos/dumps to media-irreplaceable; that is intent, not proof of active off-disk backups.

### Paperless and paper acquisition

Source: [runtime](../../../nix/modules/services/paperless/runtime.nix#L37), [upstream module](/nix/store/dgl0m61l12l94psyr98mlyz7r48mkjnx-source/nixos/modules/services/misc/paperless.nix:515), [research integration](../../../nix/profiles/research.nix), [fetcher](../../../nix/modules/system/research/papers-fetch/papers-fetch.py#L70).

- R `papers-fetch <identifier/title>`: query → identifier classification → arXiv, or title-to-DOI Crossref then DOI resolver chain Unpaywall/OpenAlex → remote PDF download → `.pdf.part` → rename into consume directory. D: completed PDF is the explicit handoff into Paperless. Invalid/unresolved/network outcomes terminate with failure; resolver source defines exact conditions. No daemon or timer for fetcher is declared. No Paperless DB authority is needed by this handoff; research profile makes the consume directory public.
- P `paperless-consumer`: document_consumer process reads arrivals. P `paperless-task-queue`: Celery worker. P `paperless-scheduler`: Celery Beat. P `paperless-web`: Granian ASGI/WS HTTP on port 28981. The runtime names OCR, archive and indexing behavior; upstream declares Redis transport and scheduler/worker split. Exact application task edges remain upstream behavior.
- P `redis-paperless` is enabled unless a custom Redis connection overrides it; none is set locally. P shared PostgreSQL supplies the separate paperless database. The worker can reach network mail servers, but no configured mailbox/import rule is established by this source.
- R `paperless-secret-key`: required startup procedure creates/reuses the secret-key environment file. R scheduler `preStart`: checks package version marker, migrates schema if changed, reindexes if needed, reconciles admin credentials if their persisted comparison state changes. These startup procedures feed persistent state and later execution; they are not extra always-running services.
- S: `/var/lib/paperless` state/index/consume area, separate database, media PDFs/thumbnails under `${nori.fs.library.path}/papers`, secret/version/superuser markers. A: paperless user + media group, writable library binds for all four application units. L: scheduler wants consumer/web/queue; consumer/web bind to scheduler and join worker namespace. These namespace/lifecycle relations are not themselves task data flow.
- R PostgreSQL logical dump at 03:30 is explicitly selected; restic intent at 04:30 consumes the dump. Upstream exporter is optional and not enabled in the local declaration; do not add an exporter run to the active graph from product familiarity.

### Vaultwarden

Source: [runtime](../../../nix/modules/services/vaultwarden/runtime.nix#L38), [upstream module](/nix/store/dgl0m61l12l94psyr98mlyz7r48mkjnx-source/nixos/modules/services/security/vaultwarden/default.nix:269).

- P `vaultwarden`: HTTP on 8222 with SQLite backend. D: vault client requests/responses and configured Authelia OIDC interactions (`SSO_AUTHORITY`, client, scopes); master-password path remains enabled. Signups false is an explicit state-transition gate. Secret environment file is an A input, not a public data stream.
- S: `/var/lib/vaultwarden` including SQLite; application item encryption/protocol internals were not inspected. A: static service account and keys group for environment file.
- R conditional restic preparation: if DB exists, flock → SQLite `VACUUM INTO` temporary file → rename into `/var/backup/vaultwarden`. Intended inputs include service state plus that snapshot. Its trigger depends on enabled restic delivery, currently disabled at canonical backup policy. Upstream has an optional `backup-vaultwarden` job gated by non-null `backupDir`; this local runtime does not set that option and the inspected upstream default is null, so no such unit follows from these declarations. The presence of our preparation directory does not enable it.

### Radicale

Source: [runtime](../../../nix/modules/services/radicale/runtime.nix#L25), [manifest](../../../nix/modules/services/radicale/manifest.nix).

- P Radicale: CalDAV/CardDAV request/response boundary on 5232. D/S: collections under `/var/lib/radicale/collections`; htpasswd file is authentication state. R tmpfiles bootstraps an empty users file; actual credential enrollment is an operator procedure, not an enabled account.
- A: bcrypt htpasswd, family route explicitly exempted from browser forward-auth because DAV clients do not follow it. Backup includes `/var/lib/radicale`; not currently active delivery. No separate database, worker or scheduler is declared here.

### Syncthing

Source: [runtime](../../../nix/modules/services/syncthing/runtime.nix#L33), [upstream units](/nix/store/dgl0m61l12l94psyr98mlyz7r48mkjnx-source/nixos/modules/services/networking/syncthing.nix:990).

- P `syncthing`: peer protocol and GUI (8384). D: peer ↔ local files, plus GUI management commands. S: device/folder configuration and index under the configured home/config/database paths.
- **Unknown:** actual peers, folder IDs and paths are UI-managed (`overrideDevices=false`, `overrideFolders=false`), so the source does not support a concrete cross-machine synchronization edge.
- R `syncthing-init` is the upstream configuration updater when cleaned declarative settings are nonempty; settings update is separate from ongoing peer sync. No per-folder one-shot is declared here.
- A: runs as nori, GUI open on all addresses behind route/firewall, explicit tailnet ports 22000 TCP/UDP and 21027 UDP; filesystem binds for declared downloads/library. Comment says discovery LAN-only but executable firewall allows its UDP port on tailscale0—use code for access edge. No extra GUI user/password is declared.

### Samba

Source: [runtime](../../../nix/modules/services/samba/runtime.nix#L39), [filesystem generator](../../../nix/modules/system/storage/default.nix), [upstream service](/nix/store/dgl0m61l12l94psyr98mlyz7r48mkjnx-source/nixos/modules/services/network-filesystems/samba.nix:304).

- P `samba-smbd`: SMB file reads/writes. D/S: connected client ↔ selected shares ↔ underlying filesystem state. `samba-nmbd` and `samba-winbindd` explicitly disabled; do not draw them as active backends.
- `media` share is conditional on a downloads filesystem declaration and maps `/mnt/media`; other shares derive from `nori.fs.*.samba` (not a hand-maintained second list). A: valid nori user, smbpasswd-managed credentials, forced write UID/GID and masks; tailnet and Waydroid bridge are permitted peers, global openFirewall false. Share ownership and Immich/Paperless access do not imply automatic data exchange between those services.
- R tmpfiles ensures selected directories and ownership. Credential provisioning is a manual procedure. Actual client sessions and data mutations are unknown.

### Miniflux

Source: [runtime](../../../nix/modules/services/miniflux/runtime.nix#L32), [upstream module](/nix/store/dgl0m61l12l94psyr98mlyz7r48mkjnx-source/nixos/modules/services/web-apps/miniflux.nix:127).

- P `miniflux`: feed-reader HTTP boundary on 8087; shared PostgreSQL is enabled with local database. D: HTTP clients and configured OIDC issuer, DB reads/writes. Runtime commentary identifies feed-reader purpose; feed subscriptions, refresh schedules and exact outbound feed URLs are not declared, so keep feed retrieval as an opaque application procedure.
- R `miniflux-dbsetup`: PostgreSQL setup hook drops legacy hstore extension before service start. Bootstrap administrator/OAuth configuration supplied through SOPS template. S: application state in DB (runtime explicitly states no user file store).
- R logical DB dump at 03:30; intended restic snapshot input at 04:30. A: dynamic user plus keys supplementary group. Family route, OIDC auto-user creation enabled. Do not confuse separate DB ownership with separate PostgreSQL hosting process.

## AI, development and projection services

### Ollama and Open WebUI

Source: [Ollama runtime](../../../nix/modules/services/ollama/runtime.nix#L34), [active manifest](../../../nix/modules/services/ollama/manifest.nix#L2), [WebUI runtime](../../../nix/modules/services/open-webui/runtime.nix#L38), [inactive manifest](../../../nix/modules/services/open-webui/manifest.nix#L2), [upstream Ollama](/nix/store/dgl0m61l12l94psyr98mlyz7r48mkjnx-source/nixos/modules/services/misc/ollama.nix:214).

- P `ollama serve` is **currently declared enabled** (`active=true`), despite historical pause commentary. HTTP inference boundary 11434, CUDA package, `OLLAMA_KEEP_ALIVE=0`. S: `/var/lib/ollama` models; model pulls are manual because loadModels is unset. Upstream `ollama-model-loader` is conditional on nonempty loadModels or syncModels; not an implied active scheduled loader. Per-request child GPU runners are package internals, not enumerated in this repo.
- P `open-webui serve` is **declared disabled** (`active=false`). The retained hypothetical D chain is WebUI requests → Ollama loopback 11434 and Authelia discovery; its routes, hardening/unit additions and backup intent are gated. S: retained private StateDirectory SQLite/chat/upload state; no current live claim.
- R when enabled and delivery active, SQLite backup preparation uses flock, VACUUM INTO and rename. This is conditional future execution, not a current process. Optional OpenRouter in comments is not configured data flow.

### Hindsight

Source: [runtime](../../../nix/modules/services/hindsight/runtime.nix#L62), [manifest](../../../nix/modules/services/hindsight/manifest.nix).

- P `chatlog-hindsight`: `steam-run uvx hindsight-api@0.9.0`, loopback 9077, one worker. D: API requests, configured openai-codex LLM provider, declared `pg0://hindsight-embed-chatlog-pilot` database; cache roots in nori's home. Retained document text and observations enabled. Exact embedded PostgreSQL child-process topology and its state path are **unknown from this declaration**, as are live ingestion schedules. Do not fabricate a Chatlog ingestion timer.
- P `hindsight-control-plane`: packaged Next.js control-plane CLI on loopback 9999, points API at 9077; L requires API. P `hindsight-mcp-origin`: Caddy has two listeners: bearer-gated `/mcp/chatlog-insights-v1` on 9078 forwards to API; loopback UI proxy 9998 forwards to 9999 with header rewrites. Default unmatched request →404. D paths and A gates are explicit. Backend MCP exposes recall/reflect only, stateless mode.
- S: memory DB/index and writable home caches; source labels pilot index derivable from canonical Chatlog sessions and skips backup. Canonical-session location and retention policy are outside this module. All three run as nori; API/UI home write authority is explicit. Hindsight manifest active assertion guards importing an inactive runtime.

### Herdr projects MCP

Source: [runtime](../../../nix/modules/services/herdr-projects-mcp/runtime.nix#L62).

- P `herdr-projects-mcp`: Bun runs mutable external source `/srv/share/projects/herdr-mcp/src/server/http.ts`, localhost 9080 `/mcp`. Inputs: MCP requests, registry JSON, bearer token file, configured Herdr binary/session `projects`. S: facade SQLite `/home/nori/.local/state/herdr-mcp/projects/facade.sqlite` and execution root `/tmp/herdr-mcp-projects`.
- Gate: source file, installed MCP SDK and preexisting SQLite must exist. Runtime ownership nori; only state/execution roots writable, source read-only. Actual tool operations, mailbox transitions, subprocess orchestration and transaction semantics belong to that external source, **not verified here**.
- P `herdr-projects-mcp-origin`: Caddy 9081 (loopback + tailnet), `/mcp`→9080 and default404; L requires backend. Authentication comparison is declared to happen in Bun before dispatch, not in this proxy configuration.
- P `herdr-projects-mcp-relay`: Bun relay.ts, outbound configured Worker WebSocket → local `/mcp`; L backend dependency, separate source-file condition, restart always. This is a second projection path alongside the shared cloudflared tunnel; do not collapse relay and tunnel into one process. Registry/store semantics are common backend concerns; network transport alternatives are not separate actor identities by themselves.

### Shared MCP tunnel and dev-share

Source: [runtime](../../../nix/modules/services/mcp-origin-tunnel/runtime.nix#L16), [dev-share implementation](../../../tools/dev-share.rs), [route declaration](../../../infra/cloudflare/routes/dev-share.json).

- P `mcp-origin-cloudflared`: one named tunnel, QUIC, local metrics9079; D: three hostname dispatches to Hindsight origin, projects origin and declared dev-share origin; otherwise404. L requires both MCP origins; A uses SOPS credentials and nori account. Single connector owns the complete ingress table; duplicate connectors with different tables are a routing-custody hazard, not useful independent throughput branches.
- R/manual persistent-session `dev-share`: CLI parses chosen origin/mode, emits public URL/QR; secure gateway path runs a locked Caddy subprocess using `$XDG_RUNTIME_DIR/dev-share.lock`, origin supplied through environment. Quick-share path spawns cloudflared and discovers its generated URL. Their lifetimes follow the triggered command. No always-running dev-share Caddy is declared in the module. Exact flags and validation are in Rust source; arbitrary app server internals are outside scope.

### Attic

Source: [runtime](../../../nix/modules/services/attic/runtime.nix#L16).

- P `atticd` monolithic mode: HTTP5000 serves configured cache protocol and API; D/S: local chunks at `nori.fs.cache.path`, SQLite `/var/lib/atticd/server.db`; zstd configured. JWT environment is A. Garbage collection is an **internal scheduled procedure** (12h interval, 30d default retention), not a separate declared service. No new external database process.
- R `attic-cache-bootstrap`: boot wantedBy, requires atticd, waits for HTTP readiness, POST missing cache, PATCH desired config, GET/read-back compare. Inputs include private token/keypair files; writes cache config, returns success/failure. This is a reconcile loop over persistent API state. Restart on selected secret changes declared. Runtime artifacts are temporary credential/header JSON files, not canonical state.
- H/A: stable atticd user owns cache files and has bind access; root performs bootstrap. Cache data marked derivable and backup skipped. Old 'OneTouch-backed' comment conflicts with canonical cachePath indirection; draw the filesystem declaration, not that historical device claim.

### Heim, Glance and Clamor

Sources: [Heim runtime](../../../nix/modules/services/heim/runtime.nix#L40), [Heim manifest](../../../nix/modules/services/heim/manifest.nix), [Glance runtime](../../../nix/modules/services/glance/runtime.nix#L64), [Clamor manifest](../../../nix/modules/services/clamor/manifest.nix).

- Heim R manual artifact consumer/build unit: selected Git repository/ref → fetch/reset source → compare commit sentinel/dist → Bun install/build if needed → stage/rename static dist → update `.last-built-commit` → restart serve. No boot trigger on build. S: checkout, build deps, dist and commit sentinel under `/var/lib/heim`. P `heim-serve`: darkhttpd9094, starts at boot only if dist exists, read-only bind. Browser requests→static bytes; no declared runtime DB. Historical mention of orphan PostgreSQL database is not evidence it currently exists. Public route.
- Glance P HTTP8086: generated route dashboard entries → bookmarks; configured weather/local server stats/Twitch/RSS widgets → rendered page. RSS12h cache configured; actual weather endpoint and package cache persistence are not declared. S: transient widget/cache state is a package boundary; repository declares dashboard stateless and no backup. Public audience is explicit; there is no additional Glance→all-linked-services polling edge for bookmark navigation.
- Clamor: **external persistent process boundary only**. This repository declares endpoint4173, operator audience and workload placement, but no runtimeModule. Source warns canonical Pi proxy requires tailnet/all-interface listener and peer-guard acceptance; existing tailscale-serve compatibility is commentary, not a live observation. Launch conditions, child processes, state, requests/responses and actual listener are unknown here. Keep as an external box requiring its own source survey, not an invented Nix service.

## Shared state and recurring procedures

- Shared PostgreSQL is one hosting/process family with isolated service database/user declarations for Immich, Paperless and Miniflux, not three boxes automatically. Local startup schema/extension/admin procedures above mutate that feedback state. [PostgreSQL backup module](/nix/store/dgl0m61l12l94psyr98mlyz7r48mkjnx-source/nixos/modules/services/backup/postgresql-backup.nix:189) emits a per-database triggered dump when `backupAll=false`; separate local runtime declarations merge database selections.
- [Canonical backup policy](../../../inventory/backup.nix) is disabled. Therefore include/prepare/timer declarations should be drawn as **dormant intended delivery**, distinct from enabled local DB dumps and existing state. No assertion of current backup success follows from source. Backup/storage lead should expand snapshot, restore and sender/receiver processes once, rather than duplicate them per service.
- [SOPS/keys], Unix users/groups, filesystem binds, GPU device access, route audience and interface firewall rules are A/H relations. They are not messages. A secret file → startup environment can be a typed input wire without exposing its bytes.

## Workstation desktop and home composition

Sources: [host home composition](../../../nix/hosts/workstation/home.nix#L20), [desktop profile](../../../nix/home/profiles/desktop/default.nix), [system desktop composition](../../../nix/modules/system/desktop/default.nix), [home desktop composition](../../../nix/home/desktop/default.nix).

| Process family | Inputs → outputs and state feedback | Enablement/dependencies/authority |
|---|---|---|
| P greetd → tuigreet; R login/session bootstrap → P UWSM/Hyprland | Credentials/session selection → authenticated graphical session; input/window events → rendered desktop and IPC observations. Remembered user/session is feedback. | [greetd](../../../nix/modules/system/desktop/greetd.nix), [Hyprland](../../../nix/modules/system/desktop/hyprland.nix): enabled, UWSM true. Session startup imports display environment and bounces hyprland-session.target. |
| P compositor-start clients: Zed, Zen, snappy-switcher daemon, layer-autohide | Editor/browser interactive boundaries; switcher reads window list/thumbnails; autohide observes focus/workspace events and dispatches hide. | Actual [Lua autostart](../../../nix/home/desktop/hypr-rice/hyprland.lua#L65) launches them and hyprpolkitagent. Their app internals are excluded. |
| P Persona widgets + wallpaper; P hyprpaper fallback | Desktop data/notification/interaction boundary → widgets/video surfaces; persisted disabled markers control future starts. | [units](../../../nix/home/desktop/persona-quickshell/default.nix#L243): separate two units, ExecCondition tests persona-desktop state; wallpaper after hyprpaper; session-scoped, Restart=no. Internal QML processes not fully expanded. |
| P Waybar; R/manual pwvucontrol | Status/control surfaces and commands; volume UI edits audio graph. | [Waybar](../../../nix/home/desktop/waybar.nix#L35): enabled user service under Hyprland target; pwvucontrol is explicit unit, no inferred boot startup. |
| P hyprsunset; R hyprlock | Time schedule→temperature (07:00 identity,20:00 3500K); lock request→screenshot/credential UI→unlock. | [hyprsunset](../../../nix/home/desktop/hyprsunset.nix#L21), [hyprlock](../../../nix/home/desktop/hypr-lock.nix#L1). Manual lock only; **hypridle deliberately absent**, even though older comments elsewhere mention it. |
| P PipeWire + Pulse compatibility + WirePlumber; P idle inhibitor | Audio clients/devices↔audio streams; WirePlumber policy/default state feeds future routing; active audio→Wayland idle inhibition. | [audio](../../../nix/modules/system/desktop/audio.nix), [inhibitor](../../../nix/home/desktop/wayland-pipewire-idle-inhibit.nix#L21): PipeWire, ALSA32, pulse, WirePlumber enabled; legacy PulseAudio disabled. Inhibitor is session-scoped. |
| P DBus/desktop portals/Polkit/Tumbler | App portal/elevation/thumbnail requests→authorized results or thumbnails; concrete DBus-call protocols remain upstream boundary. | [Hyprland](../../../nix/modules/system/desktop/hyprland.nix), [apps](../../../nix/modules/system/desktop/apps.nix): GTK fallback portal, Polkit and thumbnail daemon enabled. Thunar/plugins installed, not a continuous daemon claim. |
| P hypr-session-logd; R capture/save/prune/restore | Hyprland socket2 events→debounced snapshots; saved topology/state + current windows→launch/match/move restore effects. Ring and named saves feed future restores. | [unit](../../../nix/home/desktop/hypr-rice/runtime.nix#L1300), [scripts](../../../nix/home/desktop/hypr-rice/hypr-session/lib.sh#L24). State defaults ~/.local/state/hypr-session; session logd persistent, CLI actions triggered. Not a full checkpoint of app internals. |
| R rice palette/layout/layer commands | Keybinding/menu selection + current compositor state→layout/window/application operations; named layers and native layout are feedback. | [runtime](../../../nix/home/desktop/hypr-rice/runtime.nix), [Lua](../../../nix/home/desktop/hypr-rice/hyprland.lua). Popup terminal lazy-spawns Ghostty only if needed; tests/manual commands not autostart. |
| P Sunshine | Remote client inputs→existing session input; rendered/audio stream→remote client. Pairing/config state external to inspected declaration. | [Sunshine](../../../nix/modules/system/desktop/sunshine.nix): enabled user-session autoStart, NVENC, privileged capture capability, tailnet ports only. Logged-in desktop prerequisite; no extra desktop app launched by configured built-in Desktop stream. |
| P libvirtd; R/P guest QEMU + optional swtpm; Waydroid container/session boundary | VM/container lifecycle requests→guest execution; guest disk/session state feeds later boots. | [virt](../../../nix/modules/system/desktop/virt.nix), [Waydroid](../../../nix/hosts/workstation/waydroid.nix). Enabled substrate, but actual guest list/runs unknown. QEMU runAsRoot=false, nori libvirtd group. No concrete guest process inferred from capability enablement. |
| R creative media processing | resolve-remux scans input clips→ffprobe bitdepth/audio decision→ffmpeg DNxHR MOV in sibling remux dir; existing output skips next run. | [script](../../../nix/home/desktop/resolve-remux.sh), [profile](../../../nix/home/profiles/creative/video.nix). Manual invocation; Resolve/Handbrake/VLC/mpv/Audacity installed interactive boundaries, not scheduled workflows. |

### Coding-agent execution and feedback

- Interactive P/R **Herdr pane → shell → chosen agent/tools** is an invocation family, not a declaration that every installed agent is running. [agentic-workstation](../../../nix/home/profiles/development/agentic-workstation.nix) installs Codex wrapper, OMP-related capabilities, Herdr, Pagu, OpenCode/Pi and other tools. [agentic-tools](../../../nix/home/profiles/development/agentic-tools.nix) imports Claude/OMP/LSP/skills/notify. Credentials, provider protocols, application child trees and harness persistence are external package/runtime boundaries unless explicitly declared in those modules; no enumeration from brand familiarity.
- R **pane scope attachment** on interactive Bash startup with HERDR_PANE_ID: DBus StartTransientUnit → scope assignment → `/proc/self/cgroup` verification; failure warns. H/A/resource boundary is per-pane transient scope nested under herdr.slice, not a message pipeline. Explicit byte/percentage memory/swap and CPU/IO budgets in [host home](../../../nix/hosts/workstation/home.nix) bound descendants.
- R **agent-notify hook**: native stop/permission/question event payload → harness/project/pane identification → nori-alert audience agents. [hook mapper](../../../nix/home/agent-notify/default.nix#L29) is explicitly separate from alert delivery; absence of nori-alert logs and skips. Codex wrapper injects hook config; OMP/Claude/OpenCode/Pi integrations are selected. This is a process/event wire that should connect to the alert lead's delivery box, not another ntfy implementation.
- R **saturation-alert** every5min: PSI/memory/swap/tasks + Herdr agent list/cgroup attribution + prior severity/cooldown state → classified alert, optional critical checkpoint prompts, persisted next state. [source](../../../nix/home/saturation-alert.nix#L248). Enabled by workstation profile. It does not kill arbitrary agents; checkpointPrompt defaults true and controls the critical-only prompt branch. StateDirectory supplies feedback.
- R **steady-state-resource-alert** timer: cgroup memory/swap/FD/tasks per configured Persona/Waybar targets + warmup baseline/streak state → journal/alert and updated state. [source](../../../nix/home/desktop/steady-state-resource-alert.nix#L280). Explicit target declarations carry intended progress evidence; resource-growth detection is an observation, not proof of a leak.
- R **user-notify@unit** from failed restart-capable units: wait recovery window→inspect still-failed state+journal→nori-alert. [restart policy](../../../nix/home/user-restart-policy.nix) defines bounded restart defaults and OnFailure wiring only for declared HM units. Hand-installed units are explicitly outside its coverage; do not infer an active herdr-monitor merely from incident commentary.
- Home symlinks to `/srv/nori` in host home are **storage references**, not synchronization processes. Installed productivity/communication/research apps (Bitwarden desktop, editors, Discord, Tidal, Obsidian, Zotero etc.) are **interactive boundary inventory**, not proof of server integration, data path, shared identity or scheduled synchronization.

## Composition guidance and unresolved evidence

Candidate process wiring that source actually supports:

```text
research query → papers-fetch → completed PDF → Paperless consumer / task queue
                                                   ↕ DB/index/media state
HTTP user request → Pi entry plane → selected application → application state
                                             ↘ configured OIDC issuer
MCP client → shared tunnel → origin proxy → Herdr backend ↔ facade state
                         ↘ Hindsight proxy → API ↔ memory DB
remote relay ↔ Herdr relay process ↔ same Herdr backend
Git ref → Heim build → static dist → Heim serve → HTTP bytes
Hyprland events → session capture → saved topology → restore → Hyprland effects
agent halt → agent-notify → alert delivery
resource samples + prior baseline → watchdog → alert/checkpoint + next baseline
```

These arrows deliberately omit ownership/hosting edges. Draw workstation hosting, Unix principal access, storage ownership, GPU capacity and per-pane supervision as separate annotations/relations. Expose behaviorally relevant retained state even when it is abstracted. Daemon longevity alone does not require a domain-state feedback wire; a stateless server can remain stateless at its chosen boundary.

Remaining bounds: runtime reachability/credentials, actual dynamically configured Syncthing peers and Miniflux feeds, Clamor/external Herdr HTTP implementation, Hindsight embedded runtime/ingestion, per-app internal job transitions, service request causality, runtime actor identity/incarnation mapping, real capacity and failure recovery were not inspected. Desktop boundary excludes every plugin, browser tab, language-server subprocess, individual GUI app document model and guest internals. Expand those only through their own source/protocol inventories. No language choice or repository rewrite follows from this inventory.
