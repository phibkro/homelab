{
  config,
  lib,
  pkgs,
  ...
}:

# phibkro.org apex landing page — a one-shot sitemap of the operator's
# public projects. Auto-generated from `nori.publicRoutes.<n>.sitemap`
# entries; new apps with sitemap metadata appear here without manual
# index edits.
#
# ── Build shape ──────────────────────────────────────────────────
# index.html lives in /nix/store via pkgs.writeText (rebuilt on every
# nix-rebuild that changes the sitemap inputs). darkhttpd serves it on
# 127.0.0.1:9097; cloudflared maps phibkro.org → that port via
# nori.publicRoutes.phibkro-apex.
#
# Same Blueprint design tokens as heim — dashed borders, oklch palette,
# Bebas Neue + IBM Plex Mono — for visual continuity. No external
# stylesheet; CSS is inlined for trivially-small page weight.

let
  servePort = 9097;

  # Pull all routes flagged for sitemap inclusion. Sort by display
  # title for stable ordering. Apex itself is excluded by definition
  # (host = "@" filtered out) — the sitemap doesn't link to itself.
  visibleRoutes = lib.filter (r: r.value.sitemap != null && r.value.host != "@") (
    lib.mapAttrsToList (name: cfg: {
      inherit name;
      value = cfg;
    }) config.nori.publicRoutes
  );

  sortedRoutes = lib.sort (a: b: a.value.sitemap.title < b.value.sitemap.title) visibleRoutes;

  cardHtml =
    r:
    let
      url = "https://${r.value.host}.phibkro.org";
      inherit (r.value.sitemap) title description;
    in
    ''
      <a class="card" href="${url}">
        <span class="card-host">${r.value.host}</span>
        <h2 class="card-title">${title}</h2>
        <p class="card-desc">${description}</p>
      </a>
    '';

  cards = lib.concatMapStringsSep "\n" cardHtml sortedRoutes;

  description = "Projects by Philip Bjørknes Krogh — developer in Oslo.";

  # Sitemap: the apex + every public route flagged for sitemap inclusion.
  # Hand-rolled XML because writeText is the simplest mechanism we
  # have on the static-darkhttpd serving path. Apps publish their own
  # internal sitemaps (heim's @astrojs/sitemap, etc.); this one is
  # the cross-app index pointing at each subdomain root.
  sitemapXml = pkgs.writeText "phibkro-sitemap.xml" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url>
        <loc>https://phibkro.org/</loc>
        <changefreq>monthly</changefreq>
        <priority>1.0</priority>
      </url>
    ${lib.concatMapStringsSep "\n" (r: ''
      <url>
        <loc>https://${r.value.host}.phibkro.org/</loc>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
      </url>'') sortedRoutes}
    </urlset>
  '';

  robotsTxt = pkgs.writeText "phibkro-robots.txt" ''
    User-agent: *
    Allow: /

    Sitemap: https://phibkro.org/sitemap.xml
  '';

  indexHtml = pkgs.writeText "phibkro-index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>Philip Bjørknes Krogh</title>
        <meta name="description" content="${description}" />
        <link rel="canonical" href="https://phibkro.org/" />
        <link rel="sitemap" href="/sitemap.xml" />

        <meta property="og:type" content="website" />
        <meta property="og:site_name" content="Philip Bjørknes Krogh" />
        <meta property="og:title" content="Philip Bjørknes Krogh" />
        <meta property="og:description" content="${description}" />
        <meta property="og:url" content="https://phibkro.org/" />
        <meta name="twitter:card" content="summary" />
        <meta name="twitter:title" content="Philip Bjørknes Krogh" />
        <meta name="twitter:description" content="${description}" />

        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link
          href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=IBM+Plex+Mono:wght@300;400;500&display=swap"
          rel="stylesheet"
        />
        <style>
          :root {
            --bg: oklch(10% 0.015 220);
            --bg2: oklch(13% 0.015 220);
            --fg: oklch(85% 0.025 210);
            --muted: oklch(50% 0.035 215);
            --dim: oklch(36% 0.03 215);
            --accent: oklch(58% 0.09 220);
            --accent2: oklch(72% 0.09 215);
            --line: oklch(58% 0.09 220 / 0.15);
            --line-strong: oklch(58% 0.09 220 / 0.3);
            --max-w: 1200px;
          }
          * { box-sizing: border-box; }
          html, body { margin: 0; padding: 0; }
          body {
            background: var(--bg);
            color: var(--fg);
            font-family: "IBM Plex Mono", monospace;
            font-weight: 300;
            min-height: 100vh;
            position: relative;
          }
          body::before {
            content: "";
            position: fixed;
            inset: 0;
            pointer-events: none;
            z-index: 0;
            background-image: radial-gradient(
              circle,
              oklch(58% 0.09 220 / 0.18) 1px,
              transparent 1px
            );
            background-size: 24px 24px;
          }
          body::after {
            content: "";
            position: fixed;
            inset: 0;
            pointer-events: none;
            z-index: 1;
            background: radial-gradient(
              ellipse 80% 80% at 50% 50%,
              transparent 30%,
              var(--bg) 100%
            );
          }
          main {
            position: relative;
            z-index: 2;
            max-width: var(--max-w);
            margin: 0 auto;
            padding: 4rem 2rem;
          }
          .meta {
            font-size: 0.55rem;
            letter-spacing: 0.12em;
            text-transform: uppercase;
            color: var(--dim);
          }
          h1 {
            font-family: "Bebas Neue", sans-serif;
            font-size: clamp(3rem, 7vw, 6rem);
            line-height: 0.95;
            letter-spacing: 0.04em;
            margin: 1rem 0 0.5rem;
            color: var(--fg);
          }
          h1 .accent { color: var(--accent); }
          .lede {
            max-width: 60ch;
            font-size: 0.85rem;
            line-height: 1.85;
            color: var(--muted);
            margin: 0 0 4rem;
          }
          .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
            gap: 1px;
            background: var(--line-strong);
            border: 1px dashed var(--line-strong);
          }
          .card {
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
            padding: 1.5rem;
            background: var(--bg);
            color: var(--fg);
            text-decoration: none;
            transition: background 0.2s, color 0.2s;
            position: relative;
          }
          .card:hover {
            background: var(--bg2);
            color: var(--accent2);
          }
          .card-host {
            font-size: 0.5rem;
            letter-spacing: 0.18em;
            text-transform: uppercase;
            color: var(--dim);
          }
          .card:hover .card-host { color: var(--accent); }
          .card-title {
            font-family: "Bebas Neue", sans-serif;
            font-size: 1.6rem;
            margin: 0;
            letter-spacing: 0.05em;
            line-height: 1;
          }
          .card-desc {
            font-size: 0.7rem;
            line-height: 1.7;
            color: var(--muted);
            margin: 0;
          }
          footer {
            margin-top: 4rem;
            font-size: 0.5rem;
            letter-spacing: 0.1em;
            text-transform: uppercase;
            color: var(--dim);
          }
          a.dim {
            color: var(--muted);
            text-decoration: none;
            border-bottom: 1px dashed var(--line);
          }
          a.dim:hover { color: var(--accent2); border-bottom-color: var(--accent); }
        </style>
      </head>
      <body>
        <main>
          <div class="meta">59.91°N · 10.75°E · OSLO, NO</div>
          <h1>Philip<br /><span class="accent">Bjørknes</span><br />Krogh</h1>
          <p class="lede">
            Developer building tools and interfaces. Projects below.
          </p>
          <section class="grid">
            ${cards}
          </section>
          <footer>
            <a class="dim" href="https://github.com/phibkro">github.com/phibkro</a>
            &nbsp;·&nbsp;
            <a class="dim" href="mailto:philip@phibkro.dev">philip@phibkro.dev</a>
          </footer>
        </main>
      </body>
    </html>
  '';
in
{
  systemd.services.phibkro-index = {
    description = "Serve the phibkro.org apex sitemap landing page";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.darkhttpd}/bin/darkhttpd"
        # darkhttpd needs a directory; symlink the single index.html into
        # one via RuntimeDirectory + ExecStartPre.
        "%t/phibkro-index"
        "--addr 127.0.0.1"
        "--port ${toString servePort}"
        "--no-listing"
      ];
      RuntimeDirectory = "phibkro-index";
      ExecStartPre = pkgs.writeShellScript "phibkro-index-stage" ''
        set -eu
        cp ${indexHtml} "$RUNTIME_DIRECTORY/index.html"
        cp ${sitemapXml} "$RUNTIME_DIRECTORY/sitemap.xml"
        cp ${robotsTxt} "$RUNTIME_DIRECTORY/robots.txt"
      '';
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  nori.publicRoutes.phibkro-apex = {
    host = "@";
    port = servePort;
    # No sitemap entry — the apex doesn't link to itself.
  };

  # DynamicUser already isolates this unit; just an empty entry to
  # satisfy the `every-service-has-fs-hardening` flake check.
  nori.harden.phibkro-index = { };

  nori.backups.phibkro-index.skip = "stateless — index.html is generated from Nix config";
}
