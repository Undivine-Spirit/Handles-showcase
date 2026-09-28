# Deploying to a Kubernetes cluster

For running the reconciliation daemon on a Kubernetes cluster (e.g. a
friend's Raspberry Pi cluster) instead of `docker-compose` on a single
machine. Both deploy the same image
(`ghcr.io/undivine-spirit/handles-reconcile-daemon`) - see the root
[`docker-compose.yml`](../docker-compose.yml) and
[`docs/DEPLOYMENT.md`](../docs/DEPLOYMENT.md) for that simpler path.

## Read this before applying anything to someone else's cluster

**A Kubernetes Secret is base64-*encoded*, not encrypted, by default.**
Anyone with `kubectl get secret -o yaml` access to the `handles` namespace
can read the eBay client secret and OAuth tokens in plaintext. If this is
deployed to a cluster someone else administers, that's a real trust
decision, not a technicality - talk to them about it before real
credentials land here. Options if that's a concern, roughly in order of
effort: ask for a namespace-scoped RBAC role that excludes `get` on
Secrets for other users, look at a cluster-level secrets encryption
setup, or use a tool like Sealed Secrets / External Secrets Operator so
the plaintext value never sits in `etcd` (or in this repo) at all. None
of that is set up yet - `secret.example.yaml` is the plain baseline.

## Why a CronJob, not a Deployment

A `Deployment` is for something that should always be running (a web
server, this project's own eventual UI if it were server-hosted). This
daemon's job is periodic - check, act, wait - so a `CronJob` is the
better-fitting primitive: Kubernetes creates a fresh Pod on schedule, the
container runs one pass and exits (`RUN_ONCE=true`,
`core/bin/reconcile_daemon.dart`), and Kubernetes cleans it up. No
container sits idle between runs.

## Architecture: why the image had to change

Raspberry Pis are **arm64**; the CI runner that builds this image is
**amd64**. Without a multi-platform build (see
`.github/workflows/ci.yml`'s `build-docker-image` job - QEMU + Buildx,
`platforms: linux/amd64,linux/arm64`), the image simply wouldn't run on
Pi hardware. `docker pull`/`kubectl` resolve the right architecture from
one multi-platform image automatically - nothing cluster-side needs to
know or care which architecture it's on.

## One-time setup

1. `kubectl apply -f k8s/namespace.yaml`
2. `kubectl apply -f k8s/configmap.yaml`
3. `cp k8s/secret.example.yaml k8s/secret.yaml`, fill in real values
   (gitignored - never commit the filled-in version), then
   `kubectl apply -f k8s/secret.yaml`.
   - `handles-git-credentials`: a GitHub personal access token, scoped to
     *only* this repo, with just Contents: Read and write - not a
     personal login token, and not broader than this job needs.
   - `handles-ebay-secrets`: one key per connected account, same shape as
     `core/secrets/<account_key>.json`. Run the one-time OAuth consent
     flow via the desktop app first (same manual copy-the-token-over step
     as the docker-compose path - see `docs/DEPLOYMENT.md`).
4. `kubectl apply -f k8s/cronjob.yaml`

## Checking on it

```bash
kubectl get cronjob -n handles
kubectl get jobs -n handles          # past runs
kubectl logs -n handles job/<job-name>   # a specific run's output
kubectl create job -n handles --from=cronjob/handles-reconcile manual-test-run
                                       # trigger one run immediately, without
                                       # waiting for the schedule
```

## What's genuinely not solved yet

- **Secrets trust boundary**, covered above - a real conversation to have,
  not a default to accept silently.
- **No persistent volume** - each run re-clones the catalog repo fresh
  (`initContainers` in `cronjob.yaml`) rather than reusing a checkout
  across runs, to stay portable across whatever storage class (or lack of
  one) the cluster has. Fine for a small catalog; worth revisiting if the
  repo grows large enough that a fresh shallow clone every 15 minutes
  becomes wasteful.
- **No monitoring/alerting** if a run starts failing silently - `kubectl
  get jobs` shows failures, but nothing pages anyone about it.
