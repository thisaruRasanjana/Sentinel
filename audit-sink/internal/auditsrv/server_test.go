package auditsrv

import (
	"context"
	"os"
	"testing"

	pb "github.com/thisaruRasanjana/Sentinel/audit-sink/pkg/auditv1"
)

func TestRecordEvent_WritesJSONL(t *testing.T) {
	tmpFile, err := os.CreateTemp(t.TempDir(), "audit-*.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	defer tmpFile.Close()

	srv, err := NewAuditServer(tmpFile.Name())
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Close()

	ack, err := srv.RecordEvent(context.Background(), &pb.AuditEvent{
		EventId:    "evt-001",
		Timestamp:  "2026-10-13T06:00:00Z",
		AgentId:    "agent:test",
		Principal:  "user:test",
		ToolId:     "invoice.create",
		StatusCode: 201,
		Outcome:    "SUCCESS",
		LatencyMs:  42,
		TraceId:    "trace-001",
	})
	if err != nil {
		t.Fatalf("RecordEvent failed: %v", err)
	}
	if !ack.Accepted {
		t.Fatal("expected ack.Accepted to be true")
	}
	if ack.ChainHash == "" {
		t.Fatal("expected non-empty chain hash")
	}
}

func TestRecordEvent_HashChaining(t *testing.T) {
	tmpFile, err := os.CreateTemp(t.TempDir(), "audit-*.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	defer tmpFile.Close()

	srv, err := NewAuditServer(tmpFile.Name())
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Close()

	ack1, _ := srv.RecordEvent(context.Background(), &pb.AuditEvent{
		EventId: "evt-001", Timestamp: "2026-10-13T06:00:00Z",
		AgentId: "agent:a", Principal: "user:a", ToolId: "t1",
		StatusCode: 200, Outcome: "SUCCESS", LatencyMs: 10, TraceId: "tr-1",
	})

	ack2, _ := srv.RecordEvent(context.Background(), &pb.AuditEvent{
		EventId: "evt-002", Timestamp: "2026-10-13T06:00:01Z",
		AgentId: "agent:b", Principal: "user:b", ToolId: "t2",
		StatusCode: 201, Outcome: "SUCCESS", LatencyMs: 20, TraceId: "tr-2",
	})

	if ack1.ChainHash == ack2.ChainHash {
		t.Fatal("two different events must produce different hashes")
	}
}
