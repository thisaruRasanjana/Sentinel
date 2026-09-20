public type Invoice record {|
    string id;
    string customer;
    decimal amount;
    string currency;
    string status;
    string created_at;
|};

public type CreateInvoiceRequest record {|
    string customer;
    decimal amount;
    string currency;
|};
