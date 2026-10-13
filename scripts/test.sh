#!/bin/bash
export PATH=$PATH:/Applications/Docker.app/Contents/Resources/bin

# Wait for gateway to be healthy
echo "Waiting for Gateway to be ready..."
until curl -s -f http://localhost:8080/health > /dev/null; do
  sleep 1
done

echo "Gateway is ready!"

# Generate token
echo "Generating token..."
TOKEN=$(curl -s -X POST http://localhost:9000/tokens \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "agent:invoice-assistant", "principal": "user:thisaru", "scopes": ["billing:write", "inventory:read"]}' \
  | jq -r '.token')

if [ -z "$TOKEN" ]; then
    echo "Failed to generate token"
    exit 1
fi

echo "Token generated: $TOKEN"

echo "-------------------------------------"
echo "Testing tool-billing (invoice.create)"
echo "-------------------------------------"
curl -i -X POST http://localhost:8080/tools/invoice.create \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"customer": "acme-corp", "amount": 1500.00, "currency": "USD"}'

echo ""
echo "-------------------------------------"
echo "Testing tool-inventory (inventory.check)"
echo "-------------------------------------"
curl -i -X POST http://localhost:8080/tools/inventory.check \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"sku": "WIDGET-001"}'

echo ""
echo "-------------------------------------"
echo "Verifying audit log"
echo "-------------------------------------"

# Give the audit-sink a moment to flush
sleep 1

# Copy the audit log out of the container
docker compose -f deploy/compose/docker-compose.yml exec -T audit-sink cat /data/audit.jsonl > /tmp/sentinel-audit.jsonl 2>/dev/null

AUDIT_LINES=$(wc -l < /tmp/sentinel-audit.jsonl | tr -d ' ')
echo "Audit log contains $AUDIT_LINES entries"

if [ "$AUDIT_LINES" -lt 2 ]; then
    echo "FAIL: Expected at least 2 audit entries (billing + inventory)"
    exit 1
fi

# Verify hash chaining: second entry's prev_hash should equal first entry's hash
FIRST_HASH=$(head -1 /tmp/sentinel-audit.jsonl | jq -r '.hash')
SECOND_PREV=$(sed -n '2p' /tmp/sentinel-audit.jsonl | jq -r '.prev_hash')

echo "First entry hash:       $FIRST_HASH"
echo "Second entry prev_hash: $SECOND_PREV"

if [ "$FIRST_HASH" = "$SECOND_PREV" ]; then
    echo "PASS: Hash chain is valid"
else
    echo "FAIL: Hash chain is broken"
    exit 1
fi

echo ""
echo "All tests passed!"
