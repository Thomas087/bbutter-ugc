# Bright Data — Instagram Posts Dataset

This skill uses the Bright Data Datasets v3 API to scrape Instagram posts
for `buttbutter_official`.

## Authentication and identifiers

All requests require `Authorization: Bearer $BRIGHTDATA_API_KEY`. The
Instagram posts dataset id is `$BRIGHTDATA_DATASET_ID`. Both values live
in `.env`.

## Flow

1. **Trigger** the discover-new-posts-by-URL flow
   (`POST /datasets/v3/trigger?dataset_id=<id>&notify=false&include_errors=true&type=discover_new&discover_by=url`)
   with a wrapped input body:
   ```json
   {
     "input": [
       {
         "url": "https://www.instagram.com/<handle>/",
         "start_date": "MM-DD-YYYY"   // optional: omit on first fetch
       }
     ]
   }
   ```
   Response: `{"snapshot_id": "s_xxx"}`.

   **Lookback policy.**
   - First fetch (no cache / no `last_fetched`): `start_date` is omitted
     entirely, so Bright Data returns every post from the account's
     origin (full backfill).
   - Subsequent runs: `start_date` = `last_fetched` from the cache,
     converted from ISO 8601 to MM-DD-YYYY. Incremental only.

   Any overlap around the boundary is handled by client-side
   `merge_by_key` dedup on `post_id`. To force a full re-scrape, delete
   the cache file and re-run.

   Other per-URL parameters the endpoint supports (currently unused by
   the skill): `num_of_posts`, `end_date`, `post_type` ("Post" / "Reel" /
   "Story"), `posts_to_not_include`.

2. **Poll** `GET /datasets/v3/progress/<snapshot_id>` until `.status == "ready"`.
   Other states: `running`, `building`, `failed`.

3. **Download** `GET /datasets/v3/snapshot/<snapshot_id>?format=json`.
   Response: a JSON array of post objects. Fields typically include
   `post_id`, `url`, `caption`, `posted_at`, `media_type`, `likes`,
   `comments`, `hashtags` — but the skill treats anything beyond
   `post_id` as pass-through.

   **Video filter.** Before merging, the script drops any post whose
   `media_type` / `post_type` / `content_type` / `product_type` matches
   `video` or `reel` (case-insensitive). Carousels are built from
   images, so only image and carousel posts feed the inspiration pool.
   Posts missing all four fields are kept (fail-open).

## Script

All three steps are wrapped in `scripts/fetch_instagram.sh`. Claude calls
that script via Bash once per handle; the script handles trigger + poll
+ download + merge. Do not reimplement the flow in the prompt.

## Failure modes

- Snapshot times out after ~8 minutes (20 attempts with 3s→30s backoff) → script exits 2, cache left intact.
- Auth error (401) → script exits nonzero. Check `.env` / key validity.
- Dataset id invalid → 4xx from trigger call; script exits 1.

When a fetch fails, continue the pipeline and add a line to the output's
`## Gaps` section describing what was stale.
