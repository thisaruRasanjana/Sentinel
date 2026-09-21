public type ErrorDetail record {|
    string code;
    string message;
    string trace_id;
    int? retry_after_ms;
|};

public type ErrorResponse record {|
    ErrorDetail 'error;
|};

public type AgentIdentity record {|
    string agent_id;
    string principal;
    string[] scopes;
|};
