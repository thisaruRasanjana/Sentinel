package limiter

import (
	"fmt"
	"math/rand"
	"sync"
	"testing"
)

// NaiveLimiter is a simple, single-mutex rate limiter for comparison purposes.
type NaiveLimiter struct {
	mu      sync.Mutex
	buckets map[string]*Bucket
	agentR  float64
	agentM  float64
	toolR   float64
	toolM   float64
}

func NewNaiveLimiter(ar, am, tr, tm float64) *NaiveLimiter {
	return &NaiveLimiter{
		buckets: make(map[string]*Bucket),
		agentR:  ar,
		agentM:  am,
		toolR:   tr,
		toolM:   tm,
	}
}

func (n *NaiveLimiter) Check(agentID, toolID string, cost int) (bool, int, int64) {
	n.mu.Lock()
	defer n.mu.Unlock()

	tb, tbOk := n.buckets[agentID+":"+toolID]
	gb, gbOk := n.buckets[agentID]

	if !tbOk {
		tb = NewBucket(n.toolM, n.toolR)
		n.buckets[agentID+":"+toolID] = tb
	}
	if !gbOk {
		gb = NewBucket(n.agentM, n.agentR)
		n.buckets[agentID] = gb
	}

	gbAllowed, gbRem, gbRetry := gb.Allow(cost)
	if !gbAllowed {
		return false, gbRem, gbRetry
	}

	return tb.Allow(cost)
}

func generateAgents(num int) []string {
	agents := make([]string, num)
	for i := 0; i < num; i++ {
		agents[i] = fmt.Sprintf("agent_%d", i)
	}
	return agents
}

func generateTools(num int) []string {
	tools := make([]string, num)
	for i := 0; i < num; i++ {
		tools[i] = fmt.Sprintf("tool_%d", i)
	}
	return tools
}

func BenchmarkShardedLimiter(b *testing.B) {
	agents := generateAgents(100)
	tools := generateTools(10)
	
	// Shards = 64
	l := NewShardedLimiter(64, 1000.0, 1000.0, 1000.0, 1000.0)

	concurrencies := []int{1, 8, 64, 512}

	for _, p := range concurrencies {
		b.Run(fmt.Sprintf("Goroutines-%d", p), func(b *testing.B) {
			b.SetParallelism(p)
			b.RunParallel(func(pb *testing.PB) {
				// Each goroutine picks a random agent and tool
				for pb.Next() {
					agent := agents[rand.Intn(len(agents))]
					tool := tools[rand.Intn(len(tools))]
					l.Check(agent, tool, 1)
				}
			})
		})
	}
}

func BenchmarkNaiveLimiter(b *testing.B) {
	agents := generateAgents(100)
	tools := generateTools(10)

	l := NewNaiveLimiter(1000.0, 1000.0, 1000.0, 1000.0)

	concurrencies := []int{1, 8, 64, 512}

	for _, p := range concurrencies {
		b.Run(fmt.Sprintf("Goroutines-%d", p), func(b *testing.B) {
			b.SetParallelism(p)
			b.RunParallel(func(pb *testing.PB) {
				for pb.Next() {
					agent := agents[rand.Intn(len(agents))]
					tool := tools[rand.Intn(len(tools))]
					l.Check(agent, tool, 1)
				}
			})
		})
	}
}
