package limiter

import (
	"sync"
	"time"
)

// Bucket represents a single token bucket for rate limiting.
// It uses lazy refill to avoid background goroutines.
type Bucket struct {
	mu         sync.Mutex
	tokens     float64
	max        float64
	rate       float64 // tokens per second
	lastRefill time.Time
}

// NewBucket creates a new Bucket with the specified capacity (max) and rate (tokens per second).
func NewBucket(max float64, rate float64) *Bucket {
	return &Bucket{
		tokens:     max,
		max:        max,
		rate:       rate,
		lastRefill: time.Now(),
	}
}

// Allow checks if 'cost' tokens are available.
// If they are, it deducts them and returns (true, remaining, 0).
// If they aren't, it returns (false, remaining, retryAfterMs).
func (b *Bucket) Allow(cost int) (bool, int, int64) {
	b.mu.Lock()
	defer b.mu.Unlock()

	now := time.Now()

	// Lazy refill
	elapsed := now.Sub(b.lastRefill).Seconds()
	if elapsed > 0 {
		newTokens := elapsed * b.rate
		b.tokens += newTokens
		if b.tokens > b.max {
			b.tokens = b.max
		}
		b.lastRefill = now
	}

	costF := float64(cost)

	if b.tokens >= costF {
		b.tokens -= costF
		return true, int(b.tokens), 0
	}

	// Calculate how long until we have enough tokens
	deficit := costF - b.tokens
	retryAfterSec := deficit / b.rate
	retryAfterMs := int64(retryAfterSec * 1000)

	return false, int(b.tokens), retryAfterMs
}

// State returns the current token count and last refill time.
// Used for Redis write-behind.
func (b *Bucket) State() (float64, time.Time) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.tokens, b.lastRefill
}

// RestoreState restores the token count and last refill time from Redis.
func (b *Bucket) RestoreState(tokens float64, lastRefill time.Time) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.tokens = tokens
	b.lastRefill = lastRefill
}
