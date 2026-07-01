package endpoints

import (
	"context"
	"github.com/go-playground/validator"
	"github.com/labstack/echo/v4"
	"github.com/mehdihadeli/go-mediatr"
	echomiddleware "github.com/meysamhadeli/shop-golang-microservices/internal/pkg/http/echo/middleware"
	"github.com/meysamhadeli/shop-golang-microservices/internal/pkg/logger"
	"github.com/meysamhadeli/shop-golang-microservices/internal/pkg/utils"
	dtosv1 "github.com/meysamhadeli/shop-golang-microservices/internal/services/product_service/product/features/getting_products/v1/dtos"
	queriesv1 "github.com/meysamhadeli/shop-golang-microservices/internal/services/product_service/product/features/getting_products/v1/queries"
	"net/http"
	"os"
	"time"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

func MapRoute(validator *validator.Validate, log logger.ILogger, echo *echo.Echo, ctx context.Context) {
	group := echo.Group("/api/v1/products")
	// JWT disabled temporarily for observability and MTTR experiments (set DISABLE_AUTH=true to bypass)
	if os.Getenv("DISABLE_AUTH") == "true" {
		group.GET("", getAllProducts(validator, log, ctx))
	} else {
		group.GET("", getAllProducts(validator, log, ctx), echomiddleware.ValidateBearerToken())
	}
}

// GetAllProducts
// @Tags Products
// @Summary Get all product
// @Description Get all products
// @Accept json
// @Produce json
// @Param GetProductsRequestDto query dtos.GetProductsRequestDto false "GetProductsRequestDto"
// @Success 200 {object} dtos.GetProductsResponseDto
// @Security ApiKeyAuth
// @Router /api/v1/products [get]
func getAllProducts(validator *validator.Validate, log logger.ILogger, ctx context.Context) echo.HandlerFunc {
	return func(c echo.Context) error {

		span := trace.SpanFromContext(c.Request().Context())

		// Skenario 1 — Database Failure
		if os.Getenv("SIMULATE_DB_FAILURE") == "true" {
			span.SetStatus(codes.Error, "database unavailable")
			span.SetAttributes(
				attribute.Bool("error", true),
				attribute.String("incident.type", "db_failure"),
				attribute.String("db.system", "postgresql"),
				attribute.String("error.category", "infrastructure"),
			)
			span.AddEvent("database_connection_failed")

			return c.JSON(http.StatusInternalServerError, map[string]interface{}{
				"success": false,
				"message": "database unavailable",
			})
		}

		// Skenario 2 — Dependency Failure
		if os.Getenv("SIMULATE_INVENTORY_DOWN") == "true" {
			span.SetStatus(codes.Error, "inventory service unavailable")
			span.SetAttributes(
				attribute.String("incident.type", "dependency_failure"),
				attribute.String("dependency", "inventory-service"),
				attribute.String("network.protocol", "http"),
				attribute.Bool("error", true),
			)
			span.AddEvent("inventory_request_timeout")

			return c.JSON(http.StatusInternalServerError, map[string]interface{}{
				"success": false,
				"message": "inventory service unavailable",
			})
		}

		// Skenario 4 — Slow Query
		if os.Getenv("SIMULATE_SLOW_DB") == "true" {
			time.Sleep(5 * time.Second)
			span.SetAttributes(
				attribute.String("incident.type", "latency"),
				attribute.Bool("performance.degradation", true),
				attribute.Bool("error", false),
			)
			span.SetStatus(codes.Ok, "")
		}

		// Skenario 5 — Memory Leak / Resource Exhaustion
		if os.Getenv("SIMULATE_HIGH_CPU") == "true" {
			start := time.Now()
			for time.Since(start) < 2*time.Second {
				// Burn CPU for 2 seconds
			}
		}

		listQuery, err := utils.GetListQueryFromCtx(c)
		if err != nil {
			return echo.NewHTTPError(http.StatusBadRequest, err)
		}

		request := &dtosv1.GetProductsRequestDto{ListQuery: listQuery}
		if err := c.Bind(request); err != nil {
			log.Warn("Bind", err)
			return echo.NewHTTPError(http.StatusBadRequest, err)
		}

		query := queriesv1.NewGetProducts(request.ListQuery)

		queryResult, err := mediatr.Send[*queriesv1.GetProducts, *dtosv1.GetProductsResponseDto](ctx, query)

		if err != nil {
			log.Warnf("GetProducts", err)
			return echo.NewHTTPError(http.StatusBadRequest, err)
		}

		return c.JSON(http.StatusOK, queryResult)
	}
}
