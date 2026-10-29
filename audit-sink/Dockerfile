FROM golang:1.26-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o audit-sink ./cmd/server

FROM alpine:3.20

RUN mkdir -p /data
COPY --from=builder /app/audit-sink /audit-sink
ENV AUDIT_LOG_PATH=/data/audit.jsonl

EXPOSE 9003

CMD ["/audit-sink"]
