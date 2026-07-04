package echomiddleware

import (
	"strconv"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// HttpServerDurationMilliseconds is the histogram metric that tracks HTTP request
// latency in milliseconds with method, route, and status labels.
// This metric produces:
//   - http_server_duration_milliseconds_bucket
//   - http_server_duration_milliseconds_sum
//   - http_server_duration_milliseconds_count
var HttpServerDurationMilliseconds = prometheus.NewHistogramVec(
	prometheus.HistogramOpts{
		Name:    "http_server_duration_milliseconds",
		Help:    "HTTP server request duration in milliseconds",
		Buckets: []float64{5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000},
	},
	[]string{"method", "route", "status"},
)

func init() {
	prometheus.MustRegister(HttpServerDurationMilliseconds)
}

// PrometheusMetricsMiddleware returns an Echo middleware that records HTTP
// request duration using the http_server_duration_milliseconds histogram.
// It is designed to coexist with OpenTelemetry tracing — it only records
// Prometheus metrics and does not modify the request context or trace spans.
func PrometheusMetricsMiddleware() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			// Skip the /metrics endpoint itself to avoid self-instrumentation noise
			if c.Request().URL.Path == "/metrics" {
				return next(c)
			}

			start := time.Now()

			err := next(c)

			duration := time.Since(start).Seconds() * 1000 // convert to milliseconds

			status := c.Response().Status
			if err != nil {
				if he, ok := err.(*echo.HTTPError); ok {
					status = he.Code
				}
			}

			route := c.Path()
			if route == "" {
				route = c.Request().URL.Path
			}

			HttpServerDurationMilliseconds.WithLabelValues(
				c.Request().Method,
				route,
				strconv.Itoa(status),
			).Observe(duration)

			return err
		}
	}
}

// MetricsHandler returns an Echo handler that serves Prometheus metrics
// at the /metrics endpoint using the default prometheus registry.
func MetricsHandler() echo.HandlerFunc {
	h := promhttp.Handler()
	return func(c echo.Context) error {
		h.ServeHTTP(c.Response(), c.Request())
		return nil
	}
}
