import ballerina/grpc;
import ballerina/protobuf;

public const string AUDIT_DESC = "0A0B61756469742E70726F746F121173656E74696E656C2E61756469742E7631228C020A0A41756469744576656E7412190A086576656E745F696418012001280952076576656E744964121C0A0974696D657374616D70180220012809520974696D657374616D7012190A086167656E745F696418032001280952076167656E744964121C0A097072696E636970616C18042001280952097072696E636970616C12170A07746F6F6C5F69641805200128095206746F6F6C4964121F0A0B7374617475735F636F6465180620012805520A737461747573436F646512180A076F7574636F6D6518072001280952076F7574636F6D65121D0A0A6C6174656E63795F6D7318082001280352096C6174656E63794D7312190A0874726163655F696418092001280952077472616365496422450A08417564697441636B121A0A08616363657074656418012001280852086163636570746564121D0A0A636861696E5F686173681802200128095209636861696E4861736832590A0C41756469745365727669636512490A0B5265636F72644576656E74121D2E73656E74696E656C2E61756469742E76312E41756469744576656E741A1B2E73656E74696E656C2E61756469742E76312E417564697441636B423D5A3B6769746875622E636F6D2F74686973617275526173616E6A616E612F53656E74696E656C2F61756469742D73696E6B2F706B672F61756469747631620670726F746F33";

public isolated client class AuditServiceClient {
    *grpc:AbstractClientEndpoint;

    private final grpc:Client grpcClient;

    public isolated function init(string url, *grpc:ClientConfiguration config) returns grpc:Error? {
        self.grpcClient = check new (url, config);
        check self.grpcClient.initStub(self, AUDIT_DESC);
    }

    isolated remote function RecordEvent(AuditEvent|ContextAuditEvent req) returns AuditAck|grpc:Error {
        map<string|string[]> headers = {};
        AuditEvent message;
        if req is ContextAuditEvent {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("sentinel.audit.v1.AuditService/RecordEvent", message, headers);
        [anydata, map<string|string[]>] [result, _] = payload;
        return <AuditAck>result;
    }

    isolated remote function RecordEventContext(AuditEvent|ContextAuditEvent req) returns ContextAuditAck|grpc:Error {
        map<string|string[]> headers = {};
        AuditEvent message;
        if req is ContextAuditEvent {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("sentinel.audit.v1.AuditService/RecordEvent", message, headers);
        [anydata, map<string|string[]>] [result, respHeaders] = payload;
        return {content: <AuditAck>result, headers: respHeaders};
    }
}

public isolated client class AuditServiceAuditAckCaller {
    private final grpc:Caller caller;

    public isolated function init(grpc:Caller caller) {
        self.caller = caller;
    }

    public isolated function getId() returns int {
        return self.caller.getId();
    }

    isolated remote function sendAuditAck(AuditAck response) returns grpc:Error? {
        return self.caller->send(response);
    }

    isolated remote function sendContextAuditAck(ContextAuditAck response) returns grpc:Error? {
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

public type ContextAuditAck record {|
    AuditAck content;
    map<string|string[]> headers;
|};

public type ContextAuditEvent record {|
    AuditEvent content;
    map<string|string[]> headers;
|};

@protobuf:Descriptor {value: AUDIT_DESC}
public type AuditAck record {|
    boolean accepted = false;
    string chain_hash = "";
|};

@protobuf:Descriptor {value: AUDIT_DESC}
public type AuditEvent record {|
    string event_id = "";
    string timestamp = "";
    string agent_id = "";
    string principal = "";
    string tool_id = "";
    int status_code = 0;
    string outcome = "";
    int latency_ms = 0;
    string trace_id = "";
|};
