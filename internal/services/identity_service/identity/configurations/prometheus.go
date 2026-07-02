package configurations

import (
	prometheus "github.com/labstack/echo-contrib/prometheus"
	"github.com/labstack/echo/v4"
)

func ConfigMetrics(e *echo.Echo) {

	p := prometheus.NewPrometheus("identity_service", nil)

	p.Use(e)

}
