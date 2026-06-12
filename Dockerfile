# Stage 1: Builder
FROM hexpm/elixir:1.16.2-erlang-26.2.3-debian-bookworm-20240130-slim AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git && apt-get clean && rm -f /var/lib/apt/lists/*

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Set build environment
ENV MIX_ENV="prod"

# Install Elixir dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy configuration and source files
COPY config config
COPY lib lib
COPY priv priv
COPY assets assets

# Compile assets and digest them
RUN mix assets.deploy

# Build the release
RUN mix compile
RUN mix release

# Stage 2: Runner (distroless-like slim debian runner)
FROM debian:bookworm-slim AS runner

# Install runtime dependencies
RUN apt-get update -y && apt-get install -y libstdc++6 openssl ca-certificates curl postgresql-client && apt-get clean && rm -f /var/lib/apt/lists/*

# Set locale
ENV LANG=C.UTF-8

# Create non-root user and setup directory
WORKDIR /app
RUN chown nobody /app

# Copy the compiled release
COPY --from=builder --chown=nobody /app/_build/prod/rel/ex_gocd ./

USER nobody

# Start the application release
CMD ["/app/bin/ex_gocd", "start"]
