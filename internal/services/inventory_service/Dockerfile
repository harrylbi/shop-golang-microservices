# syntax=docker/dockerfile:1

FROM golang:1.25-alpine AS builder

WORKDIR /app

COPY internal/pkg/go.mod internal/pkg/go.sum ./internal/pkg/
COPY internal/services/inventory_service/go.mod internal/services/inventory_service/go.sum ./internal/services/inventory_service/

WORKDIR /app/internal/services/inventory_service
RUN go mod download

WORKDIR /app
COPY internal/pkg ./internal/pkg
COPY internal/services/inventory_service ./internal/services/inventory_service

WORKDIR /app/internal/services/inventory_service
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main ./cmd/main.go


FROM alpine:3.18

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /app/internal/services/inventory_service/main .
COPY --from=builder /app/internal/services/inventory_service/config ./config

####################################################
# Application
####################################################
ENV APP_ENV=docker
ENV CONFIG_PATH=/app/config

####################################################
# OpenTelemetry
####################################################
ENV OTEL_SERVICE_NAME=inventory-service
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
ENV OTEL_EXPORTER_OTLP_PROTOCOL=grpc
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp

EXPOSE 5004

CMD ["./main"]
