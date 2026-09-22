# Sentinel — Agent API Governance Platform

Sentinel is a governance layer that sits between autonomous AI agents and the enterprise APIs they call. It enforces identity, quota, schema validity, and auditability on agent traffic.

## Architecture

```
                        ┌──────────────────┐
   AI agents ─────────► │  Gateway         │  Ballerina
                        │  (edge, :8080)   │
                        └───┬────┬─────┬───┘
                            │    │     │
              gRPC ─────────┘    │     └───────── HTTP ──────┐
                 │               │                           │
                 ▼               ▼                           ▼
        ┌────────────────┐  ┌──────────────┐        ┌────────────────┐
        │ Policy Engine  │  │  Registry    │        │ Tool Services  │
        │ Go, :9001      │  │  Go, :9002   │        │ Ballerina      │
        │ quota + limits │  │  tool defs   │        │ :7001-7003     │
        └───────┬────────┘  └──────┬───────┘        └────────────────┘
                │                  │
                ▼                  ▼
            ┌───────┐         ┌──────────┐
            │ Redis │         │ Postgres │
            └───────┘         └──────────┘
```
*Status: Core Gateway routing and tool services are active. Additional governance modules (Policy, Registry, Identity) are in active development.*

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

## Project Status & Roadmap

Sentinel is currently under active development. Below is the roadmap of core governance capabilities:

| Capability | Status | Description |
|---|---|---|
| **API Gateway & Tool Dispatch** | Available | Abstract agent tool routing with standardized error envelopes |
| **Tool Backends** | Available | Sample billing and inventory microservices |
| **Agent Identity & Auth** | Available | JWT verification, agent API key validation, and RBAC |
| **Policy Engine & Rate Limiter** | Available | In-memory sharded token bucket with distributed quota tracking |
| **Tool Registry** | Planned | Dynamic tool discovery, method mapping, and schema validation |
| **Audit Pipeline** | Planned | Tamper-evident logging of all LLM/agent invocations |
| **Distributed Observability** | Planned | OpenTelemetry tracing and latency metrics across tool hops |
| **Resilience & Circuit Breaking** | Planned | Fail-fast mechanics, fallback strategies, and timeout guardrails |
