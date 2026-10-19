#!/bin/sh
set -e

DIST=/opt/panel-dist
cd /app

# Fill the /app volume with the panel's files: the first time, and later only when this image is newer than the
# files in the volume, so an update made from the panel is never undone by an older image
image_version=$(cat "$DIST/VERSION")
fill=no

if [ ! -f VERSION ]; then
    fill=yes
else
    volume_version=$(cat VERSION)
    newest=$(printf '%s\n%s\n' "$image_version" "$volume_version" | sort -V | tail -n 1)

    if [ "$newest" = "$image_version" ] && [ "$image_version" != "$volume_version" ]; then
        fill=yes
    fi
fi

if [ "$fill" = yes ]; then
    for name in app system config vendor database public; do
        rm -rf "$name"
        cp -a "$DIST/$name" "$name"
    done

    rm -f ENCODED
    for name in VERSION ENCODED composer.json composer.lock .env.example; do
        if [ -f "$DIST/$name" ]; then
            cp "$DIST/$name" "$name"
        fi
    done
fi

# The volume is made by Docker as root; PHP-FPM works as www-data and the panel replaces its own files
mkdir -p storage
find /app ! -user www-data -exec chown www-data:www-data {} +

# Make or update .env as www-data, so the file is owned by the user that writes it later
runuser -u www-data -- php /usr/local/bin/prepare-env.php

exec "$@"
