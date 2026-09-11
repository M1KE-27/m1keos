# Imagen del servidor de MIKE OS.
#
# En dos fases: una compila y otra sólo lleva lo compilado. La imagen final no
# tiene Elixir, ni Erlang instalado aparte, ni el código fuente: es un binario
# autocontenido sobre Debian slim. Unos 60 MB en vez de más de mil, y nada de
# lo que no se usa está ahí para que alguien lo use.
# La versión de Elixir tiene que ir con la del equipo donde se genera el
# proyecto: el runtime.exs que escribe Phoenix 1.8 usa el modificador ~r//E,
# que no existe antes de Elixir 1.20 y hace que el arranque muera con
# "invalid_option at position E".
ARG ELIXIR=1.20.4
ARG OTP=29.0.6
ARG DEBIAN=bookworm-20260824-slim

FROM hexpm/elixir:${ELIXIR}-erlang-${OTP}-debian-${DEBIAN} AS construir

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod

# Las dependencias primero y solas: así Docker reaprovecha esta capa mientras
# no cambie mix.lock, que es casi siempre. Copiar todo de golpe obligaría a
# recompilar media internet por cambiar una línea de código.
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
# Compilar ANTES de preparar los assets. Phoenix 1.8 genera hojas de estilo
# durante la compilación (los componentes "colocated"), así que al revés
# Tailwind se queja de que no encuentra un archivo que todavía no existe:
#   Can't resolve 'phoenix-colocated/.../colocated.css'
RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS final

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# UTF-8 de verdad: sin esto los acentos de la interfaz salen rotos.
RUN sed -i '/es_ES.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=es_ES.UTF-8 LANGUAGE=es_ES:es LC_ALL=es_ES.UTF-8

WORKDIR /app
# Sin root. Si algún día hay un fallo en el servidor, que no sea además con
# todos los permisos de la máquina.
RUN chown nobody /app
USER nobody

COPY --from=construir --chown=nobody:root /app/_build/prod/rel/mikeos_servidor ./

ENV MIX_ENV=prod
EXPOSE 4000
CMD ["/app/bin/server"]
