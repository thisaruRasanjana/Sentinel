package registrysrv

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sync"

	pb "github.com/thisaruRasanjana/Sentinel/registry/pkg/registryv1"
)

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
	s.mu.RLock()
	defer s.mu.RUnlock()

	tool, exists := s.tools[req.GetToolId()]
	if !exists {
		return &pb.GetToolResponse{
			Found: false,
		}, nil
	}

	return &pb.GetToolResponse{
		Found: true,
		Metadata: &pb.ToolMetadata{
			UpstreamUrl:   tool.UpstreamURL,
			HttpMethod:    tool.HTTPMethod,
			RequiredScope: tool.RequiredScope,
		},
	}, nil
}
