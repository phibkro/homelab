#!/usr/bin/env python3
"""papers-fetch — resolve a DOI / arXiv-id / title to an open-access PDF and
drop it into Paperless-ngx's consume directory.

The OA-first resolution chain (docs/specs/2026-06-23-papers-acquisition.md):

    arXiv id   ─▶ arXiv API           (preprints — full PDF, free, stable)
    DOI / title─▶ Unpaywall           (DOI → legal OA PDF URL if one exists)
               ─▶ OpenAlex            (metadata + best_oa_location PDF)
               ─▶ Crossref            (DOI metadata + publisher link, last resort)

Gray-zone registries (Sci-Hub / Anna's) are intentionally NOT implemented.
The `--allow-gray-zone` flag exists only so the wrapper module can surface the
opt-in posture; flipping it raises (the legal chain is the whole product).

Exit codes:
    0  PDF resolved + written to the consume dir
    1  usage / config error (bad args, missing email)
    2  no open-access PDF found anywhere in the chain
    3  network / download error
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import arxiv
import httpx
from habanero import Crossref

# Polite-pool UA for the metadata APIs (Unpaywall/OpenAlex/Crossref ask for a
# mailto so they can contact you about misuse — it earns the faster rate limit).
API_USER_AGENT = "homelab-papers-fetch/1.0 (mailto:{email})"

# Download UA: publisher CDNs serving the *actual* OA PDF (PeerJ, Elsevier's
# OA mirror, MDPI, …) routinely 403 a bare library UA even for openly-licensed
# files. A browser-like UA is the difference between a 403 and the PDF. This is
# NOT gray-zone impersonation (cf. tonic ADR-0010): the OA index already told us
# the file is openly licensed — we're only getting past a blunt UA filter.
DOWNLOAD_USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
)
ARXIV_ID_RE = re.compile(r"^(arxiv:)?(\d{4}\.\d{4,5}(v\d+)?|[a-z\-]+(\.[A-Z]{2})?/\d{7})$", re.I)
DOI_RE = re.compile(r"^(doi:|https?://(dx\.)?doi\.org/)?(10\.\d{4,9}/\S+)$", re.I)


@dataclass
class Resolved:
    """A located OA PDF plus enough metadata to name the file."""

    pdf_url: str
    title: str
    source: str  # which step of the chain found it


def _slug(text: str, limit: int = 80) -> str:
    """Filesystem-safe slug for the dropped filename. Paperless re-reads its
    own title from the document content/metadata on consume, so this only has
    to be unique-ish and legible, not authoritative."""
    cleaned = re.sub(r"[^\w\s-]", "", text).strip()
    cleaned = re.sub(r"[\s_-]+", "-", cleaned)
    return (cleaned[:limit] or "paper").strip("-")


def _classify(query: str) -> tuple[str, str]:
    """Return (kind, normalized) where kind ∈ {arxiv, doi, title}."""
    q = query.strip()
    if ARXIV_ID_RE.match(q):
        return "arxiv", re.sub(r"^arxiv:", "", q, flags=re.I)
    m = DOI_RE.match(q)
    if m:
        return "doi", m.group(3)
    return "title", q


def _resolve_arxiv(arxiv_id: str) -> Resolved | None:
    client = arxiv.Client()
    results = list(client.results(arxiv.Search(id_list=[arxiv_id], max_results=1)))
    if not results:
        return None
    r = results[0]
    return Resolved(pdf_url=r.pdf_url, title=r.title, source="arxiv")


def _resolve_unpaywall(doi: str, email: str) -> Resolved | None:
    url = f"https://api.unpaywall.org/v2/{doi}"
    resp = httpx.get(url, params={"email": email}, timeout=30, follow_redirects=True)
    if resp.status_code != 200:
        return None
    data = resp.json()
    # Only `url_for_pdf` is a direct PDF link; `url` is the OA *landing page*
    # (HTML → 403, not the file). best_oa_location often lacks a PDF link even
    # when another location has one, so scan every oa_location for the first
    # direct PDF. Papers exposing only landing pages (PeerJ, eLife) return None
    # here → fall through to OpenAlex, then a clean "no OA PDF" exit (we don't
    # scrape landing pages).
    locations = [data.get("best_oa_location") or {}] + (data.get("oa_locations") or [])
    for loc in locations:
        pdf = loc.get("url_for_pdf")
        if pdf:
            return Resolved(pdf_url=pdf, title=data.get("title") or doi, source="unpaywall")
    return None


def _resolve_openalex(doi: str, email: str) -> Resolved | None:
    url = f"https://api.openalex.org/works/doi:{doi}"
    resp = httpx.get(
        url,
        params={"mailto": email},
        headers={"User-Agent": API_USER_AGENT.format(email=email)},
        timeout=30,
        follow_redirects=True,
    )
    if resp.status_code != 200:
        return None
    data = resp.json()
    loc = data.get("best_oa_location") or {}
    pdf = loc.get("pdf_url")
    if not pdf:
        return None
    return Resolved(pdf_url=pdf, title=data.get("title") or doi, source="openalex")


def _title_to_doi(title: str, email: str) -> str | None:
    # habanero wraps transport errors (incl. timeouts) in a bare RuntimeError,
    # so the resolve-level handler can't see an httpx exception here — catch
    # broadly and treat any Crossref failure as "couldn't resolve a DOI".
    cr = Crossref(mailto=email, timeout=30)
    try:
        res = cr.works(query_bibliographic=title, limit=1)
    except Exception:  # noqa: BLE001 — habanero raises RuntimeError, not httpx
        return None
    items = res.get("message", {}).get("items", [])
    if not items:
        return None
    return items[0].get("DOI")


def resolve(query: str, email: str) -> Resolved | None:
    """Walk the OA-first chain. Returns the first hit, or None if exhausted."""
    kind, value = _classify(query)

    if kind == "arxiv":
        return _resolve_arxiv(value)

    if kind == "title":
        doi = _title_to_doi(value, email)
        if doi is None:
            return None
        value = doi  # fall through into the DOI chain

    # DOI chain: Unpaywall → OpenAlex (Crossref gives metadata but rarely a
    # free PDF link, so it's only used above to turn a title into a DOI).
    for step in (_resolve_unpaywall, _resolve_openalex):
        hit = step(value, email)
        if hit is not None:
            return hit
    return None


def download(resolved: Resolved, out_dir: Path) -> Path:
    """Stream the PDF into out_dir under a slugged name. Atomic: write to a
    .part sibling, then rename, so Paperless's consumer never sees a half file."""
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / f"{_slug(resolved.title)}.pdf"
    tmp = dest.with_suffix(".pdf.part")
    with httpx.stream(
        "GET",
        resolved.pdf_url,
        headers={
            "User-Agent": DOWNLOAD_USER_AGENT,
            "Accept": "application/pdf,*/*",
        },
        timeout=60,
        follow_redirects=True,
    ) as resp:
        resp.raise_for_status()
        with tmp.open("wb") as fh:
            for chunk in resp.iter_bytes():
                fh.write(chunk)
    tmp.rename(dest)
    return dest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="papers-fetch",
        description="Resolve a DOI / arXiv-id / title to an OA PDF → Paperless consume dir.",
    )
    parser.add_argument("query", help="a DOI, an arXiv id, or a paper title")
    parser.add_argument(
        "--out-dir",
        required=True,
        type=Path,
        help="directory to drop the PDF into (Paperless consume dir)",
    )
    parser.add_argument(
        "--email",
        required=True,
        help="contact email — Unpaywall + OpenAlex + Crossref require it in the polite-pool query string (not a secret)",
    )
    parser.add_argument(
        "--allow-gray-zone",
        action="store_true",
        help="opt into gray-zone registries (NOT implemented — the OA chain is the product; this raises)",
    )
    args = parser.parse_args(argv)

    if args.allow_gray_zone:
        print(
            "papers-fetch: --allow-gray-zone is not implemented; the OA chain is the only path.",
            file=sys.stderr,
        )
        return 1

    try:
        resolved = resolve(args.query, args.email)
    except (httpx.HTTPError, arxiv.ArxivError) as exc:
        print(f"papers-fetch: resolution failed: {exc}", file=sys.stderr)
        return 3

    if resolved is None:
        print(
            f"papers-fetch: no open-access PDF found for {args.query!r} "
            "(arXiv → Unpaywall → OpenAlex all empty).",
            file=sys.stderr,
        )
        return 2

    try:
        dest = download(resolved, args.out_dir)
    except httpx.HTTPError as exc:
        print(f"papers-fetch: download failed ({resolved.pdf_url}): {exc}", file=sys.stderr)
        return 3

    print(f"papers-fetch: [{resolved.source}] {resolved.title!r} → {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
