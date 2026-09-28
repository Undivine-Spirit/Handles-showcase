# Multi-store inventory sync platform — project plan

## 1. Goal

Build an automated, cross-platform (Windows + Android) inventory and listing
management system that:

- Treats a GitHub repository as the single source of truth for the product catalog.
- Automatically syncs listings and inventory levels across multiple online
  marketplaces — starting with eBay, with Walmart Marketplace as a second
  active target (API researched in `API_RESEARCH.md`; requires completing
  Walmart's seller/API onboarding approval before it can be built against),
  plus additional stores TBD (see open questions). Amazon SP-API is
  researched and ready to add as a future expansion once there's an Amazon
  storefront to connect (see section 9's upgrade path and roadmap step 17).
- Automatically unlists or reduces quantity on connected stores when the
  source-of-truth catalog changes (e.g. an item sells out on one channel).
- Gives the user one front-end interface to view and manage everything at once,
  from either a Windows machine or an Android phone.
- Adapts its own resource usage (CPU, network, polling frequency) to the
  hardware it's running on, and to whether the device is plugged into power or
  running on battery.
- Includes an event log and hardware monitor view for visibility into what the
  system is doing and what resources it has available.
- Flags profitable Amazon opportunities — both new items worth sourcing and
  existing catalog items worth cross-listing there — without requiring Amazon
  API developer registration up front (see section 9).
- Reminds the user of their own outstanding duties (manual updates the system
  can't do for them) so nothing silently goes stale (see section 11).

## 2. Core principle: GitHub repo as source of truth

- The repo holds the canonical catalog state (one JSON or CSV record per SKU),
  plus a commit history that doubles as an audit trail.
- Every store adapter reads intended state from the repo and reconciles it
  against what's actually live on that marketplace.
- Every state-changing action (price change, quantity change, delist) is
  committed to the repo — either just before or immediately after it's
  confirmed on a store — so the repo always reflects reality, and `git log`
  shows who/what/when for every change.

**2026-09-02: the app stopped keeping its own clone.** The requirement:
the source of truth should be served from the backend, because local saves
plus server-side changes create conflicting copies. Until this date the app
had its own independent git clone (`CatalogSyncService`) alongside the
daemon's - two copies of the same repo that could genuinely drift, plus a
real bug it turned out to have: Android has no `git` binary on `PATH` by
default, so that clone almost certainly never actually worked there.

Fixed with `core/bin/api_server.dart` - a small HTTP API (`package:shelf`)
that shares the daemon's own mounted catalog checkout (same files, same
disk, no git round-trip between the two processes) and exposes it over
HTTP. The app is a plain HTTP client now (`CatalogApiClient`), no git
knowledge at all - which also means it works identically on every
platform, not just wherever `git` happens to be on PATH. The repo itself
is still the source of truth and the audit trail hasn't changed; there's
just one git checkout doing the writing server-side now instead of N.
See `docs/DEPLOYMENT.md`'s "catalog API" section for the deployment
picture, including that this needs a real TLS setup (reverse proxy or a
VPN) before the app reaches it from outside your own network - the
server speaks plain HTTP and doesn't terminate TLS itself.

## 3. System components

1. **Store adapters** — one per marketplace *type* (Amazon, eBay, + others
   later), all implementing a shared interface: `get_listing`,
   `create_listing`, `update_listing`, `delist`, `get_inventory`. A single
   adapter must support multiple configured **accounts**, each with its own
   credentials — confirmed necessary 2026-08-23, since two separate eBay
   stores (see `catalog/stores.json`) run on the same adapter. The catalog's `stores` map is
   keyed by account, not platform, for this reason.
2. **Reconciliation engine** — the brain. Periodically diffs the
   source-of-truth catalog against each store's live state and issues the
   necessary create/update/delist calls. Owns the "auto-unlist / auto-subtract
   inventory" logic.
3. **GitHub state layer** — reads and writes catalog snapshots, manages
   commits, exposes current catalog state to the front-end.
4. **Front-end client(s)** — Windows desktop app and Android app, both reading
   from the same GitHub-backed state so the user sees one unified view
   regardless of device.
5. **Resource & power-aware scheduler** — decides sync frequency and
   concurrency based on live hardware readings and power source. Every
   background component in this list (adapters, reconciliation, the
   profitability engine's future automation, reminder checks) runs through
   this scheduler rather than spinning up its own unmanaged timer — one place
   that decides how much of the machine's resources are available right now.
6. **Event log, hardware monitor & duty reminders** — structured logging of
   every sync action, plus a live view of CPU/RAM/network/battery status, plus
   native OS notifications for anything logged as needing the user's action
   (see section 11).
7. **Amazon profitability engine** — a shared calculator (see section 9) that
   flags sourcing, cross-listing, and competitive-pricing opportunities on
   Amazon, fed by manually-entered price data in v1 (no Amazon API key
   required) and by full SP-API automation later.
8. **Automated sourcing & listing engine** (see section 10) — bulk version
   of component 7: scans Amazon at scale, auto-generates and pushes
   listings via the same store-adapter interface every other component
   uses, monitors *supplier* stock (not the seller's own), and feeds the
   duty-reminder system when a sourced item needs fulfilling.

## 4. Unified catalog schema (draft — refine per store during implementation)

- `sku` — canonical internal ID
- `title`, `description`, `price`, `quantity`
- `images[]`
- `category` / `condition`
- `stores` — map of `{ store_name: { external_listing_id, external_offer_id
  (eBay-specific), last_synced_at, sync_status } }`

## 5. Reconciliation logic (the auto-unlist / auto-subtract engine)

- Source-of-truth quantity is authoritative. When it drops to 0, the engine
  issues a delist (or "out of stock" flag, whichever a given store supports)
  to every connected store.
- When quantity decreases but stays above 0, issue quantity-update calls to
  every connected store.
- After every write, perform a write-then-verify read-back before marking
  that store's `sync_status` as confirmed in the repo.
- **Conflict rule (the hardest part of this system):** if a store reports a
  quantity lower than the source of truth — e.g. someone bought the item
  directly on that marketplace — that sale needs to decrement the
  source-of-truth quantity too, which then needs to cascade back out to every
  *other* connected store. This is a two-way merge, not a one-way push. Give
  this dedicated design time before writing the reconciliation engine; get
  the merge policy and race-condition handling (two stores selling the last
  unit at the same time) right on paper first.

**2026-09-02: built, as reconciliation engine v2.** The design pass this
section asked for, then the implementation
(`core/lib/src/reconciliation/reconciliation_engine.dart`):

- Each store's `StoreListingState` now carries `last_confirmed_quantity` -
  what that store showed the last time a write was verified. A fresh read
  below that baseline is a real sale on that channel; a store with no
  baseline yet (never been through a v2 write) is never treated as a
  mystery sale - there's nothing to compare against.
- **Sum the drops across every store**, not just the first one found - two
  channels can each sell real units in the same pass (eBay sells 2, Walmart
  sells 1 - that's 3 real units gone, not 1). A "take the lowest number"
  policy would silently undercount whenever more than one channel sells in
  the same pass.
- New source-of-truth quantity = old quantity minus total sold, floored at
  0, then cascaded to every connected store (the store the sale happened on
  usually already matches, so that side is typically a no-op).
- **Oversold - the exact race condition this section named (two stores each
  selling what was really the last unit) - is never auto-resolved.**
  Quantity floors at 0, every store gets delisted, but a distinct
  `ReconciliationOutcome.oversold` fires (`EventSeverity.actionNeeded` in
  the daemon) instead of silently picking a "winner": a human has to
  cancel/refund one order, which this engine has no way to do itself.
  Confirmed decision, not an oversight.
- Quantity's real source of truth is deliberately still "whichever store
  actually sold the item," read live each pass, with the catalog record as
  the cascade target and manual override (Console → tap an item → edit) as
  the exception path - not a locally-cached number the app or daemon can
  drift on independently. This is also why the app keeps its own
  git-backed catalog sync (section 2) rather than only ever reading through
  the daemon: it needs to work fully away from the server, not just as a
  thin client of it.

## 6. Cross-platform strategy (Windows + Android)

Options to evaluate for a single shared front-end codebase:

- **Flutter** — single Dart codebase, strong Windows + Android support, mature
  battery/power-state plugins on both platforms, relatively light on
  resources.
- **.NET MAUI** — good Windows-native feel, decent Android support; a natural
  fit if the backend ends up in C#.
- **Python (Kivy/BeeWare) + a backend service** — keeps the reconciliation
  engine and UI in one language, but weaker mobile polish and packaging story.
- **Electron (Windows) + Capacitor (Android)** — shared web tech, but a
  heavier resource footprint, which cuts against the resource-awareness goal.

**Recommendation for Claude Code to evaluate first:** Flutter, given the
explicit hardware-resource constraint in this project — it's lighter than
Electron and has solid first-party support for reading power/battery state on
both target platforms.

## 7. Resource-awareness & power-state detection

**Where this actually lives, revised 2026-08-27:** written before section
10's decision to run reconciliation as a self-hosted daemon (Docker/
Kubernetes) rather than inside the desktop app itself. A Raspberry Pi
cluster is where resource constraints genuinely bite - a Windows desktop
running the UI is not. The daemon's own lightweight resource check
(`core/bin/reconcile_daemon.dart` - `/proc`-based, since it always runs in
a Linux container regardless of host) is the primary implementation now;
the Windows/Android sections below stay accurate for the *app*, but are
lower priority than originally ordered, since the app's role shifted
toward UI/dashboard rather than also running its own background sync loop.

- **Windows:** power state via the Win32 `GetSystemPowerStatus` call, or
  `System.Windows.Forms.SystemInformation.PowerStatus` in .NET, or
  `psutil.sensors_battery()` if a Python component is involved. CPU/RAM via
  WMI or `psutil`.
- **Android:** charging state via `BatteryManager` (`ACTION_BATTERY_CHANGED`
  broadcast, `isCharging` / `EXTRA_STATUS`). CPU/RAM via `ActivityManager`.
- **Adaptive behavior:** on battery → lower sync frequency and concurrency,
  defer non-critical syncs. Plugged in / high-spec hardware → sync more
  aggressively. Benchmark available CPU cores and RAM at startup to set a
  baseline concurrency cap, then adjust live as power state changes.
- **The floor is efficient, not the ceiling:** the scheduler should default
  to a lean footprint, but on a plugged-in, high-spec machine it should scale
  up and actually use the headroom available — reconcile more stores
  concurrently, refresh more often — rather than staying artificially
  throttled once the constraint that justified throttling is gone.

## 8. Event log & hardware monitor

- Structured event log (SQLite table or JSON lines) recording every sync
  attempt, API call, error, and hardware-state change, with timestamps.
- Front-end view modeled loosely on Windows Event Viewer: a filterable list of
  events (info / warning / error) alongside a live hardware panel (CPU %,
  RAM %, network activity, battery/power status).

**2026-08-29: built, on both ends.** `EventLogStore` (JSON lines, `core/lib/src/event_log.dart`)
is written by the daemon into `catalog/.events.jsonl` on every reconciliation
action, and now read by the app too — `CatalogSyncService` (`app/lib/services/`)
gives the app its own git checkout of the same repo (Settings → Catalog
Repository), so `ActivityLogPanel` shows the real log instead of sample rows,
and it's what `ReminderService.notifyForNewEvents` scans after each sync. CPU
%/RAM %/network stay unimplemented — `HardwarePanel` shows real battery/power
state via `battery_plus` and says so explicitly rather than showing a faked
number for the rest.

## 9. Amazon profitability engine

One shared calculator, fed from three angles requested together
(2026-08-23) because they all reduce to the same math:

1. **Sourcing/arbitrage** — is an item on Amazon worth buying to resell on
   our own channels?
2. **Cross-list check** — is an existing catalog SKU worth *also* listing on
   Amazon?
3. **Competitive pricing** — what is Amazon charging for the same/similar
   item right now, so our own price stays sane?

**No auto-buy — confirmed decision, 2026-08-23.** Amazon has no API for
placing a normal retail purchase at all (not a registration gap — it doesn't
exist, by Amazon's own design), and the workarounds that exist (Zinc and
similar) automate around Amazon's own bot defenses, the same
terms-of-service risk already ruled out for scraping Mercari/Poshmark/Vinted
— now with a payment method attached. Full detail in `API_RESEARCH.md`'s
"Amazon pricing data & purchasing" section. Handles' job stops at surfacing
a **direct link to the Amazon product page** for a candidate that clears the
profitability bar — the seller completes the purchase themselves, in their
own account, whenever they choose to.

**Data source rollout — three stages, each one a real upgrade, not a
placeholder:**

1. **Now: manual entry.** A person spot-checks items using Keepa's free browser
   extension (no account, no API key) and type the ASIN, category, and
   observed price into Handles. Costs nothing, ships immediately, proves out
   the calculator and the link-out flow before any money is spent on data
   access.
2. **Once subscribed: Keepa's paid API**, for running this unattended across
   a large catalog. This is a real subscription cost (from €19/mo, see the
   tier table in `API_RESEARCH.md`) — **not activated yet (2026-08-23).**
   The cost is very reducible
   through design, not a pricing negotiation: most of a resale/vintage
   catalog has no matching current Amazon listing at all, so (a) filter to
   only the plausibly-matchable subset before spending any token, (b) use
   Product Finder's bulk discovery mode (10 tokens + 1/100 results) instead
   of paying ~1 token per individual lookup for broad scanning, and (c)
   refresh weekly or on-change, not continuously. Done that way, the
   cheapest tier (€19/mo, 1 token/min) likely covers it — the naive "check
   every SKU on a tight schedule" approach is exactly what this design
   avoids needing, and what would drive the cost up sharply.
3. **Once selling on Amazon:** the seller's own SP-API registration
   (roadmap step 17) unlocks the Product Pricing/Catalog Items API,
   replacing Keepa entirely for items already in scope of that seller
   account. The calculator itself doesn't change across any of these three
   stages — only where the price number comes from.

**The calculator itself:**

- Inputs: observed Amazon price, category (fee % varies by category),
  fulfillment assumption (FBA vs. FBM — fee structures differ a lot), and
  either a cost basis (sourcing case) or the item's current price on our own
  channels (cross-list/competitive case).
- Fee model (2026 rates, frozen since Jan 2024, see `API_RESEARCH.md`):
  referral fee 8–20% by category (most categories 15%), $0.30 minimum
  referral fee per item, FBA fulfillment roughly $3–4 for a small/light
  standard item plus a 3.5% fuel & logistics surcharge, and a newer
  low-inventory fee ($0.89–1.11/unit) if that applies.
- Output: estimated net proceeds, margin vs. cost/comp, a
  worth-it / marginal / not-worth-it flag, and a direct Amazon product link
  — not just a number, since a person should be able to scan a list and
  click straight through to buy.

Any future automated batch lookups run through the resource & power-aware
scheduler (section 7/component 5) like everything else background — no
separate unmanaged polling loop.

## 10. Automated sourcing & listing engine

Bulk version of section 9's calculator, added 2026-08-27: a sourcing
engine that scans Amazon for candidates, auto-generates and pushes
listings, monitors *supplier* stock/price and delists when the supplier
runs out, and leaves fulfillment to a human. A commercial tool researched
for comparison does this for eBay only, with **no Walmart support at
all** - which is Handles' concrete opening, not just parity-chasing.
Built natively on the shared store-adapter interface, the same engine
covers **Walmart** and eBay alike, so one tool covers everything instead
of two.

**Key modeling decision: a sourced listing is not a `CatalogItem`.**
`CatalogItem` (section 4) represents inventory the seller physically
owns - its `quantity` is a source of truth the seller controls and pushes
OUT to stores, and "out of stock" means *their own* stock hit zero. A
sourced/arbitrage listing is the opposite shape: no owned quantity, price
is *derived* (source cost + markup, not set by hand), and "out of
stock" means the *supplier* (Amazon) ran out - a completely different
event with a different consequence (delist and stop offering it, not
"restock when convenient"). Forcing both into one schema would leak one
model's assumptions into the other (e.g. `CatalogItem.isSoldOut` would
lie about which side actually went to zero). Kept as a separate
`SourcedListing` type instead, sharing the `StoreAdapter` interface
(section 3, component 1) so listing to Walmart or eBay is the exact same
adapter code either model uses - only the "where does the price/quantity
number come from" logic differs.

**Four components, in build order (see roadmap steps 7-8):**

1. **`SourcedListing` data model** - source product reference (ASIN),
   source price, markup rule, target stores, current supplier stock
   status, and the live listing IDs it maps to per store once pushed.
2. **Supplier stock/price monitor** - re-checks each sourced item's
   Amazon status on a schedule (same Keepa foundation as section 9, same
   cost-reduction discipline - don't re-check everything constantly).
   When the supplier goes out of stock, delist everywhere that item is
   currently live, the same auto-unlist principle section 5 already uses
   for owned inventory, applied to the opposite trigger.
3. **Listing generator** - given a sourced item that clears the
   profitability bar, generates title/description/price
   (cost + fees + markup, reusing section 9's fee model) and calls the
   *same* `StoreAdapter.createListing` every other component uses -
   Walmart support falls out of this for free once the Walmart adapter
   (roadmap step 3) exists, no separate mechanism needed.
4. **Bulk sourcing** - Keepa's Product Finder (section 9's cheap
   discovery mode, already researched) run at scale instead of one item
   at a time, feeding component 3 a batch of scored candidates.

**2026-08-29: brand-authorization/resale-risk checking - researched, not yet
built.** An "auto brand checker" was requested so resold items don't
carry a legal issue - four independent research passes (Keepa's own docs,
Amazon's SP-API, the third-party reseller-tool landscape, eBay VeRO) came
back with a clear, if unglamorous, answer:

- **Keepa does not do this at all.** Its Product Object has `brand`/
  `manufacturer` as plain text name fields, nothing else - no gating, IP-risk,
  or VeRO field anywhere in its API, docs, or feature list. Confirmed by
  checking the schema and endpoint list directly, not inferred.
- **Amazon has a real, automatable API for this** - the SP-API Listings
  Restrictions API (`getListingsRestrictions`) - but it answers "can I list
  this on Amazon under my own seller account," which isn't Handles' actual
  question here (Handles buys on Amazon, doesn't sell there). It says nothing
  about eBay/Walmart risk.
- **eBay has no equivalent.** VeRO is purely reactive for sellers - no API,
  no complete list (eBay's own published VeRO profile page admits it's
  incomplete), no way to check before listing. You only find out after a
  rights owner's takedown.
- **Real third-party tools exist** (AZInsight/AZAlert, Seller Assistant's
  IP-Alert on Amazon; PriceYak/AutoDS/SuperDS VeRO checkers on eBay;
  LogoVerify for cross-platform litigation history) - all of them work by
  matching a brand against a database of *already-recorded* complaints/
  lawsuits, none of them predict risk, several explicitly disclaim that
  history isn't a guarantee. Nothing covers Walmart at all - a genuine
  research gap, not a "no."
- **Nothing, anywhere, does predictive brand-risk scoring.** Not worth
  promising.

**Buildable v1, when this gets picked up:** an in-house "known-risk flag" on
a sourced item - cross-reference the Amazon product's `brand` field against
(a) eBay's public VeRO Participant Profiles list and (b) a manually curated
list of well-known repeat enforcers/high-complaint categories (luxury/
designer goods, branded apparel/sneakers, licensed toys, cosmetics/
supplements, watches/jewelry, branded electronics). This is a blocklist
match, not a clearance check - a miss means "not in our incomplete list,"
never "safe." Track Handles' own removal/strike history per brand over
time too - a better predictor for a given catalog than any external
list. Also worth adopting as a practical habit in the meantime: Seller Assistant's IP-Alert (free) while sourcing, PriceYak's or
SuperDS's free VeRO checker before pushing to eBay - no need to rebuild
what already exists for free.

**Fulfillment stays exactly as strict as section 9 already decided: no
auto-buy.** When a sourced listing sells, that's a duty-reminder trigger
(section 11) - "SKU X sold on Walmart, source it from Amazon now" - not
an automated purchase. Same reasoning as before: Amazon has no purchase
API, and building around that gap means automating past Amazon's own bot
defenses, which stays off the table regardless of which app is asking.

**Worth knowing, not a blocker:** listing an item before owning it and
sourcing it from another retailer after a sale is what eBay's own policy
calls "drop shipping from another retailer" - eBay's actual line is
narrower than "don't get caught": it turns on whether the supplier
(Amazon) ever ships directly to the eBay buyer, versus the seller
receiving it and shipping it themselves. Real, publicly-sold software
exists for this exact workflow, so it's clearly a tolerated, common
practice - flagged here because Handles would be doing this directly,
not because it's a new kind of risk.

## 11. Reminders & duty notifications

Several parts of this system depend on a human actually doing something —
without a nudge, those things silently go stale. Rather than a parallel
system, this extends the event log (section 8): a reminder is just an event
tagged with an "action needed" category that *also* fires a native OS
notification instead of only sitting in a log view.

**Delivery:** one `ReminderService` interface (`app/lib/services/reminder_service.dart`)
backed by two packages, not one — checked against the actual resolved source
rather than assumed: `flutter_local_notifications` (18.0.1) only ships
Android/iOS/macOS/Linux channels, no Windows one, so Windows goes through
`local_notifier` instead (a thin wrapper over the real Windows toast/shortcut
APIs). Callers only ever see `notify()`/`notifyForEvent()`; which backend runs
is `ReminderService`'s problem. No server or push service needed either way;
this runs locally on the user's own devices.

**Draft trigger list (refine once it's seen in practice — cadence
and thresholds should be user-configurable, not hardcoded):**

- A conflict item (section 5) sits unresolved past a configurable threshold
  (default 24h).
- A monitor-only platform (Mercari/Poshmark/Vinted, section 14) has a stale
  `sync_status` because the source-of-truth quantity changed and nobody's
  updated that store yet.
- The Walmart account in `catalog/stores.json` is still missing a
  `store_url` / pending approval — periodic nudge until it's filled in.
- Reconciliation hasn't completed successfully in longer than expected.
- Amazon profitability engine (section 9): an optional recurring "go check
  Keepa" reminder — off by default, since this is the one duty that's
  opt-in rather than system-critical.
- Sourcing & listing engine (section 10): a sourced listing sold and needs
  fulfilling - "SKU X sold on <store>, buy it on Amazon now." Not
  opt-in like the one above - this one has a real time-sensitivity
  (a buyer is waiting), so it fires every time, not on a schedule.

**2026-08-29: the actual speed of this loop matters more than any item on the
list above.** For Mercari/Poshmark/Vinted (section 14 - no write API, ever),
a fast notification isn't a nice-to-have on top of automation, it *is* the
automation: there's no auto-delist to fall back on, so how quickly the seller
finds out **is** the whole value this app provides for those three stores.
Before this date the app only synced the catalog repo (and therefore only
noticed new events) on cold start or a manual "Sync Now" tap - an event could
sit unseen indefinitely if the app just stayed open. Fixed with a real
polling loop: `HandlesSettings.autoSyncIntervalMinutes` (Settings → Catalog
Repository, default 3, `0` disables it) drives a `Timer.periodic` in
`AppState` that pulls the repo and fires reminders for anything new,
independent of the daemon's own `RECONCILE_INTERVAL_MINUTES` (default 15) -
polling faster than the daemon produces events just means most polls find
nothing, which costs nothing that matters. Honest limitation, not hidden:
this keeps firing on Windows as long as the app is running, but on Android
only while it's in the foreground - the OS suspends a plain Dart timer once
fully backgrounded. True always-on Android push would mean the daemon
calling a real push service (e.g. FCM) directly instead of the app polling -
a real backend addition, not built.

## 12. Phased roadmap (easiest → hardest)

1. Unified catalog schema + GitHub repo scaffolding (data structure, commit
   conventions).
2. eBay adapter (the first active, fully-automated store) +
   write-then-verify loop.
3. Walmart Marketplace adapter — second active store. Requires completing
   Walmart's seller/API onboarding approval first (see `API_RESEARCH.md`);
   start that approval process early since it's a lead-time item, not
   something that blocks on code.
4. **Amazon profitability engine v1** (section 9) — Keepa-assisted manual
   entry. Independent of the store adapters above; can be built in parallel
   any time after step 1.
5. Reconciliation engine v1 — one-way push (source of truth → stores),
   including the auto-unlist-on-zero logic, validated against eBay and
   Walmart.
6. Reconciliation engine v2 — two-way merge / conflict resolution (see
   section 5). Plan this on paper before coding it.
7. **Automated sourcing & listing engine v1** (section 10) — the
   `SourcedListing` data model, plus a supplier stock/price monitor. Needs
   step 4's Keepa foundation and step 3's Walmart adapter (or eBay's, for
   an earlier partial version) to actually push anything.
8. Automated sourcing & listing engine v2 (section 10) — bulk Product
   Finder sourcing + auto-generated listings at scale, once v1's data
   model and monitor are proven on a handful of items by hand.
9. Windows desktop front-end — read-only dashboard first, then read/write
   controls.
10. Resource-aware scheduler on Windows (power state + CPU/RAM benchmarking).
11. Event log + hardware monitor view (Windows first).
12. **Duty reminders** (section 11) — layered on the event log; needs step
    11 done first. Also where the sourcing engine's fulfillment prompts
    ("SKU X sold, source it now") land, once step 7 exists.
13. Monitor-only adapters for Mercari, Poshmark, and Vinted — `get_listing`
    for visibility plus a "needs manual action" flag, per the constraint in
    section 14.
14. Android front-end port, sharing business logic where the chosen
    framework allows.
15. Resource-aware scheduler on Android (battery/charging detection).
16. Hardening — credential security review, rate-limit backoff tuning,
    packaging and distribution for both platforms.
17. **Future expansion:** Amazon SP-API adapter, once there's an Amazon
    storefront to connect. Research is already complete in `API_RESEARCH.md` —
    this becomes a "write one more adapter" task against the existing
    interface, not a redesign, and it's also what upgrades the profitability
    engine (step 4) from manual entry to fully automated.

## 13. Open questions to resolve before/during implementation

- Which stores beyond Amazon, eBay, and Walmart? (Shopify, Etsy, Facebook
  Marketplace, Mercari, Poshmark, Vinted already researched — see section 14
  for why the last three are monitor-only. Others need their own entry in
  `API_RESEARCH.md` before an adapter is built.)
- ~~Final choice of cross-platform framework~~ **Resolved: Flutter** (see
  section 6) — `app/` is built on it.
- ~~Where does the reconciliation engine actually run~~ **Resolved,
  2026-08-23: self-hosted, as an always-on Docker container** (self-owned
  hardware, not a paid cloud service) — see `docs/DEPLOYMENT.md` and
  `core/bin/reconcile_daemon.dart`. Not a per-platform instance; one daemon
  reconciles the whole catalog regardless of which device (if any) is
  otherwise open.
- ~~Credential storage strategy across two OS environments~~ **Resolved for
  the desktop/mobile app: `SecureCredentialStore`** (Windows DPAPI / Android
  Keystore via `flutter_secure_storage`, see `app/lib/services/`). The
  headless daemon above uses a *different* strategy by necessity (mounted
  secret files, no OS keychain to call) — see `docs/DEPLOYMENT.md`'s
  "config and secrets" section for why that's not a contradiction.

## 14. Platform risk: not every requested store can be automated the same way

Research turned up an important constraint: Mercari, Poshmark, and Vinted do
not offer official public APIs for seller inventory/listing management (full
detail in `API_RESEARCH.md`). Third-party tools exist for all three, but they
rely on reverse-engineered private endpoints or session emulation rather than
a sanctioned integration — carrying real risk of account suspension and
silent breakage, and likely violating each platform's terms of service.

Until an official integration path is confirmed for these three, the
reconciliation engine should treat them as **manual-update or
read-only-monitoring channels**, not automated read/write targets like Amazon
and eBay. The architecture in section 3 still works for this — a "store
adapter" for one of these platforms can simply implement `get_listing` for
monitoring and surface a "needs manual action" flag instead of implementing
`update_listing` / `delist`, rather than requiring a structural redesign
later if an official API does become available.

**2026-08-29: `get_listing`-via-scraping deliberately not built.** A real
`get_listing` for these three would mean the same reverse-engineered private
endpoints / session emulation this section already flags as ToS/suspension
risk — the same category already ruled out for Amazon in section 9. Built
instead: the catalog table lets a user paste each listing's real URL once
(`app/lib/widgets/catalog_table.dart`'s monitor-only pills), then opens it in
one tap via `url_launcher` for a manual check/delist. No scraping, no
`get_listing` adapter method for these platforms - "needs manual action" is
the permanent state here, not a placeholder for one.

## 15. Suggested Claude Code model usage

Use Claude Sonnet 5 as the default for implementation — it's fast,
cost-effective, and well suited to the bulk of well-specified coding work
here (adapters, UI screens, logging). Switch to Claude Opus 4.8 specifically
for the architecture-heavy decisions: the two-way conflict-resolution logic
in section 5, and the cross-platform framework decision in section 6. Claude
Code supports switching models mid-session with `/model`.
