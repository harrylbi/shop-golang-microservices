#!/bin/bash
# =============================================================================
# Skenario 4: Database Timeout
# =============================================================================
# Deskripsi:
#   Mengirim request ke endpoint /debug/db-timeout yang menjalankan
#   SELECT pg_sleep(5) untuk mensimulasikan query lambat.
#
# Ekspektasi Jaeger:
#   - Span dengan duration > 5000ms
#   - Span name: GET /debug/db-timeout
#   - Jika ada context timeout, span akan error
#
# Metrik Prometheus:
#   - http_server_duration_milliseconds_bucket (bucket >5s terisi)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/db-timeout.log"
REPEAT="${1:-5}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Skenario 4: Database Timeout Simulation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== Database Timeout Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
echo "Target: $PRODUCT_BASE/debug/db-timeout" >> "$LOG_FILE"
echo "Repeat: $REPEAT kali" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

TIMEOUT_COUNT=0

for i in $(seq 1 "$REPEAT"); do
  TIMESTAMP=$(date '+%H:%M:%S')

  RESULT=$(curl -s -w "\n%{http_code} %{time_total}" --max-time 30 "$PRODUCT_BASE/debug/db-timeout" 2>/dev/null || echo -e "\n000 0.000")
  HTTP_CODE=$(echo "$RESULT" | tail -1 | awk '{print $1}')
  TIME_TOTAL=$(echo "$RESULT" | tail -1 | awk '{print $2}')
  BODY=$(echo "$RESULT" | head -n -1)

  echo "[$TIMESTAMP] Request #$i — HTTP $HTTP_CODE — ${TIME_TOTAL}s" >> "$LOG_FILE"
  echo "  Body: $BODY" >> "$LOG_FILE"

  IS_TIMEOUT=$(echo "$TIME_TOTAL > 4.0" | bc -l 2>/dev/null || echo "0")
  if [ "$IS_TIMEOUT" = "1" ]; then
    echo -e "${RED}[$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${TIME_TOTAL}s (DB SLOW ⚠)${NC}"
    TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
  else
    echo -e "${GREEN}[$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${TIME_TOTAL}s${NC}"
  fi

  sleep 1
done

echo "---" >> "$LOG_FILE"
echo "Summary: $TIMEOUT_COUNT / $REPEAT requests experienced DB delay" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Summary: ${RED}$TIMEOUT_COUNT / $REPEAT${CYAN} requests experienced DB delay (>4s)${NC}"
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Cek Jaeger: ${NC}http://localhost:16686  →  Service: product_service  →  Min Duration: 5s"
