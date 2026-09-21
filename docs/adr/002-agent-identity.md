# ADR 002: Agent Identity and Authorization

## Context
Sentinel acts as a governance proxy between autonomous AI agents and enterprise APIs. Unlike human users who interact via web sessions, agents operate via programmatic API calls, often with high frequency and unpredictable loops. 

We need a mechanism to:
1. Uniquely identify the agent making the call.
2. Identify the human principal the agent is acting on behalf of.
3. Restrict the agent's actions to a specific set of granted scopes.
4. Cryptographically verify this identity at the edge (Gateway) without relying on downstream services, ensuring they remain decoupled from authentication concerns.

## Decision
We will use **JSON Web Tokens (JWT)** signed with **RS256** (RSA Signature with SHA-256).

- **Token Structure**: 
  - `sub`: Agent identifier (e.g., `agent:invoice-assistant`).
  - `principal`: Human identifier (e.g., `user:alice`).
  - `scopes`: An array of permitted actions (e.g., `["billing:write", "inventory:read"]`).
  - Standard claims: `iss` (sentinel), `aud` (sentinel-gateway), `exp`, `jti`.
- **Validation**: The Ballerina Gateway verifies the JWT signature against a trusted public certificate on every request.
- **Enforcement**: The Gateway enforces that the token contains the required scope for the requested tool before forwarding the payload. Downstream services do not perform authentication; they trust the Gateway.

## Alternatives Rejected
1. **API Keys**: While simpler, API keys are opaque strings. To attach scopes and principals to an API key, the Gateway would need to query a database on every request, adding latency. JWTs are stateless and self-contained.
2. **OAuth2 / OIDC**: A full OAuth2 server (like Keycloak) is too heavy for this portfolio project. A bespoke lightweight token issuer is sufficient to demonstrate the architectural pattern of edge authentication.
3. **mTLS (Mutual TLS)**: Provides strong identity but is complex to distribute and rotate for diverse agent clients. It also does not natively carry rich authorization scopes as easily as JWTs.

## Consequences
- **Positive**: Gateway latency is kept low because verification is entirely local (cryptographic math, no database lookups).
- **Positive**: Downstream tool services are purely focused on business logic.
- **Negative**: The Gateway becomes a single point of trust. If the Gateway is compromised or misconfigured, downstream services are vulnerable. This necessitates strict network isolation (e.g., downstream services only accept connections from the Gateway).
- **Future Work (Deferred)**: Scope narrowing. An agent should not be able to exercise a scope (even if present in its JWT) if the human principal it acts for lacks that permission. This requires a persistent Registry of principal permissions, which will be evaluated in Phase 4.
