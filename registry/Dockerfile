FROM golang:1.26-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o registry ./cmd/server

FROM alpine:3.20

COPY --from=builder /app/registry /registry
COPY tools.json /tools.json
ENV TOOLS_JSON_PATH=/tools.json

EXPOSE 9002

CMD ["/registry"]
