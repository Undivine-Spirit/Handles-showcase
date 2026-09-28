# handles_core

Pure Dart package - catalog model, the shared `StoreAdapter` interface,
per-marketplace adapter implementations (eBay and Walmart), the
reconciliation engine, and the three server binaries in `bin/`. No Flutter
dependency on purpose, so it's usable and testable with just the Dart SDK.
The Flutter app (`app/`, Windows + Android) depends on this package rather
than duplicating any of this logic.

## Status

- [x] `CatalogItem` / `StoreListingState` - mirrors `catalog/schema.json`,
      including each store's `last_confirmed_quantity` (reconciliation
      v2's baseline) and `listing_url` (monitor-only deep links).
- [x] `StoreAdapter` interface - `docs/PROJECT_PLAN.md` section 3.
- [x] eBay adapter - Inventory API (inventory item + offer), OAuth 2.0
      authorization-code flow with automatic refresh, multi-account
      support.
- [x] Walmart adapter - Inventory API (synchronous, confident) +
      feed-based Item Management (`MP_ITEM`/`MP_MAINTENANCE`, asynchronous
      submit-then-poll, wrapped so `createListing`/`updateListing` still
      look synchronous to callers). Client-credentials OAuth - simpler
      than eBay's, no browser/consent step. Structurally different from
      eBay in three ways worth reading before touching it - see
      `WalmartAdapter`'s class doc comment. Several specifics (exact feed
      JSON schema, whether price updates really belong on the
      maintenance feed vs. a separate Pricing API) are flagged as
      unverified rather than guessed past - see `docs/API_RESEARCH.md`.
- [x] Reconciliation engine v2 - the real two-way merge
      (`docs/PROJECT_PLAN.md` section 5). Each store's live quantity is
      compared against the last value confirmed there, drops across every
      store are summed and subtracted from the source of truth once, and
      the new quantity is pushed to every connected store with
      write-then-verify. An oversell (more sold across stores than was
      available) delists everywhere and is flagged `oversold` for a human
      rather than auto-resolved. Replaces v1's one-way push and its
      `conflictDetected` flag.
- [x] Real secure credential storage - resolved in `app/` (this package
      still only defines the interface, on purpose). See
      `app/lib/services/secure_credential_store.dart`.
- [x] Category system - `Category`/`CategoryRecommender` (keyword-matching
      v1, not ML - see its doc comment) and `HandlesSettings` for priority
      categories + user-added custom categories.
- [x] `CatalogRepository` - reads/writes the catalog as one JSON file per
      SKU (the "GitHub state layer" from `docs/PROJECT_PLAN.md` section 3,
      component 3).
- [x] `GitSync` - commits and pushes catalog changes, tested against a
      real local bare repo (not mocked).
- [x] `EventLogStore` - JSON-lines event log (`catalog/.events.jsonl`),
      written by both the daemon and the catalog API. Severities are
      `info`, `warning`, `actionNeeded` and `error`; the app raises a
      native notification for the last two.
- [x] `bin/reconcile_daemon.dart` - headless, always-on reconciliation
      loop, meant to run in Docker (see `Dockerfile`,
      `docs/DEPLOYMENT.md`) on self-hosted hardware rather than requiring
      the desktop app to be open. Logs why it skips any account (missing
      secrets, missing policy IDs, no refresh token yet). Supports two run
      shapes from one binary: loop internally (docker-compose) or
      `RUN_ONCE=true` and exit after one pass (Kubernetes `CronJob`). In
      loop mode it also wakes early when `bin/webhook_server.dart` drops
      a trigger file.
- [x] `bin/api_server.dart` + `CatalogDataStore` - the catalog API the
      app talks to (2026-09-02), sharing the daemon's catalog directory:
      items, events and the brand-risk list, behind one bearer token
      (refuses to start without one). Doesn't terminate TLS itself - see
      `docs/DEPLOYMENT.md`.
- [x] `bin/webhook_server.dart` - marketplace webhook receiver
      (2026-09-25). Walmart's `PO_CREATED`, verified with HMAC-SHA256,
      wakes the daemon through a trigger file. eBay's account-deletion
      topic completes the challenge handshake, but its per-notification
      signature isn't cryptographically verified yet, so those
      notifications are logged for manual review and never acted on. A
      global rate limit of 30 requests/minute covers both routes.
- [x] Brand risk list - `BrandRiskList`/`BrandRiskChecker`, a known-risk
      blocklist (exact match after trimming and lowercasing), not a
      clearance check. `SourcingListingGenerator` holds a flagged brand
      for human review instead of publishing it.
