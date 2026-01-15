# Build stage
ARG ELIXIR_VERSION=1.16.0
ARG OTP_VERSION=26.2.1
ARG DEBIAN_VERSION=bookworm-20231009-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js for asset compilation
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build environment
ENV MIX_ENV="prod"

# Copy shared library first
COPY shared ../shared

# Install mix dependencies
COPY phoenix_app/mix.exs phoenix_app/mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files
COPY phoenix_app/config/config.exs phoenix_app/config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy assets
COPY phoenix_app/priv priv
COPY phoenix_app/assets assets

# Install npm dependencies and compile assets
WORKDIR /app/assets
RUN npm install

WORKDIR /app

# Compile assets
RUN mix assets.deploy

# Compile the release
COPY phoenix_app/lib lib
RUN mix compile

# Copy runtime config
COPY phoenix_app/config/runtime.exs config/

# Build release
RUN mix release

# Runner stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV="prod"

# Copy the release from builder
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/webtoon_web ./

USER nobody

# Run migrations on startup and start the server
CMD ["/app/bin/webtoon_web", "start"]
