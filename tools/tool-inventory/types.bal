public type InventoryItem record {|
    string sku;
    string name;
    int quantity;
    string warehouse;
|};

public type StockCheckRequest record {|
    string sku;
|};

public type StockUpdateRequest record {|
    string sku;
    int quantity_delta;
|};
