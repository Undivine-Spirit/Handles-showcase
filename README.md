# Handles

> **Showcase copy** of a private repository, current as of 27 September 2026. Store names and links are placeholders, commit history isn't included, and CI here runs only when started by hand.

List the same stock on several marketplaces and you're keeping several counts that drift apart with every sale. Handles keeps one.

It's a multi-store inventory system: a Flutter app for Windows and Android, a sync engine that runs headless, and a small backend you host yourself. The catalog is the single source of truth. When a unit sells on any connected store, Handles subtracts it from the catalog, pushes the new count to the rest, and delists the item everywhere once it hits zero.

## What makes it hard

**Sales don't take turns.** Two stores can each sell a unit between sync passes. Handles compares every store's live count with the last value it confirmed there, adds up the drops, and subtracts the total once. If two stores sell the last unit, it doesn't pick a winner: it delists everywhere and flags the oversell for a person, because cancelling an order isn't a sync engine's call.

**Every marketplace works differently.** One applies a change and answers immediately; another takes batch feeds that have to be polled until they finish. One needs a browser sign-in with a consent screen; another uses app credentials. Adapters hide all of it behind one five-method interface, and the sync engine reads back every write to confirm it landed. Where a marketplace has no seller API, Handles doesn't scrape it; it keeps the listing one tap away for a manual update.

**It runs unattended.** Sync lives in a daemon, not the app, so nothing depends on a laptop being open. One binary can loop under Docker Compose or run once per Kubernetes CronJob, and it skips a pass while the host is under load. Oversells and failed writes arrive as native notifications on Windows and Android.

**It stays private.** The catalog API is published only on localhost, reached through a private Tailscale network, and requires a bearer token. The one piece meant to face the internet, a webhook receiver, rejects unsigned requests, is rate-limited, and never writes catalog data; at most it wakes the daemon early. The app never handles a marketplace password: any sign-in happens on the marketplace's own page, and tokens stay in OS-encrypted storage.

## Stack

Flutter · Dart · Docker Compose · GitHub Actions · GHCR · Tailscale

| Path | Contents |
| --- | --- |
| [`app/`](app/) | Windows and Android app |
| [`core/`](core/) | Pure-Dart engine: store adapters, reconciliation, daemon, catalog API, webhook receiver |
| [`catalog/`](catalog/) | Catalog schema: one JSON file per SKU |
| [`k8s/`](k8s/) | Kubernetes CronJob manifests |
| [`docs/`](docs/) | Design plan, API research, deployment guide, case study |

## Status

In active development. In the original repository, every push runs static analysis and both test suites, with marketplace APIs simulated; pushes to `main` also build the Windows app, the Android APK, and the daemon and API container images for x86-64 and ARM64. The backend runs on a self-hosted server, and connecting live store accounts is the current step.

---

**Read more:** [Handles, self-hosted](docs/CASE_STUDY.md), a case study of the deployment, the CI pipeline, and the problems solved along the way.

© 2026 Undivine-Spirit. All rights reserved; see [LICENSE](LICENSE).