- [x] Sourcing engine, components 1-3 - `SourcedListing` (deliberately
      separate from `CatalogItem`, see `docs/PROJECT_PLAN.md` section 10
      for why), `SourcingPriceCalculator` (destination-platform fee math,
      not Amazon's - a different formula from section 9's calculator on
      purpose), `SourcingMonitor` (the actual out-of-stock checker:
      delists a sourced item everywhere it's live the moment the supplier
      runs out), and `SourcingListingGenerator` (computes a price and
      pushes it live via the shared `StoreAdapter` interface - Walmart and
      eBay both work here with zero sourcing-specific adapter code).
- [ ] Sourcing engine, component 4 - bulk sourcing via Keepa's Product
      Finder. Needs a real Keepa subscription to do anything beyond
      what's already tested against fakes.
- [x] `AmazonFeeModel`/`AmazonProfitabilityCalculator` - section 9's
      calculator. Deliberately the Amazon-fee twin of
      `SourcingPriceCalculator`, not the same calculator - see its doc
      comment for why those stay separate.
- [x] `SystemResourcesReader`/`ProcSystemResourcesReader` - resource-aware
      scheduling for the *daemon* (revised from the original Windows/
      Android app-side plan, see `docs/PROJECT_PLAN.md` section 7's
      2026-08-27 note: a Raspberry Pi cluster is where this actually
      matters). Reads `/proc/meminfo`+`/proc/loadavg`, skips a pass rather
      than push an already-strained device further, fails open (proceeds
      anyway) if the check itself breaks. Parsing logic is tested with
      sample `/proc` content directly, since real `/proc` files don't
      exist on a Windows dev machine - which is also where the fail-open
      path was confirmed for real, by running the daemon there.
- [ ] Other store adapters (Mercari/Poshmark/Vinted stay monitor-only per
      `docs/PROJECT_PLAN.md` section 14 - no write API exists to adapt to).

## Docker / Kubernetes

`Dockerfile` is one multi-stage build with three final targets - `daemon`
(`bin/reconcile_daemon.dart`), `api` (`bin/api_server.dart`) and `webhook`
(`bin/webhook_server.dart`) - each a single AOT-compiled binary on a slim
Debian runtime, running as a non-root user. CI publishes the `daemon` and
`api` images to GHCR for amd64 + arm64; the `webhook` image has no CI job
yet. See `docs/DEPLOYMENT.md` for the full explanation (multi-stage build,
config/secrets split, how it fits the CI/CD pipeline) and
`../docker-compose.yml` for running all three on a single always-on
machine. For a Kubernetes cluster instead (e.g. a Raspberry Pi cluster)
see `../k8s/README.md` - the daemon as a `CronJob`, not a long-running
container, and a real credentials-trust question worth reading before
deploying to a cluster you don't administer yourself.

## Running this yourself

Needs the Dart SDK (ships with Flutter, or install standalone -
<https://dart.dev/get-dart>). CI runs the same commands on every push.

```bash
dart pub get
dart test
dart analyze
```

## Wiring up a real eBay account

1. Register a developer app at <https://developer.ebay.com> and get a
   client ID/secret. Two separate registrations needed for
   `ebay_store_a` and `ebay_store_b` (`catalog/stores.json`) -
   or one app used for both, each with its own OAuth consent - either way,
   each account needs its own token pair, never shared.
2. Copy `secrets/ebay_credentials.example.json` to
   `secrets/<account_key>.json` (gitignored) and fill in the client
   ID/secret for that account. The daemon reads this file directly
   (`FileCredentialStore`); the app keeps its own credentials in OS
   secure storage (`SecureCredentialStore`).
3. Run the one-time consent flow. The app's Settings screen does this
   (`EbayLoopbackAuthFlow` - the system browser plus a local redirect
   listener), or call `EbayOAuthClient.buildConsentUrl()` and
   `exchangeAuthorizationCode()` directly. The refresh token it stores is
   good for ongoing automatic use; copying it into the daemon's secrets
   file is a manual step today (see `docs/DEPLOYMENT.md`).
4. Look up (or ask eBay support for) that account's Business Policy IDs
   (fulfillment/payment/return) and merchant location key from Seller Hub -
   required by `EbayAccountConfig`, not something this code can invent.

## Wiring up a real Walmart account

No browser or consent step. Copy `secrets/walmart_credentials.example.json`
to `secrets/walmart.json` (matching the account key in
`catalog/stores.json`) and fill in the client ID/secret from Walmart's
Developer Portal - the daemon mints an access token on first use. Walmart's
seller/API onboarding approval has to be complete before any endpoint works
(see `docs/API_RESEARCH.md`).
