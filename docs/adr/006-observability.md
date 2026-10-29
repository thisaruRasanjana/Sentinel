# ADR 006: Distributed Observability with OpenTelemetry and Prometheus

## Status
Accepted

## Context
All Sentinel Go services (policy-engine, registry, audit-sink) process agent requests but emit no structured telemetry. There is no way to measure request latency, error rates, or trace a request across service boundaries.

## Decision
We add two complementary observability layers:

1. **OpenTelemetry Distributed Tracing** — each Go service creates spans using the OTel Go SDK and exports them via OTLP gRPC to a Jaeger all-in-one container. The gRPC instrumentation is provided by `otelgrpc.NewServerHandler()` which automatically extracts W3C `traceparent` from incoming gRPC metadata and creates child spans.

2. **Prometheus Metrics** — each Go service exposes a `/metrics` HTTP endpoint on a dedicated admin port (`9011`, `9012`, `9013`). Prometheus scrapes these every 15 seconds. Grafana visualizes the data with a pre-provisioned dashboard.

3. **Gateway Trace Propagation** — the Ballerina Gateway does not run a native OTel SDK (no compatible library for Ballerina 2201.13.6). Instead it forwards the W3C `traceparent` header from incoming requests to downstream HTTP and gRPC calls, enabling trace correlation between client-generated traces and the Go service spans.

## Consequences
- **Positive:** End-to-end request latency is visible in Jaeger traces, broken down by service boundary.
- **Positive:** Per-tool and per-agent error rates are queryable via Prometheus.
- **Positive:** Grafana dashboard provides at-a-glance operational health.
- **Negative:** OTel exporter connects to Jaeger on startup. If Jaeger is unavailable, services log a warning and continue operating without tracing (graceful degradation).
- **Negative:** Gateway trace propagation is simplified (UUIDs used as trace IDs rather than a proper 128-bit hex). Full W3C compliance would require a Ballerina OTel library.
- **Negative:** Metrics ports (9011–9013) are exposed to the Docker bridge network. In production these should be firewalled.

