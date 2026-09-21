import ballerina/http;
import ballerina/jwt;
import ballerina/uuid;

configurable string keystorePath = "./resources/keystore.p12";
configurable string keystorePassword = "ballerina";
configurable string keyAlias = "sentinel";
configurable string keyPassword = "ballerina";
configurable int tokenTtlSeconds = 3600;

service / on new http:Listener(9000) {

    resource function post tokens(@http:Payload TokenRequest req) returns TokenResponse|http:InternalServerError {

        jwt:IssuerConfig issuerConfig = {
            issuer: "sentinel",
            audience: "sentinel-gateway",
            expTime: <decimal>tokenTtlSeconds,
            customClaims: {
                "principal": req.principal,
                "scopes": req.scopes
            },
            signatureConfig: {
                config: {
                    keyStore: {
                        path: keystorePath,
                        password: keystorePassword
                    },
                    keyAlias: keyAlias,
                    keyPassword: keyPassword
                }
            }
        };

        // sub claim is set via the username field in IssuerConfig
        issuerConfig.username = req.agent_id;
        issuerConfig.jwtId = uuid:createType1AsString();

        string|error jwtToken = jwt:issue(issuerConfig);

        if jwtToken is string {
            return {
                token: jwtToken,
                expires_in: tokenTtlSeconds,
                agent_id: req.agent_id
            };
        } else {
            return {
                body: "Failed to issue token: " + jwtToken.message()
            };
        }
    }
}
