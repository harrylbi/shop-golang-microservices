#!/bin/bash
# =============================================================================
# Simulasi Skenario 2: Dependency Failure (Inventory Service Down)
# =============================================================================
# Endpoint:  GET /api/v1/products  (endpoint produksi)
# Env var:   SIMULATE_INVENTORY_DOWN=true
#
# Ekspektasi:
#   - HTTP 500 dengan body: {"success":false,"message":"inventory service unavailable"}
#   - Jaeger span: status=ERROR, incident.type=dependency_failure
#   - Event: inventory_request_timeout
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
ENDPOINT="${PRODUCT_BASE}/api/v1/products"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/incident-dependency-failure.log"
REPEAT="${1:-10}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Skenario 2: Dependency Failure (Natural HTTP 500)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Endpoint: GET /api/v1/products${NC}"
echo -e "${YELLOW}  Env var:  SIMULATE_INVENTORY_DOWN=true${NC}"
echo ""

echo "=== Dependency Failure Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
echo "Target: $ENDPOINT" >> "$LOG_FILE"
echo "Repeat: $REPEAT kali" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

ERROR_COUNT=0

for i in $(seq 1 "$REPEAT"); do
  RESPONSE=$(curl -s -w "\n%{http_code}" "$ENDPOINT" 2>/dev/null || echo -e "\nconnection refused")
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | head -n -1)
  TIMESTAMP=$(date '+%H:%M:%S')

  echo "[$TIMESTAMP] Request #$i — HTTP $HTTP_CODE" >> "$LOG_FILE"
  echo "  Body: $BODY" >> "$LOG_FILE"

  if [ "$HTTP_CODE" = "500" ]; then
    echo -e "${RED}[$TIMESTAMP] #$i — HTTP $HTTP_CODE ✗  ${BODY}${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  elif [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}[$TIMESTAMP] #$i — HTTP $HTTP_CODE ✓${NC}"
  else
    echo -e "${YELLOW}[$TIMESTAMP] #$i — HTTP $HTTP_CODE  ${BODY}${NC}"
  fi

  sleep 0.3
done

echo "---" >> "$LOG_FILE"
echo "Summary: $ERROR_COUNT / $REPEAT request returned HTTP 500" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: ${RED}$ERROR_COUNT / $REPEAT${CYAN} requests returned HTTP 500${NC}"
echo -e "${CYAN}Log:     ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Jaeger Query:${NC}"
echo -e "  Tags: incident.type=dependency_failure"
echo -e "  Tags: dependency=inventory-service"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
