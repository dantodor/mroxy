########################################################################
FROM elixir:1.8.2-slim

ENV SHELL=/bin/sh
ENV application_directory=/usr/src/app
ENV ENABLE_XVBF=true

RUN mkdir -p $application_directory

WORKDIR $application_directory

# Install utilities
RUN apt-get update --fix-missing && apt-get -y upgrade

# Run everything after as non-privileged user.
USER root

ENV MIX_ENV=prod

# Install Hex + Rebar
RUN mix do local.hex --force, local.rebar --force

# Cache & compile elixir deps
COPY config/ $application_directory/config/
COPY mix.exs mix.lock $application_directory/
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Get rest of application and compile
COPY . $application_directory/
RUN mix compile --no-deps-check

RUN mix do deps.loadpaths --no-deps-check

CMD ["mix", "run", "--no-halt"]
