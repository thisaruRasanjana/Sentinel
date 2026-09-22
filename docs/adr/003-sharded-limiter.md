# ADR 003: Sharded Rate Limiter for Policy Engine

## Status
Accepted

## Context
The Sentinel policy engine must evaluate rate limits for thousands of AI agents making high-frequency API calls. A traditional single-mutex rate limiter in Go would suffer from severe lock contention under such high concurrency. Furthermore, we need to enforce both a global agent limit and a tool-specific limit per request.

## Decision
We implemented a **Sharded Rate Limiter** pattern using Go. 

1. **Partitioning:** The limiter is partitioned into `N` shards (defaulting to 64 or a multiple of CPU cores). Each shard contains a map of buckets protected by its own `sync.RWMutex`.
2. **Routing:** We hash the `agentID` using `fnv32a` to deterministically route an agent to a specific shard. This guarantees that both the tool-specific bucket (`agentID:toolID`) and the global bucket (`agentID`) are protected by the same mutex lock, avoiding deadlocks and cross-shard locking.
3. **Lazy Refill:** Instead of running background goroutines to refill tokens, buckets calculate elapsed time and refill tokens automatically upon every `Check` call.
4. **Redis Write-Behind:** The limiter state is asynchronously synced to Redis via a background pipeline to ensure resilience across restarts without adding network latency to the hot path.

## Consequences
- **Positive:** Massive reduction in lock contention. Benchmarks show `~93ns` per operation at 512 concurrent goroutines, compared to `~573ns` for a naive single-mutex implementation.
- **Negative:** Memory overhead slightly increases due to the array of shards and their respective maps.
- **Negative:** In the event of an abrupt crash, the last few seconds of token consumption may not have been synced to Redis, potentially allowing a slight over-usage when the service restarts. This is deemed an acceptable trade-off for sub-millisecond p99 latencies.
