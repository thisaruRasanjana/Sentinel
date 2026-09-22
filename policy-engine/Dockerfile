FROM golang:1.26-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o policy-engine ./cmd/server

FROM alpine:3.20

COPY --from=builder /app/policy-engine /policy-engine
EXPOSE 9001 9010

CMD ["/policy-engine"]
