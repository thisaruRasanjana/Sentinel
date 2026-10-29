package metrics

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	EventsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "sentinel_audit_events_total",
		Help: "Total number of audit events recorded.",
	}, []string{"outcome"})

	EventLatencyMs = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "sentinel_audit_event_latency_ms",
		Help:    "Latency of audit event write operations in milliseconds.",
		Buckets: []float64{0.5, 1, 2, 5, 10, 25, 50, 100},
	}, []string{"outcome"})
)

// StartMetricsServer starts a Prometheus /metrics HTTP endpoint on the given address.
// Call this in a goroutine: go metrics.StartMetricsServer(":9013")
func StartMetricsServer(addr string) {
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	if err := http.ListenAndServe(addr, mux); err != nil {
		// log is not imported here intentionally — caller handles startup log
		panic("metrics server failed: " + err.Error())
	}
}

