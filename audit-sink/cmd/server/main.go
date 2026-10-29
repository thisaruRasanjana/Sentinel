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

	"github.com/thisaruRasanjana/Sentinel/audit-sink/internal/auditsrv"
	"github.com/thisaruRasanjana/Sentinel/audit-sink/internal/metrics"
	"github.com/thisaruRasanjana/Sentinel/audit-sink/internal/telemetry"
	pb "github.com/thisaruRasanjana/Sentinel/audit-sink/pkg/auditv1"
)

func main() {
	log.Println("Starting audit-sink service...")

	// 1. Initialize OpenTelemetry
	shutdown, err := telemetry.Init("sentinel-audit-sink")
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
		log.Println("Metrics server listening on :9013")
		metrics.StartMetricsServer(":9013")
	}()

	// 3. Open audit log
	logPath := os.Getenv("AUDIT_LOG_PATH")
	if logPath == "" {
		logPath = "/data/audit.jsonl"
	}

	srv, err := auditsrv.NewAuditServer(logPath)
	if err != nil {
		log.Fatalf("Failed to initialize audit server: %v", err)
	}
	defer srv.Close()
	log.Printf("Audit log writing to: %s", logPath)

	// 4. Start gRPC server with OTel interceptor
	lis, err := net.Listen("tcp", ":9003")
	if err != nil {
		log.Fatalf("Failed to listen on :9003: %v", err)
	}

	grpcServer := grpc.NewServer(
		grpc.StatsHandler(otelgrpc.NewServerHandler()),
	)
	pb.RegisterAuditServiceServer(grpcServer, srv)
	reflection.Register(grpcServer)

	go func() {
		log.Println("Audit-sink gRPC server listening on :9003")
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
