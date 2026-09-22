package main

import (
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/thisaruRasanjana/Sentinel/registry/internal/registrysrv"
	pb "github.com/thisaruRasanjana/Sentinel/registry/pkg/registryv1"
)

func main() {
	log.Println("Starting registry service...")

	// Find tools.json
	toolsFile := os.Getenv("TOOLS_JSON_PATH")
	if toolsFile == "" {
		toolsFile = "tools.json"
	}

	srv, err := registrysrv.NewRegistryServer(toolsFile)
	if err != nil {
		log.Fatalf("Failed to initialize registry server: %v", err)
	}
	log.Printf("Loaded tool definitions from %s", toolsFile)

	lis, err := net.Listen("tcp", ":9002")
	if err != nil {
		log.Fatalf("Failed to listen on :9002: %v", err)
	}

	grpcServer := grpc.NewServer()
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
