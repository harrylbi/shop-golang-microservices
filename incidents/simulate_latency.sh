#!/bin/bash
# =============================================================================
# Skenario: Realistic High Latency Simulation
# =============================================================================
# Deskripsi:
#   Mensimulasikan berbagai pola latency yang umum terjadi di lingkungan
#   microservices produksi. Menggunakan endpoint produksi yang sudah ada
#   (GET /api/v1/products, POST /api/v1/products, GET /api/v1/products/:id)
#   dengan fault injection via environment variable SIMULATE_*.
#
#   Skenario latency yang disimulasikan:
#     1. Slow Database Query     — SIMULATE_SLOW_DB=true (5s delay)
#     2. Inter-service HTTP call — POST /api/v1/products (calls inventory)
#     3. RabbitMQ queue buildup  — POST /api/v1/products burst writes
#     4. CPU/IO resource contention — SIMULATE_HIGH_CPU=true (2s burn)
#     5. Cascading downstream    — docker stop identity-service
#     6. Combined traffic storm  — concurrent requests saat degradasi
#
# Cara pakai:
#   1. Set env var yang sesuai di docker-compose services.yaml
#   2. Rebuild container: docker compose -f ... up -d --build product-service
#   3. Jalankan: bash simulate_latency.sh [repeat_per_skenario]
#
# Ekspektasi Jaeger:
#   - Span dengan duration >2000ms (slow DB, CPU burn)
#   - Span dengan duration >5000ms (slow query)
#   - Trace multi-service (product → inventory → identity)
#   - Cascading failure pattern saat downstream mati
#
# Metrik Prometheus:
#   - http_server_duration_milliseconds_bucket (bucket tinggi terisi)
#   - http_server_duration_milliseconds_sum (melonjak)
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
IDENTITY_BASE="${IDENTITY_BASE:-http://localhost:5002}"
INVENTORY_BASE="${INVENTORY_BASE:-http://localhost:5004}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/latency-realistic.log"
REPEAT="${1:-5}"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

TOTAL_REQUESTS=0
SLOW_REQUESTS=0
ERROR_REQUESTS=0

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Realistic Latency Simulation — Production Scenarios${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Product   → $PRODUCT_BASE"
echo -e "  Identity  → $IDENTITY_BASE"
echo -e "  Inventory → $INVENTORY_BASE"
echo -e "  Repeat per skenario: $REPEAT"
echo ""

echo "=== Realistic Latency Simulation — $(date -Iseconds) ===" > "$LOG_FILE"
echo "Repeat per scenario: $REPEAT" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

# ─── Helper: kirim request dan ukur latency ────────────────────────────────────
measure_request() {
  local METHOD="$1"
  local URL="$2"
  local DATA="${3:-}"
  local LABEL="$4"
  local THRESHOLD="${5:-2000}"  # ms

  local START_TIME END_TIME ELAPSED_MS RESPONSE HTTP_CODE
  START_TIME=$(date +%s%N)

  if [ "$METHOD" = "POST" ] && [ -n "$DATA" ]; then
    RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 -X POST "$URL" \
      -H "Content-Type: application/json" -d "$DATA" 2>/dev/null || echo -e "\n000")
  elif [ "$METHOD" = "PUT" ] && [ -n "$DATA" ]; then
    RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 -X PUT "$URL" \
      -H "Content-Type: application/json" -d "$DATA" 2>/dev/null || echo -e "\n000")
  else
    RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 "$URL" 2>/dev/null || echo -e "\n000")
  fi

  END_TIME=$(date +%s%N)
  ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  local TIMESTAMP
  TIMESTAMP=$(date '+%H:%M:%S')

  TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))

  echo "[$TIMESTAMP] $LABEL — HTTP $HTTP_CODE — ${ELAPSED_MS}ms" >> "$LOG_FILE"

  if [ "$HTTP_CODE" -ge 500 ] 2>/dev/null; then
    echo -e "  ${RED}[$TIMESTAMP] $LABEL — HTTP $HTTP_CODE — ${ELAPSED_MS}ms ✗ ERROR${NC}"
    ERROR_REQUESTS=$((ERROR_REQUESTS + 1))
  elif [ "$ELAPSED_MS" -gt "$THRESHOLD" ]; then
    echo -e "  ${RED}[$TIMESTAMP] $LABEL — HTTP $HTTP_CODE — ${ELAPSED_MS}ms ⚠ SLOW${NC}"
    SLOW_REQUESTS=$((SLOW_REQUESTS + 1))
  else
    echo -e "  ${GREEN}[$TIMESTAMP] $LABEL — HTTP $HTTP_CODE — ${ELAPSED_MS}ms ✓${NC}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SKENARIO 1: Slow Database Query
