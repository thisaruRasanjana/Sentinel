import ballerina/grpc;
import ballerina/protobuf;

public const string POLICY_DESC = "0A0C706F6C6963792E70726F746F121273656E74696E656C2E706F6C6963792E763122560A0C436865636B5265717565737412190A086167656E745F696418012001280952076167656E74496412170A07746F6F6C5F69641802200128095206746F6F6C496412120A04636F73741803200128055204636F7374226D0A0D436865636B526573706F6E736512180A07616C6C6F7765641801200128085207616C6C6F776564121C0A0972656D61696E696E67180220012805520972656D61696E696E6712240A0E72657472795F61667465725F6D73180320012803520C726574727941667465724D73325D0A0D506F6C69637953657276696365124C0A05436865636B12202E73656E74696E656C2E706F6C6963792E76312E436865636B526571756573741A212E73656E74696E656C2E706F6C6963792E76312E436865636B526573706F6E736542415A3F6769746875622E636F6D2F74686973617275526173616E6A616E612F53656E74696E656C2F706F6C6963792D656E67696E652F706B672F706F6C6963797631620670726F746F33";

public isolated client class PolicyServiceClient {
    *grpc:AbstractClientEndpoint;

    private final grpc:Client grpcClient;

    public isolated function init(string url, *grpc:ClientConfiguration config) returns grpc:Error? {
        self.grpcClient = check new (url, config);
        check self.grpcClient.initStub(self, POLICY_DESC);
    }

    isolated remote function Check(CheckRequest|ContextCheckRequest req) returns CheckResponse|grpc:Error {
        map<string|string[]> headers = {};
        CheckRequest message;
        if req is ContextCheckRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("sentinel.policy.v1.PolicyService/Check", message, headers);
        [anydata, map<string|string[]>] [result, _] = payload;
        return <CheckResponse>result;
    }

    isolated remote function CheckContext(CheckRequest|ContextCheckRequest req) returns ContextCheckResponse|grpc:Error {
        map<string|string[]> headers = {};
        CheckRequest message;
        if req is ContextCheckRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("sentinel.policy.v1.PolicyService/Check", message, headers);
        [anydata, map<string|string[]>] [result, respHeaders] = payload;
        return {content: <CheckResponse>result, headers: respHeaders};
    }
}

public type ContextCheckResponse record {|
    CheckResponse content;
    map<string|string[]> headers;
|};

public type ContextCheckRequest record {|
    CheckRequest content;
    map<string|string[]> headers;
|};

@protobuf:Descriptor {value: POLICY_DESC}
public type CheckResponse record {|
    boolean allowed = false;
    int remaining = 0;
    int retry_after_ms = 0;
|};

@protobuf:Descriptor {value: POLICY_DESC}
public type CheckRequest record {|
    string agent_id = "";
    string tool_id = "";
    int cost = 0;
|};
