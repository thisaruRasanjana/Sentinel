# Sentinel — Agent API Governance Platform

**System architecture and implementation plan**

---

## 1. What this is

Sentinel is a governance layer that sits between autonomous AI agents and the enterprise APIs they call.

Agents are a difficult class of API client. They retry aggressively, loop when confused, call tools in
unpredictable sequences, and act on behalf of a human principal whose permissions they must not exceed.
Every call they make has to be attributable after the fact. Sentinel enforces identity, quota, schema
validity, and auditability on that traffic.

**This project does not build agents or models.** The agent is the *client class* that motivates the
requirements. Everything built here is API platform and distributed systems engineering.

### Design goals

| Goal | Consequence in the design |
|---|---|
| Every call is attributable to an agent and its human principal | Signed identity propagated end to end; immutable audit log |
| No agent can exceed its quota, even under concurrent bursts | Centralised policy engine with atomic decisions |
| Downstream failures must not cascade | Circuit breakers, timeouts, bounded retries at the edge |
| Tools are declared, not hardcoded | Registry-driven routing with schema validation |
| The platform is observable across language boundaries | OpenTelemetry trace context propagated Ballerina → Go |

### Explicit non-goals

- Not building agents, LLM calls, or prompting logic.
- Not a service mesh — this is L7 application-level governance.
- Not multi-tenant SaaS. Single organisation, multiple agents.
- Not production-hardened. This is a portfolio system optimised for demonstrating design judgement.

---

## 2. Technology decisions

| Layer | Technology | Rationale |
|---|---|---|
| Edge gateway, orchestration | **Ballerina** | Network-first language; services, resilience, and data binding are language constructs rather than framework code. This is the integration layer, which is what Ballerina is designed for. |
| Policy engine, registry, audit | **Go 1.22+** | Concurrency primitives and predictable latency for the hot path. Gin for HTTP surfaces. |
| Inter-service (hot path) | **gRPC** | The gateway calls the policy engine on every request. Binary framing and persistent connections matter here. |
| Inter-service (control plane) | **REST/JSON** | Registry CRUD is low-frequency; JSON is easier to debug and inspect. |
| Async transport | **NATS JetStream** | Audit events must not block the request path. Lighter operationally than Kafka for this scale. |
| Persistence | **PostgreSQL** | Registry definitions and the audit log. |
| Cache / distributed counters | **Redis** | Quota state that must survive a policy engine restart. |
| Observability | **OpenTelemetry, Prometheus, Grafana, Jaeger** | Cross-language tracing is the whole point; both Ballerina and Go have OTel support. |
| Orchestration | **Docker Compose → Kubernetes** | Compose until the system works end to end, then K8s manifests as a later phase. |

### Why polyglot at all

This is the central architectural decision and should be documented as ADR-001.

Ballerina and Go are doing genuinely different jobs. The gateway is I/O-bound integration work —
protocol mediation, transformation, fan-out, resilience policy. That is Ballerina's design centre, and
expressing it in Go would mean hand-rolling what Ballerina gives as language constructs.

The policy engine is a latency-critical decision service called on every single request, where tail
latency directly becomes gateway tail latency. It needs fine-grained control over memory layout, lock
contention, and allocation. That is Go's strength and not Ballerina's.

A single-language version of this system would be worse at one end or the other. The split is the point.

---

## 3. Service topology

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

        Gateway ──publish──► NATS JetStream ──► Audit Service (Go, :9003) ──► Postgres
