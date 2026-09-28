# Deploying the reconciliation daemon (and what it's teaching)

This doc covers two things at once: how to actually self-host the
always-on reconciliation service, and the reasoning behind each piece -
written with an eye toward the concepts a cloud/DevOps role would expect
you to know, not just "run this command." Covers the `docker-compose`
path (a single always-on machine). Deploying to a **Kubernetes cluster**
instead (e.g. a friend's Raspberry Pi cluster) - a `CronJob` rather than a
long-running container, and a real trust question worth thinking about
before real credentials land on someone else's cluster - is
[`k8s/README.md`](../k8s/README.md).

## The shape of the whole thing

Two separate deployables came out of this project, and it's worth being
clear they're different:

- **`app/`** - the Flutter UI. Runs on a human's Windows machine or
  Android phone, when they open it. Distributed as a built .exe/.apk
  (see the CI workflow's `build-windows`/`build-android` jobs).
- **`core/`'s `bin/reconcile_daemon.dart`** - a headless, always-on
  process. Runs continuously on whatever hardware you point it at,
  independent of anyone's app being open. This is what actually needs
  Docker - a GUI app doesn't get "containerized" for end users the way a
  server process does, which is why the app itself isn't part of this
  deployment story.
- **`core/`'s `bin/api_server.dart`** - added 2026-09-02, runs alongside
  the daemon on the same host. The app talks to this over HTTP instead of
  keeping its own independent git clone the way it briefly did - see
  "The catalog API" section below for why.

All three depend on the same `core/` package (catalog model, adapters,
reconciliation engine) - one piece of business logic, three different
runtimes wrapping it.

## The Dockerfile: multi-stage builds

`core/Dockerfile` has two `FROM` lines - that's what makes it
"multi-stage." Stage 1 (`dart:3.13`) has the full Dart SDK and compiles
the daemon into a single native executable. Stage 2
(`debian:bookworm-slim`) starts completely fresh and copies in *only*
that compiled binary - not the SDK, not the source, not the pub cache.

Why this matters beyond "smaller image": the final image can't leak
source code or build tooling if it's ever compromised, and it starts
faster because there's less to pull. This is the standard pattern for any
compiled language in Docker (Go, Rust, Java all do the same thing) - if
you're asked about Docker image size in an interview, multi-stage builds
are very often the answer.

Also worth noticing: `COPY pubspec.yaml pubspec.lock ./` happens *before*
`COPY . .`, with `dart pub get` run in between. Docker caches each
instruction as its own layer; if the pubspec files haven't changed, that
`pub get` layer gets reused even when application code has, so an
ordinary code change doesn't force every dependency to redownload. Layer
ordering for cache efficiency is a real, commonly-asked Docker skill.

## The catalog API and why the app needs HTTPS to reach it

Until 2026-09-02, the app kept its own independent git clone of the
catalog repo (`CatalogSyncService`, since removed) - the same idea as the
daemon's clone, just running on whatever device the app happened to be
on. Two problems with that, one theoretical and one that turned out to
already be real:

- The requirement: the source of truth should be served from the
  backend, because local saves plus server-side changes create
  conflicting copies. Two independent clones (app's device, daemon's
  host) really can drift - not from git merge conflicts exactly, but from each side
  believing its own last-synced state is current.
- **Android has no `git` binary in `PATH` by default.** The old
  `CatalogSyncService` shelled out to `git` the same way `GitSync` does
  server-side - which almost certainly never worked on Android at all,
  only on Windows (and only if `git` happened to be installed there).
  This wasn't caught earlier because Android builds in this project
  haven't been run against a real device with this code path exercised.

The fix: `core/bin/api_server.dart`, a small HTTP API (`package:shelf`)
that owns the catalog data server-side, shares the exact same mounted
`CATALOG_CHECKOUT_PATH` as `reconcile-daemon` (see `docker-compose.yml`)
- not a second clone, the same files on the same disk, so the two
processes see each other's writes without any git round-trip between
them. The app is now a plain HTTP client (`app/lib/services/catalog_api_client.dart`)
with no git knowledge at all, which also means it works identically on
every platform Flutter targets, Android included.

**This needs a real TLS setup before you point the app at it from outside
your own network.** `api_server.dart` only checks one shared bearer token
(`API_AUTH_TOKEN`) - sent as `Authorization: Bearer <token>` on every
request - and does **not** terminate TLS itself. Over plain HTTP, that
token (and every catalog record) is readable to anything between the app
and the server. Put a reverse proxy with a real certificate in front of
it - a few common, low-effort options for a home server:

- **Caddy** - a single binary that gets you automatic Let's Encrypt certs
  with a few lines of config, probably the least ceremony of the three.
- **nginx** (or Traefik) - more moving parts, more control, the more
  "industry standard" answer if that's specifically what you want
  practice with.
- **Tailscale/WireGuard** - skip public TLS certs entirely by putting the
  server on a private VPN the app also joins; simplest if "mobility"
  mainly means "my own devices, from anywhere," not "an API anyone on the
  internet could theoretically reach."

None of these are set up by this repo - which one fits depends on
whether you want the server reachable from any network (needs real TLS +
DNS) or just from your own devices (a VPN is simpler and arguably safer).

## Config and secrets: two different problems, two different answers

The Dockerfile sets defaults like `ENV RECONCILE_INTERVAL_MINUTES=15` -
ordinary configuration, not secret, so plain environment variables are
fine (this is "12-factor app" style config: behavior changes via env
vars at run time, never by editing and rebuilding the image).

Actual secrets (eBay client secret, OAuth refresh tokens) are a different
problem and get a different answer: they live in files under
`core/secrets/`, mounted into the container as a **volume** at runtime
(see `docker-compose.yml`), never `COPY`'d into the image. An image layer
is effectively permanent and can be pulled/inspected by anyone with
registry access - baking a secret into one means it's in the image
forever, even if you "remove" it in a later commit. Mounting at runtime
means the secret only ever exists on the host machine and in the running
container's memory.

## The CI/CD pipeline (`.github/workflows/ci.yml`)

Read top to bottom, it's a fairly standard pipeline shape:

1. **`core`/`app` jobs** - fast feedback on every push: static analysis
   (`analyze`) and unit/widget tests (`test`). This is the "CI" half -
   catch regressions before anything gets built.
2. **`build-windows`/`build-android`** - real native builds, gated to
   only run after tests pass (`needs: app`) and only on `main` or a
   manual trigger (not every WIP push - these are slower). Uses GitHub's
   *hosted* runners, which already have Visual Studio and the Android SDK
   installed - notice this sidesteps needing either toolchain on a local
   dev machine at all.
3. **`build-docker-image`** / **`build-catalog-api-image`** - build the
   daemon's and the catalog API's images (`core/Dockerfile`'s `daemon`
   and `api` stages - each job passes an explicit `target:`, since
   without one buildx just builds whichever stage happens to be last in
   the file) and push both to **GHCR** (GitHub Container Registry),
   authenticating with the workflow's own auto-generated `GITHUB_TOKEN`
   rather than a secret you have to create and rotate yourself. Each
   tagged both `latest` and with the commit SHA, so you can always pin to
   an exact build if `latest` ever causes a problem.

This is "CI/CD" in the sense that actually fits a self-hosted deployment:
continuous *integration* (test automatically) and continuous *delivery*
of a build artifact (a fresh image is always published), stopping short
of continuous *deployment* onto your own hardware - that last mile (a
webhook or poller reaching into your home network to auto-update a
running container) is a deliberately separate, harder problem, not
implemented here. For now, updating means pulling the new image yourself.

## Actually running it

Prerequisites: Docker Desktop (or Docker Engine) installed on the
always-on machine, and a real `git clone` of this repo there with push
access configured (a personal access token or SSH key with write access -
the daemon's `GitSync` shells out to the same `git` a human would use).

1. `cp .env.example .env` and fill it in - including a real
   `API_AUTH_TOKEN` (`openssl rand -hex 32`), the catalog API refuses to
   start without one.
2. For each `automation: full` account in `catalog/stores.json` you want
   automated, create `core/secrets/<account_key>.json` (copy
   `core/secrets/ebay_credentials.example.json` as a starting point) with
   the eBay app credentials and Business Policy IDs filled in.
3. Run the one-time OAuth consent flow for that account - today, that
   means using the desktop app's Settings screen pointed at the same
   secrets location, since that's where `EbayLoopbackAuthFlow` already
   lives. Copying the resulting token into the daemon's secrets file
   (rather than sharing one secure-storage backend across an app and a
   headless container, which don't have a common OS keychain to share
   anyway) is a real manual step today, not automated yet.
4. `docker compose up -d --build` from the repo root - brings up both
   `reconcile-daemon` and `catalog-api`.
5. `docker compose logs -f` to watch either - the daemon logs every
   reconciliation pass, including *why* it skipped an account (missing
   secrets, missing policy IDs, no adapter for that platform yet), not
   just silence; the API logs every request via shelf's `logRequests()`.
6. In the app's Settings → Catalog Server, point it at the API - either
   `http://<host>:8080` on your own network for now, or the HTTPS URL
   your reverse proxy fronts it with once that's set up (see above) - and
   the same `API_AUTH_TOKEN` from `.env`.

## Real-time updates: the webhook receiver (`core/bin/webhook_server.dart`)

Added 2026-09-25, alongside the self-hosted deployment above: a third
service, `webhook-receiver` (`core/Dockerfile`'s `webhook` stage), that
turns a real marketplace event into an *immediate* reconciliation pass
instead of waiting out `RECONCILE_INTERVAL_MINUTES`.

**Why eBay isn't really part of this:** eBay's Notification API does list
order-related topics, but multiple 2024-2025 eBay Community/Developer Forum
threads confirm they don't reliably fire for ordinary third-party sellers
(subscribing and receiving nothing, unresolved by eBay support). The *only*
eBay notification confirmed to work is the mandatory **Marketplace Account
Deletion** (GDPR) topic - a compliance requirement, not order data. This
repo implements that topic's challenge-response handshake
(`EbayNotificationVerifier.computeChallengeResponse`) correctly, but
**does not cryptographically verify the per-notification `X-EBAY-SIGNATURE`**
- that's ECDSA/P-256, which `package:crypto` doesn't do, and this
environment has no live eBay sandbox credentials to test a from-scratch EC
implementation against. A deletion request is logged for manual review, not
auto-processed. eBay orders/sales still come from `EbayAdapter`'s normal
poll, unchanged.

**Why Walmart is the real payoff:** Walmart's `PO_CREATED` webhook
(resource `ORDER`) is genuine and documented, with an HMAC-SHA256 auth
scheme this repo verifies for real (`WalmartWebhookVerifier`). A valid
`PO_CREATED` call writes a trigger file
(`$CATALOG_DIR/.trigger-now`) that `reconcile_daemon.dart`'s loop polls
every `TRIGGER_CHECK_INTERVAL_SECONDS` (default 5) instead of sleeping the
full interval in one block - the daemon and the webhook receiver are
separate containers, so a shared file in the volume both already mount is
the bridge, not a new network/auth path between internal services.

**Why this is the one public-facing exception to "stay on the tailnet":**
eBay/Walmart's own servers call this endpoint - they can't join a private
Tailscale network. Expose only this service, via
**`tailscale funnel --bg 8443 / http://127.0.0.1:8081`** - port **8443**, not
443. Funnel is enabled per-port, not per-path, and `tailscale serve` already
owns 443 for the catalog API (see section above); funneling 443 would take
over or expose that same listener, undoing the whole "catalog API stays
private" design. Confirm with `tailscale serve status` afterward - it
should show 443 as `tailnet only` and 8443 as the Funnel/public one, nothing
else. Walmart requires a response within 3 seconds - the handler does the
minimal synchronous work (verify HMAC, write the trigger file) and nothing
else, so Tailscale Funnel's extra relay hop doesn't risk that timeout.

One more thing to close out before actually running the Funnel command:
eBay's account-deletion route logs a notification for manual review rather
than acting on it automatically (see `EbayNotificationVerifier`'s doc
comment) - it never calls eBay's API or triggers a reconciliation pass, so a
forged/repeated call can't burn API quota or touch catalog data the way it
could on the Walmart route. It can still flood logs, though (bounded by the
services' `json-file` `max-size`/`max-file` logging options, but still worth
avoiding) - `webhook_server.dart` applies a simple global rate limit
(`_RateLimiter`, 30 req/min across both routes) to the whole server before
Funnel goes live, as defense-in-depth for the one genuinely public part of
this deployment.

Setup once the Funnel URL is live: run Walmart's Test Notification API
against it, then create the `PO_CREATED`/`ORDER`/`V1` subscription with
`authMethod: HMAC`; for eBay, call `createDestination` against the account-
deletion route and complete the handshake, then subscribe to
`MARKETPLACE_ACCOUNT_DELETION` only.

## What's genuinely not solved yet

- **TLS termination for the catalog API.** Covered above - `api_server.dart`
  speaks plain HTTP and expects a reverse proxy (or a VPN) in front of it
  for anything beyond your own LAN. Not something this repo can set up
  for you; it depends on your own domain/network situation.
- **Auto-deploy on update.** Pulling `ghcr.io/.../handles-reconcile-daemon:latest`
  and restarting is a manual step right now. A common next step here
  would be something like Watchtower (a container that watches a registry
  and restarts services when a new image lands) - deliberately not added
  yet, since it's a real decision (how often to check, whether to auto-
  restart unattended) rather than a default to bolt on.
- **Health checks / monitoring.** The container logs to stdout
  (`docker compose logs`), but nothing alerts you if it crashes or stalls.
  Fine for now; worth revisiting once this is handling real accounts.
- **Multi-account credential sharing between app and daemon.** Covered
  above - today it's a manual copy, not a shared secure store.
