package server

import (
	"context"
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"time"

	"github.com/labstack/echo/v4"
	echoserver "github.com/meysamhadeli/shop-golang-microservices/internal/pkg/http/echo/server"
	"github.com/meysamhadeli/shop-golang-microservices/internal/pkg/logger"
	"github.com/meysamhadeli/shop-golang-microservices/internal/services/product_service/config"
	"github.com/pkg/errors"
	"go.uber.org/fx"
	"gorm.io/gorm"
)

func RunServers(lc fx.Lifecycle, log logger.ILogger, e *echo.Echo, ctx context.Context, cfg *config.Config, db *gorm.DB) error {

	lc.Append(fx.Hook{
		OnStart: func(_ context.Context) error {
			go func() {
				if err := echoserver.RunHttpServer(ctx, e, log, cfg.Echo); !errors.Is(err, http.ErrServerClosed) {
					log.Fatalf("error running http server: %v", err)
				}
			}()

			e.GET("/", func(c echo.Context) error {
				return c.String(http.StatusOK, config.GetMicroserviceName(cfg.ServiceName))
			})

			// Debug endpoints — only enabled when ENABLE_DEBUG=true
			// Used for incident simulation and observability research
			if os.Getenv("ENABLE_DEBUG") == "true" {
				log.Infof("Debug endpoints enabled (ENABLE_DEBUG=true)")
				registerDebugEndpoints(e, log, db)
			}

			return nil
		},
		OnStop: func(_ context.Context) error {
			log.Infof("all servers shutdown gracefully...")
			return nil
		},
	})

	return nil
}

// registerDebugEndpoints registers debug/testing endpoints for incident simulation.
// These endpoints should NEVER be enabled in production.
func registerDebugEndpoints(e *echo.Echo, log logger.ILogger, db *gorm.DB) {

	// Skenario 1: HTTP 500 — returns Internal Server Error
	e.GET("/debug/error", func(c echo.Context) error {
		log.Error("DEBUG: Simulated internal server error triggered")
		return echo.NewHTTPError(http.StatusInternalServerError, "simulated internal server error for incident testing")
	})

	// Skenario 2: High Latency — adds 3-5 second delay before responding
	e.GET("/debug/latency", func(c echo.Context) error {
		delay := time.Duration(3+rand.Intn(3)) * time.Second
		log.Infof("DEBUG: Simulating high latency (%v delay)", delay)
		time.Sleep(delay)
		return c.JSON(http.StatusOK, map[string]interface{}{
			"message":  "response after artificial delay",
			"delay_ms": delay.Milliseconds(),
		})
	})

	// Skenario 4: Database Timeout — runs pg_sleep(5) to simulate slow query
	e.GET("/debug/db-timeout", func(c echo.Context) error {
		log.Info("DEBUG: Simulating database timeout with pg_sleep(5)")
		result := db.Exec("SELECT pg_sleep(5)")
		if result.Error != nil {
			log.Errorf("DEBUG: Database timeout error: %v", result.Error)
			return echo.NewHTTPError(http.StatusGatewayTimeout, fmt.Sprintf("database timeout: %v", result.Error))
		}
		return c.JSON(http.StatusOK, map[string]string{
			"message": "pg_sleep(5) completed (no timeout occurred)",
		})
	})

	// Skenario 6: Service Panic — triggers panic for recovery testing
	e.GET("/debug/panic", func(c echo.Context) error {
		log.Error("DEBUG: Simulating service panic")
		panic("testing panic — incident simulation for observability research")
	})
}
