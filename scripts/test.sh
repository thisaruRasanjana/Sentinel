#!/bin/bash

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
