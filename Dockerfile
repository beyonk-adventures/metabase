###################
# STAGE 1.1: builder frontend
###################

FROM node:12.20.1-alpine as frontend

WORKDIR /app/source

ENV FC_LANG en-US LC_CTYPE en_US.UTF-8

# frontend dependencies
COPY yarn.lock package.json .yarnrc ./
RUN yarn install --production --frozen-lockfile
#RUN npx pnpm install

###################
# STAGE 1.2: builder backend
###################

# Build currently doesn't work on > Java 11 (i18n utils are busted) so build on 8 until we fix this
FROM adoptopenjdk/openjdk8:nightly as backend

WORKDIR /app/source

ENV FC_LANG en-US LC_CTYPE en_US.UTF-8

# bash:    various shell scripts
# curl:    needed by script that installs Clojure CLI

RUN apt-get update -yq && apt-get install -yq git curl bash

# lein:    backend dependencies and building
RUN curl https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein -o /usr/local/bin/lein && \
  chmod +x /usr/local/bin/lein && \
  /usr/local/bin/lein upgrade

# backend dependencies
COPY project.clj .
RUN lein deps

###################
# STAGE 1.3: main builder
###################

# Build currently doesn't work on > Java 11 (i18n utils are busted) so build on 8 until we fix this
FROM adoptopenjdk/openjdk8:nightly as builder

WORKDIR /app/source

ENV FC_LANG en-US LC_CTYPE en_US.UTF-8

# bash:    various shell scripts
# curl:    needed by script that installs Clojure CLI
# git:     ./bin/version
# yarn:    frontend building
# gettext: translations
# java-cacerts: installs updated cacerts to /etc/ssl/certs/java/cacerts

RUN apt-get update -yq && apt-get install -yq git wget curl make gettext ca-certificates-java

RUN curl -sL https://deb.nodesource.com/setup_15.x | bash - \
      && apt-get install -y nodejs \
      && npm install -g yarn

# lein:    backend dependencies and building
RUN curl https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein -o /usr/local/bin/lein && \
  chmod +x /usr/local/bin/lein && \
  /usr/local/bin/lein upgrade

# Clojure CLI (needed for some build scripts)
RUN curl https://download.clojure.org/install/linux-install-1.10.1.708.sh -o /tmp/linux-install-1.10.1.708.sh && \
  chmod +x /tmp/linux-install-1.10.1.708.sh && \
  sh /tmp/linux-install-1.10.1.708.sh

# import AWS RDS cert into /etc/ssl/certs/java/cacerts
RUN curl https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem -o rds-combined-ca-bundle.pem  && \
  /opt/java/openjdk/bin/keytool -noprompt -import -trustcacerts -alias aws-rds \
  -file rds-combined-ca-bundle.pem \
  -keystore /etc/ssl/certs/java/cacerts \
  -keypass changeit -storepass changeit

COPY --from=frontend /app/source/. .
COPY --from=backend /app/source/. .
COPY --from=backend /root/. /root/

# add the rest of the source
COPY . .

# build the app
RUN INTERACTIVE=false bin/build

# ###################
# # STAGE 2: runner
# ###################

FROM adoptopenjdk/openjdk11:jre-nightly as runner

WORKDIR /app

ENV FC_LANG en-US LC_CTYPE en_US.UTF-8

# dependencies
RUN apt-get update -yq && apt-get install -yq ttf-dejavu fontconfig

# add fixed cacerts
COPY --from=builder /etc/ssl/certs/java/cacerts /opt/java/openjdk/lib/security/cacerts

# add Metabase script and uberjar
RUN mkdir -p bin target/uberjar
COPY --from=builder /app/source/target/uberjar/metabase.jar /app/target/uberjar/
COPY --from=builder /app/source/bin/start /app/bin/

# create the plugins directory, with writable permissions
RUN mkdir -p /plugins && chmod a+rwx /plugins

# expose our default runtime port
EXPOSE 3000

# run it
ENTRYPOINT ["/app/bin/start"]
