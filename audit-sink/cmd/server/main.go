package main

import (
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/thisaruRasanjana/Sentinel/audit-sink/internal/auditsrv"
	pb "github.com/thisaruRasanjana/Sentinel/audit-sink/pkg/auditv1"
)

func main() {
	log.Println("Starting audit-sink service...")

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

	lis, err := net.Listen("tcp", ":9003")
	if err != nil {
		log.Fatalf("Failed to listen on :9003: %v", err)
	}

	grpcServer := grpc.NewServer()
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