# Membutuhkan: SIMULATE_SLOW_DB=true pada product-service container
# Efek: GET /api/v1/products delay 5 detik (HTTP 200 tapi sangat lambat)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${MAGENTA}▶ Skenario 1: Slow Database Query${NC}"
echo -e "${YELLOW}  (Requires SIMULATE_SLOW_DB=true pada product-service)${NC}"
echo "[Skenario 1] Slow Database Query" >> "$LOG_FILE"

for i in $(seq 1 "$REPEAT"); do
  measure_request "GET" "$PRODUCT_BASE/api/v1/products?page=1&size=10" "" \
    "#$i GET /api/v1/products (slow DB)" 4000
  sleep 0.5
done

# ═══════════════════════════════════════════════════════════════════════════════
# SKENARIO 2: Inter-service HTTP/gRPC Latency
# Efek natural: POST /api/v1/products melibatkan komunikasi ke inventory-service
# dan identity-service. Latency terakumulasi dari chain of calls.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${MAGENTA}▶ Skenario 2: Inter-service Communication Latency${NC}"
echo -e "${YELLOW}  POST /api/v1/products → product_service → inventory + identity${NC}"
echo "[Skenario 2] Inter-service Communication" >> "$LOG_FILE"

for i in $(seq 1 "$REPEAT"); do
  TS=$(date +%s%N)
  measure_request "POST" "$PRODUCT_BASE/api/v1/products" \
    "{\"name\":\"Latency-Test-$TS\",\"description\":\"Inter-service latency test\",\"price\":$((RANDOM % 500 + 50)),\"inventoryId\":$((RANDOM % 2 + 1)),\"count\":$((RANDOM % 20 + 1))}" \
    "#$i POST /api/v1/products (inter-service)" 1000
  sleep 0.3
done

# ═══════════════════════════════════════════════════════════════════════════════
# SKENARIO 3: RabbitMQ Queue Buildup (Burst Write)
# Efek: Mengirim banyak POST secara cepat untuk membuat antrian RabbitMQ
# menumpuk, meningkatkan latency publish message.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${MAGENTA}▶ Skenario 3: RabbitMQ Queue Buildup (Burst Write)${NC}"
echo -e "${YELLOW}  Rapid-fire POST — memaksa antrian pesan menumpuk${NC}"
echo "[Skenario 3] RabbitMQ Queue Buildup" >> "$LOG_FILE"

BURST_COUNT=$((REPEAT * 3))
for i in $(seq 1 "$BURST_COUNT"); do
  TS=$(date +%s%N)
  measure_request "POST" "$PRODUCT_BASE/api/v1/products" \
    "{\"name\":\"Burst-$TS\",\"description\":\"Queue buildup test\",\"price\":$((RANDOM % 100 + 10)),\"inventoryId\":1,\"count\":$((RANDOM % 10 + 1))}" \
    "#$i POST burst (queue buildup)" 1500 &

  # Kirim 3 request paralel, lalu tunggu
  if (( i % 3 == 0 )); then
    wait
  fi
done
wait
sleep 1

# ═══════════════════════════════════════════════════════════════════════════════
# SKENARIO 4: CPU/IO Resource Contention
# Membutuhkan: SIMULATE_HIGH_CPU=true pada product-service container
# Efek: GET /api/v1/products burn CPU 2 detik per request
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${MAGENTA}▶ Skenario 4: Resource Contention (CPU Burn)${NC}"
echo -e "${YELLOW}  (Requires SIMULATE_HIGH_CPU=true pada product-service)${NC}"
echo "[Skenario 4] Resource Contention (CPU)" >> "$LOG_FILE"

for i in $(seq 1 "$REPEAT"); do
  measure_request "GET" "$PRODUCT_BASE/api/v1/products?page=1&size=5" "" \
    "#$i GET /api/v1/products (CPU contention)" 1500
  sleep 0.3
done

# ═══════════════════════════════════════════════════════════════════════════════
# SKENARIO 5: Cascading Latency (Downstream Service Slow/Down)
# Efek: Stop identity-service → POST ke product-service timeout karena
# gRPC call ke identity gagal → cascading delay/error ke caller.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${MAGENTA}▶ Skenario 5: Cascading Latency — Downstream Degradation${NC}"
echo "[Skenario 5] Cascading Latency" >> "$LOG_FILE"

# Phase A: Baseline — semua service aktif
echo -e "${GREEN}  [Phase A] Baseline — semua service aktif${NC}"
measure_request "GET" "$PRODUCT_BASE/api/v1/products?page=1&size=5" "" \
  "baseline GET products" 2000
measure_request "POST" "$PRODUCT_BASE/api/v1/products" \
  '{"name":"Cascade-Baseline","description":"baseline","price":100,"inventoryId":1,"count":1}' \
  "baseline POST products" 2000

