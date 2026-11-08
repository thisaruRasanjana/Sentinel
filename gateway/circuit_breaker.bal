import ballerina/http;

// Configurable resilience parameters (overridable via Config.toml / BAL_CONFIG_DATA)
configurable decimal upstreamTimeoutSeconds = 5.0;
configurable decimal cbResetTimeSeconds = 15.0;
configurable float cbFailureThreshold = 0.5;
configurable decimal cbRollingWindowSeconds = 60.0;
configurable decimal cbBucketSizeSeconds = 10.0;
configurable int cbRequestVolumeThreshold = 5;

// Gateway Prometheus-style metrics counters.
// Ballerina does not have a native Prometheus client library, so we expose
// counters as JSON on a /metrics-compatible endpoint. These are module-level
// mutable variables protected by lock blocks in the isolated class.
isolated class GatewayMetrics {
    private int totalRequests = 0;
    private int totalErrors = 0;
    private int totalTimeouts = 0;
    private int totalCircuitOpen = 0;
    private int totalSuccess = 0;
    private int totalAuthFailures = 0;
    private int totalPolicyDenied = 0;
    private int totalRegistryErrors = 0;
    private int totalUpstreamErrors = 0;

    isolated function incRequests() {
        lock {
            self.totalRequests += 1;
        }
    }

    isolated function incSuccess() {
        lock {
            self.totalSuccess += 1;
        }
    }

    isolated function incErrors() {
        lock {
            self.totalErrors += 1;
        }
    }

    isolated function incTimeouts() {
        lock {
            self.totalTimeouts += 1;
        }
    }

    isolated function incCircuitOpen() {
        lock {
            self.totalCircuitOpen += 1;
        }
    }

    isolated function incAuthFailures() {
        lock {
            self.totalAuthFailures += 1;
        }
    }

    isolated function incPolicyDenied() {
        lock {
            self.totalPolicyDenied += 1;
        }
    }

    isolated function incRegistryErrors() {
        lock {
            self.totalRegistryErrors += 1;
        }
    }

    isolated function incUpstreamErrors() {
        lock {
            self.totalUpstreamErrors += 1;
        }
    }

    // Returns Prometheus text exposition format
    isolated function toPrometheusText() returns string {
        lock {
            string[] lines = [];
            lines.push("# HELP sentinel_gateway_requests_total Total gateway requests.");
            lines.push("# TYPE sentinel_gateway_requests_total counter");
            lines.push("sentinel_gateway_requests_total " + self.totalRequests.toString());
            lines.push("# HELP sentinel_gateway_success_total Total successful gateway requests.");
            lines.push("# TYPE sentinel_gateway_success_total counter");
            lines.push("sentinel_gateway_success_total " + self.totalSuccess.toString());
            lines.push("# HELP sentinel_gateway_errors_total Total gateway errors.");
            lines.push("# TYPE sentinel_gateway_errors_total counter");
            lines.push("sentinel_gateway_errors_total " + self.totalErrors.toString());
            lines.push("# HELP sentinel_gateway_timeouts_total Total upstream timeout errors.");
            lines.push("# TYPE sentinel_gateway_timeouts_total counter");
            lines.push("sentinel_gateway_timeouts_total " + self.totalTimeouts.toString());
            lines.push("# HELP sentinel_gateway_circuit_open_total Total requests rejected by open circuit breaker.");
            lines.push("# TYPE sentinel_gateway_circuit_open_total counter");
            lines.push("sentinel_gateway_circuit_open_total " + self.totalCircuitOpen.toString());
            lines.push("# HELP sentinel_gateway_auth_failures_total Total authentication failures.");
            lines.push("# TYPE sentinel_gateway_auth_failures_total counter");
            lines.push("sentinel_gateway_auth_failures_total " + self.totalAuthFailures.toString());
            lines.push("# HELP sentinel_gateway_policy_denied_total Total policy denied requests.");
            lines.push("# TYPE sentinel_gateway_policy_denied_total counter");
            lines.push("sentinel_gateway_policy_denied_total " + self.totalPolicyDenied.toString());
            lines.push("# HELP sentinel_gateway_registry_errors_total Total registry lookup errors.");
            lines.push("# TYPE sentinel_gateway_registry_errors_total counter");
            lines.push("sentinel_gateway_registry_errors_total " + self.totalRegistryErrors.toString());
            lines.push("# HELP sentinel_gateway_upstream_errors_total Total upstream call errors.");
            lines.push("# TYPE sentinel_gateway_upstream_errors_total counter");
            lines.push("sentinel_gateway_upstream_errors_total " + self.totalUpstreamErrors.toString());
            return string:'join("\n", ...lines) + "\n";
        }
    }
}

final GatewayMetrics gatewayMetrics = new GatewayMetrics();

// ResilientClientCache creates http:Client instances with circuit breaker + timeout config.
isolated class ResilientClientCache {
    private map<http:Client> clients = {};

    isolated function getClient(string url) returns http:Client|error {
        lock {
            if self.clients.hasKey(url) {
                return self.clients.get(url);
            }
            http:Client newClient = check new (url, {
                timeout: upstreamTimeoutSeconds,
                circuitBreaker: {
                    rollingWindow: {
                        timeWindow: cbRollingWindowSeconds,
                        bucketSize: cbBucketSizeSeconds,
                        requestVolumeThreshold: cbRequestVolumeThreshold
                    },
                    failureThreshold: cbFailureThreshold,
                    resetTime: cbResetTimeSeconds,
                    statusCodes: [500, 502, 503, 504]
                }
            });
            self.clients[url] = newClient;
            return newClient;
        }
    }
}

// Detect if an error is a timeout error by checking the error message.
// Ballerina http:Client returns errors with "timed out" or "Idle timeout" in the message.
isolated function isTimeoutError(error err) returns boolean {
    string msg = err.message().toLowerAscii();
    return msg.includes("timed out") || msg.includes("idle timeout") || msg.includes("timeout");
}

// Detect if an error is a circuit breaker rejection.
// Ballerina http:Client returns errors with "circuit breaker" in the message when the circuit is open.
isolated function isCircuitBreakerOpen(error err) returns boolean {
    string msg = err.message().toLowerAscii();
    return msg.includes("circuit breaker") || msg.includes("upstream unavailable");
}
