package auditsrv

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"sync"

	pb "github.com/thisaruRasanjana/Sentinel/audit-sink/pkg/auditv1"
)

// AuditEntry is the JSON structure written to the log file.
// It wraps the protobuf AuditEvent fields and adds hash chaining.
type AuditEntry struct {
	EventID    string `json:"event_id"`
	Timestamp  string `json:"timestamp"`
	AgentID    string `json:"agent_id"`
	Principal  string `json:"principal"`
	ToolID     string `json:"tool_id"`
	StatusCode int32  `json:"status_code"`
	Outcome    string `json:"outcome"`
	LatencyMs  int64  `json:"latency_ms"`
	TraceID    string `json:"trace_id"`
	PrevHash   string `json:"prev_hash"`
	Hash       string `json:"hash"`
}

type AuditServer struct {
	pb.UnimplementedAuditServiceServer
	mu       sync.Mutex
	file     *os.File
	prevHash string
}

func NewAuditServer(logPath string) (*AuditServer, error) {
	f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return nil, fmt.Errorf("failed to open audit log: %w", err)
	}
	return &AuditServer{
		file:     f,
		prevHash: "GENESIS",
	}, nil
}

func (s *AuditServer) RecordEvent(ctx context.Context, ev *pb.AuditEvent) (*pb.AuditAck, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	entry := AuditEntry{
		EventID:    ev.GetEventId(),
		Timestamp:  ev.GetTimestamp(),
		AgentID:    ev.GetAgentId(),
		Principal:  ev.GetPrincipal(),
		ToolID:     ev.GetToolId(),
		StatusCode: ev.GetStatusCode(),
		Outcome:    ev.GetOutcome(),
		LatencyMs:  ev.GetLatencyMs(),
		TraceID:    ev.GetTraceId(),
		PrevHash:   s.prevHash,
	}

	// Compute hash over the entry (excluding the Hash field itself)
	hashInput := fmt.Sprintf("%s|%s|%s|%s|%s|%d|%s|%d|%s|%s",
		entry.EventID, entry.Timestamp, entry.AgentID, entry.Principal,
		entry.ToolID, entry.StatusCode, entry.Outcome, entry.LatencyMs,
		entry.TraceID, entry.PrevHash)
	sum := sha256.Sum256([]byte(hashInput))
	entry.Hash = hex.EncodeToString(sum[:])

	line, err := json.Marshal(entry)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal audit entry: %w", err)
	}

	if _, err := s.file.Write(append(line, '\n')); err != nil {
		return nil, fmt.Errorf("failed to write audit entry: %w", err)
	}

	s.prevHash = entry.Hash

	return &pb.AuditAck{
		Accepted:  true,
		ChainHash: entry.Hash,
	}, nil
}

func (s *AuditServer) Close() error {
	return s.file.Close()
}
