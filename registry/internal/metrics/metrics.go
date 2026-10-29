package metrics

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	LookupTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "sentinel_registry_lookups_total",
		Help: "Total number of tool registry lookup requests.",
	}, []string{"found"})

	LookupLatencyMs = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "sentinel_registry_lookup_latency_ms",
		Help:    "Latency of tool registry lookups in milliseconds.",
		Buckets: []float64{0.1, 0.5, 1, 2, 5, 10, 25},
	}, []string{"found"})
)

func StartMetricsServer(addr string) {
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	if err := http.ListenAndServe(addr, mux); err != nil {
		panic("metrics server failed: " + err.Error())
	}
}

