package auditsrv

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"sync"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"

	"github.com/thisaruRasanjana/Sentinel/audit-sink/internal/metrics"
	pb "github.com/thisaruRasanjana/Sentinel/audit-sink/pkg/auditv1"
)

var tracer = otel.Tracer("sentinel/audit-sink")

// AuditEntry is the JSON structure written to the log file.
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
	// Start an OTel span. The parent span is extracted automatically from ctx
	// by the otelgrpc server interceptor in main.go.
	ctx, span := tracer.Start(ctx, "AuditServer.RecordEvent")
	defer span.End()

	span.SetAttributes(
		attribute.String("audit.event_id", ev.GetEventId()),
		attribute.String("audit.agent_id", ev.GetAgentId()),
		attribute.String("audit.tool_id", ev.GetToolId()),
		attribute.String("audit.outcome", ev.GetOutcome()),
		attribute.Int("audit.status_code", int(ev.GetStatusCode())),
	)

	start := time.Now()

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

	hashInput := fmt.Sprintf("%s|%s|%s|%s|%s|%d|%s|%d|%s|%s",
		entry.EventID, entry.Timestamp, entry.AgentID, entry.Principal,
		entry.ToolID, entry.StatusCode, entry.Outcome, entry.LatencyMs,
		entry.TraceID, entry.PrevHash)
	sum := sha256.Sum256([]byte(hashInput))
	entry.Hash = hex.EncodeToString(sum[:])

	line, err := json.Marshal(entry)
	if err != nil {
		span.SetStatus(codes.Error, "marshal failed")
		metrics.EventsTotal.WithLabelValues("error").Inc()
		return nil, fmt.Errorf("failed to marshal audit entry: %w", err)
	}

	if _, err := s.file.Write(append(line, '\n')); err != nil {
		span.SetStatus(codes.Error, "write failed")
		metrics.EventsTotal.WithLabelValues("error").Inc()
		return nil, fmt.Errorf("failed to write audit entry: %w", err)
	}

	s.prevHash = entry.Hash

	elapsed := float64(time.Since(start).Milliseconds())
	metrics.EventsTotal.WithLabelValues(ev.GetOutcome()).Inc()
	metrics.EventLatencyMs.WithLabelValues(ev.GetOutcome()).Observe(elapsed)

	span.SetStatus(codes.Ok, "")
	return &pb.AuditAck{
		Accepted:  true,
		ChainHash: entry.Hash,
	}, nil
}

func (s *AuditServer) Close() error {
	return s.file.Close()
}
