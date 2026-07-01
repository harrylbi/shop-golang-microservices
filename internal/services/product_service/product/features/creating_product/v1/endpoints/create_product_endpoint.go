package endpoints

import (
	"context"
	"github.com/go-playground/validator"
	"github.com/labstack/echo/v4"
	"github.com/mehdihadeli/go-mediatr"
	echomiddleware "github.com/meysamhadeli/shop-golang-microservices/internal/pkg/http/echo/middleware"
	"github.com/meysamhadeli/shop-golang-microservices/internal/pkg/logger"
	commandsv1 "github.com/meysamhadeli/shop-golang-microservices/internal/services/product_service/product/features/creating_product/v1/commands"
	dtosv1 "github.com/meysamhadeli/shop-golang-microservices/internal/services/product_service/product/features/creating_product/v1/dtos"
	"github.com/pkg/errors"
	"net/http"
	"os"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

func MapRoute(validator *validator.Validate, log logger.ILogger, echo *echo.Echo, ctx context.Context) {
	group := echo.Group("/api/v1/products")
	// JWT disabled temporarily for observability and MTTR experiments (set DISABLE_AUTH=true to bypass)
	if os.Getenv("DISABLE_AUTH") == "true" {
		group.POST("", createProduct(validator, log, ctx))
	} else {
		group.POST("", createProduct(validator, log, ctx), echomiddleware.ValidateBearerToken())
	}
}

// CreateProduct
// @Tags        Products
// @Summary     Create product
// @Description Create new product item
// @Accept      json
// @Produce     json
// @Param       CreateProductRequestDto body     dtos.CreateProductRequestDto true "Product data"
// @Success     201                     {object} dtos.CreateProductResponseDto
// @Security ApiKeyAuth
// @Router      /api/v1/products [post]
// @Router      /orders [post]
func createProduct(validator *validator.Validate, log logger.ILogger, ctx context.Context) echo.HandlerFunc {
	return func(c echo.Context) error {

		span := trace.SpanFromContext(c.Request().Context())

		// Skenario 3 — RabbitMQ Failure
		if os.Getenv("SIMULATE_RABBITMQ_FAILURE") == "true" {
			span.SetStatus(codes.Error, "message publish failed")
			span.SetAttributes(
				attribute.String("incident.type", "messaging_failure"),
				attribute.String("messaging.system", "rabbitmq"),
				attribute.Bool("error", true),
			)
			span.AddEvent("rabbitmq_publish_failed")

			return c.JSON(http.StatusInternalServerError, map[string]interface{}{
				"success": false,
				"message": "message publish failed",
			})
		}

		request := &dtosv1.CreateProductRequestDto{}

		if err := c.Bind(request); err != nil {
			badRequestErr := errors.Wrap(err, "[createProductEndpoint_handler.Bind] error in the binding request")
			log.Error(badRequestErr)
			return echo.NewHTTPError(http.StatusBadRequest, err)
		}

		command := commandsv1.NewCreateProduct(request.Name, request.Description, request.Price, request.InventoryId, request.Count)

		if err := validator.StructCtx(ctx, command); err != nil {
			validationErr := errors.Wrap(err, "[createProductEndpoint_handler.StructCtx] command validation failed")
			log.Error(validationErr)
			return echo.NewHTTPError(http.StatusBadRequest, err)
		}

		result, err := mediatr.Send[*commandsv1.CreateProduct, *dtosv1.CreateProductResponseDto](ctx, command)

		if err != nil {
			log.Errorf("(CreateProduct.Handle) id: {%s}, err: {%v}", command.ProductID, err)
			return echo.NewHTTPError(http.StatusBadRequest, err)
		}

		log.Infof("(product created) id: {%s}", command.ProductID)
		return c.JSON(http.StatusCreated, result)
	}
}
