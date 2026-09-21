package adminapi

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/limiter"
)

type AdminServer struct {
	router  *gin.Engine
	limiter *limiter.ShardedLimiter
}

func NewAdminServer(l *limiter.ShardedLimiter) *AdminServer {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	srv := &AdminServer{
		router:  r,
		limiter: l,
	}

	srv.setupRoutes()
	return srv
}

func (s *AdminServer) setupRoutes() {
	s.router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "policy-engine"})
	})

	// TODO: Add more admin endpoints (e.g. GET /limits/:agent, PUT /limits/:agent)
	// For now, this just satisfies the healthcheck requirement.
}

func (s *AdminServer) Run(addr string) error {
	return s.router.Run(addr)
}
