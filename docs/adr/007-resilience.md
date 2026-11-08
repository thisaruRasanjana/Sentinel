# ADR 007: Resilience & Circuit Breaking

## Status
Accepted

## Context
The Sentinel Gateway proxies all agent requests to upstream tool services. Without resilience controls:
- A hanging upstream blocks the gateway thread until the default 60-second TCP timeout.
- A failing upstream causes every request to that tool to fail with a 502 error, with no backoff.
- There is no visibility into timeout or circuit breaker events.

## Decision
We add three resilience mechanisms to the Gateway:

1. **Per-upstream timeout** (default 5 seconds) — configured via Ballerina's `http:ClientConfiguration.timeout`. Requests that exceed the deadline return HTTP 504 (UPSTREAM_TIMEOUT).

2. **Per-upstream circuit breaker** — configured via Ballerina's built-in `http:CircuitBreakerConfig`. The circuit trips open when the failure rate exceeds 50% over a 60-second rolling window (minimum 5 requests). While open, requests fail immediately with HTTP 503 (CIRCUIT_OPEN) instead of being forwarded. After a 15-second cooldown, one probe request is sent (half-open). If it succeeds, the circuit closes.

3. **Gateway Prometheus metrics** — the Gateway now exposes a `/metrics` endpoint in Prometheus text exposition format on the existing `:8080` listener. Metrics include request counts, success/error/timeout/circuit-open counters.

All resilience parameters are configurable via `BAL_CONFIG_DATA` environment variables.

The Go services (policy-engine, registry, audit-sink) are unchanged. They already have gRPC deadline propagation via the OTel interceptor.

## Circuit Breaker State Machine

```
   CLOSED  ──────  failure rate > 50%  ──────>  OPEN
     ↑                                            │
     │                                    resetTime (15s)
     │                                            │
     └──── probe succeeds ──── HALF-OPEN  <───────┘
                                  │
                          probe fails → OPEN
```

## Consequences
- **Positive:** Upstream failures are detected within 5 seconds instead of 60.
- **Positive:** The circuit breaker prevents cascading load on a failing upstream.
- **Positive:** Agents receive a clear 503 + CIRCUIT_OPEN error code and can retry after the reset period.
- **Positive:** The audit log records UPSTREAM_TIMEOUT and CIRCUIT_OPEN outcomes for forensic analysis.
- **Positive:** Grafana dashboard shows circuit breaker and timeout rates in real time.
- **Negative:** During the open state, all requests to the affected upstream fail immediately — this is by design (fail-fast) but means brief outages cause tool unavailability.
- **Negative:** Circuit breaker is per upstream URL, not per tool ID. If two tools share the same upstream, a failure in one trips the breaker for both.
- **Negative:** No retry logic is implemented. Retries risk duplicating side effects for non-idempotent tools (e.g., invoice creation).

