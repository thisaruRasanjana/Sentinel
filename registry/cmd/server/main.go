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

	"github.com/thisaruRasanjana/Sentinel/registry/internal/metrics"
	"github.com/thisaruRasanjana/Sentinel/registry/internal/registrysrv"
	"github.com/thisaruRasanjana/Sentinel/registry/internal/telemetry"
	pb "github.com/thisaruRasanjana/Sentinel/registry/pkg/registryv1"
)

func main() {
	log.Println("Starting registry service...")

	// 1. Initialize OpenTelemetry
	shutdown, err := telemetry.Init("sentinel-registry")
	if err != nil {
		log.Printf("Warning: OTel init failed (continuing without tracing): %v", err)
		shutdown = func(ctx context.Context) {}
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		shutdown(ctx)
	}()

	// 2. Start Prometheus metrics server
	go func() {
		log.Println("Metrics server listening on :9012")
		metrics.StartMetricsServer(":9012")
	}()

	// 3. Load tools
	toolsFile := os.Getenv("TOOLS_JSON_PATH")
	if toolsFile == "" {
		toolsFile = "tools.json"
	}

	srv, err := registrysrv.NewRegistryServer(toolsFile)
	if err != nil {
		log.Fatalf("Failed to initialize registry server: %v", err)
	}
	log.Printf("Loaded tool definitions from %s", toolsFile)

	// 4. Start gRPC server with OTel interceptor
	lis, err := net.Listen("tcp", ":9002")
	if err != nil {
		log.Fatalf("Failed to listen on :9002: %v", err)
	}

	grpcServer := grpc.NewServer(
		grpc.StatsHandler(otelgrpc.NewServerHandler()),
	)
	pb.RegisterRegistryServiceServer(grpcServer, srv)
	reflection.Register(grpcServer)

	go func() {
		log.Println("Registry gRPC server listening on :9002")
		if err := grpcServer.Serve(lis); err != nil {
			log.Fatalf("gRPC server failed: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("Shutting down...")
	grpcServer.GracefulStop()
	log.Println("Goodbye.")
}
