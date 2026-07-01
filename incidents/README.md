# Incident Simulation Framework

Framework simulasi incident untuk penelitian **incident response** dan **MTTR (Mean Time To Recover)** pada arsitektur microservices.

## Arsitektur

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│   Product    │────▶│   Identity   │     │   Inventory     │
│   Service    │gRPC │   Service    │     │   Service       │
│  :5000       │     │  :5002       │     │  :5004          │
└──────┬───────┘     └──────────────┘     └─────────────────┘
       │ publish                                │ consume
       ▼                                        ▼
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  RabbitMQ   │     │  PostgreSQL  │     │ OTel Collector  │
│  :5672      │     │  :5432       │     │  :4317          │
└─────────────┘     └──────────────┘     └────────┬────────┘
                                                  │
                                    ┌─────────────┼─────────────┐
                                    ▼             ▼             ▼
                              ┌──────────┐ ┌───────────┐ ┌──────────┐
                              │  Jaeger  │ │Prometheus │ │   n8n    │
                              │  :16686  │ │  :8889    │ │  :5678   │
                              └──────────┘ └───────────┘ └──────────┘
```

## Prasyarat

- Docker & Docker Compose
- `curl`, `bc`, `jq` (opsional)
- Semua container infrastructure dan services sudah running:

```bash
make docker-compose_infra_up    # rabbitmq, postgres, jaeger, otel-collector
make docker-compose_services_up # product, identity, inventory services
```

## Cara Menjalankan

### Menjalankan satu skenario:

```bash
cd incidents/
bash simulate_http500.sh
```

### Menjalankan semua skenario (sequential):

```bash
cd incidents/
for script in simulate_*.sh; do
  echo "========== Running: $script =========="
  bash "$script"
  echo ""
  sleep 5
done
```

### Parameter opsional:

Beberapa script menerima argumen jumlah repeat:

```bash
bash simulate_http500.sh 20       # 20 kali request
bash simulate_latency.sh 5        # 5 kali request
bash simulate_retry_storm.sh 15 3 # 15 parallel x 3 rounds
```

## Daftar Skenario

| # | Skenario | Script | Endpoint/Target |
|---|----------|--------|-----------------|
| 1 | HTTP 500 Error | `simulate_http500.sh` | `GET /debug/error` |
| 2 | High Latency | `simulate_latency.sh` | `GET /debug/latency` |
| 3 | RabbitMQ Unreachable | `simulate_rabbitmq_failure.sh` | `docker stop rabbitmq` + create product |
| 4 | Database Timeout | `simulate_db_timeout.sh` | `GET /debug/db-timeout` (pg_sleep) |
| 5 | Validation Error | `simulate_validation_error.sh` | `POST /api/v1/products` payload invalid |
| 6 | Service Panic | `simulate_panic.sh` | `GET /debug/panic` |
| 7 | Cascading Timeout | `simulate_cascading_timeout.sh` | `docker stop identity-service` + create |
| 8 | Retry Storm | `simulate_retry_storm.sh` | Parallel requests saat RabbitMQ mati |
| 9 | Message Publish Failed | `simulate_publish_failed.sh` | `docker stop rabbitmq` + publish |
| 10 | Trace Context Lost | `simulate_trace_lost.sh` | Request tanpa/dengan `traceparent` |

## Ekspektasi Trace di Jaeger

Buka: **http://localhost:16686**

### Skenario 1: HTTP 500

- **Service**: `product_service`
- **Operation**: `GET /debug/error`
- **Tags**: `otel.status_code=ERROR`, `http.status_code=500`, `error=true`
- **Span**: Pendek (~1ms), ada error tag

### Skenario 2: High Latency

- **Service**: `product_service`
- **Operation**: `GET /debug/latency`
- **Filter**: Min Duration = `3s`
- **Span**: Panjang (3-5s), duration bar menonjol di timeline

### Skenario 3: RabbitMQ Unreachable

- **Service**: `product_service`
- **Operation**: `POST /api/v1/products`
- **Tags**: `error=true`, echo-error berisi connection/publish error
- **Pattern**: Error span saat RabbitMQ mati → success span setelah recovery

### Skenario 4: Database Timeout

- **Service**: `product_service`
- **Operation**: `GET /debug/db-timeout`
- **Filter**: Min Duration = `5s`
- **Span**: Duration ≥ 5s, mungkin error jika context timeout lebih kecil

### Skenario 5: Validation Error

- **Service**: `product_service`, `identity_service`
- **Tags**: `http.status_code=400`, `error=true`
- **Span**: Pendek, ada validation error message

### Skenario 6: Service Panic

- **Service**: `product_service`
- **Operation**: `GET /debug/panic`
- **Tags**: `http.status_code=500`, `error=true`
- **Span**: Echo recover middleware menangkap panic

### Skenario 7: Cascading Timeout

- **Service**: `product_service` (parent) → `identity_service` (child)
- **Pattern**: Parent span error karena child service tidak merespons
- **Bandingkan**: Trace sebelum vs sesudah identity-service mati

### Skenario 8: Retry Storm

- **Service**: `product_service`
- **Pattern**: Lonjakan jumlah trace dalam timeframe singkat (< 1 menit)
- **Lookback**: Last 5 Minutes → perhatikan spike di trace count

### Skenario 9: Message Publish Failed

- **Service**: `product_service`
- **Tags**: `error=true`, echo-error berisi publish error
- **Mirip** skenario 3 tapi fokus pada error message publish

### Skenario 10: Trace Context Lost

- **Test A**: 5 trace ID terpisah (tidak saling terhubung)
- **Test B**: Request terhubung via shared trace ID dari `traceparent`
- **Verifikasi**: Bandingkan jumlah root span pada kedua test

## Metrik Prometheus yang Muncul

Endpoint metrics: **http://localhost:8889/metrics**

| Metrik | Skenario | Keterangan |
|--------|----------|------------|
| `http_server_duration_milliseconds_count` | Semua | Counter jumlah request per endpoint |
| `http_server_duration_milliseconds_sum` | 2, 4 | Sum durasi — melonjak saat latency tinggi |
| `http_server_duration_milliseconds_bucket` | 2, 4 | Histogram bucket — bucket besar terisi |
| `rpc_client_duration_milliseconds_count` | 7 | gRPC client call count |
| `rpc_client_duration_milliseconds_sum` | 7 | gRPC call duration sum |

### Cara query metrik:

```bash
# Total request count
curl -s http://localhost:8889/metrics | grep http_server_duration_milliseconds_count

