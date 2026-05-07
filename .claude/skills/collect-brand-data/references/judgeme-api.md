# JudgeMe — Reviews API

This skill uses the JudgeMe public REST API to fetch product reviews.

## Authentication

Every request takes `api_token=$JUDGEME_API_KEY` and `shop_domain=$JUDGEME_SHOP_DOMAIN`
as query parameters (JudgeMe's convention — not header-based).

## Endpoint

`GET https://judge.me/api/v1/reviews`

## Parameters the skill uses

| Param | Purpose |
|---|---|
| `api_token` | Auth |
| `shop_domain` | Auth |
| `product_id` | Filter to one product |
| `page`, `per_page` | Pagination (default per_page: 50) |
| `updated_at_min` | Incremental fetch since last run |

## Response shape

```json
{
  "reviews": [ ... ],
  "current_page": 1,
  "per_page": 50,
  "total": 137
}
```

The script paginates until `reviews_seen >= total` (or the page returns
empty), with a hard cap of 100 pages.

## Script

All logic lives in `scripts/fetch_reviews.sh`. Claude calls it once per
product from `brand/products/catalog.yaml`. The script handles pagination,
incremental filtering, and merging.

## Failure modes

- Rate limiting (429) → script does not currently retry; fails loudly
  on non-JSON response and preserves the existing cache. If this
  becomes an issue in practice, add retry-with-backoff.
- Invalid token → 401; script exits nonzero.
- Product id unknown → empty `reviews` array; script succeeds with zero
  new reviews.
