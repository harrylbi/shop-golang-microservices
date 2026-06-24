# syntax=docker/dockerfile:1

FROM golang:1.23-alpine AS builder

WORKDIR /app

# Copy the go.mod and go.sum files first to leverage Docker cache
COPY internal/pkg/go.mod internal/pkg/go.sum ./internal/pkg/
COPY internal/services/identity_service/go.mod internal/services/identity_service/go.sum ./internal/services/identity_service/

# Download dependencies
WORKDIR /app/internal/services/identity_service
RUN go mod download

# Copy the source code
WORKDIR /app
COPY internal/pkg ./internal/pkg
COPY internal/services/identity_service ./internal/services/identity_service

# Build the binary
WORKDIR /app/internal/services/identity_service
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main ./cmd/main.go

# Production stage
FROM alpine:3.18
RUN apk --no-cache add ca-certificates

WORKDIR /app
COPY --from=builder /app/internal/services/identity_service/main .
COPY --from=builder /app/internal/services/identity_service/config ./config

ENV APP_ENV=docker
ENV CONFIG_PATH=/app/config

EXPOSE 5002 6600

CMD ["./main"]
