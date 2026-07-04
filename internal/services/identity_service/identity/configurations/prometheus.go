package configurations

import (
	"github.com/labstack/echo/v4"
	echomiddleware "github.com/meysamhadeli/shop-golang-microservices/internal/pkg/http/echo/middleware"
)

func ConfigMetrics(e *echo.Echo) {

	// Register the custom Prometheus metrics middleware that produces
	// http_server_duration_milliseconds histogram with method/route/status labels.
	// This is compatible with the existing OpenTelemetry tracing middleware.
	e.Use(echomiddleware.PrometheusMetricsMiddleware())

	// Expose Prometheus metrics at /metrics endpoint
	e.GET("/metrics", echomiddleware.MetricsHandler())
}
