import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:8080");

@test:Config {}
function testHealthCheck() returns error? {
    json response = check testClient->get("/health");
    test:assertEquals(check response.status, "ok");
    test:assertEquals(check response.'service, "gateway");
}

@test:Config {}
function testUnknownToolId() returns error? {
    http:Response response = check testClient->post("/tools/unknown.tool", {});
    test:assertEquals(response.statusCode, 404);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, "TOOL_NOT_FOUND");
}
