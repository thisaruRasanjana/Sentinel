import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:7001");

@test:Config {}
function testHealthCheck() returns error? {
    json response = check testClient->get("/health");
    test:assertEquals(check response.status, "ok");
    
    test:assertEquals(check response.'service, "tool-billing");
}

@test:Config {}
function testCreateAndRetrieveInvoice() returns error? {
    CreateInvoiceRequest req = {
        customer: "acme-corp",
        amount: 1500.00,
        currency: "USD"
    };

    Invoice createdInvoice = check testClient->post("/invoices", req);
    test:assertEquals(createdInvoice.customer, "acme-corp");
    test:assertEquals(createdInvoice.status, "DRAFT");

    Invoice retrievedInvoice = check testClient->get("/invoices/" + createdInvoice.id);
    test:assertEquals(retrievedInvoice.id, createdInvoice.id);
    test:assertEquals(retrievedInvoice.customer, "acme-corp");
}

@test:Config {}
function testRetrieveNonExistentInvoice() returns error? {
    http:Response response = check testClient->get("/invoices/invalid-id");
    test:assertEquals(response.statusCode, 404);
}