```

### 3.1 Gateway (Ballerina)

The only component exposed to agents. Responsibilities, in request order:

1. Terminate HTTP, parse and bind the request to typed records.
2. Verify the agent's JWT (signature, expiry, issuer, audience).
3. Extract agent identity, principal, and granted scopes.
4. Resolve the requested tool from the registry (cached, see §5.2).
5. Authorise: does the agent hold the scope this tool requires?
6. Call the policy engine over gRPC for a quota decision.
7. Validate the request body against the tool's declared input schema.
8. Forward to the tool service with circuit breaker, timeout, and bounded retry.
9. Publish an audit event to NATS (fire-and-forget, never blocks the response).
10. Return the response, or a structured error.

Ballerina specifics to use deliberately — these are the reason the project teaches the language:

- `service` / `resource` declarations rather than framework routing.
- `ballerina/jwt` for token validation.
- `ballerina/grpc` with a generated stub from the policy proto.
- `http:Client` with `retryConfig` and `circuitBreakerConfig` — built-in, do not hand-roll.
- `ballerina/constraint` for declarative payload validation where schemas are static.
- Union types and `check` for error propagation; no exception-style control flow.
- `worker` declarations where concurrent fan-out is genuinely needed.
- `ballerina/observe` + OTel exporter for trace propagation.

### 3.2 Policy Engine (Go)

A decision service. Given an agent, a tool, and a cost, it answers allow or deny, atomically.

**This is the systems-depth component of the project.** Requirements:

- Single gRPC method on the hot path: `Check(agentID, toolID, cost) → (allowed, remaining, retryAfter)`.
- Sharded in-memory state. Partition by hash of `agentID` across N shards, each with its own mutex,
  so unrelated agents never contend. N configurable, default `runtime.NumCPU() * 4`.
- Token bucket per `(agent, tool)` pair, plus a coarser per-agent global bucket.
- Lazy refill: compute tokens from elapsed time on read rather than running background tickers.
- Redis write-behind so quota state survives a restart; Redis is never on the read path.
- A Gin-based HTTP admin API on a separate port for inspecting and adjusting limits.

**Benchmarks are a deliverable, not an afterthought.** Required, committed as `bench/`:

- `go test -bench` on the limiter core across 1, 8, 64, 512 goroutines.
- Comparison against a naive single-mutex map implementation — this is the number that justifies the design.
- `-race` clean under concurrent load.
- End-to-end p50/p95/p99 gateway latency with the policy check in and out of the path, under `k6`.

Record the results in `docs/benchmarks.md` with the methodology, hardware, and the honest interpretation.
State what the numbers do *not* prove.

### 3.3 Registry (Go)

Control plane. CRUD over tool definitions, backed by Postgres, served with Gin.

A tool definition declares:

```json
{
  "tool_id": "invoice.create",
  "version": "1.2.0",
  "upstream_url": "http://tool-billing:7001/invoices",
  "method": "POST",
  "required_scope": "billing:write",
  "input_schema": { "...": "JSON Schema" },
  "default_cost": 5,
  "timeout_ms": 3000,
  "deprecated": false
}
```

Versioning rules to implement and document:

- Tools are addressed as `toolId@version`; omitting the version resolves to the latest non-deprecated.
- Additive schema changes bump minor. Removing or narrowing a field requires a major bump.
- Deprecated tools still resolve but return a `Sunset` response header.

### 3.4 Audit Service (Go)

Consumes from NATS JetStream and writes to Postgres. Separate from the request path by design —
audit durability must never be able to fail a live agent call.

- Idempotent writes keyed on event ID; JetStream delivers at-least-once.
- Batch inserts with a size and time trigger.
- A Gin query API: filter by agent, principal, tool, outcome, time range.

### 3.5 Tool Services (Ballerina)

Two or three small downstream services standing in for enterprise APIs. Keep them simple — they exist to
be governed, not to be interesting. One should include a deliberate failure mode (configurable latency
injection and error rate) so circuit breaking can be demonstrated rather than merely claimed.

---

## 4. Identity and authorisation

Agents authenticate with a JWT issued by a small local issuer (a Ballerina service is fine; do not build
a full OAuth2 server).

```json
{
  "sub": "agent:invoice-assistant",
  "principal": "user:thisaru",
  "scopes": ["billing:read", "billing:write"],
  "exp": 1750000000,
  "jti": "..."
}
```

Two rules that make this more than a toy:

1. **Scope narrowing.** An agent's effective permissions are the intersection of its own grants and its
   principal's permissions. An agent can never exceed the human it acts for, even if its token claims more.
2. **Delegation depth.** If an agent calls a tool that itself invokes another agent, the propagated token
   carries a depth counter. Reject beyond a configured maximum. This prevents unbounded delegation chains.

Document both in ADRs. They are the kind of detail that separates a considered design from a tutorial.

---

## 5. Request path details

### 5.1 Failure semantics

Decide and document each of these explicitly:

| Failure | Behaviour | Reasoning |
|---|---|---|
| Policy engine unreachable | **Fail closed** (503) | A governance system that stops governing under load is not a governance system. |
| Registry unreachable | Serve from cache; fail closed if cold | Tool definitions change rarely; a stale definition is safer than no answer. |
| NATS unreachable | Log locally, continue serving | Audit is durable-but-async; losing observability must not deny service. |
| Tool service failing | Circuit break after threshold, return 503 with `Retry-After` | Standard bulkheading. |
| Token invalid or expired | 401 immediately, before any downstream work | Cheapest possible rejection. |

The fail-closed vs fail-open choice for the policy engine is the single best interview talking point in
this system. Be able to argue both sides.

### 5.2 Caching

- Tool definitions: in-gateway cache, 30s TTL, refreshed asynchronously on expiry rather than on demand,
  so a cache miss never adds latency to a live request.
- JWT signing keys: cached with a longer TTL, invalidated on verification failure.
- Never cache policy decisions. That would defeat the purpose.

### 5.3 Error contract

Every error response uses the same envelope, including from downstream services:

```json
{
  "error": {
    "code": "QUOTA_EXCEEDED",
    "message": "Agent quota exhausted for tool invoice.create",
    "trace_id": "a1b2c3...",
    "retry_after_ms": 4200
  }
}
```

Consistent, machine-readable errors matter more than usual here, because the consumer is an agent that
must decide programmatically whether to retry, back off, or give up.

---

## 6. Observability

The cross-language trace is the thing to get right. A single request should produce one connected trace
spanning the Ballerina gateway, the Go policy engine, and the Ballerina tool service.

- Propagate W3C `traceparent` headers; gRPC metadata for the policy call.
- Ballerina: `ballerina/observe` with the OTel exporter.
- Go: `go.opentelemetry.io/otel` with gRPC and Gin instrumentation.
- Jaeger for trace visualisation.

Metrics worth exposing (Prometheus):

- `gateway_requests_total{tool,outcome}`
- `gateway_request_duration_seconds` (histogram, per tool)
- `policy_decisions_total{result}`
- `policy_check_duration_seconds`
- `circuit_breaker_state{tool}`
- `audit_events_published_total` / `audit_events_persisted_total` (the gap is the loss rate)

One Grafana dashboard, committed as JSON, showing request rate, error rate, latency percentiles, and
quota rejections.

---

## 7. Repository layout

```
sentinel/
├── README.md
├── docs/
│   ├── architecture.md          # this document, maintained
│   ├── benchmarks.md
│   └── adr/
│       ├── 001-polyglot-split.md
│       ├── 002-fail-closed-policy.md
│       ├── 003-sharded-limiter.md
│       ├── 004-async-audit.md
│       └── 005-tool-versioning.md
├── proto/
│   └── policy/v1/policy.proto
├── gateway/                     # Ballerina
│   ├── Ballerina.toml
│   ├── service.bal
│   ├── auth.bal
│   ├── registry_client.bal
│   ├── policy_client.bal
│   ├── audit.bal
│   ├── types.bal
│   └── tests/
├── policy-engine/               # Go
│   ├── cmd/server/
│   ├── internal/limiter/        # pure Go, no framework
│   ├── internal/grpcsrv/
│   ├── internal/adminapi/       # Gin
│   ├── internal/store/          # Redis write-behind
│   └── bench/
├── registry/                    # Go + Gin
├── audit/                       # Go + NATS consumer
├── tools/                       # Ballerina stand-in services
├── loadtest/                    # k6 scripts
├── deploy/
│   ├── compose/
│   └── k8s/
└── .github/workflows/
```

---

## 8. Implementation phases

Each phase must end with a working, demoable system. Never leave the repo in a state where nothing runs.

**Phase 0 — Contracts.** Define `policy.proto`, the tool definition schema, the error envelope, and the
JWT claim structure. Write ADR-001. Nothing else. Getting contracts settled first is what makes the rest
parallelisable, and it is genuinely how this is done in industry.

**Phase 1 — Walking skeleton.** Ballerina gateway forwarding to one Ballerina tool service. Compose file.
No auth, no policy, no registry. Prove the polyglot build and run story works before adding anything.

**Phase 2 — Identity.** JWT issuer, gateway verification, scope checks, scope narrowing. Returns 401/403
correctly. Tests for token tampering, expiry, and scope escalation attempts.

**Phase 3 — Policy engine.** The systems phase, and the longest. Build the sharded limiter as a standalone
Go package with its own tests and benchmarks *before* wiring it into anything. Then gRPC server, then
gateway integration, then Redis write-behind. Write `docs/benchmarks.md` and ADR-003 here.

**Phase 4 — Registry.** Postgres-backed tool definitions, Gin CRUD API, gateway resolution with async
cache refresh, schema validation of inbound payloads, versioning rules.

**Phase 5 — Audit pipeline.** NATS JetStream, gateway publisher, Go consumer, Postgres schema, query API.
Demonstrate that killing the audit service does not affect live traffic.

**Phase 6 — Observability.** OTel across both languages, Jaeger, Prometheus metrics, Grafana dashboard.
Deliverable: a screenshot of one trace spanning Ballerina → Go → Ballerina.

**Phase 7 — Resilience.** Circuit breakers, timeouts, retry budgets. Failure injection in tool services.
A documented chaos test: kill each dependency in turn, record actual behaviour against §5.1's table.
Where reality differs from the design, fix one and document the other.

**Phase 8 — Kubernetes.** Manifests, health and readiness probes, resource limits, HPA on the gateway.
Only after everything above works under Compose.

---

## 9. What makes this worth reviewing

Most portfolio microservice projects are a set of CRUD services with a gateway in front. The parts of this
that are not that, and which should be foregrounded in the README:

1. **A defended polyglot split.** Two languages chosen for different reasons, with the reasoning written down.
2. **A hand-built, benchmarked concurrent data structure** with an honest comparison against the naive version.
3. **Explicit failure semantics**, decided in advance and then verified by chaos testing rather than assumed.
4. **A real cross-language distributed trace**, which is harder than it sounds and rarely done in student work.
5. **ADRs.** Recording what was rejected and why is the clearest available evidence of design judgement.

The README should open with the problem, show the architecture diagram, link the ADRs, and state the
benchmark result in one line. A reviewer who reads only the first screen should understand what was built
and why it was built that way.

---

## 10. Claiming this honestly

What this project supports on a CV:

> Designed and built a polyglot API governance platform (Ballerina, Go) with contract-first service
> boundaries, scoped agent authentication, a sharded concurrent quota engine, async audit streaming,
> and cross-language distributed tracing.

What it does not support: the title "architect", claims of production or scale experience, or implying
the system ran real traffic. The benchmark numbers should always be stated with the conditions attached.
Overstating any of this is the fastest way to lose an interview that the project itself had won.
