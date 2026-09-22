package main

import (
	"context"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/adminapi"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/grpcsrv"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/limiter"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/store"
	pb "github.com/thisaruRasanjana/Sentinel/policy-engine/pkg/policyv1"
)

func main() {
	log.Println("Starting policy engine...")

	// 1. Initialize Limiter (64 shards, 500 agents/min global, 100 tools/min local)
	agentRate, agentMax := 500.0/60.0, 500.0
	toolRate, toolMax := 100.0/60.0, 100.0
	l := limiter.NewShardedLimiter(64, agentRate, agentMax, toolRate, toolMax)

	// 1.5 Setup Redis Write-Behind
	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "localhost:6379"
	}
	rStore := store.NewRedisStore(redisAddr, l)
	
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Try to load state on startup
	if err := rStore.LoadState(ctx, agentRate, agentMax, toolRate, toolMax); err != nil {
		log.Printf("Warning: Failed to load state from Redis: %v", err)
	} else {
		log.Println("Successfully loaded quota state from Redis.")
	}

	// Start background sync every 5 seconds
	go rStore.StartWriteBehind(ctx, 5*time.Second)

	// 2. Start Admin API (Health check)
	adminSrv := adminapi.NewAdminServer(l)
	go func() {
		log.Println("Admin API listening on :9010")
		if err := adminSrv.Run(":9010"); err != nil {
			log.Fatalf("Admin API failed: %v", err)
		}
	}()

	// 3. Start gRPC Server
	lis, err := net.Listen("tcp", ":9001")
	if err != nil {
		log.Fatalf("Failed to listen on :9001: %v", err)
	}

	grpcServer := grpc.NewServer()
	policySrv := grpcsrv.NewPolicyServer(l)
	pb.RegisterPolicyServiceServer(grpcServer, policySrv)
	reflection.Register(grpcServer)

	go func() {
		log.Println("gRPC server listening on :9001")
		if err := grpcServer.Serve(lis); err != nil {
			log.Fatalf("gRPC server failed: %v", err)
		}
	}()

	// 4. Wait for termination signal
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("Shutting down...")
	grpcServer.GracefulStop()
	
	// Ensure final sync and stop background routine
	cancel()
	rStore.SyncToRedis(context.Background())
	log.Println("Goodbye.")
}
