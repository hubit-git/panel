# Build from the repository root. The image of the panel (PHP-FPM); the web server is the plain Caddy image.
#   development (default target `app`): docker build -f docker/Dockerfile .   (built from this repository)
#   a release: docker build -f docker/Dockerfile --target release --build-context dist=FOLDER .
#              (FOLDER is the content of the release zip, the encoded product; tools/release.sh does this)

# 1. The React app
FROM node:22-alpine AS frontend
WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
# The build writes to ../backend/public/static
RUN mkdir -p /build/backend/public && npm run build

# 2. The PHP packages
FROM composer:2 AS vendor
WORKDIR /app
COPY backend/ ./
RUN composer install --no-dev --optimize-autoloader --no-interaction --ignore-platform-reqs

# 3. The runtime: PHP-FPM with what the panel needs. The panel's files are added by the two targets below.
FROM php:8.1-fpm-bookworm AS runtime
LABEL org.opencontainers.image.source="https://github.com/hubit-git/panel"
ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN install-php-extensions pdo_mysql zip opcache ioncube_loader

# The panel's files wait in /opt/panel-dist. /app is a volume (files, storage and .env together, so the panel can
# update itself the same way as on any host); the entrypoint fills it from here the first time.
WORKDIR /app
COPY docker/php.ini /usr/local/etc/php/conf.d/zz-panel.ini
COPY docker/prepare-env.php /usr/local/bin/prepare-env.php
COPY docker/entrypoint.sh /usr/local/bin/panel-entrypoint
RUN chmod +x /usr/local/bin/panel-entrypoint

ENTRYPOINT ["panel-entrypoint"]
CMD ["php-fpm"]

# 4. A release: the encoded product comes in as the named context `dist`
FROM runtime AS release
COPY --from=dist / /opt/panel-dist

# 5. Development (the last stage is the default target): built from this repository
FROM runtime AS app
COPY --from=vendor /app /opt/panel-dist
COPY --from=frontend /build/backend/public/static /opt/panel-dist/public/static
