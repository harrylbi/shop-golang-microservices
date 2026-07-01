#!/bin/bash
# =============================================================================
# Skenario 9: Message Publish Failed
# =============================================================================
# Deskripsi:
#   RabbitMQ dimatikan, lalu dicoba publish event via create product.
#   Fokus pada error publish message, bukan connection error.
#
# Ekspektasi Jaeger:
#   - Span dengan error tag berisi "publish" error
#   - Service: product_service
#
# Metrik Prometheus:
#   - http_server_duration_milliseconds_count (error)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/publish-failed.log"
REPEAT="${1:-5}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Skenario 9: Message Publish Failed${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== Message Publish Failed — $(date -Iseconds) ===" > "$LOG_FILE"

# --- Phase 1: Stop RabbitMQ ---
echo -e "${RED}[Phase 1] Menghentikan RabbitMQ...${NC}"
echo "[Phase 1] docker stop rabbitmq" >> "$LOG_FILE"

docker stop rabbitmq 2>&1 | tee -a "$LOG_FILE"
echo -e "${YELLOW}  Menunggu 5 detik...${NC}"
sleep 5

# --- Phase 2: Coba publish via create product ---
echo ""
echo -e "${RED}[Phase 2] Publish message saat RabbitMQ mati${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 2] Publish attempts" >> "$LOG_FILE"

FAIL_COUNT=0

for i in $(seq 1 "$REPEAT"); do
  TIMESTAMP=$(date '+%H:%M:%S')

  RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$PRODUCT_BASE/api/v1/products" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Publish-Fail-$i\",\"description\":\"test publish failed\",\"price\":100,\"inventoryId\":1,\"count\":1}" 2>/dev/null || echo -e "\nHTTP_CODE:000")
  HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
  BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

  echo "[$TIMESTAMP] #$i — HTTP ${HTTP_CODE:-000}" >> "$LOG_FILE"
  echo "  Body: $BODY" >> "$LOG_FILE"

  if [ "${HTTP_CODE:-000}" != "201" ]; then
    echo -e "${RED}  [$TIMESTAMP] #$i — HTTP ${HTTP_CODE:-000} — publish failed ✗${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo -e "${GREEN}  [$TIMESTAMP] #$i — HTTP ${HTTP_CODE:-000} ✓${NC}"
  fi

  sleep 1
done

# --- Phase 3: Start RabbitMQ kembali ---
echo ""
echo -e "${GREEN}[Phase 3] Menyalakan RabbitMQ kembali...${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 3] docker start rabbitmq" >> "$LOG_FILE"

docker start rabbitmq 2>&1 | tee -a "$LOG_FILE"
echo -e "${YELLOW}  Menunggu 15 detik untuk RabbitMQ ready...${NC}"
sleep 15

# --- Phase 4: Verifikasi publish berhasil ---
echo ""
echo -e "${GREEN}[Phase 4] Verifikasi publish berhasil${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 4] Verifikasi publish" >> "$LOG_FILE"

RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$PRODUCT_BASE/api/v1/products" \
  -H "Content-Type: application/json" \
  -d '{"name":"Publish-Recovery","description":"post recovery","price":200,"inventoryId":1,"count":1}' 2>/dev/null || echo -e "\nHTTP_CODE:000")
HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESP" | grep -v "HTTP_CODE:")

if [ "${HTTP_CODE:-000}" = "201" ]; then
  echo -e "${GREEN}  Publish berhasil setelah recovery (HTTP $HTTP_CODE) ✓${NC}"
else
  echo -e "${RED}  Publish masih gagal (HTTP ${HTTP_CODE:-000}) ✗${NC}"
fi
echo "  Recovery: HTTP ${HTTP_CODE:-000}" >> "$LOG_FILE"
echo "  Body: $BODY" >> "$LOG_FILE"

echo "---" >> "$LOG_FILE"
echo "Summary: $FAIL_COUNT / $REPEAT publish failed" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Summary: ${RED}$FAIL_COUNT / $REPEAT${CYAN} publish failed${NC}"
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Cek Jaeger: ${NC}http://localhost:16686  →  Service: product_service  →  Tag: error=true"
