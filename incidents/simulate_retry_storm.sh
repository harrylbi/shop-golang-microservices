#!/bin/bash
# =============================================================================
# Skenario 8: Retry Storm
# =============================================================================
# Deskripsi:
#   Mensimulasikan retry storm — mengirim banyak request paralel ke endpoint
#   yang gagal (RabbitMQ mati) sehingga menghasilkan lonjakan jumlah trace
#   di Jaeger dan peningkatan metrik error.
#
# Ekspektasi Jaeger:
#   - Lonjakan jumlah trace dalam waktu singkat
#   - Banyak trace dengan error=true
#
# Metrik Prometheus:
#   - http_server_duration_milliseconds_count (spike drastis)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/retry-storm.log"
PARALLEL="${1:-10}"
ROUNDS="${2:-5}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Skenario 8: Retry Storm Simulation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== Retry Storm Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
echo "Parallel: $PARALLEL requests per round" >> "$LOG_FILE"
echo "Rounds: $ROUNDS" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# --- Phase 1: Stop RabbitMQ untuk memicu error ---
echo -e "${RED}[Phase 1] Menghentikan RabbitMQ...${NC}"
echo "[Phase 1] docker stop rabbitmq" >> "$LOG_FILE"

docker stop rabbitmq 2>&1 | tee -a "$LOG_FILE"
echo -e "${YELLOW}  Menunggu 5 detik...${NC}"
sleep 5

# --- Phase 2: Retry storm ---
echo ""
echo -e "${RED}[Phase 2] Retry storm — $PARALLEL parallel x $ROUNDS rounds${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 2] Retry storm" >> "$LOG_FILE"

TOTAL_REQUESTS=0
TOTAL_ERRORS=0

for round in $(seq 1 "$ROUNDS"); do
  TIMESTAMP=$(date '+%H:%M:%S')
  echo -e "${YELLOW}  Round $round/$ROUNDS — $PARALLEL parallel requests${NC}"
  echo "  Round $round — $(date -Iseconds)" >> "$LOG_FILE"

  ROUND_ERRORS=0
  for j in $(seq 1 "$PARALLEL"); do
    (
      RESP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -X POST "$PRODUCT_BASE/api/v1/products" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"Retry-Storm-R${round}-${j}\",\"description\":\"storm test\",\"price\":100,\"inventoryId\":1,\"count\":1}" 2>/dev/null || echo "000")
      echo "    [R$round-$j] HTTP $RESP" >> "$LOG_FILE"
      if [ "$RESP" != "201" ]; then
        echo "ERROR" >> "$LOG_DIR/.storm_errors_$$"
      fi
    ) &
  done
  wait

  # Count errors from this round
  if [ -f "$LOG_DIR/.storm_errors_$$" ]; then
    ROUND_ERRORS=$(wc -l < "$LOG_DIR/.storm_errors_$$" 2>/dev/null || echo "0")
    TOTAL_ERRORS=$((TOTAL_ERRORS + ROUND_ERRORS))
    rm -f "$LOG_DIR/.storm_errors_$$"
  fi

  TOTAL_REQUESTS=$((TOTAL_REQUESTS + PARALLEL))
  echo -e "${RED}    Round $round: $ROUND_ERRORS/$PARALLEL errors${NC}"
  echo "    Round $round errors: $ROUND_ERRORS/$PARALLEL" >> "$LOG_FILE"

  sleep 1
done

# --- Phase 3: Start RabbitMQ kembali ---
echo ""
echo -e "${GREEN}[Phase 3] Menyalakan RabbitMQ kembali...${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 3] docker start rabbitmq" >> "$LOG_FILE"

docker start rabbitmq 2>&1 | tee -a "$LOG_FILE"
sleep 10

echo "" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"
echo "Summary:" >> "$LOG_FILE"
echo "  Total requests: $TOTAL_REQUESTS" >> "$LOG_FILE"
echo "  Total errors: $TOTAL_ERRORS" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Summary:${NC}"
echo -e "  Total requests: ${YELLOW}$TOTAL_REQUESTS${NC}"
echo -e "  Total errors: ${RED}$TOTAL_ERRORS${NC}"
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Cek Jaeger: ${NC}http://localhost:16686  →  Service: product_service  →  Lookback: Last 5 Minutes"
echo -e "${CYAN}  Perhatikan lonjakan jumlah trace dan banyaknya error span${NC}"
