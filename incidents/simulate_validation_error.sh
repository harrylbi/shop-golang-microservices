#!/bin/bash
# =============================================================================
# Skenario 5: Validation Error
# =============================================================================
# Deskripsi:
#   Mengirim payload invalid ke endpoint yang memiliki validasi:
#   - POST /api/v1/products dengan field wajib kosong
#   - POST /api/v1/products dengan tipe data salah
#   - POST /api/v1/users dengan field wajib kosong
#
# Ekspektasi Jaeger:
#   - Span dengan tag http.status_code=400
#   - Tag echo-error berisi validation error message
#
# Metrik Prometheus:
#   - http_server_duration_milliseconds_count (label 400)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
IDENTITY_BASE="${IDENTITY_BASE:-http://localhost:5002}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/validation-error.log"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Skenario 5: Validation Error Simulation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== Validation Error Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
echo "" >> "$LOG_FILE"

# --- Test 1: Product tanpa field wajib ---
echo -e "${RED}[Test 1] POST /api/v1/products — field kosong${NC}"
echo "[Test 1] POST /api/v1/products — field kosong" >> "$LOG_FILE"

RESP1=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$PRODUCT_BASE/api/v1/products" \
  -H "Content-Type: application/json" \
  -d '{}' 2>/dev/null || echo "connection refused")
echo "  Response: $RESP1" | tee -a "$LOG_FILE"
echo "" >> "$LOG_FILE"
sleep 0.5

# --- Test 2: Product dengan name kosong ---
echo ""
echo -e "${RED}[Test 2] POST /api/v1/products — name kosong, price negatif${NC}"
echo "[Test 2] POST /api/v1/products — name kosong, price negatif" >> "$LOG_FILE"

RESP2=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$PRODUCT_BASE/api/v1/products" \
  -H "Content-Type: application/json" \
  -d '{"name":"","description":"","price":-100,"inventoryId":0,"count":0}' 2>/dev/null || echo "connection refused")
echo "  Response: $RESP2" | tee -a "$LOG_FILE"
echo "" >> "$LOG_FILE"
sleep 0.5

# --- Test 3: Product dengan tipe data salah ---
echo ""
echo -e "${RED}[Test 3] POST /api/v1/products — tipe data salah${NC}"
echo "[Test 3] POST /api/v1/products — tipe data salah" >> "$LOG_FILE"

RESP3=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$PRODUCT_BASE/api/v1/products" \
  -H "Content-Type: application/json" \
  -d '{"name":12345,"description":null,"price":"bukan_angka","inventoryId":"abc","count":"xyz"}' 2>/dev/null || echo "connection refused")
echo "  Response: $RESP3" | tee -a "$LOG_FILE"
echo "" >> "$LOG_FILE"
sleep 0.5

# --- Test 4: GET product dengan UUID invalid ---
echo ""
echo -e "${RED}[Test 4] GET /api/v1/products/invalid-uuid${NC}"
echo "[Test 4] GET /api/v1/products/invalid-uuid" >> "$LOG_FILE"

RESP4=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$PRODUCT_BASE/api/v1/products/not-a-valid-uuid" 2>/dev/null || echo "connection refused")
echo "  Response: $RESP4" | tee -a "$LOG_FILE"
echo "" >> "$LOG_FILE"
sleep 0.5

# --- Test 5: Register user tanpa field wajib ---
echo ""
echo -e "${RED}[Test 5] POST /api/v1/users — field kosong${NC}"
echo "[Test 5] POST /api/v1/users — field kosong" >> "$LOG_FILE"

RESP5=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$IDENTITY_BASE/api/v1/users" \
  -H "Content-Type: application/json" \
  -d '{}' 2>/dev/null || echo "connection refused")
echo "  Response: $RESP5" | tee -a "$LOG_FILE"
echo "" >> "$LOG_FILE"
sleep 0.5

# --- Test 6: Register user dengan email invalid ---
echo ""
echo -e "${RED}[Test 6] POST /api/v1/users — email invalid${NC}"
echo "[Test 6] POST /api/v1/users — email invalid" >> "$LOG_FILE"

RESP6=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$IDENTITY_BASE/api/v1/users" \
  -H "Content-Type: application/json" \
  -d '{"firstName":"","lastName":"","userName":"","email":"bukan-email","password":""}' 2>/dev/null || echo "connection refused")
echo "  Response: $RESP6" | tee -a "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "---" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo -e "${CYAN}Cek Jaeger: ${NC}http://localhost:16686  →  Tag: http.status_code=400"
