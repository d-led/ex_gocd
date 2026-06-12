# Stage 1: Builder
FROM golang:1.26-alpine AS builder

RUN apk add --no-cache git gcc musl-dev

WORKDIR /app

# Copy dependency files and download
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Statically compile the binary without CGO
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o gocd-agent .

# Stage 2: Runner
FROM alpine:latest

# Install runtime dependencies needed for SCM checkout and execution
RUN apk add --no-cache ca-certificates git bash openssh-client curl

WORKDIR /app

# Copy compiled agent binary
COPY --from=builder /app/gocd-agent /usr/local/bin/gocd-agent

# Configure default agent environment
ENV AGENT_SERVER_URL="http://localhost:4000"
ENV EX_GOCD_DEMO_COOKIE="ex-gocd-demo-cookie"

CMD ["gocd-agent"]
