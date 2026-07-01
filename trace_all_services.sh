#!/bin/bash
# =============================================================================
# trace_all_services.sh
# Skrip tracing lengkap untuk semua service dan endpoint
# Jalankan: bash trace_all_services.sh
# =============================================================================

PRODUCT_BASE=http://localhost:5000
IDENTITY_BASE=http://localhost:5002
INVENTORY_BASE=http://localhost:5004

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

sep() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
header() { sep; echo -e "${YELLOW}  $1${NC}"; sep; }

# =============================================================================
# PRODUCT SERVICE  (port 5000)
# =============================================================================
header "PRODUCT SERVICE"

echo -e "\n${GREEN}[1] GET /  (health check)${NC}"
curl -s $PRODUCT_BASE/
echo -e "\n"

echo -e "${GREEN}[2] GET /api/v1/products  (list all products)${NC}"
curl -s "$PRODUCT_BASE/api/v1/products?page=1&size=10"
echo -e "\n"

echo -e "${GREEN}[3] GET /api/v1/products/search?name=laptop  (search)${NC}"
curl -s "$PRODUCT_BASE/api/v1/products/search?name=laptop&page=1&size=10"
echo -e "\n"

echo -e "${GREEN}[4] POST /api/v1/products  (create product)${NC}"
CREATE_RESPONSE=$(curl -s -X POST "$PRODUCT_BASE/api/v1/products" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "RTX 5090",
    "description": "NVIDIA GeForce RTX 5090 - High-end GPU",
    "price": 1500,
    "inventoryId": 1,
    "count": 10
  }')
echo "$CREATE_RESPONSE"
echo -e "\n"

# Ambil ID dari response create, fallback ke ID pertama dari list
PRODUCT_ID=$(echo "$CREATE_RESPONSE" | grep -o '"productId":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$PRODUCT_ID" ]; then
  echo -e "${YELLOW}  [!] Gagal ambil ID dari create, mencoba dari list...${NC}"
  LIST_RESPONSE=$(curl -s "$PRODUCT_BASE/api/v1/products?page=1&size=1")
  PRODUCT_ID=$(echo "$LIST_RESPONSE" | grep -o '"productId":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$PRODUCT_ID" ]; then
  echo -e "${RED}  [!] Tidak ada product ID ditemukan, skip GET/UPDATE/DELETE by ID${NC}"
else
  echo -e "${GREEN}[5] GET /api/v1/products/:id  (get by id: $PRODUCT_ID)${NC}"
  curl -s "$PRODUCT_BASE/api/v1/products/$PRODUCT_ID"
  echo -e "\n"

  echo -e "${GREEN}[6] PUT /api/v1/products/:id  (update product: $PRODUCT_ID)${NC}"
  curl -s -X PUT "$PRODUCT_BASE/api/v1/products/$PRODUCT_ID" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "RTX 5090 Ti",
      "description": "Updated GPU",
      "price": 1700,
      "inventoryId": 1,
      "count": 15
    }'
  echo -e "\n"

  echo -e "${GREEN}[7] DELETE /api/v1/products/:id  (delete product: $PRODUCT_ID)${NC}"
  curl -s -X DELETE "$PRODUCT_BASE/api/v1/products/$PRODUCT_ID"
  echo -e "\n"
fi

# =============================================================================
# IDENTITY SERVICE  (port 5002)
# =============================================================================
header "IDENTITY SERVICE"

echo -e "\n${GREEN}[1] GET /  (health check)${NC}"
curl -s $IDENTITY_BASE/
echo -e "\n"

echo -e "${GREEN}[2] POST /api/v1/users  (register user)${NC}"
TIMESTAMP=$(date +%s)
curl -s -X POST "$IDENTITY_BASE/api/v1/users" \
  -H "Content-Type: application/json" \
  -d "{
    \"firstName\": \"Harry\",
    \"lastName\": \"Tracer\",
    \"userName\": \"tracer_${TIMESTAMP}\",
    \"email\": \"tracer_${TIMESTAMP}@example.com\",
    \"password\": \"Password123!\"
  }"
echo -e "\n"

# =============================================================================
# INVENTORY SERVICE  (port 5004)
# =============================================================================
header "INVENTORY SERVICE"

echo -e "\n${GREEN}[1] GET /  (health check)${NC}"
curl -s $INVENTORY_BASE/
echo -e "\n"

sep
echo -e "${YELLOW}  Selesai — semua endpoint sudah dihit untuk tracing${NC}"
sep
