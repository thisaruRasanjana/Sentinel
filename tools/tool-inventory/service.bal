import ballerina/http;

// In-memory data store for inventory.
// Note: Tool services intentionally use simple error responses rather than the
// gateway's ErrorResponse envelope. They represent downstream enterprise APIs
// that Sentinel governs — their error formats are outside Sentinel's control.
// The gateway is responsible for translating errors into the standard envelope.
map<InventoryItem> inventoryStore = {
    "WIDGET-001": { sku: "WIDGET-001", name: "Premium Widget", quantity: 100, warehouse: "WH-A" },
    "GADGET-002": { sku: "GADGET-002", name: "Basic Gadget", quantity: 50, warehouse: "WH-B" }
};

service / on new http:Listener(7002) {

    // Health check endpoint
    resource function get health() returns json {
        return {
            "status": "ok",
            "service": "tool-inventory"
        };
    }

    // Check stock for a SKU
    resource function post inventory/'check(@http:Payload StockCheckRequest req) returns InventoryItem|http:NotFound {
        InventoryItem? item = inventoryStore[req.sku];
        if item is InventoryItem {
            return item;
        }
        return <http:NotFound>{
            body: { "error": "SKU not found" }
        };
    }

    // Update stock for a SKU
    resource function post inventory/update(@http:Payload StockUpdateRequest req) returns InventoryItem|http:NotFound|http:BadRequest {
        InventoryItem? item = inventoryStore[req.sku];
        if item is InventoryItem {
            if item.quantity + req.quantity_delta < 0 {
                return <http:BadRequest>{
                    body: { "error": "Insufficient stock" }
                };
            }
            item.quantity += req.quantity_delta;
            inventoryStore[req.sku] = item;
            return item;
        }
        return <http:NotFound>{
            body: { "error": "SKU not found" }
        };
    }
}
