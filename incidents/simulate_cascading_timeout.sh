#!/bin/bash
# =============================================================================
# Skenario 7: Cascading Timeout
# =============================================================================
# Deskripsi:
#   Mensimulasikan cascading timeout antar service:
#   - Product service memanggil Identity service via gRPC
#   - Stop identity-service container → gRPC call timeout
#   - Observasi error propagation di parent trace (product_service)
#
# Ekspektasi Jaeger:
#   - Parent span (product_service) dengan error=true
#   - Child span (identity_service gRPC) gagal/timeout
#   - Trace menunjukkan cascading failure pattern
#
# Metrik Prometheus:
#   - rpc_client_duration_milliseconds (gRPC client metrics)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
IDENTITY_BASE="${IDENTITY_BASE:-http://localhost:5002}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/cascading-timeout.log"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Skenario 7: Cascading Timeout Simulation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== Cascading Timeout Simulation — $(date -Iseconds) ===" > "$LOG_FILE"

# --- Phase 1: Baseline (semua service aktif) ---
echo -e "${GREEN}[Phase 1] Baseline — semua service aktif${NC}"
echo "[Phase 1] Baseline — semua service aktif" >> "$LOG_FILE"

BASELINE_PRODUCT=$(curl -s -o /dev/null -w "%{http_code}" "$PRODUCT_BASE/" 2>/dev/null || echo "000")
BASELINE_IDENTITY=$(curl -s -o /dev/null -w "%{http_code}" "$IDENTITY_BASE/" 2>/dev/null || echo "000")

echo "  Product service: HTTP $BASELINE_PRODUCT" | tee -a "$LOG_FILE"
echo "  Identity service: HTTP $BASELINE_IDENTITY" | tee -a "$LOG_FILE"

# Create product (involves gRPC call to identity for validation)
echo ""
echo -e "${GREEN}  Baseline create product:${NC}"
BASELINE_CREATE=$(curl -s -w "\n%{http_code} %{time_total}" -X POST "$PRODUCT_BASE/api/v1/products" \
  -H "Content-Type: application/json" \
  -d '{"name":"Cascade-Baseline","description":"baseline test","price":100,"inventoryId":1,"count":1}' 2>/dev/null || echo -e "\n000 0.000")
echo "  Response: $(echo "$BASELINE_CREATE" | tail -1)" | tee -a "$LOG_FILE"
echo "" >> "$LOG_FILE"

sleep 1

# --- Phase 2: Stop Identity Service ---
echo ""
echo -e "${RED}[Phase 2] Menghentikan identity-service...${NC}"
echo "[Phase 2] docker stop identity-service" >> "$LOG_FILE"

docker stop identity-service 2>&1 | tee -a "$LOG_FILE"
echo -e "${YELLOW}  Menunggu 5 detik...${NC}"
sleep 5

# --- Phase 3: Request saat identity-service mati ---
echo ""
echo -e "${RED}[Phase 3] Request saat identity-service mati${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 3] Request saat identity-service mati" >> "$LOG_FILE"

for i in $(seq 1 5); do
  TIMESTAMP=$(date '+%H:%M:%S')

  # Create product — may trigger gRPC call to identity service
  RESULT=$(curl -s -w "\n%{http_code} %{time_total}" --max-time 30 -X POST "$PRODUCT_BASE/api/v1/products" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Cascade-Fail-$i\",\"description\":\"test saat identity mati\",\"price\":100,\"inventoryId\":1,\"count\":1}" 2>/dev/null || echo -e "\n000 0.000")
  HTTP_CODE=$(echo "$RESULT" | tail -1 | awk '{print $1}')
  TIME_TOTAL=$(echo "$RESULT" | tail -1 | awk '{print $2}')
  BODY=$(echo "$RESULT" | head -n -1)

  echo "  [$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${TIME_TOTAL}s" >> "$LOG_FILE"
  echo "  Body: $BODY" >> "$LOG_FILE"
  echo -e "${RED}  [$TIMESTAMP] #$i — HTTP $HTTP_CODE — ${TIME_TOTAL}s${NC}"

  sleep 2
done

# Coba juga GET products (non-cascading, seharusnya tetap jalan)
echo ""
echo -e "${YELLOW}  GET /api/v1/products (non-cascading, seharusnya OK):${NC}"
echo "[Phase 3b] GET products (non-cascading)" >> "$LOG_FILE"

NON_CASCADE=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" "$PRODUCT_BASE/api/v1/products" 2>/dev/null || echo "000 0.000")
echo "  Response: $NON_CASCADE" | tee -a "$LOG_FILE"

# --- Phase 4: Start Identity Service kembali ---
echo ""
echo -e "${GREEN}[Phase 4] Menyalakan identity-service kembali...${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 4] docker start identity-service" >> "$LOG_FILE"

docker start identity-service 2>&1 | tee -a "$LOG_FILE"
echo -e "${YELLOW}  Menunggu 15 detik untuk identity-service ready...${NC}"
sleep 15

# --- Phase 5: Verifikasi recovery ---
echo ""
echo -e "${GREEN}[Phase 5] Verifikasi recovery${NC}"
echo "" >> "$LOG_FILE"
echo "[Phase 5] Verifikasi recovery" >> "$LOG_FILE"

RECOVERY_IDENTITY=$(curl -s -o /dev/null -w "%{http_code}" "$IDENTITY_BASE/" 2>/dev/null || echo "000")
echo "  Identity service: HTTP $RECOVERY_IDENTITY" | tee -a "$LOG_FILE"

RECOVERY_CREATE=$(curl -s -w "\n%{http_code} %{time_total}" -X POST "$PRODUCT_BASE/api/v1/products" \
  -H "Content-Type: application/json" \
  -d '{"name":"Cascade-Recovery","description":"post recovery","price":100,"inventoryId":1,"count":1}' 2>/dev/null || echo -e "\n000 0.000")
echo "  Recovery create: $(echo "$RECOVERY_CREATE" | tail -1)" | tee -a "$LOG_FILE"

echo "" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo -e "${CYAN}Cek Jaeger: ${NC}http://localhost:16686  →  cari trace dengan error span dari product_service + identity_service"
echo -e "${CYAN}  Bandingkan trace parent-child sebelum dan sesudah identity-service mati${NC}"
