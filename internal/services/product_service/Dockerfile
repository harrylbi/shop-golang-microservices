# syntax=docker/dockerfile:1

FROM golang:1.23-alpine AS builder

WORKDIR /app

COPY internal/pkg/go.mod internal/pkg/go.sum ./internal/pkg/
COPY internal/services/product_service/go.mod internal/services/product_service/go.sum ./internal/services/product_service/

WORKDIR /app/internal/services/product_service
RUN go mod download

WORKDIR /app
COPY internal/pkg ./internal/pkg
COPY internal/services/product_service ./internal/services/product_service

WORKDIR /app/internal/services/product_service
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main ./cmd/main.go


FROM alpine:3.18

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /app/internal/services/product_service/main .
COPY --from=builder /app/internal/services/product_service/config ./config

####################################################
# Application
####################################################
ENV APP_ENV=docker
ENV CONFIG_PATH=/app/config

####################################################
# OpenTelemetry
####################################################
ENV OTEL_SERVICE_NAME=product-service
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
ENV OTEL_EXPORTER_OTLP_PROTOCOL=grpc
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp

EXPOSE 5000
EXPOSE 6600

CMD ["./main"]
