public type TokenRequest record {|
    string agent_id;
    string principal;
    string[] scopes;
|};

public type TokenResponse record {|
    string token;
    int expires_in;
    string agent_id;
|};
