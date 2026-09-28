# Multi-stage build: two separate images layered into one build, so the
# final shipped image doesn't carry the Dart SDK, pub cache, or source
# tree - only the compiled binary and what it needs at runtime. This is
# the single most common Docker pattern for compiled languages (same idea
# in Go, Rust, Java) and it matters for two real reasons: a smaller image
# pulls/starts faster, and it doesn't ship build tooling an attacker could
# abuse if the container were ever compromised.

# ---- Stage 1: build ----
# Pinned to a specific Dart version, not `:latest` - a floating tag means
# "what this builds" can silently change out from under you months later.
FROM dart:3.13 AS build
WORKDIR /build

# Copy just the dependency manifests first, then `pub get`, BEFORE copying
# the rest of the source. Docker caches each instruction as a layer; if
# pubspec.yaml/pubspec.lock haven't changed, this layer gets reused on the
# next build even if application code has - so editing a .dart file
# doesn't force every dependency to redownload.
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY . .
RUN dart pub get --offline

# AOT-compile both binaries to standalone native executables - no Dart
# runtime needed to run either, similar to how Go or Rust produce a
# single binary. One build stage, two outputs, so both images share the
# exact same dependency resolution rather than risking drift between two
# separate builds.
RUN dart compile exe bin/reconcile_daemon.dart -o /build/reconcile_daemon
RUN dart compile exe bin/api_server.dart -o /build/api_server
RUN dart compile exe bin/webhook_server.dart -o /build/webhook_server

# ---- Stage 2: shared runtime base ----
# debian:bookworm-slim, not `scratch` or alpine - both binaries shell out
# to the real `git` CLI (see lib/src/git_sync.dart), so the runtime image
# needs an actual OS with git installed, not just the compiled binary.
# Alpine's musl libc has occasionally caused issues with Dart AOT
# binaries; slim Debian avoids that class of problem. One shared base so
# the git/ca-certificates install and non-root user setup aren't
# duplicated across two images.
FROM debian:bookworm-slim AS runtime-base
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Run as a non-root user - if either container is ever compromised, the
# process shouldn't have root inside it. Standard hardening step, not
# specific to this app.
RUN useradd --create-home --shell /usr/sbin/nologin handles
USER handles
WORKDIR /app

# ---- Stage 3a: the reconciliation daemon ----
FROM runtime-base AS daemon
COPY --from=build --chown=handles:handles /build/reconcile_daemon /app/reconcile_daemon

# Config lives in environment variables (12-factor app style) rather than
# being baked into the image - the same image works for anyone who runs
# it, configured entirely at `docker run`/compose time. See
# docker-compose.yml and docs/DEPLOYMENT.md for what these mean.
ENV CATALOG_DIR=/app/catalog
ENV SECRETS_DIR=/app/secrets
ENV RECONCILE_INTERVAL_MINUTES=15
ENV GIT_SYNC_ENABLED=false

ENTRYPOINT ["/app/reconcile_daemon"]

# ---- Stage 3b: the catalog API - docs/PROJECT_PLAN.md section 2, 2026-09-02 ----
# Selected via `docker-compose.yml`'s `build.target: api` - same context,
# same Dockerfile, a different final stage, not a second Dockerfile to
# keep in sync with this one.
FROM runtime-base AS api
COPY --from=build --chown=handles:handles /build/api_server /app/api_server

ENV CATALOG_DIR=/app/catalog
ENV API_PORT=8080
ENV API_GIT_PUSH=false
# API_AUTH_TOKEN has no default on purpose - api_server.dart refuses to
# start without one rather than silently running unauthenticated.

ENTRYPOINT ["/app/api_server"]

# ---- Stage 3c: the marketplace webhook receiver ----
# The one piece of this deployment meant to be reachable from the public
# internet (via Tailscale Funnel, not the tailnet-only `tailscale serve`
# the catalog API uses) - see docs/DEPLOYMENT.md's webhook entry.
FROM runtime-base AS webhook
COPY --from=build --chown=handles:handles /build/webhook_server /app/webhook_server

ENV CATALOG_DIR=/app/catalog
ENV WEBHOOK_PORT=8081
# EBAY_VERIFICATION_TOKEN/EBAY_WEBHOOK_ENDPOINT_URL/WALMART_CLIENT_SECRET
# have no defaults on purpose - webhook_server.dart disables whichever
# route's credentials are missing, and refuses to start if both are.

ENTRYPOINT ["/app/webhook_server"]
