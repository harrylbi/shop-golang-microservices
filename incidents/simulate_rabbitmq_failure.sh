#!/bin/bash
# =============================================================================
# Skenario 3: RabbitMQ Unreachable
# =============================================================================
# Deskripsi:
#   Menghentikan container RabbitMQ, lalu mencoba create product (yang
#   membutuhkan publish message). Setelah mencatat error, RabbitMQ
#   dinyalakan kembali dan request diulang untuk verifikasi recovery.
#
# Ekspektasi Jaeger:
#   - Span dengan error=true saat RabbitMQ mati
#   - Tag echo-error berisi error publish/connection
#   - Span sukses setelah RabbitMQ recovery
#
# Metrik Prometheus:
#   - http_server_duration_milliseconds_count (error vs success)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/rabbitmq-failure.log"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Skenario 3: RabbitMQ Unreachable${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== RabbitMQ Failure Simulation — $(date -Iseconds) ===" > "$LOG_FILE"

# --- Phase 1: Baseline (RabbitMQ aktif) ---
echo -e "${GREEN}[Phase 1] Baseline — RabbitMQ aktif${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 1] Baseline — RabbitMQ aktif" >> "$LOG_FILE"

BASELINE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$PRODUCT_BASE/api/v1/products" \
  -H "Content-Type: application/json" \
  -d '{"name":"RabbitMQ-Test-Baseline","description":"baseline test","price":100,"inventoryId":1,"count":1}' 2>/dev/null || echo "connection refused")
echo "  Response: $BASELINE" >> "$LOG_FILE"
echo -e "  Response: $(echo "$BASELINE" | head -1)"

sleep 1

# --- Phase 2: Stop RabbitMQ ---
echo ""
echo -e "${RED}[Phase 2] Menghentikan RabbitMQ...${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 2] docker stop rabbitmq" >> "$LOG_FILE"

docker stop rabbitmq 2>&1 | tee -a "$LOG_FILE"
echo -e "${YELLOW}  Menunggu 5 detik agar service mendeteksi disconnect...${NC}"
sleep 5

# --- Phase 3: Request saat RabbitMQ mati ---
echo ""
echo -e "${RED}[Phase 3] Request saat RabbitMQ mati${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 3] Request saat RabbitMQ mati" >> "$LOG_FILE"

for i in $(seq 1 5); do
  TIMESTAMP=$(date '+%H:%M:%S')
  RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$PRODUCT_BASE/api/v1/products" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"RabbitMQ-Fail-$i\",\"description\":\"test saat mq mati\",\"price\":100,\"inventoryId\":1,\"count\":1}" 2>/dev/null || echo "connection refused")
  HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
  BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

  echo "  [$TIMESTAMP] #$i — HTTP ${HTTP_CODE:-000}" >> "$LOG_FILE"
  echo "  Body: $BODY" >> "$LOG_FILE"
  echo -e "${RED}  [$TIMESTAMP] #$i — HTTP ${HTTP_CODE:-000}${NC}"

  sleep 1
done

# --- Phase 4: Start RabbitMQ kembali ---
echo ""
echo -e "${GREEN}[Phase 4] Menyalakan RabbitMQ kembali...${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 4] docker start rabbitmq" >> "$LOG_FILE"

docker start rabbitmq 2>&1 | tee -a "$LOG_FILE"
echo -e "${YELLOW}  Menunggu 15 detik untuk RabbitMQ ready...${NC}"
sleep 15

# --- Phase 5: Verifikasi recovery ---
echo ""
echo -e "${GREEN}[Phase 5] Verifikasi recovery${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 5] Verifikasi recovery" >> "$LOG_FILE"

for i in $(seq 1 3); do
  TIMESTAMP=$(date '+%H:%M:%S')
  RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$PRODUCT_BASE/api/v1/products" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"RabbitMQ-Recovery-$i\",\"description\":\"test setelah mq nyala\",\"price\":200,\"inventoryId\":1,\"count\":1}" 2>/dev/null || echo "connection refused")
  HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
  BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

  echo "  [$TIMESTAMP] #$i — HTTP ${HTTP_CODE:-000}" >> "$LOG_FILE"
  echo "  Body: $BODY" >> "$LOG_FILE"

  if [ "${HTTP_CODE:-000}" = "201" ]; then
    echo -e "${GREEN}  [$TIMESTAMP] #$i — HTTP $HTTP_CODE ✓ (recovered)${NC}"
  else
    echo -e "${RED}  [$TIMESTAMP] #$i — HTTP ${HTTP_CODE:-000} ✗ (belum recover)${NC}"
  fi

  sleep 1
done

echo "" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo -e "${CYAN}Cek Jaeger: ${NC}http://localhost:16686  →  Service: product_service  →  Tag: error=true"