# Phase B: Stop identity-service → cascading delay
echo ""
echo -e "${RED}  [Phase B] Menghentikan identity-service...${NC}"
echo "  [Phase B] docker stop identity-service" >> "$LOG_FILE"
docker stop identity-service 2>&1 | while read -r line; do echo "  $line"; done
echo -e "${YELLOW}  Menunggu 5 detik...${NC}"
sleep 5

echo -e "${RED}  [Phase B] Request saat identity-service mati:${NC}"
for i in $(seq 1 "$REPEAT"); do
  measure_request "POST" "$PRODUCT_BASE/api/v1/products" \
    "{\"name\":\"Cascade-Fail-$i\",\"description\":\"test downstream mati\",\"price\":100,\"inventoryId\":1,\"count\":1}" \
    "#$i POST cascade (identity down)" 2000
  sleep 1
done

# Non-cascading GET (seharusnya tetap jalan, tapi mungkin lambat)
echo -e "${YELLOW}  GET request (non-cascading, should still work):${NC}"
for i in $(seq 1 3); do
  measure_request "GET" "$PRODUCT_BASE/api/v1/products?page=1&size=5" "" \
    "#$i GET products (identity down)" 2000
  sleep 0.3
done

# Phase C: Recovery
echo ""
echo -e "${GREEN}  [Phase C] Menyalakan identity-service kembali...${NC}"
echo "  [Phase C] docker start identity-service" >> "$LOG_FILE"
docker start identity-service 2>&1 | while read -r line; do echo "  $line"; done
echo -e "${YELLOW}  Menunggu 15 detik untuk recovery...${NC}"
sleep 15

echo -e "${GREEN}  [Phase C] Verifikasi recovery:${NC}"
measure_request "POST" "$PRODUCT_BASE/api/v1/products" \
  '{"name":"Cascade-Recovery","description":"post recovery","price":100,"inventoryId":1,"count":1}' \
  "recovery POST products" 2000

# ═══════════════════════════════════════════════════════════════════════════════
# SKENARIO 6: Combined Traffic Storm (Campuran Read+Write saat degradasi)
# Efek: Banyak request campuran GET + POST secara bersamaan — mengukur
# bagaimana latency meningkat saat load tinggi.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${MAGENTA}▶ Skenario 6: Combined Traffic Storm${NC}"
echo -e "${YELLOW}  Concurrent mixed GET + POST requests${NC}"
echo "[Skenario 6] Combined Traffic Storm" >> "$LOG_FILE"

# Fetch existing product ID for read tests
CACHED_ID=$(curl -s "$PRODUCT_BASE/api/v1/products?page=1&size=1" 2>/dev/null \
  | grep -o '"productId":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")

STORM_COUNT=$((REPEAT * 2))
for i in $(seq 1 "$STORM_COUNT"); do
  # Mix GET and POST
  if (( i % 3 == 0 )); then
    TS=$(date +%s%N)
    measure_request "POST" "$PRODUCT_BASE/api/v1/products" \
      "{\"name\":\"Storm-$TS\",\"description\":\"traffic storm\",\"price\":$((RANDOM % 300 + 10)),\"inventoryId\":1,\"count\":$((RANDOM % 5 + 1))}" \
      "#$i POST storm" 2000 &
  elif [ -n "$CACHED_ID" ] && (( i % 3 == 1 )); then
    measure_request "GET" "$PRODUCT_BASE/api/v1/products/$CACHED_ID" "" \
      "#$i GET by ID storm" 2000 &
  else
    measure_request "GET" "$PRODUCT_BASE/api/v1/products?page=1&size=10" "" \
      "#$i GET list storm" 2000 &
  fi

  if (( i % 4 == 0 )); then
    wait
  fi
done
wait

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "---" >> "$LOG_FILE"
echo "Summary:" >> "$LOG_FILE"
echo "  Total requests: $TOTAL_REQUESTS" >> "$LOG_FILE"
echo "  Slow requests (above threshold): $SLOW_REQUESTS" >> "$LOG_FILE"
echo "  Error requests (HTTP 5xx): $ERROR_REQUESTS" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  SUMMARY${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Total requests:  ${YELLOW}$TOTAL_REQUESTS${NC}"
echo -e "  Slow (>threshold): ${RED}$SLOW_REQUESTS${NC}"
echo -e "  Errors (5xx):    ${RED}$ERROR_REQUESTS${NC}"
echo -e "  Log:             $LOG_FILE"
echo ""
echo -e "${CYAN}Observability:${NC}"
echo -e "  Jaeger:      http://localhost:16686"
echo -e "    → Service: product_service"
echo -e "    → Sort: Longest First"
echo -e "    → Tags: incident.type=latency | performance.degradation=true"
echo -e "  Prometheus:  http://localhost:9090"
echo -e "    → Query: http_server_duration_milliseconds_bucket"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
