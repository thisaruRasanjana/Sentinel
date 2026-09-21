import ballerina/http;
import ballerina/test;
import ballerina/jwt;
import ballerina/uuid;

http:Client testClient = check new ("http://localhost:8080");

function generateTestToken(string agentId, string[] scopes, int ttlSeconds) returns string|error {
    jwt:IssuerConfig issuerConfig = {
        username: agentId,
        issuer: "sentinel",
        audience: "sentinel-gateway",
        expTime: <decimal>ttlSeconds,
        jwtId: uuid:createType1AsString(),
        customClaims: {
            "principal": "user:test",
            "scopes": scopes
        },
        signatureConfig: {
            config: {
                keyStore: {
                    path: "../token-issuer/resources/keystore.p12",
                    password: "ballerina"
                },
                keyAlias: "sentinel",
                keyPassword: "ballerina"
            }
        }
    };
    return jwt:issue(issuerConfig);
}

@test:Config {}
function testHealthCheck() returns error? {
    json response = check testClient->get("/health");
    test:assertEquals(check response.status, "ok");
    test:assertEquals(check response.'service, "gateway");
}

@test:Config {}
function testNoAuthHeader() returns error? {
    http:Response response = check testClient->post("/tools/invoice.create", {});
    test:assertEquals(response.statusCode, 401);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, "UNAUTHORIZED");
}

@test:Config {}
function testInvalidToken() returns error? {
    http:Request req = new;
    req.setHeader("Authorization", "Bearer invalid.token.string");
    http:Response response = check testClient->post("/tools/invoice.create", req);
    test:assertEquals(response.statusCode, 401);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, "UNAUTHORIZED");
}

@test:Config {}
function testExpiredToken() returns error? {
    string expiredToken = check generateTestToken("agent:test", ["billing:write"], -3600);
    
    http:Request req = new;
    req.setHeader("Authorization", "Bearer " + expiredToken);
    http:Response response = check testClient->post("/tools/invoice.create", req);
    test:assertEquals(response.statusCode, 401);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, "UNAUTHORIZED");
}

@test:Config {}
function testValidTokenCorrectScope() returns error? {
    string token = check generateTestToken("agent:test", ["billing:write"], 3600);
    
    http:Request req = new;
    req.setHeader("Authorization", "Bearer " + token);
    req.setJsonPayload({ "customer": "test", "amount": 100.0, "currency": "USD" });
    
    http:Response response = check testClient->post("/tools/invoice.create", req);
    // Should get a 201 from the billing service or 502 if backend is down, but NOT 401/403
    test:assertTrue(response.statusCode == 201 || response.statusCode == 502, "Should pass auth");
}

@test:Config {}
function testValidTokenWrongScope() returns error? {
    string token = check generateTestToken("agent:test", ["billing:read"], 3600);
    
    http:Request req = new;
    req.setHeader("Authorization", "Bearer " + token);
    req.setJsonPayload({ "customer": "test", "amount": 100.0, "currency": "USD" });
    
    http:Response response = check testClient->post("/tools/invoice.create", req);
    test:assertEquals(response.statusCode, 403);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, "FORBIDDEN");
}
