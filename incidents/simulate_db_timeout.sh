#!/bin/bash
# =============================================================================
# Simulasi Skenario 4: Slow Query (5s Delay)
# =============================================================================
# Endpoint:  GET /api/v1/products  (endpoint produksi)
# Env var:   SIMULATE_SLOW_DB=true
#
# Ekspektasi:
#   - HTTP 200 tetapi response time >5 detik
#   - Jaeger span: duration >5s, incident.type=latency, performance.degradation=true
#   - Status OK (bukan error)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
ENDPOINT="${PRODUCT_BASE}/api/v1/products"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/incident-slow-query.log"
REPEAT="${1:-5}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Skenario 4: Slow Query (5s Delay, HTTP 200)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Endpoint: GET /api/v1/products${NC}"
echo -e "${YELLOW}  Env var:  SIMULATE_SLOW_DB=true${NC}"
echo ""

echo "=== Slow Query Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
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

  if [ "$ELAPSED_MS" -gt 4000 ]; then
    echo -e "${RED}[$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${ELAPSED_MS}ms ⚠ SLOW${NC}"
    SLOW_COUNT=$((SLOW_COUNT + 1))
  else
    echo -e "${GREEN}[$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${ELAPSED_MS}ms ✓${NC}"
  fi

  sleep 0.5
done

echo "---" >> "$LOG_FILE"
echo "Summary: $SLOW_COUNT / $REPEAT request were slow (>4s)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: ${YELLOW}$SLOW_COUNT / $REPEAT${CYAN} requests were slow (>4s)${NC}"
echo -e "${CYAN}Log:     ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Jaeger Query:${NC}"
echo -e "  Tags: incident.type=latency"
echo -e "  Tags: performance.degradation=true"
echo -e "  Sort: Longest First (duration >5s)"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
