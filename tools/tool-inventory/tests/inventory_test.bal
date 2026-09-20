import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:7002");

@test:Config {}
function testHealthCheck() returns error? {
    json response = check testClient->get("/health");
    test:assertEquals(check response.status, "ok");
    test:assertEquals(check response.'service, "tool-inventory");
}

@test:Config {}
function testStockCheckExisting() returns error? {
    StockCheckRequest req = { sku: "WIDGET-001" };
    InventoryItem item = check testClient->post("/inventory/check", req);
    test:assertEquals(item.sku, "WIDGET-001");
    test:assertEquals(item.quantity, 100);
}

@test:Config {}
function testStockCheckNonExisting() returns error? {
    StockCheckRequest req = { sku: "INVALID-SKU" };
    http:Response response = check testClient->post("/inventory/check", req);
    test:assertEquals(response.statusCode, 404);
}

// Fix: Mutating tests have explicit ordering so quantity deltas are predictable.
// Order: testStockUpdatePositive -> testStockUpdateNegative -> testStockUpdateInsufficient
@test:Config {}
function testStockUpdatePositive() returns error? {
    StockUpdateRequest req = { sku: "WIDGET-001", quantity_delta: 20 };
    InventoryItem item = check testClient->post("/inventory/update", req);
    test:assertEquals(item.quantity, 120);
}

@test:Config { dependsOn: [testStockUpdatePositive] }
function testStockUpdateNegative() returns error? {
    StockUpdateRequest req = { sku: "WIDGET-001", quantity_delta: -50 };
    InventoryItem item = check testClient->post("/inventory/update", req);
    // 120 - 50 = 70 (because it runs after the positive update)
    test:assertEquals(item.quantity, 70);
}

@test:Config { dependsOn: [testStockUpdateNegative] }
function testStockUpdateInsufficient() returns error? {
    StockUpdateRequest req = { sku: "WIDGET-001", quantity_delta: -1000 };
    http:Response response = check testClient->post("/inventory/update", req);
    test:assertEquals(response.statusCode, 400);
}