# Error rate (filter label http_status_code 4xx/5xx)
curl -s http://localhost:8889/metrics | grep 'http_server_duration.*status_code="5'

# Latency histogram
curl -s http://localhost:8889/metrics | grep http_server_duration_milliseconds_bucket
```

## Alert yang Dipicu (Alertmanager)

Jika Alertmanager dan Prometheus sudah dikonfigurasi, berikut contoh alert rules yang seharusnya terpicu:

### Contoh Prometheus Alert Rules

```yaml
# File: prometheus/alert_rules.yml
groups:
  - name: microservices_alerts
    rules:
      # Skenario 1, 6: High error rate
      - alert: HighErrorRate
        expr: |
          sum(rate(http_server_duration_milliseconds_count{http_status_code=~"5.."}[5m]))
          / sum(rate(http_server_duration_milliseconds_count[5m])) > 0.1
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Error rate > 10% pada {{ $labels.service_name }}"

      # Skenario 2, 4: High latency
      - alert: HighLatency
        expr: |
          histogram_quantile(0.95,
            rate(http_server_duration_milliseconds_bucket[5m])
          ) > 2000
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "P95 latency > 2s pada {{ $labels.service_name }}"

      # Skenario 3, 9: RabbitMQ down
      - alert: RabbitMQDown
        expr: up{job="rabbitmq"} == 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ tidak merespons"

      # Skenario 7: Service down
      - alert: ServiceDown
        expr: up{job=~".*_service"} == 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.job }} tidak merespons"
```

## Webhook ke n8n

### Setup Webhook n8n

1. Buka n8n di **http://localhost:5678**
2. Buat workflow baru dengan trigger **Webhook**
3. Set method: `POST`
4. Catat webhook URL (contoh: `http://localhost:5678/webhook/incident-alert`)

### Contoh konfigurasi Alertmanager → n8n:

```yaml
# alertmanager.yml
route:
  receiver: n8n-webhook
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 1h

receivers:
  - name: n8n-webhook
    webhook_configs:
      - url: 'http://n8n:5678/webhook/incident-alert'
        send_resolved: true
```

