# Marketplace API research

Reference notes for building each store adapter. Verify all specifics against
current official documentation before implementation — auth flows and rate
limits do change over time.

## Amazon Selling Partner API (SP-API)

**Status: deferred — not in current build scope.** No adapter is being
built against this yet. Keeping the research below on file so this becomes a "write one more
adapter" task later, not a re-research task.

- REST-based API covering orders, inventory, listings, and reports; it
  replaced the older MWS system.
- Auth: OAuth 2.0 via Login with Amazon (LWA). Older SP-API integrations also
  required AWS IAM credentials and SigV4 request signing, but recent tooling
  (e.g. the community `python-amazon-sp-api` library's v1 release) has
  dropped the mandatory AWS signing step for most calls — confirm current
  requirements against Amazon's official docs before assuming LWA-only auth
  is sufficient for every endpoint you need.
- Must register as an SP-API developer, create an app, and go through
  seller authorization (OAuth consent) to get a refresh token.
- Rate limits are per-endpoint token buckets, roughly 0.1–100 requests/second
  depending on the endpoint — budget backoff/retry logic accordingly.
- A sandbox environment is available for testing before production.
- Relevant endpoint family: the Listings Items API for create/update/delete,
  and inventory-related endpoints for stock levels.
- Known gotcha: Amazon's system is eventually consistent — a write can
  succeed but not immediately reflect on a read-back. Build a short delay/
  retry into the verification step, not an immediate check.
- Source: https://developer.amazonservices.com/, community integration
  guides (Apidog SP-API guide), `python-amazon-sp-api` package notes.

## Amazon pricing data & purchasing (for the profitability engine, section 9 of PROJECT_PLAN.md)

Two separate questions, researched 2026-08-23, both with a "no" that shaped
the design:

**Can Handles place an Amazon purchase automatically? No, and this is by
design on Amazon's side, not a gap to work around.** No official Amazon API
lets any application place a normal retail order — not PA-API, not SP-API
(that only covers *selling* through Amazon's own fulfillment, not buying).
The one automatable ordering path, the Amazon Business Ordering API, is B2B
procurement for Amazon Business accounts — a different product, not
applicable to sourcing/reselling. Third-party "auto-buy" services (Zinc and
similar) exist only by automating around Amazon's checkout and bot defenses
(CAPTCHAs, IP bans, 2FA) — the same terms-of-service risk category already
ruled out for scraping Mercari/Poshmark/Vinted, now with real money and a
payment method attached. **Decision (2026-08-23): no auto-buy, full
stop.** Handles surfaces a direct link to the
Amazon product page for a human to complete the purchase themselves, in
their own account, with their own payment method.

**Where the price data comes from: Keepa, and it needs to be a paid API for
this to run unattended at scale.** The free Keepa browser extension only
overlays data while a human is actively looking at an Amazon page — it
cannot run in the background. The Keepa API removes that limit, at a real
cost:

| Tier | Price | Throughput |
|---|---|---|
| Power User | €19/mo | 1 token/min |
| Starter | €49/mo | 20 tokens/min |
| — | €129/mo | 60 tokens/min |
| — | €459/mo | 250 tokens/min |
| — | €1,499/mo | 1,000 tokens/min |
| — | €4,499/mo | 4,000 tokens/min |

(Custom rates available between these preset points. Tokens expire 60
minutes after being issued, so throughput is a sustained rate, not a
stockpile-able monthly pool.)

Two very different costs per ASIN:
- **Direct product lookup** (checking a specific, already-known ASIN):
  ~1 token per ASIN.
- **Product Finder** (discovery by filter criteria — category, price drop,
  sales rank, etc., *not* a specific ASIN you already have): **10 tokens +
  1 token per 100 ASINs returned.** A single query returning 1,000 matching
  candidates costs ~20 tokens total — roughly 50x cheaper per ASIN than
  looking each one up individually.

**Cost-reduction strategy (this is the actual lever, not a pricing
negotiation):** naively checking every catalog SKU against Amazon on a
tight cadence is what drives the cost up, and most of that spend would be
wasted — resale/vintage/one-off items generally have no matching current
Amazon listing to check against in the first place. Only new, mass-produced, brand+model-identifiable items are
realistic candidates. So:

1. **Filter before spending a token** — flag which catalog SKUs are even
   plausibly Amazon-matchable at ingestion time; only that subset (likely a
   small fraction of the catalog, exact ratio TBD against real catalog
   data) is ever queried.
2. **Discover cheaply, verify selectively** — use Product Finder's
   bulk/cheap query mode to surface broad candidate lists, and only spend
   the pricier per-ASIN lookup token on the small subset that clears an
   initial filter.
3. **Refresh on a sane cadence, not continuously** — weekly (or
   trigger-based: new item added, cost/price changed) instead of daily,
   cutting volume 7x+ versus a naive daily sweep.
4. **Start on the cheapest tier and scale only if real usage proves it
   necessary** — same principle as the resource-aware scheduler (section 7):
   efficient by default, scale up only against a demonstrated need, not a
   worst-case guess. The €19/mo tier (1 token/min ≈ 1,440 tokens/day) likely
   covers a properly filtered, weekly-cadence subset comfortably; it will
   not cover blanket-checking a large catalog on a tight schedule, which is
   exactly the case this design avoids needing.
- Source: https://keepa.com/api-docs/, https://revenuegeeks.com/software/keepa/api,
  https://keepaapi.readthedocs.io/en/latest/product_query.html.

## eBay Sell APIs

- Auth: OAuth 2.0, with two relevant grant types — client credentials grant
  (app-level token, for public data) and authorization code grant (user-level
  token, needed to manipulate a specific seller's inventory).
- The OAuth token endpoint itself is separately rate-limited: client
  credentials grant ≈ 1,000 requests/day, authorization code grant ≈ 10,000/
  day, refresh token grant ≈ 50,000/day.
- API call limits are set per-API, not globally. Example: the Account API
  defaults to 25,000 calls/day for individual/small-business developer
  accounts; higher limits are available after eBay's "Application Growth
  Check."
- Data model: the Inventory API splits a listing into two linked objects —
  an "inventory item" (product data) and an "offer" (the live price/quantity/
  marketplace publication). You create/update the inventory item, then
  publish an offer against it to make it live. Plan your schema mapping
  around this split rather than treating a listing as one flat object.
- Source: https://developer.ebay.com/develop/get-started/api-call-limits,
  https://developer.ebay.com/api-docs/static/oauth-rate-limits.html.

## Mercari (US)

- No official public API for seller inventory/listing management exists.
- Third-party wrappers (e.g. `mercapi` for mercari.jp, various unofficial
  "mercari-us" packages) work by reverse-engineering Mercari's internal
  GraphQL endpoints, including undocumented "automatic persisted queries."
  This is unsupported, can break without notice, and likely violates
  Mercari's terms of service.
- **Recommendation: do not build automation against Mercari's private
  endpoints.** Realistic options are manual updates only, or contacting
  Mercari directly to ask about a business/partner integration path.

## Poshmark

- No official public developer API for sellers. Poshmark's own tools (Smart
  List AI, Closet Insights, Promoted Closet) are first-party only.
- A large ecosystem of third-party "closet bots" (PrimeLister, ClosetMate,
  Sidekick, etc.) automates sharing, relisting, and offers, but generally
  through session emulation rather than a sanctioned API. Poshmark's policy
  stance on this kind of automation has shifted over time.
- **Recommendation:** treat the same as Mercari — manual-update or
  read-only-monitoring only, until an official integration path is
  confirmed.

## Vinted

- No general public API for individual seller listing management was found.
  A "Pro Seller API" exists but appears scoped to insights, rewards, and
  tier status for Vinted's Pro Seller program (business accounts) — not
  general listing CRUD.
- Existing third-party tools mostly scrape public product pages rather than
  using a sanctioned write API.
- **Recommendation:** confirm directly with Vinted whether a given seller
  account qualifies for Pro Seller status and exactly what that API exposes,
  before assuming inventory automation is possible here.

## Walmart Marketplace

- Auth: OAuth 2.0. Generate a Client ID and Client Secret in the Walmart
  Developer Portal, exchange for an access token via the Token API. Tokens
  are short-lived (~15 minutes) — track `expires_in` and refresh
  proactively rather than waiting for a 401.
- Must complete Walmart's seller onboarding and API access setup before any
  endpoint works — this is an approval gate, not just a signup form; budget
  lead time before this adapter can be tested end-to-end.
- Rate limits are per-seller (direct integrations and approved Solution
  Providers get separate limits), enforced via a token-bucket algorithm.
  Exceeding it returns `429 Too Many Requests` — same shape as eBay/Amazon,
  so the shared adapter interface's backoff/retry logic should cover this
  too.
- Relevant endpoint family: the **Inventory API** for retrieving/updating
  quantity by SKU and ship node — synchronous, well-documented, confident
  in this one.
- **Item creation/update is feed-based and asynchronous, unlike eBay's
  synchronous Inventory API calls** (confirmed 2026-08-27, still not a full
  doc pass — real request/response JSON schemas not verified). You submit
  a feed (`POST /v3/feeds?feedType=MP_ITEM` for new items,
  `MP_MAINTENANCE` for partial updates to existing ones — e.g. price
  changes without resubmitting the whole item), then poll
  `GET /v3/feeds/{feedId}` until Walmart finishes processing it. No
  eBay-style "immediately get an ID back" - `EbayAdapter`'s and
  `WalmartAdapter`'s `createListing` share the same return shape, but
  Walmart's implementation polls internally to honor that contract rather
  than exposing the async feed lifecycle to callers.
- No confirmed eBay-style "withdraw" for delisting. `WalmartAdapter.delist`
  sets quantity to 0 via the (confident, synchronous) Inventory API - the
  same auto-unlist behavior section 5's reconciliation logic already
  relies on. A more thorough removal from search results may need an
  additional item-status feed - not implemented, not confirmed necessary,
  revisit once real Walmart credentials exist to check actual behavior.
- Pricing sits in its own "Pricing APIs" family per Walmart's docs,
  separate again from both Inventory and Item Management - not confirmed
  whether `WalmartAdapter`'s price updates (routed through the
  `MP_MAINTENANCE` feed below) are actually the right mechanism versus a
  dedicated Pricing endpoint. Flagged, not guessed past.
- Not yet confirmed: eventual-consistency behavior on writes (Amazon
  explicitly documents this; Walmart's public docs don't call it out one
  way or the other). **Default to the same write-then-verify-with-delay
  pattern used for Amazon until proven unnecessary** — safer than assuming
  synchronous consistency.
- Source: https://developer.walmart.com/us-marketplace/docs/introduction-to-marketplace-apis,
  https://developer.walmart.com/us-marketplace/docs/rate-limiting,
  https://developer.walmart.com/global-marketplace/docs/inventory-api-overview.

## Two stores on one platform — resolved

Confirmed 2026-08-23: the two eBay stores are **two separate eBay seller
accounts**, not one store with two names. No new adapter needed, but this does mean the
eBay adapter has to support multiple configured accounts (each with its own
OAuth token pair), not just one — see the `stores` field shape change in
`catalog/schema.json` and the registry in `catalog/stores.json`.

Connected accounts (`catalog/stores.json` is the source of truth for these,
this is just a summary; account names are placeholders in this copy):

| Account key | Platform | Automation |
|---|---|---|
| `ebay_store_a` | eBay | full |
| `ebay_store_b` | eBay | full |
| `poshmark` | Poshmark | monitor only |
| `vinted` | Vinted | monitor only |
| `mercari` | Mercari | monitor only |
| `walmart` | Walmart | full (once approved) |
| `amazon` | Amazon | deferred |
