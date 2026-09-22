package limiter

import (
	"testing"
	"time"
)

func TestLimiter_SingleAgentSingleTool(t *testing.T) {
	// 1 token per second, max 5 for agent, 2 for tool
	l := NewShardedLimiter(1, 1.0, 5.0, 1.0, 2.0)

	// First two requests should pass (tool max = 2)
	allowed, _, _ := l.Check("agent1", "tool1", 1)
	if !allowed {
		t.Errorf("Expected first request to be allowed")
	}

	allowed, _, _ = l.Check("agent1", "tool1", 1)
	if !allowed {
		t.Errorf("Expected second request to be allowed")
	}

	// Third request should fail because tool bucket is empty
	allowed, _, retryAfter := l.Check("agent1", "tool1", 1)
	if allowed {
		t.Errorf("Expected third request to be denied")
	}
	if retryAfter <= 0 {
		t.Errorf("Expected positive retryAfter, got %d", retryAfter)
	}
}

func TestLimiter_RefillOverTime(t *testing.T) {
	// Large rate so refill is fast in testing without waiting too long
	l := NewShardedLimiter(1, 100.0, 5.0, 100.0, 2.0)

	l.Check("agent1", "tool1", 2) // empty the tool bucket

	allowed, _, _ := l.Check("agent1", "tool1", 1)
	if allowed {
		t.Errorf("Expected immediate request to fail")
	}

	// Wait for refill (rate 100/s = 0.01s per token, wait 15ms)
	time.Sleep(15 * time.Millisecond)

	allowed, _, _ = l.Check("agent1", "tool1", 1)
	if !allowed {
		t.Errorf("Expected request to pass after refill")
	}
}

func TestLimiter_GlobalLimitEnforced(t *testing.T) {
	// Agent global max is 2, but tool max is 5.
	// Hitting different tools should quickly exhaust global limit.
	l := NewShardedLimiter(1, 1.0, 2.0, 1.0, 5.0)

	allowed, _, _ := l.Check("agent1", "tool1", 1) // global remaining 1
	if !allowed {
		t.Errorf("Expected first request to pass")
	}

	allowed, _, _ = l.Check("agent1", "tool2", 1) // global remaining 0
	if !allowed {
		t.Errorf("Expected second request to pass")
	}

	// Tool 3 bucket is full, but global bucket is empty
	allowed, _, _ = l.Check("agent1", "tool3", 1)
	if allowed {
		t.Errorf("Expected third request to fail due to global limit")
	}
}