### Contoh payload yang diterima n8n:

```json
{
  "status": "firing",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "HighErrorRate",
        "severity": "critical",
        "service_name": "product_service"
      },
      "annotations": {
        "summary": "Error rate > 10% pada product_service"
      },
      "startsAt": "2026-07-01T06:00:00Z"
    }
  ]
}
```

### Workflow n8n yang disarankan:

```
Webhook → IF severity=critical → Slack/Telegram notification
                                → Log ke database
                                → Auto-restart container (opsional)
       → IF severity=warning  → Log saja
```

## Analisis MTTR

### MTTR Sebelum Otomatisasi (Manual)

| Fase | Durasi | Keterangan |
|------|--------|------------|
| **Deteksi** | 5-15 menit | Tim menyadari ada masalah (dari komplain user atau monitoring manual) |
| **Identifikasi** | 10-30 menit | Cek log manual, reproduksi error, identifikasi root cause |
| **Respons** | 5-15 menit | Komunikasi tim, eskalasi |
| **Perbaikan** | 10-30 menit | Restart service, rollback, hotfix |
| **Verifikasi** | 5-10 menit | Memastikan service kembali normal |
| **Total MTTR** | **35-100 menit** | ~60 menit rata-rata |

### MTTR Sesudah Otomatisasi (dengan OTel + Jaeger + Alertmanager + n8n)

| Fase | Durasi | Keterangan |
|------|--------|------------|
| **Deteksi** | 30 detik - 2 menit | Alertmanager mendeteksi anomali dari metrik Prometheus |
| **Identifikasi** | 1-5 menit | Jaeger trace langsung menunjukkan error span + root cause |
| **Respons** | < 30 detik | n8n webhook otomatis notifikasi + trigger runbook |
| **Perbaikan** | 2-10 menit | Auto-restart via n8n atau manual dengan konteks yang jelas |
| **Verifikasi** | 1-2 menit | Alert resolved otomatis dikirim ke n8n |
| **Total MTTR** | **5-20 menit** | ~10 menit rata-rata |

### Perbandingan

| Metrik | Sebelum | Sesudah | Improvement |
|--------|---------|---------|-------------|
| **MTTR rata-rata** | ~60 menit | ~10 menit | **83% lebih cepat** |
| **Waktu deteksi** | 5-15 menit | < 2 menit | **87% lebih cepat** |
| **Waktu identifikasi** | 10-30 menit | 1-5 menit | **83% lebih cepat** |
| **Akurasi root cause** | ~60% | ~95% | **Jauh lebih akurat** |
| **False positive rate** | Tinggi | Rendah | Terfilter oleh rules |

### Rumus MTTR:

```
MTTR = Waktu_Deteksi + Waktu_Identifikasi + Waktu_Respons + Waktu_Perbaikan + Waktu_Verifikasi
```

## Output Files

Semua log disimpan di folder `incidents/logs/`:

```
incidents/
├── logs/
│   ├── incident-http500.log
│   ├── latency.log
│   ├── rabbitmq-failure.log
│   ├── db-timeout.log
│   ├── validation-error.log
│   ├── panic.log
│   ├── cascading-timeout.log
│   ├── retry-storm.log
│   ├── publish-failed.log
│   └── trace-lost.log
├── simulate_http500.sh
├── simulate_latency.sh
├── simulate_rabbitmq_failure.sh
├── simulate_db_timeout.sh
├── simulate_validation_error.sh
├── simulate_panic.sh
├── simulate_cascading_timeout.sh
├── simulate_retry_storm.sh
├── simulate_publish_failed.sh
├── simulate_trace_lost.sh
└── README.md
```

## Catatan Penting

> **Debug endpoints** (`/debug/*`) hanya aktif saat environment variable `ENABLE_DEBUG=true` di-set pada product-service. Jangan aktifkan di production!

> **Skenario 3, 8, 9** akan menghentikan container RabbitMQ. Pastikan tidak ada proses penting yang sedang berjalan. Script akan mengembalikan RabbitMQ ke kondisi aktif setelah selesai.

> **Skenario 7** akan menghentikan container identity-service. Script akan mengembalikannya setelah selesai.
