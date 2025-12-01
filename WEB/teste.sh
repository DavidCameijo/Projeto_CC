#!/bin/bash
BASE=http://localhost:3000

echo "1) Health"
curl -s $BASE/health | jq .

echo "2) Login as admin"
ADMIN_TOKEN=$(curl -s -X POST $BASE/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"adminpassword"}' | jq -r .token)
echo "Admin token: $ADMIN_TOKEN"

echo "3) GET /feriados (admin)"
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" $BASE/feriados | jq .

echo "4) POST /feriados (admin)"
curl -s -X POST $BASE/feriados \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"day":25,"month":12,"description":"Natal Teste"}' | jq .
