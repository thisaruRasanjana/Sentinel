package main

import (
	"context"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/adminapi"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/grpcsrv"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/limiter"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/metrics"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/store"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/telemetry"
	pb "github.com/thisaruRasanjana/Sentinel/policy-engine/pkg/policyv1"
)

func main() {
	log.Println("Starting policy engine...")

	// 1. Initialize OpenTelemetry
	shutdown, err := telemetry.Init("sentinel-policy-engine")
	if err != nil {
		log.Printf("Warning: OTel init failed (continuing without tracing): %v", err)
		shutdown = func(ctx context.Context) {}
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		shutdown(ctx)
	}()

	// 2. Start Prometheus metrics server (separate from admin API on :9010)
	go func() {
		log.Println("Metrics server listening on :9011")
		metrics.StartMetricsServer(":9011")
	}()

	// 3. Initialize Limiter
	agentRate, agentMax := 500.0/60.0, 500.0
	toolRate, toolMax := 100.0/60.0, 100.0
	l := limiter.NewShardedLimiter(64, agentRate, agentMax, toolRate, toolMax)

	// 4. Setup Redis Write-Behind
	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "localhost:6379"
	}
	rStore := store.NewRedisStore(redisAddr, l)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if err := rStore.LoadState(ctx, agentRate, agentMax, toolRate, toolMax); err != nil {
		log.Printf("Warning: Failed to load state from Redis: %v", err)
	} else {
		log.Println("Successfully loaded quota state from Redis.")
	}

	go rStore.StartWriteBehind(ctx, 5*time.Second)

	// 5. Start Admin API
	adminSrv := adminapi.NewAdminServer(l)
	go func() {
		log.Println("Admin API listening on :9010")
		if err := adminSrv.Run(":9010"); err != nil {
			log.Fatalf("Admin API failed: %v", err)
		}
	}()

	// 6. Start gRPC server with OTel interceptor
	lis, err := net.Listen("tcp", ":9001")
	if err != nil {
		log.Fatalf("Failed to listen on :9001: %v", err)
	}

	grpcServer := grpc.NewServer(
		grpc.StatsHandler(otelgrpc.NewServerHandler()),
	)
	policySrv := grpcsrv.NewPolicyServer(l)
	pb.RegisterPolicyServiceServer(grpcServer, policySrv)
	reflection.Register(grpcServer)

	go func() {
		log.Println("gRPC server listening on :9001")
		if err := grpcServer.Serve(lis); err != nil {
			log.Fatalf("gRPC server failed: %v", err)
		}
	}()

	// 7. Wait for termination
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("Shutting down...")
	grpcServer.GracefulStop()
	cancel()
	rStore.SyncToRedis(context.Background())
	log.Println("Goodbye.")
}
