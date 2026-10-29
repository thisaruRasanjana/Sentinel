package metrics

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	ChecksTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "sentinel_policy_checks_total",
		Help: "Total number of policy check requests.",
	}, []string{"allowed"})

	CheckLatencyMs = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "sentinel_policy_check_latency_ms",
		Help:    "Latency of policy check operations in milliseconds.",
		Buckets: []float64{0.1, 0.5, 1, 2, 5, 10, 25, 50},
	}, []string{"allowed"})
)

func StartMetricsServer(addr string) {
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	if err := http.ListenAndServe(addr, mux); err != nil {
		panic("metrics server failed: " + err.Error())
	}
}

