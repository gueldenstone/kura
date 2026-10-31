# Builds the production release. Based on the image Phoenix generates (`mix phx.gen.release --docker`),
# on Debian rather than Alpine to avoid DNS resolution issues in production.
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - build image
#   - https://hub.docker.com/_/debian/tags - release image
ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=28.5.0.8
ARG DEBIAN_VERSION=bookworm-20261027-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# build tools for the SQLite and password hashing NIFs
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# compile-time config first, so a config change recompiles the dependencies
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv
COPY lib lib
RUN mix compile

COPY assets assets
RUN mix assets.deploy

# runtime.exs changes do not need a recompile
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/kura ./

# the SQLite database lives on a volume mounted here
RUN mkdir /data && chown nobody /data
VOLUME /data

USER nobody

CMD ["/app/bin/server"]
