package grpcsrv

import (
	"context"
	"strconv"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"

	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/limiter"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/metrics"
	pb "github.com/thisaruRasanjana/Sentinel/policy-engine/pkg/policyv1"
)

var tracer = otel.Tracer("sentinel/policy-engine")

type PolicyServer struct {
	pb.UnimplementedPolicyServiceServer
	limiter *limiter.ShardedLimiter
}

func NewPolicyServer(l *limiter.ShardedLimiter) *PolicyServer {
	return &PolicyServer{limiter: l}
}

func (s *PolicyServer) Check(ctx context.Context, req *pb.CheckRequest) (*pb.CheckResponse, error) {
	ctx, span := tracer.Start(ctx, "PolicyServer.Check")
	defer span.End()

	agentID := req.GetAgentId()
	toolID := req.GetToolId()
	cost := int(req.GetCost())
	if cost <= 0 {
		cost = 1
	}

	span.SetAttributes(
		attribute.String("policy.agent_id", agentID),
		attribute.String("policy.tool_id", toolID),
		attribute.Int("policy.cost", cost),
	)

	start := time.Now()
	allowed, remaining, retryAfter := s.limiter.Check(agentID, toolID, cost)
	elapsed := float64(time.Since(start).Milliseconds())

	allowedStr := strconv.FormatBool(allowed)
	metrics.ChecksTotal.WithLabelValues(allowedStr).Inc()
	metrics.CheckLatencyMs.WithLabelValues(allowedStr).Observe(elapsed)

	span.SetAttributes(
		attribute.Bool("policy.allowed", allowed),
		attribute.Int("policy.remaining", remaining),
	)
	span.SetStatus(codes.Ok, "")

	return &pb.CheckResponse{
		Allowed:      allowed,
		Remaining:    int32(remaining),
		RetryAfterMs: retryAfter,
	}, nil
}
