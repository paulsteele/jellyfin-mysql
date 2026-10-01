#!/bin/sh
set -eu

: "${MYSQL_HOST:?Set MYSQL_HOST}"
: "${MYSQL_PORT:?Set MYSQL_PORT}"
: "${MYSQL_DB:?Set MYSQL_DB}"
: "${MYSQL_USER:?Set MYSQL_USER}"
: "${MYSQL_PASSWORD:?Set MYSQL_PASSWORD}"

plugin_dir=/config/plugins/MySQL
configuration_dir="${JELLYFIN_CONFIG_DIR:-/config/config}"

for artifact in Jellyfin.Plugin.MySql.dll Pomelo.EntityFrameworkCore.MySql.dll MySqlConnector.dll meta.json schema-migration-id; do
    if [ ! -s "/jellyfin-mysql/plugin/${artifact}" ]; then
        printf 'Missing MySQL provider artifact: %s\n' "${artifact}" >&2
        exit 1
    fi
done

mkdir -p "${plugin_dir}" "${configuration_dir}"
cp -R /jellyfin-mysql/plugin/. "${plugin_dir}/"
cp /jellyfin-mysql/database.xml "${configuration_dir}/database.xml"

exec /jellyfin/jellyfin "$@"
