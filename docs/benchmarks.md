# Policy Engine Benchmarks

This document records the benchmarks for the Sentinel Policy Engine's concurrent sharded rate limiter (`ShardedLimiter`) compared to a naive single-mutex limiter (`NaiveLimiter`).

## Environment
- **Go Version:** go1.26.1 darwin/arm64
- **Architecture:** Apple M2 (8 cores)
- **Date:** 2026-09-21

## Results

The benchmarks simulate high-concurrency token checks across 100 agents and 10 tools per agent. 

### Sharded Limiter (64 shards)
| Goroutines | Operations (N) | ns/op | B/op | allocs/op |
|------------|---------------|-------|------|-----------|
| 1          | 17,029,297    | 59.32 | 16   | 1         |
| 8          | 19,487,109    | 84.33 | 16   | 1         |
| 64         | 14,499,735    | 83.73 | 16   | 1         |
| 512        | 13,813,062    | 93.60 | 16   | 1         |

### Naive Limiter (Single Mutex)
| Goroutines | Operations (N) | ns/op | B/op | allocs/op |
|------------|---------------|-------|------|-----------|
| 1          | 2,339,595     | 491.9 | 0    | 0         |
| 8          | 2,191,688     | 545.5 | 0    | 0         |
| 64         | 1,957,486     | 577.0 | 0    | 0         |
| 512        | 2,062,004     | 573.9 | 0    | 0         |

## Conclusion
The `ShardedLimiter` provides exceptionally stable latency under high concurrency (remaining under 100ns at 512 parallel routines), whereas the single-mutex approach suffers from lock contention and has over 6x higher base latency (573ns at 512 routines). The memory footprint is negligible (16 bytes per operation).

This proves the viability of using a partitioned lock model for the `policy-engine` to handle thousands of concurrent AI agent requests.
