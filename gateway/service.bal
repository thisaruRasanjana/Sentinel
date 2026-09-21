import ballerina/http;
import ballerina/uuid;

configurable string billingUrl = "http://tool-billing:7001";
configurable string inventoryUrl = "http://tool-inventory:7002";
configurable string policyUrl = "http://policy-engine:9001";
configurable int gatewayPort = 8080;

final http:Client billingClient = check new (billingUrl);
final http:Client inventoryClient = check new (inventoryUrl);
final PolicyServiceClient policyClient = check new (policyUrl);

service / on new http:Listener(gatewayPort) {

    // Health check endpoint — intentionally unauthenticated for load balancer probing.
    resource function get health() returns json {
        return {
            "status": "ok",
            "service": "gateway"
        };
    }

    // Agent-facing tool endpoint.
    // TODO: Phase 4 — Replace hardcoded tool routing with Registry lookup.
    // The Registry will supply upstream_url, method, required_scope, and input_schema.
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

        // --- AUTHORIZATION ---
        string? requiredScope = getRequiredScope(toolId);
        if requiredScope is null {
            return createErrorResponse(404, "TOOL_NOT_FOUND", "Unknown tool ID: " + toolId);
        }

        if !hasScope(identity, requiredScope) {
            return createErrorResponse(403, "FORBIDDEN", "Insufficient scopes. Required: " + requiredScope);
        }

        // --- POLICY CHECK ---
        // TODO: Phase 4 — Pass actual tool cost instead of 1
        CheckRequest policyReq = {agent_id: identity.agent_id, tool_id: toolId, cost: 1};
        CheckResponse|error policyRes = policyClient->Check(policyReq);

        if policyRes is error {
            // Fail closed: if policy engine is down, gateway stops serving requests.
            return createErrorResponse(503, "SERVICE_UNAVAILABLE", "Policy engine unreachable");
        } else {
            if !policyRes.allowed {
                http:Response res = createErrorResponse(429, "QUOTA_EXCEEDED", "Agent quota exhausted for tool " + toolId, policyRes.retry_after_ms);
                return res;
            }
        }

        // --- ROUTING ---
        // TODO: Phase 4 — Forward identity headers (X-Agent-Id, X-Principal) to tool services.
        http:Response|error result;

        if toolId == "invoice.create" {
            result = billingClient->post("/invoices", req);
        } else if toolId == "invoice.get" {
            var reqPayload = req.getJsonPayload();
            if reqPayload is json {
                var idResult = reqPayload.id;
                if idResult is string {
                    result = billingClient->get("/invoices/" + idResult);
                } else {
                    return createErrorResponse(400, "INVALID_REQUEST", "Missing or invalid 'id' parameter");
                }
            } else {
                return createErrorResponse(400, "INVALID_REQUEST", "Invalid JSON payload");
            }
        } else if toolId == "inventory.check" {
            result = inventoryClient->post("/inventory/check", req);
        } else {
            // toolId == "inventory.update" — only reachable tool remaining after auth check
            result = inventoryClient->post("/inventory/update", req);
        }

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
