#!/bin/bash
# =============================================================================
# Skenario 1: HTTP 500 Internal Server Error
# =============================================================================
# Deskripsi:
#   Mengirim request ke endpoint /debug/error yang mengembalikan HTTP 500.
#   Menghasilkan error span di Jaeger dan increment metrik error di Prometheus.
#
# Ekspektasi Jaeger:
#   - Span dengan tag otel.status_code=ERROR dan status-code=500
#   - Tag echo-error berisi "simulated internal server error"
#
# Metrik Prometheus:
#   - http_server_duration_milliseconds_count (bertambah)
#   - http_server_duration_milliseconds_bucket (label http.status_code=500)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/incident-http500.log"
REPEAT="${1:-10}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Skenario 1: HTTP 500 Internal Server Error${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== HTTP 500 Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
echo "Target: $PRODUCT_BASE/debug/error" >> "$LOG_FILE"
echo "Repeat: $REPEAT kali" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

ERROR_COUNT=0

for i in $(seq 1 "$REPEAT"); do
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$PRODUCT_BASE/debug/error" 2>/dev/null || echo "000")
  BODY=$(curl -s "$PRODUCT_BASE/debug/error" 2>/dev/null || echo "connection refused")
  TIMESTAMP=$(date '+%H:%M:%S')

  echo "[$TIMESTAMP] Request #$i — HTTP $RESPONSE" >> "$LOG_FILE"
  echo "  Body: $BODY" >> "$LOG_FILE"

  if [ "$RESPONSE" = "500" ]; then
    echo -e "${RED}[$TIMESTAMP] #$i — HTTP $RESPONSE ✗${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  else
    echo -e "${GREEN}[$TIMESTAMP] #$i — HTTP $RESPONSE${NC}"
  fi

  sleep 0.5
done

echo "---" >> "$LOG_FILE"
echo "Summary: $ERROR_COUNT / $REPEAT request returned HTTP 500" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Summary: ${RED}$ERROR_COUNT / $REPEAT${CYAN} requests returned HTTP 500${NC}"
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Cek Jaeger: ${NC}http://localhost:16686  →  Service: product_service  →  Tag: http.status_code=500"
