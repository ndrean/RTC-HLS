

ARG MIX_ENV="prod"
FROM hexpm/elixir:1.17.2-erlang-27.0.1-alpine-3.18.7 as build

RUN apk add --no-cache build-base git python3 curl
WORKDIR /app
RUN mix local.hex --force && \
  mix local.rebar --force

ARG MIX_ENV="prod"
ENV MIX_ENV="${MIX_ENV}"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# compile dependencies
RUN mix deps.compile

# copy assets
COPY priv priv


# compile project
COPY lib lib
RUN mix compile


# assemble release
RUN mix release

#FROM jrottenberg/ffmpeg:7.0-alpine
FROM lscr.io/linuxserver/ffmpeg:latest

ARG MIX_ENV="prod"

# install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs inotify-tools

ENV USER="elixir"

WORKDIR "/home/${USER}/app"

# Create  unprivileged user to run the release
RUN \
  addgroup \
  -g 1000 \
  -S "${USER}" \
  && adduser \
  -s /bin/sh \
  -u 1000 \
  -G "${USER}" \
  -h "/home/${USER}" \
  -D "${USER}" \
  && su "${USER}"

# run as user
USER "${USER}"

# copy release executables
COPY --from=build --chown="${USER}":"${USER}" /app/_build/"${MIX_ENV}"/rel/mix_mediasource ./

ENTRYPOINT ["bin/mix_mediasource"]

CMD ["start"]