import ballerina/http;
import ballerina/uuid;
import ballerina/time;
import ballerina/io;

configurable string policyUrl = "http://policy-engine:9001";
configurable string registryUrl = "http://registry:9002";
configurable string auditUrl = "http://audit-sink:9003";
configurable int gatewayPort = 8080;

final PolicyServiceClient policyClient = check new (policyUrl);
final RegistryServiceClient registryClient = check new (registryUrl);
final AuditServiceClient auditClient = check new (auditUrl);

// Cache http clients to upstream destinations
isolated class ClientCache {
    private map<http:Client> clients = {};

    isolated function getClient(string url) returns http:Client|error {
        lock {
            if self.clients.hasKey(url) {
                return self.clients.get(url);
            }
            http:Client newClient = check new (url);
            self.clients[url] = newClient;
            return newClient;
        }
    }
}
final ClientCache clientCache = new ClientCache();

isolated class ToolCache {
    private map<ToolMetadata> cache = {};

    isolated function get(string toolId) returns ToolMetadata? {
        lock {
            if self.cache.hasKey(toolId) {
                return self.cache.get(toolId).clone();
            }
            return null;
        }
    }

    isolated function put(string toolId, ToolMetadata metadata) {
        lock {
            self.cache[toolId] = metadata.clone();
        }
    }
}
final ToolCache toolCache = new ToolCache();

service / on new http:Listener(gatewayPort) {

    resource function get health() returns json {
        return {
            "status": "ok",
            "service": "gateway"
        };
    }

    resource function post tools/[string toolId](http:Request req) returns http:Response {
        // Record start time for latency calculation
        time:Utc startTime = time:utcNow();
        string traceId = uuid:createType1AsString();
        
        // Default identity values for audit (used if auth fails before identity is extracted)
        string auditAgentId = "unknown";
        string auditPrincipal = "unknown";

        // --- AUTHENTICATION ---
        string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
        if authHeader is http:HeaderNotFoundError {
            http:Response r = createErrorResponse(401, "UNAUTHORIZED", "Missing Authorization header");
            int latency = calculateLatencyMs(startTime);
            emitAuditEvent(auditAgentId, auditPrincipal, toolId, 401, "AUTH_FAILURE", latency, traceId);
            return r;
        }

        if !authHeader.startsWith("Bearer ") {
            http:Response r = createErrorResponse(401, "UNAUTHORIZED", "Invalid Authorization header format");
            int latency = calculateLatencyMs(startTime);
            emitAuditEvent(auditAgentId, auditPrincipal, toolId, 401, "AUTH_FAILURE", latency, traceId);
            return r;
        }

        string token = authHeader.substring(7);
        AgentIdentity|error identity = validateToken(token);

        if identity is error {
            http:Response r = createErrorResponse(401, "UNAUTHORIZED", "Invalid or expired token");
            int latency = calculateLatencyMs(startTime);
            emitAuditEvent(auditAgentId, auditPrincipal, toolId, 401, "AUTH_FAILURE", latency, traceId);
            return r;
        }
        
        // Identity extracted — update audit fields
        auditAgentId = identity.agent_id;
        auditPrincipal = identity.principal;

        // --- REGISTRY LOOKUP ---
        ToolMetadata? cachedMetadata = toolCache.get(toolId);
        ToolMetadata metadata;
        
        if cachedMetadata is null {
            GetToolRequest registryReq = {tool_id: toolId};
            GetToolResponse|error registryRes = registryClient->GetTool(registryReq);
            
            if registryRes is error {
                http:Response r = createErrorResponse(500, "REGISTRY_ERROR", "Failed to contact tool registry");
                int latency = calculateLatencyMs(startTime);
                emitAuditEvent(auditAgentId, auditPrincipal, toolId, 500, "REGISTRY_ERROR", latency, traceId);
                return r;
            }
            
            if !registryRes.found {
                http:Response r = createErrorResponse(404, "TOOL_NOT_FOUND", "Unknown tool ID: " + toolId);
                int latency = calculateLatencyMs(startTime);
                emitAuditEvent(auditAgentId, auditPrincipal, toolId, 404, "REGISTRY_ERROR", latency, traceId);
                return r;
            }
            
            ToolMetadata? regMeta = registryRes.metadata;
            if regMeta is null {
                http:Response r = createErrorResponse(500, "REGISTRY_ERROR", "Registry returned found but missing metadata");
                int latency = calculateLatencyMs(startTime);
                emitAuditEvent(auditAgentId, auditPrincipal, toolId, 500, "REGISTRY_ERROR", latency, traceId);
                return r;
            }
            metadata = regMeta;
            toolCache.put(toolId, metadata);
        } else {
            metadata = cachedMetadata;
        }

        // --- AUTHORIZATION ---
        if !hasScope(identity, metadata.required_scope) {
            http:Response r = createErrorResponse(403, "FORBIDDEN", "Insufficient scopes. Required: " + metadata.required_scope);
            int latency = calculateLatencyMs(startTime);
            emitAuditEvent(auditAgentId, auditPrincipal, toolId, 403, "AUTH_FAILURE", latency, traceId);
            return r;
        }

        // --- POLICY CHECK ---
        CheckRequest policyReq = {agent_id: identity.agent_id, tool_id: toolId, cost: 1};
        CheckResponse|error policyRes = policyClient->Check(policyReq);

        if policyRes is error {
            http:Response r = createErrorResponse(503, "SERVICE_UNAVAILABLE", "Policy engine unreachable");
            int latency = calculateLatencyMs(startTime);
            emitAuditEvent(auditAgentId, auditPrincipal, toolId, 503, "POLICY_DENIED", latency, traceId);
            return r;
        } else {
            if !policyRes.allowed {
                http:Response r = createErrorResponse(429, "QUOTA_EXCEEDED", "Agent quota exhausted for tool " + toolId, policyRes.retry_after_ms);
                int latency = calculateLatencyMs(startTime);
                emitAuditEvent(auditAgentId, auditPrincipal, toolId, 429, "POLICY_DENIED", latency, traceId);
                return r;
            }
        }

        // --- DYNAMIC ROUTING ---
        req.setHeader("X-Agent-Id", identity.agent_id);
        req.setHeader("X-Principal", identity.principal);
        
        http:Client|error upstreamClient = clientCache.getClient(metadata.upstream_url);
        if upstreamClient is error {
            http:Response r = createErrorResponse(500, "INTERNAL_ERROR", "Failed to initialize upstream client");
            int latency = calculateLatencyMs(startTime);
            emitAuditEvent(auditAgentId, auditPrincipal, toolId, 500, "UPSTREAM_ERROR", latency, traceId);
            return r;
        }
        
        http:Response|error result = upstreamClient->execute(metadata.http_method, "", req);

        if result is http:Response {
            int latency = calculateLatencyMs(startTime);
            emitAuditEvent(auditAgentId, auditPrincipal, toolId, result.statusCode, "SUCCESS", latency, traceId);
            return result;
        } else {
            http:Response r = createErrorResponse(502, "UPSTREAM_ERROR", "Failed to contact tool service");
            int latency = calculateLatencyMs(startTime);
            emitAuditEvent(auditAgentId, auditPrincipal, toolId, 502, "UPSTREAM_ERROR", latency, traceId);
            return r;
        }
    }
}

