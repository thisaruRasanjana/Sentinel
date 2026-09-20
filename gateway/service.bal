import ballerina/http;
import ballerina/uuid;

configurable string billingUrl = "http://tool-billing:7001";
configurable string inventoryUrl = "http://tool-inventory:7002";
configurable int gatewayPort = 8080;

final http:Client billingClient = check new (billingUrl);
final http:Client inventoryClient = check new (inventoryUrl);

service / on new http:Listener(gatewayPort) {

    // Health check endpoint
    resource function get health() returns json {
        return {
            "status": "ok",
            "service": "gateway"
        };
    }

    // Agent-facing tool endpoint
    // TODO: Phase 4 — Replace hardcoded tool routing with Registry lookup.
    // The Registry will supply upstream_url, method, required_scope, and input_schema.
    resource function post tools/[string toolId](http:Request req) returns http:Response {
        http:Response|error result;

        if toolId == "invoice.create" {
            result = billingClient->post("/invoices", req);
        } else if toolId == "invoice.get" {
            var payload = req.getJsonPayload();
            if payload is json {
                var idResult = payload.id;
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
        } else if toolId == "inventory.update" {
            result = inventoryClient->post("/inventory/update", req);
        } else {
            return createErrorResponse(404, "TOOL_NOT_FOUND", "Unknown tool ID: " + toolId);
        }

        if result is http:Response {
            return result;
        } else {
            return createErrorResponse(502, "UPSTREAM_ERROR", "Failed to contact tool service");
        }
    }
}

isolated function createErrorResponse(int statusCode, string code, string message) returns http:Response {
    http:Response res = new;
    res.statusCode = statusCode;
    ErrorResponse err = {
        'error: {
            code: code,
            message: message,
            trace_id: uuid:createType1AsString(),
            retry_after_ms: null
        }
    };
    res.setJsonPayload(err.toJson());
    return res;
}
