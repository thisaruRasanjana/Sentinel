import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:9000");

@test:Config {}
function testTokenIssuance() returns error? {
    TokenRequest req = {
        agent_id: "agent:test",
        principal: "user:test",
        scopes: ["billing:read"]
    };

    TokenResponse response = check testClient->post("/tokens", req);
    test:assertTrue(response.token.length() > 0, "Token should not be empty");
    test:assertEquals(response.agent_id, "agent:test");
    test:assertEquals(response.expires_in, 3600);
}

@test:Config {}
function testMissingScopes() returns error? {
    TokenRequest req = {
        agent_id: "agent:test2",
        principal: "user:test2",
        scopes: []
    };

    TokenResponse response = check testClient->post("/tokens", req);
    test:assertTrue(response.token.length() > 0, "Token should be issued even without scopes");
    test:assertEquals(response.agent_id, "agent:test2");
}

@test:Config {}
function testEmptyAgentId() returns error? {
    TokenRequest req = {
        agent_id: "",
        principal: "user:test3",
        scopes: ["billing:read"]
    };

    TokenResponse response = check testClient->post("/tokens", req);
    test:assertTrue(response.token.length() > 0, "Token should be issued");
    test:assertEquals(response.agent_id, "");
}