isolated function calculateLatencyMs(time:Utc startTime) returns int {
    decimal diff = time:utcDiffSeconds(time:utcNow(), startTime);
    return <int>(diff * 1000);
}

isolated function createErrorResponse(int statusCode, string code, string message, int? retryAfterMs = null) returns http:Response {
    http:Response res = new;
    res.statusCode = statusCode;
    ErrorResponse err = {
        'error: {
            code: code,
            message: message,
            trace_id: uuid:createType1AsString(),
            retry_after_ms: retryAfterMs
        }
    };
    res.setJsonPayload(err.toJson());
    return res;
}

// Fire-and-forget audit emission. Errors are logged but never propagated
// to the caller — audit must not affect request latency or success.
function emitAuditEvent(string agentId, string principal, string toolId,
                        int statusCode, string outcome, int latencyMs, string traceId) {
    AuditEvent event = {
        event_id: uuid:createType1AsString(),
        timestamp: time:utcToString(time:utcNow()),
        agent_id: agentId,
        principal: principal,
        tool_id: toolId,
        status_code: statusCode,
        outcome: outcome,
        latency_ms: latencyMs,
        trace_id: traceId
    };
    AuditAck|error ack = auditClient->RecordEvent(event);
    if ack is error {
        // Log but do not fail the request
        io:println("WARN: audit emission failed: " + ack.message());
    }
}
