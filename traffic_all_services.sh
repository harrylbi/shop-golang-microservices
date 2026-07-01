#!/bin/bash
# =============================================================================
# traffic_all_services.sh
# Continuous traffic generator untuk semua service — untuk uji observabilitas,
# tracing, dan MTTR di Jaeger/Prometheus/Grafana.
# Jalankan: bash traffic_all_services.sh
# Stop    : Ctrl+C
# =============================================================================

PRODUCT_BASE=http://localhost:5000
IDENTITY_BASE=http://localhost:5002
INVENTORY_BASE=http://localhost:5004

SLEEP_INTERVAL=2   # detik antar siklus
COUNTER=0

# Warna
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[$(date '+%H:%M:%S')] [siklus #$COUNTER]${NC} ${GREEN}$1${NC}"; }

echo -e "${YELLOW}"
echo "  ██████████████████████████████████████████████████"
echo "  ██  traffic_all_services.sh — continuous traffic  ██"
echo "  ██  Ctrl+C untuk berhenti                         ██"
echo "  ██████████████████████████████████████████████████"
echo -e "${NC}"
echo "  Product   → $PRODUCT_BASE"
echo "  Identity  → $IDENTITY_BASE"
echo "  Inventory → $INVENTORY_BASE"
echo ""

# ─── Cache product ID agar tidak selalu create baru ───────────────────────────
CACHED_PRODUCT_ID=""

refresh_product_id() {
  local list_resp
  list_resp=$(curl -s "$PRODUCT_BASE/api/v1/products?page=1&size=1" 2>/dev/null)
  CACHED_PRODUCT_ID=$(echo "$list_resp" | grep -o '"productId":"[^"]*"' | head -1 | cut -d'"' -f4)
}

# Ambil ID awal
refresh_product_id

# ─── Loop utama ────────────────────────────────────────────────────────────────
while true; do
  COUNTER=$((COUNTER + 1))

  # ── PRODUCT SERVICE ──────────────────────────────────────────────────────────
  log "GET /api/v1/products"
  curl -s "$PRODUCT_BASE/api/v1/products?page=1&size=10" >/dev/null

  log "GET /api/v1/products/search?name=laptop"
  curl -s "$PRODUCT_BASE/api/v1/products/search?name=laptop&page=1&size=10" >/dev/null

  log "GET /api/v1/products/search?name=gpu"
  curl -s "$PRODUCT_BASE/api/v1/products/search?name=gpu&page=1&size=10" >/dev/null

  # Setiap 5 siklus: create produk baru, lalu baca, update, hapus
  if (( COUNTER % 5 == 0 )); then
    log "POST /api/v1/products (create)"
    RESP=$(curl -s -X POST "$PRODUCT_BASE/api/v1/products" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"Traffic-Test-$(date +%s)\",
        \"description\": \"Auto-generated traffic test product\",
        \"price\": $((RANDOM % 2000 + 100)),
        \"inventoryId\": $((RANDOM % 2 + 1)),
        \"count\": $((RANDOM % 50 + 1))
      }" 2>/dev/null)
    NEW_ID=$(echo "$RESP" | grep -o '"productId":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -n "$NEW_ID" ]; then
      log "GET /api/v1/products/$NEW_ID (baca produk baru)"
      curl -s "$PRODUCT_BASE/api/v1/products/$NEW_ID" >/dev/null

      log "PUT /api/v1/products/$NEW_ID (update)"
      curl -s -X PUT "$PRODUCT_BASE/api/v1/products/$NEW_ID" \
        -H "Content-Type: application/json" \
        -d "{
          \"name\": \"Traffic-Test-Updated\",
          \"description\": \"Updated by traffic script\",
          \"price\": $((RANDOM % 2000 + 100)),
          \"inventoryId\": 1,
          \"count\": $((RANDOM % 50 + 1))
        }" >/dev/null

      log "DELETE /api/v1/products/$NEW_ID"
      curl -s -X DELETE "$PRODUCT_BASE/api/v1/products/$NEW_ID" >/dev/null

      # Refresh cached ID setelah perubahan
      refresh_product_id
    fi
  fi

  # GET by cached ID (jika ada)
  if [ -n "$CACHED_PRODUCT_ID" ]; then
    log "GET /api/v1/products/$CACHED_PRODUCT_ID (by ID)"
    curl -s "$PRODUCT_BASE/api/v1/products/$CACHED_PRODUCT_ID" >/dev/null
  fi

  # ── IDENTITY SERVICE ─────────────────────────────────────────────────────────
  log "GET / identity-service (health)"
  curl -s "$IDENTITY_BASE/" >/dev/null

  # Setiap 10 siklus: register user baru
  if (( COUNTER % 10 == 0 )); then
    TS=$(date +%s)
    log "POST /api/v1/users (register user)"
    curl -s -X POST "$IDENTITY_BASE/api/v1/users" \
      -H "Content-Type: application/json" \
      -d "{
        \"firstName\": \"Traffic\",
        \"lastName\": \"User\",
        \"userName\": \"traffic_${TS}\",
        \"email\": \"traffic_${TS}@test.com\",
        \"password\": \"Password123!\"
      }" >/dev/null
  fi

  # ── INVENTORY SERVICE ─────────────────────────────────────────────────────────
  log "GET / inventory-service (health)"
  curl -s "$INVENTORY_BASE/" >/dev/null

  echo ""
  sleep $SLEEP_INTERVAL
done
