# Phoenix-only plugin — no git/svn needed at runtime.
# Stage 1: Compiler
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
    cp -r _build/prod/rel/simple_org_chart /app/release

# Stage 2: Bare runtime — just the BEAM release
FROM alpine:3.21 AS runner

RUN apk add --no-cache ca-certificates

WORKDIR /app
COPY --from=compiler /app/release /app

ENV HOME=/app
ENV PHX_SERVER=true
EXPOSE 4101

CMD ["/app/bin/simple_org_chart", "start"]
