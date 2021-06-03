ARG PHP_VERSION="7.3"
ARG COMPOSER_VERSION="1.9"
# No Support for Gesso image with PHP 7.3 & Node 10
ARG NODE_VERSION="12"

FROM forumone/wordpress:${PHP_VERSION}-xdebug AS dev

FROM forumone/wordpress:${PHP_VERSION} AS base

FROM forumone/composer:${COMPOSER_VERSION} AS composer

RUN mkdir -p web

COPY ["auth.json", "composer.json", "composer.lock", "./"]

RUN set -ex \
  && composer install --no-dev --optimize-autoloader

FROM composer AS composer-dev

# Install additional dev dependencies
RUN set -ex \
  && composer install --optimize-autoloader

RUN rm ./auth.json

FROM forumone/gesso:php${PHP_VERSION}-node${NODE_VERSION} AS gesso

RUN apk upgrade --update && apk add --no-cache python3 python3-dev gcc make gfortran freetype-dev musl-dev libpng-dev g++ lapack-dev

# Install npm dependencies

COPY ["web/wp-content/themes/gesso/package*.json", "./"]

RUN if test -e package-lock.json; then npm ci; else npm i; fi

# Copy sources and build

COPY ["web/wp-content/themes/gesso", "./"]

RUN set -ex \
  && npx gulp build

# Use a temporary image to clean dev dependencies for production. This allows
# The dev image to start with these files in place still rather than rebuilding.
FROM gesso AS gesso-clean

RUN set -ex \
  && rm -rf node_modules

FROM gesso AS gesso-dev

RUN set -ex \
  && npm install

FROM base AS release

COPY ["composer.json", "composer.lock", "./"]

COPY --from=composer ["/app/web", "web"]

COPY --from=gesso-clean ["/app", "web/wp-content/themes/gesso"]

COPY ["web", "web"]

RUN if test -e .env.production; then mv .env.production .env; fi

FROM release AS test

COPY --from=composer-dev ["/app/web", "web"]

COPY --from=gesso-dev ["/app", "web/wp-content/themes/gesso"]

# Ensure the default image to be built is the release image so any builds
# not explicitly defining a target receive the production release image.
FROM release
