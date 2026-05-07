---
name: collect-brand-data
description: Collect and refresh all Butt Butter (buttbutter.fr) brand data under `brand/` — guidelines, product catalog, JudgeMe reviews per product, and the full Instagram history of `buttbutter_official`. Use when the user asks to refresh or sync brand data, fetch Instagram posts, pull JudgeMe reviews, or before running any downstream content skill that needs fresh brand data.
---

# Collect Brand Data — Butt Butter

You are running a read-and-refresh pipeline that keeps Butt Butter's
brand data under `brand/` up to date. The outputs feed downstream
content-generation skills (e.g. `slider-planner`, `slider-html`, `slider-images`).
This skill does **no** content generation — it only collects data.

Target layout under `brand/`:

```
brand/
├─ guidelines.md
├─ DESIGN.md
├─ logo.md
├─ packshots/
├─ instagram/
│  └─ buttbutter_official.json
├─ reviews/
│  ├─ <product-slug>.json
│  └─ …
└─ products/
   ├─ catalog.yaml
   └─ <product-slug>.md
```

## Flags

- `--force` — bypass the 24h freshness guard on Instagram and JudgeMe
  fetches (the scripts accept `--force` as a trailing argument, or
  `FORCE_REFRESH=1` in the environment).
- `--cache-only` — skip all network fetches. Just verify what exists
  under `brand/` and print the summary (step 6).

Parse flags from the user's invocation. Default: no flags.

## Pipeline (execute in order)

### Step 1 — Load env

- Read `.env`. If missing, stop and tell the user to copy `.env.example`.
- Required keys: `BRIGHTDATA_API_KEY`, `BRIGHTDATA_DATASET_ID`,
  `JUDGEME_API_KEY`, `JUDGEME_SHOP_DOMAIN`. If `--cache-only` is set,
  none of these are required; skip the check.

### Step 2 — Ensure brand guidelines

- Try to read `brand/guidelines.md`.
- **If present:** done.
- **If missing (bootstrap, only when `--cache-only` is not set):**
  - Use `WebFetch` to read:
    - `https://buttbutter.fr/`
    - `https://buttbutter.fr/pages/about` (or the About page if named
      differently — check the home page navigation first)
  - Synthesize a French-language `brand/guidelines.md` covering: mission,
    audience, tone of voice, visual identity cues, claims the brand
    makes and claims it avoids, preferred and forbidden vocabulary.
  - Write it with the Write tool.
  - Tell the user "Brand guidelines bootstrapped at brand/guidelines.md
    — review and edit before your next run."
- If `--cache-only` and the file is missing, add to `gaps`:
  `"brand/guidelines.md absent"`.

### Step 3 — Ensure product catalog

- Try to read `brand/products/catalog.yaml` and every
  `brand/products/<slug>.md`.
- **If catalog.yaml is present:** done.
- **If catalog.yaml is missing (bootstrap, only when `--cache-only`
  is not set):**
  - Use `WebFetch` to read the products index (try
    `https://buttbutter.fr/collections/all` first, fall back to
    `/products` or the main nav's "Boutique"/"Shop" link).
  - Extract product URLs. If this fails or returns no URLs, stop and
    tell the user to drop `brand/products/<slug>.md` files by hand.
  - For each product URL, use `WebFetch` to read the page. Synthesize:
    - A slug (from URL)
    - Product name
    - Hero image URL (reference only; do not download)
    - Characteristics, ingredients, claims, use cases, messaging
      do's/don'ts
  - Write `brand/products/catalog.yaml` (structured: slug, name, url,
    hero_image, judgeme_product_id — leave judgeme_product_id blank
    if not discoverable; the user fills it in).
  - Write one `brand/products/<slug>.md` per product.
  - Tell the user "Product catalog bootstrapped at brand/products/ —
    fill in judgeme_product_id fields in catalog.yaml before your
    next run so reviews can be fetched."
- If `--cache-only` and the catalog is missing, add to `gaps`:
  `"brand/products/catalog.yaml absent"`.

### Step 4 — Refresh own Instagram cache

Unless `--cache-only` is set:

- Run: `bash .claude/skills/collect-brand-data/scripts/fetch_instagram.sh buttbutter_official`
  (the script reads `$BRIGHTDATA_DATASET_ID` from `.env`; pass a dataset
  id as a second positional argument to override). Pass `--force` through
  if the user passed `--force`.
- The script handles trigger + poll + download + merge into
  `brand/instagram/buttbutter_official.json` (dedup by `post_id`).
- **Freshness guard:** the script exits 0 without calling the API if
  `last_fetched` is under 24h old. `--force` overrides.
- **On exit code 0:** proceed (fetched or skipped — both fine).
- **On exit code 2 (snapshot timeout):** the cache is stale but valid.
  Add to `gaps`:
  `"Bright Data timeout for buttbutter_official; used cache from <last_fetched>"`.
- **On any other nonzero exit:** add to `gaps` and continue.

If `--cache-only` is set, skip fetching. If the cache file is missing,
add to `gaps`.

See `references/brightdata-api.md` for API background.

### Step 5 — Refresh JudgeMe reviews

Unless `--cache-only` is set, for each product in
`brand/products/catalog.yaml` that has a `judgeme_product_id`:

- Run: `bash .claude/skills/collect-brand-data/scripts/fetch_reviews.sh <slug> <judgeme_product_id>`
  (pass `--force` through if the user passed `--force`).
- **Freshness guard:** the script exits 0 without calling the API if
  `last_fetched` is under 24h old.
- On nonzero exit, add to `gaps`: `"JudgeMe fetch failed for <slug>"`.
- Products missing `judgeme_product_id`: skip silently (no gap).

If `--cache-only`: just check which caches exist and note missing ones
in `gaps`.

See `references/judgeme-api.md` for API background.

### Step 6 — Summary

Print a short text summary to the terminal, one line per source:

- `guidelines: OK` (or `bootstrapped`, or `MISSING`)
- `products: N products in brand/products/catalog.yaml` (or `MISSING`)
- `instagram: buttbutter_official — N posts, last_fetched <iso>`
  (or `MISSING` / `timeout`)
- For each product with reviews: `reviews/<slug>: N reviews, last_fetched <iso>`
  (or `skipped (no judgeme_product_id)` / `MISSING`)
- If `gaps` is non-empty: list every entry under a `Gaps:` heading.

Example:

```
collect-brand-data complete.
  guidelines: OK
  products: 4 in brand/products/catalog.yaml
  instagram: buttbutter_official — 142 posts, last_fetched 2026-04-23T07:25:11Z
  reviews/creme-apaisante: 101 reviews, last_fetched 2026-04-23T07:25:34Z
  reviews/complement-circulation-transit: 380 reviews, last_fetched 2026-04-23T07:25:41Z
  reviews/probiotique: 3 reviews, last_fetched 2026-04-23T07:25:47Z
  reviews/soin-lavant-hygiene-intime: 12 reviews, last_fetched 2026-04-23T07:25:52Z
  Gaps: (aucun)
```

## Failure policy

- Never hard-crash mid-run. If a step has a recoverable failure (fetch
  timeout, missing optional product id), add to `gaps` and continue.
- Unrecoverable failures (missing `.env` when network fetches are
  needed, malformed YAML) stop the run with a clear message telling the
  user how to fix it.
- When unsure, prefer continuing with a gap over stopping.
