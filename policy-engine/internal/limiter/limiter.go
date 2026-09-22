package limiter

import (
	"hash/fnv"
	"runtime"
	"sync"
)

// ShardedLimiter is a concurrent, sharded rate limiter.
type ShardedLimiter struct {
	shards    []*shard
	numShards uint32
	
	// Default configuration
	agentRate float64 // per second
	agentMax  float64
	toolRate  float64 // per second
	toolMax   float64
}

type shard struct {
	mu      sync.RWMutex
	buckets map[string]*Bucket // key = "agentID:toolID"
	globals map[string]*Bucket // key = "agentID"
}

// NewShardedLimiter creates a limiter with default configurations.
// If numShards is 0, it defaults to runtime.NumCPU() * 4.
func NewShardedLimiter(numShards uint32, agentRate, agentMax, toolRate, toolMax float64) *ShardedLimiter {
	if numShards == 0 {
		numShards = uint32(runtime.NumCPU() * 4)
	}

	shards := make([]*shard, numShards)
	for i := range shards {
		shards[i] = &shard{
			buckets: make(map[string]*Bucket),
			globals: make(map[string]*Bucket),
		}
	}

	return &ShardedLimiter{
		shards:    shards,
		numShards: numShards,
		agentRate: agentRate,
		agentMax:  agentMax,
		toolRate:  toolRate,
		toolMax:   toolMax,
	}
}

func (l *ShardedLimiter) getShard(agentID string) *shard {
	h := fnv.New32a()
	h.Write([]byte(agentID))
	return l.shards[h.Sum32()%l.numShards]
}

// Check evaluates a request against both the tool-specific bucket and the agent's global bucket.
// Returns (allowed, remainingInToolBucket, retryAfterMs).
func (l *ShardedLimiter) Check(agentID, toolID string, cost int) (bool, int, int64) {
	s := l.getShard(agentID)
	bucketKey := agentID + ":" + toolID

	s.mu.RLock()
	tb, tbOk := s.buckets[bucketKey]
	gb, gbOk := s.globals[agentID]
	s.mu.RUnlock()

	if !tbOk || !gbOk {
		s.mu.Lock()
		if !tbOk {
			tb, tbOk = s.buckets[bucketKey]
			if !tbOk {
				tb = NewBucket(l.toolMax, l.toolRate)
				s.buckets[bucketKey] = tb
			}
		}
		if !gbOk {
			gb, gbOk = s.globals[agentID]
			if !gbOk {
				gb = NewBucket(l.agentMax, l.agentRate)
				s.globals[agentID] = gb
			}
		}
		s.mu.Unlock()
	}

	// 1. Check tool bucket first (cheaper and more specific)
	tbAllowed, tbRemaining, tbRetryAfter := tb.Allow(cost)
	if !tbAllowed {
		return false, tbRemaining, tbRetryAfter
	}

	// 2. Check global agent bucket
	// If global fails, we would ideally refund the tool bucket.
	// For simplicity, we let the tool bucket lose those tokens as a penalty.
	gbAllowed, gbRemaining, gbRetryAfter := gb.Allow(cost)
	if !gbAllowed {
		return false, gbRemaining, gbRetryAfter
	}

	return true, tbRemaining, 0
}

// GetBucketsForSync returns a copy of all buckets for syncing to Redis.
// This is used by the background sync goroutine.
func (l *ShardedLimiter) GetBucketsForSync() map[string]*Bucket {
	all := make(map[string]*Bucket)
	for _, s := range l.shards {
		s.mu.RLock()
		for k, b := range s.buckets {
			all[k] = b
		}
		for k, b := range s.globals {
			all[k] = b
		}
		s.mu.RUnlock()
	}
	return all
}

// RestoreBuckets injects buckets loaded from Redis on startup.
func (l *ShardedLimiter) RestoreBuckets(agentID string, toolID string, b *Bucket) {
	s := l.getShard(agentID)
	s.mu.Lock()
	defer s.mu.Unlock()
	
	if toolID == "" {
		s.globals[agentID] = b
	} else {
		s.buckets[agentID+":"+toolID] = b
	}
}
