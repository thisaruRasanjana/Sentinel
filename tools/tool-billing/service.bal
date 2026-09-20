import ballerina/http;
import ballerina/uuid;
import ballerina/time;

// In-memory data store for invoices.
// Note: Tool services intentionally use simple error responses rather than the
// gateway's ErrorResponse envelope. They represent downstream enterprise APIs
// that Sentinel governs — their error formats are outside Sentinel's control.
// The gateway is responsible for translating errors into the standard envelope.
map<Invoice> invoices = {};

service / on new http:Listener(7001) {

    // Health check endpoint
    resource function get health() returns json {
        return {
            "status": "ok",
            "service": "tool-billing"
        };
    }

    // Create an invoice
    resource function post invoices(@http:Payload CreateInvoiceRequest req) returns http:Created {
        string newId = uuid:createType1AsString();
        string currentTime = time:utcToString(time:utcNow());

        Invoice newInvoice = {
            id: newId,
            customer: req.customer,
            amount: req.amount,
            currency: req.currency,
            status: "DRAFT",
            created_at: currentTime
        };

        invoices[newId] = newInvoice;

        return {
            body: newInvoice
        };
    }

    // Retrieve an invoice
    resource function get invoices/[string id]() returns Invoice|http:NotFound {
        Invoice? invoice = invoices[id];
        if invoice is Invoice {
            return invoice;
        }
        return {
            body: { "error": "Invoice not found" }
        };
    }
}
