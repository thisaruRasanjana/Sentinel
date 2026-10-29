# ADR 005: Append-Only Hash-Chained Audit Log

## Status
Accepted

## Context
Sentinel requires a tamper-evident record of every tool invocation passing through the Gateway. This audit trail is essential for compliance, forensics, and debugging in environments where autonomous AI agents interact with enterprise APIs.

## Decision
We implement a dedicated **audit-sink** Go microservice that receives `AuditEvent` messages over gRPC from the Gateway and writes them to an append-only JSONL file. Each entry includes a SHA-256 hash computed over its fields plus the previous entry's hash, forming a hash chain. The first entry uses `"GENESIS"` as its previous hash.

The Gateway emits audit events **synchronously within the gRPC call but asynchronously from the HTTP response path** — the audit call happens after the response is determined but errors are swallowed so they never affect the caller.

## Consequences
- **Positive:** Every tool invocation is recorded with agent identity, outcome, and latency.
- **Positive:** Hash chaining makes tampering detectable — modifying any entry breaks the chain for all subsequent entries.
- **Positive:** JSONL format is trivially parseable and `grep`-friendly.
- **Negative:** The hash chain does not survive audit-sink restarts (it resets to `"GENESIS"`). Production would need to read the last line on startup.
- **Negative:** Single JSONL file will eventually need rotation (future phase).
- **Negative:** The audit call adds a small amount of latency to the request (one gRPC round-trip after routing), though errors are swallowed.
