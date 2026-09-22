package store

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/thisaruRasanjana/Sentinel/policy-engine/internal/limiter"
)

type RedisStore struct {
	client  *redis.Client
	limiter *limiter.ShardedLimiter
}

func NewRedisStore(addr string, l *limiter.ShardedLimiter) *RedisStore {
	rdb := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: "", // no password set
		DB:       0,  // use default DB
	})

	return &RedisStore{
		client:  rdb,
		limiter: l,
	}
}

// StartWriteBehind runs a background loop to persist bucket state to Redis.
func (s *RedisStore) StartWriteBehind(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.SyncToRedis(ctx)
		}
	}
}

// SyncToRedis forcibly syncs the current buckets to Redis.
func (s *RedisStore) SyncToRedis(ctx context.Context) {
	buckets := s.limiter.GetBucketsForSync()
	if len(buckets) == 0 {
		return
	}

	pipe := s.client.Pipeline()
	for key, bucket := range buckets {
		tokens, lastRefill := bucket.State()
		val := fmt.Sprintf("%f|%d", tokens, lastRefill.UnixNano())
		pipe.Set(ctx, "quota:"+key, val, 0)
	}

	_, err := pipe.Exec(ctx)
	if err != nil {
		log.Printf("Failed to sync quota state to Redis: %v", err)
	}
}

// LoadState retrieves the last known state from Redis and injects it into the limiter.
func (s *RedisStore) LoadState(ctx context.Context, agentRate, agentMax, toolRate, toolMax float64) error {
	iter := s.client.Scan(ctx, 0, "quota:*", 0).Iterator()
	for iter.Next(ctx) {
		fullKey := iter.Val()
		key := strings.TrimPrefix(fullKey, "quota:")

		val, err := s.client.Get(ctx, fullKey).Result()
		if err != nil {
			continue
		}

		parts := strings.Split(val, "|")
		if len(parts) != 2 {
			continue
		}

		tokens, err := strconv.ParseFloat(parts[0], 64)
		if err != nil {
			continue
		}

		unixNano, err := strconv.ParseInt(parts[1], 10, 64)
		if err != nil {
			continue
		}

		lastRefill := time.Unix(0, unixNano)
		
		var b *limiter.Bucket
		agentID := key
		toolID := ""

		if strings.Contains(key, ":") {
			keyParts := strings.SplitN(key, ":", 2)
			agentID = keyParts[0]
			toolID = keyParts[1]
			b = limiter.NewBucket(toolMax, toolRate)
		} else {
			b = limiter.NewBucket(agentMax, agentRate)
		}

		b.RestoreState(tokens, lastRefill)
		s.limiter.RestoreBuckets(agentID, toolID, b)
	}

	if err := iter.Err(); err != nil {
		log.Printf("Failed to load full state from Redis: %v", err)
		return err
	}

	return nil
}
