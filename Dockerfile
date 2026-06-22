# Stage 1: Compiler (Runs natively on the host platform for fast compilation)
FROM --platform=$BUILDPLATFORM hexpm/elixir:1.20.1-erlang-29.0.2-debian-bookworm-20260610-slim AS compiler

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git && apt-get clean && rm -rf /var/lib/apt/lists/*

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix local.hex --force && mix local.rebar --force

# Set build environment
ENV MIX_ENV="prod"

# Install Elixir dependencies
COPY mix.exs mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=/app/deps,sharing=shared \
    mix deps.get --only $MIX_ENV

RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=/app/deps,sharing=shared \
    --mount=type=cache,target=/app/_build,sharing=shared \
    mix deps.compile

# Copy configuration and source files
COPY config config
COPY lib lib
COPY priv priv
COPY assets assets

# Compile the application first so colocated hooks are available to esbuild.
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=/app/deps,sharing=shared \
    --mount=type=cache,target=/app/_build,sharing=shared \
    mix local.hex --force && mix local.rebar --force && mix compile

# Compile assets and digest them
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=/app/deps,sharing=shared \
    --mount=type=cache,target=/app/_build,sharing=shared \
    mix local.hex --force && mix assets.deploy

# Copy compiled files out of cache mounts to persistent locations
RUN --mount=type=cache,target=/app/deps,sharing=shared \
    --mount=type=cache,target=/app/_build,sharing=shared \
    cp -r /app/deps /app/compiled_deps && cp -r /app/_build /app/compiled_build


# Stage 2: Builder (Runs on the target platform to package the release with the target ERTS)
FROM hexpm/elixir:1.20.1-erlang-29.0.2-debian-bookworm-20260610-slim AS builder

# Install git since git dependencies need git checks during release load
RUN apt-get update -y && apt-get install -y git && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Set build environment
ENV MIX_ENV="prod"
ENV ERL_AFLAGS="+JMsingle true"

# Copy dependencies and pre-compiled build artifacts from compiler stage
COPY --from=compiler /app /app

# Move compiled files back to their correct locations
RUN mv /app/compiled_deps /app/deps && mv /app/compiled_build /app/_build

# Build the release (uses target ERTS)
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix release --overwrite && cp -r _build/prod/rel/ex_gocd /app/release

# Stage 2: Runner (distroless-like slim debian runner)
FROM debian:bookworm-slim AS runner

# Install runtime dependencies
RUN apt-get update -y && apt-get install -y libstdc++6 openssl ca-certificates curl postgresql-client && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set locale
ENV LANG=C.UTF-8

# Create non-root user and setup directory
WORKDIR /app
RUN chown nobody /app

# Copy the compiled release
COPY --from=builder --chown=nobody /app/release ./

USER nobody

# Start the application release
CMD ["/app/bin/ex_gocd", "start"]
