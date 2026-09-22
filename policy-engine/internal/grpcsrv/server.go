package grpcsrv

import (
	"context"

	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/limiter"
	pb "github.com/thisaruRasanjana/Sentinel/policy-engine/pkg/policyv1"
)

type PolicyServer struct {
	pb.UnimplementedPolicyServiceServer
	limiter *limiter.ShardedLimiter
}

func NewPolicyServer(l *limiter.ShardedLimiter) *PolicyServer {
	return &PolicyServer{
		limiter: l,
	}
}

func (s *PolicyServer) Check(ctx context.Context, req *pb.CheckRequest) (*pb.CheckResponse, error) {
	agentID := req.GetAgentId()
	toolID := req.GetToolId()
	cost := int(req.GetCost())

	if cost <= 0 {
		cost = 1 // Default cost
	}

	allowed, remaining, retryAfter := s.limiter.Check(agentID, toolID, cost)

	return &pb.CheckResponse{
		Allowed:      allowed,
		Remaining:    int32(remaining),
		RetryAfterMs: retryAfter,
	}, nil
}
