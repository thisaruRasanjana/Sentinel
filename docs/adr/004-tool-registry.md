# ADR 004: JSON-Backed In-Memory Tool Registry

## Status
Accepted

## Context
Sentinel's Gateway previously used hardcoded if-else routing logic tied to specific tool service URLs. This made adding new tools a code change, not a configuration change. Phase 4 introduces a **Tool Registry** — a dedicated service the Gateway queries at runtime to discover tool metadata (upstream URL, HTTP method, required scope).

The key design decision was: **where does the registry store tool definitions?**

Options considered:
1. **Postgres database** — persistent, supports CRUD API
2. **Redis hash** — fast, ephemeral
3. **Local JSON file** (chosen) — zero infrastructure overhead, loaded into memory at startup

## Decision
We use a **local `tools.json` file** loaded at startup into a thread-safe in-memory `map[string]ToolDef` protected by a `sync.RWMutex`. The registry exposes a **gRPC interface** (`RegistryService/GetTool`) so the Gateway remains decoupled from the storage implementation.

The Gateway adds an additional **in-process `ToolCache`** (Ballerina `isolated` class with `lock`) to avoid a gRPC round-trip on every request for known tools.

## Consequences

- **Positive:** Zero additional infrastructure dependencies — no Postgres or Redis required just for the registry.
- **Positive:** Fast reads — all tool lookups are O(1) from memory after startup.
- **Positive:** The gRPC interface abstracts the storage backend. Migrating to Postgres later only requires changing the registry implementation, not the Gateway.
- **Negative:** No persistence. Tool definitions must be in `tools.json` at deploy time. There is no CRUD API to add tools at runtime without restarting the registry.
- **Negative:** No hot-reload. If `tools.json` changes, the registry service must be restarted. The Gateway's `ToolCache` also requires a restart to evict stale entries.
- **Negative:** No TTL on the Gateway's `ToolCache`. If the registry is updated (via restart), the Gateway continues serving cached metadata until it is also restarted.

These trade-offs are acceptable for the current MVP scope. The gRPC boundary ensures a clean migration path to a database-backed registry when operational requirements demand it.
