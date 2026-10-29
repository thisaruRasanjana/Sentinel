package registrysrv

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"

	"github.com/thisaruRasanjana/Sentinel/registry/internal/metrics"
	pb "github.com/thisaruRasanjana/Sentinel/registry/pkg/registryv1"
)

var tracer = otel.Tracer("sentinel/registry")

type ToolDef struct {
	UpstreamURL   string `json:"upstream_url"`
	HTTPMethod    string `json:"http_method"`
	RequiredScope string `json:"required_scope"`
}

type RegistryServer struct {
	pb.UnimplementedRegistryServiceServer
	mu    sync.RWMutex
	tools map[string]ToolDef
}

func NewRegistryServer(jsonFile string) (*RegistryServer, error) {
	s := &RegistryServer{
		tools: make(map[string]ToolDef),
	}
	if err := s.LoadFromJSON(jsonFile); err != nil {
		return nil, fmt.Errorf("failed to load tools: %w", err)
	}
	return s, nil
}

func (s *RegistryServer) LoadFromJSON(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var parsed map[string]ToolDef
	if err := json.Unmarshal(data, &parsed); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tools = parsed
	return nil
}

func (s *RegistryServer) GetTool(ctx context.Context, req *pb.GetToolRequest) (*pb.GetToolResponse, error) {
	ctx, span := tracer.Start(ctx, "RegistryServer.GetTool")
	defer span.End()

	span.SetAttributes(attribute.String("registry.tool_id", req.GetToolId()))

	start := time.Now()

	s.mu.RLock()
	tool, exists := s.tools[req.GetToolId()]
	s.mu.RUnlock()

	elapsed := float64(time.Since(start).Milliseconds())
	foundStr := strconv.FormatBool(exists)
	metrics.LookupTotal.WithLabelValues(foundStr).Inc()
	metrics.LookupLatencyMs.WithLabelValues(foundStr).Observe(elapsed)

	if !exists {
		span.SetAttributes(attribute.Bool("registry.found", false))
		span.SetStatus(codes.Ok, "tool not found")
		return &pb.GetToolResponse{Found: false}, nil
	}

	span.SetAttributes(
		attribute.Bool("registry.found", true),
		attribute.String("registry.upstream_url", tool.UpstreamURL),
	)
	span.SetStatus(codes.Ok, "")

	return &pb.GetToolResponse{
		Found: true,
		Metadata: &pb.ToolMetadata{
			UpstreamUrl:   tool.UpstreamURL,
			HttpMethod:    tool.HTTPMethod,
			RequiredScope: tool.RequiredScope,
		},
	}, nil
}
