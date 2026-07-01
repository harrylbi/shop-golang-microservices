#!/bin/bash
# =============================================================================
# Simulasi Skenario 5: High CPU / Resource Exhaustion
# =============================================================================
# Endpoint:  GET /api/v1/products  (endpoint produksi)
# Env var:   SIMULATE_HIGH_CPU=true
#
# Ekspektasi:
#   - HTTP 200 tetapi response time meningkat
#   - Jaeger trace duration meningkat
#   - Prometheus: process_cpu_seconds_total naik
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
ENDPOINT="${PRODUCT_BASE}/api/v1/products"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/incident-high-cpu.log"
REPEAT="${1:-10}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Skenario 5: High CPU / Resource Exhaustion${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Endpoint: GET /api/v1/products${NC}"
echo -e "${YELLOW}  Env var:  SIMULATE_HIGH_CPU=true${NC}"
echo ""

echo "=== High CPU Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
echo "Target: $ENDPOINT" >> "$LOG_FILE"
echo "Repeat: $REPEAT kali" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

SLOW_COUNT=0

for i in $(seq 1 "$REPEAT"); do
  START_TIME=$(date +%s%N)
  RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 "$ENDPOINT" 2>/dev/null || echo -e "\ntimeout")
  END_TIME=$(date +%s%N)
  
  ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  TIMESTAMP=$(date '+%H:%M:%S')

  echo "[$TIMESTAMP] Request #$i — HTTP $HTTP_CODE — ${ELAPSED_MS}ms" >> "$LOG_FILE"

  if [ "$ELAPSED_MS" -gt 1500 ]; then
    echo -e "${RED}[$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${ELAPSED_MS}ms ⚠ SLOW (CPU burn)${NC}"
    SLOW_COUNT=$((SLOW_COUNT + 1))
  else
    echo -e "${GREEN}[$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${ELAPSED_MS}ms ✓${NC}"
  fi

  sleep 0.2
done

echo "---" >> "$LOG_FILE"
echo "Summary: $SLOW_COUNT / $REPEAT request were slow (>1.5s)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: ${YELLOW}$SLOW_COUNT / $REPEAT${CYAN} requests were slow (>1.5s, CPU burn)${NC}"
echo -e "${CYAN}Log:     ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Monitor:${NC}"
echo -e "  docker stats product-service  (lihat CPU usage)"
echo -e "  Jaeger: sort by Longest First"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
