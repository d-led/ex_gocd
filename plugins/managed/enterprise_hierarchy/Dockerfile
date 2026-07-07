# Build: docker build --build-arg VARIANT=full -t enterprise_hierarchy .
# Variants: git (default), full (git + svn + build-essential)

# Stage 1: Compiler (official Elixir Alpine)
FROM --platform=$BUILDPLATFORM elixir:1.20.1-otp-29-alpine AS compiler

RUN apk add --no-cache build-base git
WORKDIR /app
ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force && \
    mix deps.get --only prod && mix deps.compile

RUN mkdir -p config lib priv
COPY config config
COPY lib lib
COPY priv priv

RUN mix compile && mix release --overwrite && \
    cp -r _build/prod/rel/enterprise_hierarchy /app/release

# Stage 2: Runner (Alpine — enterprise-ready, tiny, CVE-minimal)
FROM alpine:3.21 AS runner

ARG VARIANT=git

RUN apk add --no-cache \
      git openssh-client curl ca-certificates

RUN if [ "$VARIANT" = "full" ]; then \
      apk add --no-cache \
        subversion build-base mercurial bash; \
    fi

WORKDIR /app
COPY --from=compiler /app/release /app

ENV HOME=/app
ENV PHX_SERVER=true
EXPOSE 4110

CMD ["/app/bin/enterprise_hierarchy", "start"]
