# Catalog

This directory is the source of truth described in
[`../docs/PROJECT_PLAN.md`](../docs/PROJECT_PLAN.md) section 2: one record per
SKU, validated against [`schema.json`](schema.json), with the commit history
doubling as the audit trail.

## Commit conventions

- One commit per state-changing action where practical (price change,
  quantity change, delist, new listing) — not batched, so `git log` on a SKU
  file gives an accurate history of what changed and when.
- Commit message format: `<sku>: <what changed>` — e.g.
  `HND-0001: quantity 3 -> 0 (sold on ebay)`.
- The reconciliation engine commits either just before or immediately after a
  store write is confirmed (see `sync_status` in the schema), so the repo
  always reflects the write-then-verify outcome, not just intent.

## Layout

Each SKU is its own JSON file, named `<sku>.json`, validated against
`schema.json`. See `example-item.json` for a filled-out reference record —
copy it as a starting point for real SKU files, don't commit it as-is.

A few other files live here too, none of them SKU records:
`stores.json` (connected accounts), `.events.jsonl` (the structured event
log, section 8 - created by the daemon on first run, not checked in until
then), and `brand_risk_list.json` (the sourcing engine's known-risk brand
list, section 10 - a blocklist match, not a legal clearance check; see that
section's 2026-08-29 research note for why it's built this way. Add an
entry any time a brand actually causes a problem for this catalog - that
`own_history` entry is worth more than the curated starter list).
