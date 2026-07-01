#!/bin/bash
# =============================================================================
# Skenario 10: Trace Context Lost
# =============================================================================
# Deskripsi:
#   Membandingkan request DENGAN dan TANPA trace propagation header.
#   - Tanpa header: trace terpecah menjadi beberapa trace ID terpisah
#   - Dengan header: trace menyatu dalam satu trace ID
#
# Ekspektasi Jaeger:
#   - Request tanpa traceparent → trace ID baru (tidak terhubung)
#   - Request dengan traceparent → trace terhubung dalam 1 parent
#
# Metrik Prometheus:
#   - Tidak ada perbedaan metrik, hanya perbedaan trace linkage
# =============================================================================

set -euo pipefail

PRODUCT_BASE="${PRODUCT_BASE:-http://localhost:5000}"
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/trace-lost.log"

mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Skenario 10: Trace Context Lost Simulation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "=== Trace Context Lost — $(date -Iseconds) ===" > "$LOG_FILE"

# --- Test A: Request TANPA propagation header ---
echo -e "${RED}[Test A] Request TANPA trace propagation header${NC}"
echo -e "${YELLOW}  Setiap request akan membuat trace ID baru (terpecah)${NC}"
echo "" >> "$LOG_FILE"
echo "[Test A] TANPA propagation header" >> "$LOG_FILE"

for i in $(seq 1 5); do
  TIMESTAMP=$(date '+%H:%M:%S')

  # Tanpa traceparent header — setiap request = trace baru
  RESP=$(curl -s -o /dev/null -w "%{http_code}" "$PRODUCT_BASE/api/v1/products" 2>/dev/null || echo "000")
  echo "  [$TIMESTAMP] #$i — HTTP $RESP (trace ID baru)" | tee -a "$LOG_FILE"
  sleep 0.5
done

echo ""

# --- Test B: Request DENGAN propagation header (W3C Trace Context) ---
echo -e "${GREEN}[Test B] Request DENGAN trace propagation header (traceparent)${NC}"
echo -e "${YELLOW}  Semua request akan terhubung dalam 1 trace ID${NC}"
echo "" >> "$LOG_FILE"
echo "[Test B] DENGAN propagation header (traceparent)" >> "$LOG_FILE"

# Generate shared trace ID (32 hex chars) and parent span ID (16 hex chars)
TRACE_ID=$(printf '%032x' $((RANDOM * RANDOM * RANDOM)))
echo "  Shared trace ID: $TRACE_ID" | tee -a "$LOG_FILE"

for i in $(seq 1 5); do
  TIMESTAMP=$(date '+%H:%M:%S')
  SPAN_ID=$(printf '%016x' $((RANDOM * RANDOM)))

  # W3C Trace Context format: version-traceId-parentSpanId-flags
  TRACEPARENT="00-${TRACE_ID}-${SPAN_ID}-01"

  RESP=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "traceparent: $TRACEPARENT" \
    "$PRODUCT_BASE/api/v1/products" 2>/dev/null || echo "000")
  echo "  [$TIMESTAMP] #$i — HTTP $RESP (traceparent: $TRACEPARENT)" | tee -a "$LOG_FILE"
  sleep 0.5
done

echo ""

# --- Test C: Mixed — beberapa dengan, beberapa tanpa ---
echo -e "${YELLOW}[Test C] Mixed — bergantian dengan/tanpa header${NC}"
echo "" >> "$LOG_FILE"
echo "[Test C] Mixed requests" >> "$LOG_FILE"

TRACE_ID_MIX=$(printf '%032x' $((RANDOM * RANDOM * RANDOM + 1)))

for i in $(seq 1 6); do
  TIMESTAMP=$(date '+%H:%M:%S')

  if (( i % 2 == 0 )); then
    # DENGAN header
    SPAN_ID=$(printf '%016x' $((RANDOM * RANDOM)))
    TRACEPARENT="00-${TRACE_ID_MIX}-${SPAN_ID}-01"
    RESP=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "traceparent: $TRACEPARENT" \
      "$PRODUCT_BASE/api/v1/products" 2>/dev/null || echo "000")
    echo -e "  ${GREEN}[$TIMESTAMP] #$i — HTTP $RESP — WITH traceparent${NC}" | tee -a "$LOG_FILE"
  else
    # TANPA header
    RESP=$(curl -s -o /dev/null -w "%{http_code}" "$PRODUCT_BASE/api/v1/products" 2>/dev/null || echo "000")
    echo -e "  ${RED}[$TIMESTAMP] #$i — HTTP $RESP — WITHOUT traceparent (lost!)${NC}" | tee -a "$LOG_FILE"
  fi

  sleep 0.5
done

echo "" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"
echo "Log saved: $(date -Iseconds)" >> "$LOG_FILE"

echo ""
echo -e "${CYAN}Log saved: ${NC}$LOG_FILE"
echo ""
echo -e "${CYAN}Verifikasi di Jaeger:${NC}"
echo -e "  1. Buka http://localhost:16686"
echo -e "  2. Pilih service: product_service"
echo -e "  3. Cari trace dari Test A — seharusnya ada 5 trace ID terpisah"
echo -e "  4. Cari trace dari Test B — seharusnya terlihat trace terhubung"
echo -e "  5. Bandingkan jumlah span per trace"
