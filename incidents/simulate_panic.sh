#!/bin/bash
# =============================================================================
# Skenario 6: Service Panic
# =============================================================================
# Deskripsi:
#   Mengirim request ke endpoint /debug/panic yang menjalankan panic().
#   Echo framework memiliki recover middleware sehingga service tidak crash
#   sepenuhnya, tetapi request akan menghasilkan HTTP 500.
#
# Ekspektasi Jaeger:
#   - Span dengan error=true dan status-code=500
#   - Tag echo-error berisi panic message
#
# Metrik Prometheus:
#   - http_server_duration_milliseconds_count (500 error)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/panic.log"
REPEAT="${1:-5}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Skenario 6: Service Panic Simulation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== Service Panic Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
echo "Target: $PRODUCT_BASE/debug/panic" >> "$LOG_FILE"
echo "Repeat: $REPEAT kali" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

PANIC_COUNT=0

for i in $(seq 1 "$REPEAT"); do
  TIMESTAMP=$(date '+%H:%M:%S')

  RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" --max-time 10 "$PRODUCT_BASE/debug/panic" 2>/dev/null || echo -e "\nHTTP_CODE:000")
  HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
  BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

  echo "[$TIMESTAMP] Request #$i — HTTP ${HTTP_CODE:-000}" >> "$LOG_FILE"
  echo "  Body: $BODY" >> "$LOG_FILE"

  if [ "${HTTP_CODE:-000}" = "500" ] || [ "${HTTP_CODE:-000}" = "000" ]; then
    echo -e "${RED}[$TIMESTAMP] #$i — HTTP ${HTTP_CODE:-000} (PANIC ⚠)${NC}"
    PANIC_COUNT=$((PANIC_COUNT + 1))
  else
    echo -e "${GREEN}[$TIMESTAMP] #$i — HTTP ${HTTP_CODE:-000}${NC}"
  fi

  sleep 1
done

# Verifikasi service masih hidup
echo ""
echo -e "${YELLOW}Verifikasi service masih aktif...${NC}"
echo "" >> "$LOG_FILE"
echo "Verifikasi recovery:" >> "$LOG_FILE"

HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$PRODUCT_BASE/" 2>/dev/null || echo "000")
if [ "$HEALTH" = "200" ]; then
  echo -e "${GREEN}  Service masih aktif (HTTP $HEALTH) ✓${NC}"
  echo "  Health check: HTTP $HEALTH — service aktif" >> "$LOG_FILE"
else
  echo -e "${RED}  Service tidak merespons (HTTP $HEALTH) ✗${NC}"
  echo "  Health check: HTTP $HEALTH — service tidak merespons" >> "$LOG_FILE"
fi

echo "---" >> "$LOG_FILE"
echo "Summary: $PANIC_COUNT / $REPEAT requests triggered panic" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Summary: ${RED}$PANIC_COUNT / $REPEAT${CYAN} requests triggered panic${NC}"
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Cek Jaeger: ${NC}http://localhost:16686  →  Service: product_service  →  Tag: error=true"
