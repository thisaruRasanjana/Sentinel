import ballerina/http;
import ballerina/uuid;

configurable string policyUrl = "http://policy-engine:9001";
configurable string registryUrl = "http://registry:9002";
configurable int gatewayPort = 8080;

final PolicyServiceClient policyClient = check new (policyUrl);
final RegistryServiceClient registryClient = check new (registryUrl);

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

        // --- AUTHENTICATION ---
        string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
        if authHeader is http:HeaderNotFoundError {
            return createErrorResponse(401, "UNAUTHORIZED", "Missing Authorization header");
        }

        if !authHeader.startsWith("Bearer ") {
            return createErrorResponse(401, "UNAUTHORIZED", "Invalid Authorization header format");
        }

        string token = authHeader.substring(7);
        AgentIdentity|error identity = validateToken(token);

        if identity is error {
            return createErrorResponse(401, "UNAUTHORIZED", "Invalid or expired token");
        }

        // --- REGISTRY LOOKUP ---
        ToolMetadata? cachedMetadata = toolCache.get(toolId);
        ToolMetadata metadata;
        
        if cachedMetadata is null {
            GetToolRequest registryReq = {tool_id: toolId};
            GetToolResponse|error registryRes = registryClient->GetTool(registryReq);
            
            if registryRes is error {
                return createErrorResponse(500, "REGISTRY_ERROR", "Failed to contact tool registry");
            }
            
            if !registryRes.found {
                return createErrorResponse(404, "TOOL_NOT_FOUND", "Unknown tool ID: " + toolId);
            }
            
            ToolMetadata? regMeta = registryRes.metadata;
            if regMeta is null {
                return createErrorResponse(500, "REGISTRY_ERROR", "Registry returned found but missing metadata");
            }
            metadata = regMeta;
            toolCache.put(toolId, metadata);
        } else {
            metadata = cachedMetadata;
        }

        // --- AUTHORIZATION ---
        if !hasScope(identity, metadata.required_scope) {
            return createErrorResponse(403, "FORBIDDEN", "Insufficient scopes. Required: " + metadata.required_scope);
        }

        // --- POLICY CHECK ---
        CheckRequest policyReq = {agent_id: identity.agent_id, tool_id: toolId, cost: 1};
        CheckResponse|error policyRes = policyClient->Check(policyReq);

        if policyRes is error {
            return createErrorResponse(503, "SERVICE_UNAVAILABLE", "Policy engine unreachable");
        } else {
            if !policyRes.allowed {
                return createErrorResponse(429, "QUOTA_EXCEEDED", "Agent quota exhausted for tool " + toolId, policyRes.retry_after_ms);
            }
        }

        // --- DYNAMIC ROUTING ---
        // Forward Identity Headers
        req.setHeader("X-Agent-Id", identity.agent_id);
        req.setHeader("X-Principal", identity.principal);
        
        http:Client|error upstreamClient = clientCache.getClient(metadata.upstream_url);
        if upstreamClient is error {
            return createErrorResponse(500, "INTERNAL_ERROR", "Failed to initialize upstream client");
        }
        
        http:Response|error result;
        
        // Use execute method for dynamic HTTP methods
        result = upstreamClient->execute(metadata.http_method, "", req);

        if result is http:Response {
            return result;
        } else {
            return createErrorResponse(502, "UPSTREAM_ERROR", "Failed to contact tool service");
        }
    }
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
