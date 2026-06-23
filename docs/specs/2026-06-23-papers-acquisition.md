---
summary: Acquisition pipeline for academic papers — search/reading-list → OA-first
  resolve → fetch → Paperless-ngx (OCR + full-text + phone). The "tonic for papers",
  acquisition-first. Design preceding implementation; build deferred to a fresh session.
---

# Papers acquisition — design spec

The third media-acquisition pipeline (after music/tonic and the planned books/comics
\*arr drop-ins). Same two-part shape as music — **acquire** (resolve an identity →
fetch a document) + **serve** — but the resolution chain is *legal and well-engineered*,
so this is not a gray-zone build. Operator scoped it **acquisition-first**; compression
collapses to "OCR scanned PDFs so they're searchable", which the sink already does.

## Goal (verifiable)

Paste a DOI / arXiv-id / title **or** feed a reading list → the paper lands in
Paperless-ngx, OCR'd, full-text-searchable, readable on the phone. Open-access first.

## Decisions (resolved with the operator 2026-06-23)

| Fork | Choice | Why |
|---|---|---|
| Discovery mode | **search-on-demand + reading-list sync** (NOT follow/monitor, NOT citation-crawl) | "find a paper and file it" + "backfill a list" — not a subscription engine |
| Sink | **Paperless-ngx** | homelab-native: OCR + full-text search + web UI + tagging + folder export to phone |
| Resolution posture | **OA-first**, gray-zone fallback opt-in + off by default | arXiv+Unpaywall+OpenAlex cover a large fraction legally + are stable APIs — the *right* answer, not a compromise |
| Build vs compose | **compose**; build only the thin fetcher | the sink (Paperless) + the registry clients (paper-search-mcp) exist — don't reinvent |

## Architecture

```
  [search box / paste DOI·arXiv]─┐
                                 ├─▶ RESOLVE (OA-first) ─▶ FETCH PDF ─┐
  [reading list: BibTeX / DOIs]──┘                                    ▼
                                        Paperless-ngx consume dir → OCR + index + tag + serve + phone
```

The fetcher's whole job: **resolve → download → drop in Paperless's consume folder.**
Paperless owns OCR, full-text search, tagging, the web UI, and phone access. Do **not**
rebuild any of that.

### Resolution chain (OA-first)

```
  arXiv API          preprints — full PDF (+ LaTeX source), free, stable
  Unpaywall (DOI→OA) the key tool: legal OA PDF URL for a DOI if one exists
  OpenAlex           metadata + OA links (+ author/citation graph, unused in this cut)
  Crossref           DOI metadata + publisher links
  ── fallback ──     institutional proxy (if available) → then gray-zone registries,
                     OPERATOR-OPT-IN, off by default
```

## Build plan (keyframes — implementer draws the inbetweens)

```
  P0  Paperless-ngx homelab service module  — sink stands alone first.
      nori.services-style: storage (nori.fs), OCR, consume dir, lanRoute (operator
      audience), backup intent, phone access (lanRoute or a Syncthing export folder).
      DoD: drop a PDF in the consume dir → it's OCR'd + searchable + readable on phone.

  P1  Resolver + fetcher  — evaluate `paper-search-mcp` (covers arXiv/Crossref/OpenAlex/
      Unpaywall/Semantic Scholar/… + an optional Sci-Hub workflow to leave OFF) vs direct
      arXiv+Unpaywall+OpenAlex clients. Resolve DOI/arXiv/title → fetchable OA PDF →
      download → consume dir, with source metadata.
      DoD: a DOI with a known OA version lands in Paperless, end to end.

  P2  Search-on-demand front-end  — CLI first (paste/search → queue). A thin tonic-style
      PWA later if wanted.

  P3  Reading-list sync  — ingest BibTeX / a DOI list → resolve+fetch the entries missing
      a PDF. Idempotent (skip what's already in Paperless).
```

## Open questions (decide at build time)

- **Own repo vs homelab module.** The fetcher could be a standalone repo (tonic-sibling,
  reusable) or live as a homelab module. Lean: Paperless is a homelab service regardless;
  the fetcher can start as a homelab module and graduate to its own repo if it grows.
  Tonic-generalizing to "media acquisition" is a third option — probably over-coupling.
- **Quality / format preference.** "Prefer document formats" → prefer text/vector PDF;
  ensure scanned PDFs are OCR'd (Paperless does this on consume). LaTeX-source-over-PDF
  for arXiv is a nice-to-have, not P0.
- **Gray-zone fallback.** Keep it an explicit opt-in config flag, default off; the OA chain
  is the default path. Most papers resolve legally.

## Prior art / sources

- **Sink:** Paperless-ngx — a document *archive* (OCR/search/serve), not a fetcher. <https://docs.paperless-ngx.com/>
- **Resolver:** `paper-search-mcp` — multi-source search+download (arXiv·Crossref·OpenAlex·Unpaywall·Semantic Scholar·… + optional Sci-Hub). <https://github.com/openags/paper-search-mcp>
- **OA lookup:** Unpaywall (DOI→OA), arXiv API, OpenAlex, Crossref.
- No turnkey "resolve → Paperless" integration exists (verified 2026-06-23) — the fetcher is the gap.

## Relation to the music pipeline

Same acquire+serve shape as `tonic` + `music-mirror`. Differences: papers resolve via a
*legal* chain (no scraped creds / UA impersonation — cf. [ADR-0010] in tonic); the "near-
lossless compression" half is moot (text PDFs are at the information floor — only scanned
PDFs benefit, via OCR which Paperless already does). Acquisition is the whole game here.
