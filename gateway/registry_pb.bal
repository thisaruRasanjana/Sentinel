import ballerina/grpc;
import ballerina/protobuf;

public const string REGISTRY_DESC = "0A0E72656769737472792E70726F746F121473656E74696E656C2E72656769737472792E763122290A0E476574546F6F6C5265717565737412170A07746F6F6C5F69641801200128095206746F6F6C496422670A0F476574546F6F6C526573706F6E736512140A05666F756E641801200128085205666F756E64123E0A086D6574616461746118022001280B32222E73656E74696E656C2E72656769737472792E76312E546F6F6C4D6574616461746152086D6574616461746122790A0C546F6F6C4D6574616461746112210A0C757073747265616D5F75726C180120012809520B757073747265616D55726C121F0A0B687474705F6D6574686F64180220012809520A687474704D6574686F6412250A0E72657175697265645F73636F7065180320012809520D726571756972656453636F706532690A0F52656769737472795365727669636512560A07476574546F6F6C12242E73656E74696E656C2E72656769737472792E76312E476574546F6F6C526571756573741A252E73656E74696E656C2E72656769737472792E76312E476574546F6F6C526573706F6E7365423E5A3C6769746875622E636F6D2F74686973617275526173616E6A616E612F53656E74696E656C2F72656769737472792F706B672F72656769737472797631620670726F746F33";

public isolated client class RegistryServiceClient {
    *grpc:AbstractClientEndpoint;

    private final grpc:Client grpcClient;

    public isolated function init(string url, *grpc:ClientConfiguration config) returns grpc:Error? {
        self.grpcClient = check new (url, config);
        check self.grpcClient.initStub(self, REGISTRY_DESC);
    }

    isolated remote function GetTool(GetToolRequest|ContextGetToolRequest req) returns GetToolResponse|grpc:Error {
        map<string|string[]> headers = {};
        GetToolRequest message;
        if req is ContextGetToolRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("sentinel.registry.v1.RegistryService/GetTool", message, headers);
        [anydata, map<string|string[]>] [result, _] = payload;
        return <GetToolResponse>result;
    }

    isolated remote function GetToolContext(GetToolRequest|ContextGetToolRequest req) returns ContextGetToolResponse|grpc:Error {
        map<string|string[]> headers = {};
        GetToolRequest message;
        if req is ContextGetToolRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("sentinel.registry.v1.RegistryService/GetTool", message, headers);
        [anydata, map<string|string[]>] [result, respHeaders] = payload;
        return {content: <GetToolResponse>result, headers: respHeaders};
    }
}

public isolated client class RegistryServiceGetToolResponseCaller {
    private final grpc:Caller caller;

    public isolated function init(grpc:Caller caller) {
        self.caller = caller;
    }

    public isolated function getId() returns int {
        return self.caller.getId();
    }

    isolated remote function sendGetToolResponse(GetToolResponse response) returns grpc:Error? {
        return self.caller->send(response);
    }

    isolated remote function sendContextGetToolResponse(ContextGetToolResponse response) returns grpc:Error? {
        return self.caller->send(response);
    }

    isolated remote function sendError(grpc:Error response) returns grpc:Error? {
        return self.caller->sendError(response);
    }

    isolated remote function complete() returns grpc:Error? {
        return self.caller->complete();
    }

    public isolated function isCancelled() returns boolean {
        return self.caller.isCancelled();
    }
}

public type ContextGetToolRequest record {|
    GetToolRequest content;
    map<string|string[]> headers;
|};

public type ContextGetToolResponse record {|
    GetToolResponse content;
    map<string|string[]> headers;
|};

@protobuf:Descriptor {value: REGISTRY_DESC}
public type ToolMetadata record {|
    string upstream_url = "";
    string http_method = "";
    string required_scope = "";
|};

@protobuf:Descriptor {value: REGISTRY_DESC}
public type GetToolRequest record {|
    string tool_id = "";
|};

@protobuf:Descriptor {value: REGISTRY_DESC}
public type GetToolResponse record {|
    boolean found = false;
    ToolMetadata metadata = {};
|};
