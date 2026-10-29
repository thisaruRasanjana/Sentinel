# Sentinel — Agent API Governance Platform

Sentinel is a governance layer that sits between autonomous AI agents and the enterprise APIs they call. It enforces identity, quota, schema validity, and auditability on agent traffic.

## Architecture

```
                        ┌──────────────────┐
   AI agents ─────────► │  Gateway         │  Ballerina
                        │  (edge, :8080)   │
                        └───┬────┬────┬──┬─┘
                            │    │    │  │
              gRPC ─────────┘    │    │  └──── gRPC ────┐
                 │               │    │                  │
                 ▼               ▼    │                  ▼
        ┌────────────────┐  ┌────────────┐      ┌──────────────┐
        │ Policy Engine  │  │  Registry  │      │  Audit Sink  │
        │ Go, :9001      │  │  Go, :9002 │      │  Go, :9003   │
        │ quota + limits │  │  tool defs │      │  hash-chain  │
        └───────┬────────┘  └────────────┘      └──────┬───────┘
                │                                       │
                ▼                                       ▼
            ┌───────┐                           ┌──────────────┐
            │ Redis │                           │ audit.jsonl  │
            └───────┘                           └──────────────┘
```
*Status: Core Gateway routing, tool services, Policy Engine, Registry, and Audit Sink are active.*

For detailed architecture decisions, see [docs/architecture.md](docs/architecture.md).

## Quick Start

### Option A — Local Development (Fastest)

Each service can be run directly with `bal run`. The gateway uses `Config.toml` for local defaults (already configured).

```bash
# Terminal 1
cd tools/tool-billing && bal run

# Terminal 2
cd tools/tool-inventory && bal run

# Terminal 3
cd gateway && bal run
```

### Option B — Docker Compose

To run the full stack via Docker Compose (requires the Ballerina base image pull, ~800MB first time):

```bash
cd deploy/compose
docker compose up --build
```

### Smoke Tests

1. Start all services using Docker Compose or locally.

2. Get a JWT token for an agent:
```bash
TOKEN=$(curl -s -X POST http://localhost:9000/tokens \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "agent:invoice-assistant", "principal": "user:thisaru", "scopes": ["billing:write", "inventory:read"]}' \
  | jq -r '.token')
echo $TOKEN
```

3. Call the gateway with the token:
```bash
curl -X POST http://localhost:8080/tools/invoice.create \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"customer": "acme-corp", "amount": 1500.00, "currency": "USD"}'
```

Check inventory via the gateway:
```bash
curl -X POST http://localhost:8080/tools/inventory.check \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"sku": "WIDGET-001"}'
```

## Observability

After starting the full stack with `docker compose up --build`:

| Tool | URL | Credentials |
|---|---|---|
| **Jaeger UI** (traces) | http://localhost:16686 | None |
| **Prometheus** (metrics) | http://localhost:9090 | None |
| **Grafana** (dashboard) | http://localhost:3000 | Anonymous |

In Jaeger UI, select service `sentinel-policy-engine`, `sentinel-registry`, or `sentinel-audit-sink` and click **Find Traces** to see spans from recent requests.

In Grafana, the **Sentinel Observability** dashboard is pre-provisioned under the **Sentinel** folder.

## Project Status & Roadmap

Sentinel is currently under active development. Below is the roadmap of core governance capabilities:

| Capability | Status | Description |
|---|---|---|
| **API Gateway & Tool Dispatch** | Available | Abstract agent tool routing with standardized error envelopes |
| **Tool Backends** | Available | Sample billing and inventory microservices |
| **Agent Identity & Auth** | Available | JWT verification, agent API key validation, and RBAC |
| **Policy Engine & Rate Limiter** | Available | In-memory sharded token bucket with distributed quota tracking |
| **Tool Registry** | Available | Dynamic tool discovery, method mapping, and scope validation |
| **Audit Pipeline** | Available | Tamper-evident hash-chained logging of all agent tool invocations |
| **Distributed Observability** | Available | OpenTelemetry tracing to Jaeger, Prometheus metrics, Grafana dashboard |
| **Resilience & Circuit Breaking** | Planned | Fail-fast mechanics, fallback strategies, and timeout guardrails |
