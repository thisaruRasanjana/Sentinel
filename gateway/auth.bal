import ballerina/jwt;

configurable string certFile = "../token-issuer/resources/public.crt";

// validateToken verifies the JWT signature and standard claims, then extracts
// the agent identity. Returning a domain type (AgentIdentity) rather than
// jwt:Payload keeps service.bal decoupled from the JWT library.
public isolated function validateToken(string token) returns AgentIdentity|error {
    jwt:ValidatorConfig validatorConfig = {
        issuer: "sentinel",
        audience: "sentinel-gateway",
        signatureConfig: {
            certFile: certFile
        }
    };

    jwt:Payload payload = check jwt:validate(token, validatorConfig);

    // Extract agent_id from the standard 'sub' claim
    string agentId = payload.sub ?: "unknown";

    // Extract custom claims
    var principalClaim = payload["principal"];
    string principal = principalClaim is string ? principalClaim : "unknown";

    var scopesClaim = payload["scopes"];
    string[] scopes = [];
    if scopesClaim is json[] {
        foreach var s in scopesClaim {
            if s is string {
                scopes.push(s);
            }
        }
    }

    return {
        agent_id: agentId,
        principal: principal,
        scopes: scopes
    };
}

public isolated function getRequiredScope(string toolId) returns string? {
    match toolId {
        "invoice.create"   => { return "billing:write"; }
        "invoice.get"      => { return "billing:read"; }
        "inventory.check"  => { return "inventory:read"; }
        "inventory.update" => { return "inventory:write"; }
        _                  => { return null; }
    }
}

public isolated function hasScope(AgentIdentity identity, string requiredScope) returns boolean {
    return identity.scopes.some(isolated function(string s) returns boolean {
        return s == requiredScope;
    });
}
