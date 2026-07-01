#!/bin/bash
# =============================================================================
# Skenario 2: High Latency (>2 detik)
# =============================================================================
# Deskripsi:
#   Mengirim request ke endpoint /debug/latency yang menambahkan delay 3-5 detik.
#   Mengukur response time menggunakan curl -w "%{time_total}".
#
# Ekspektasi Jaeger:
#   - Span dengan duration > 3000ms
#   - Span name: GET /debug/latency
#
# Metrik Prometheus:
#   - http_server_duration_milliseconds_bucket (bucket tinggi terisi)
#   - http_server_duration_milliseconds_sum (melonjak)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/latency.log"
REPEAT="${1:-10}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Skenario 2: High Latency Simulation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== High Latency Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
echo "Target: $PRODUCT_BASE/debug/latency" >> "$LOG_FILE"
echo "Repeat: $REPEAT kali" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

TOTAL_TIME=0
SLOW_COUNT=0

for i in $(seq 1 "$REPEAT"); do
  TIMESTAMP=$(date '+%H:%M:%S')

  RESULT=$(curl -s -w "\n%{http_code} %{time_total}" "$PRODUCT_BASE/debug/latency" 2>/dev/null || echo -e "\n000 0.000")
  HTTP_CODE=$(echo "$RESULT" | tail -1 | awk '{print $1}')
  TIME_TOTAL=$(echo "$RESULT" | tail -1 | awk '{print $2}')
  BODY=$(echo "$RESULT" | head -n -1)

  echo "[$TIMESTAMP] Request #$i — HTTP $HTTP_CODE — ${TIME_TOTAL}s" >> "$LOG_FILE"
  echo "  Body: $BODY" >> "$LOG_FILE"

  # Cek apakah slow (> 2 detik)
  IS_SLOW=$(echo "$TIME_TOTAL > 2.0" | bc -l 2>/dev/null || echo "0")
  if [ "$IS_SLOW" = "1" ]; then
    echo -e "${RED}[$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${TIME_TOTAL}s (SLOW ⚠)${NC}"
    SLOW_COUNT=$((SLOW_COUNT + 1))
  else
    echo -e "${GREEN}[$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${TIME_TOTAL}s${NC}"
  fi

  TOTAL_TIME=$(echo "$TOTAL_TIME + $TIME_TOTAL" | bc -l 2>/dev/null || echo "$TOTAL_TIME")
  sleep 0.2
done

AVG_TIME=$(echo "scale=3; $TOTAL_TIME / $REPEAT" | bc -l 2>/dev/null || echo "N/A")

echo "---" >> "$LOG_FILE"
echo "Summary:" >> "$LOG_FILE"
echo "  Slow requests (>2s): $SLOW_COUNT / $REPEAT" >> "$LOG_FILE"
echo "  Average response time: ${AVG_TIME}s" >> "$LOG_FILE"
echo "  Total time: ${TOTAL_TIME}s" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Summary:${NC}"
echo -e "  Slow requests (>2s): ${RED}$SLOW_COUNT / $REPEAT${NC}"
echo -e "  Average response time: ${YELLOW}${AVG_TIME}s${NC}"
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Cek Jaeger: ${NC}http://localhost:16686  →  Service: product_service  →  Min Duration: 3s"
