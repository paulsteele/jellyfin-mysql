FROM mcr.microsoft.com/dotnet/sdk:9.0 AS plugin-build

ARG PLUGIN_COMMIT=85fef358c8bf0ca9c0119a02f6e9e697fea161a8
ARG SCHEMA_MIGRATION_ID=20260807000000_InitialCreate

WORKDIR /src

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git init . \
    && git remote add origin https://github.com/canepan/jellyfin-plugin-mysql.git \
    && git fetch --depth=1 origin "${PLUGIN_COMMIT}" \
    && git checkout --detach FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${PLUGIN_COMMIT}"

RUN dotnet tool install --tool-path /tools dotnet-ef --version 9.0.11
ENV PATH="/tools:${PATH}"

RUN set -eu; \
    dotnet ef migrations add InitialCreate \
        --project Jellyfin.Plugin.MySql \
        --output-dir Database/Migrations \
        -- --migration-provider Jellyfin-MySql; \
    migrations_dir=Jellyfin.Plugin.MySql/Database/Migrations; \
    generated_designer="$(find "${migrations_dir}" -name '*_InitialCreate.Designer.cs')"; \
    test -n "${generated_designer}"; \
    generated_id="$(basename "${generated_designer}" .Designer.cs)"; \
    sed -i "s/${generated_id}/${SCHEMA_MIGRATION_ID}/g" "${generated_designer}"; \
    mv "${migrations_dir}/${generated_id}.cs" "${migrations_dir}/${SCHEMA_MIGRATION_ID}.cs"; \
    mv "${generated_designer}" "${migrations_dir}/${SCHEMA_MIGRATION_ID}.Designer.cs"; \
    grep -F "[Migration(\"${SCHEMA_MIGRATION_ID}\")]" "${migrations_dir}/${SCHEMA_MIGRATION_ID}.Designer.cs"; \
    dotnet publish Jellyfin.Plugin.MySql/Jellyfin.Plugin.MySql.csproj \
        --configuration Release --output /out; \
    test -s /out/Jellyfin.Plugin.MySql.dll; \
    test -s /out/Pomelo.EntityFrameworkCore.MySql.dll; \
    test -s /out/MySqlConnector.dll; \
    printf '%s\n' "${SCHEMA_MIGRATION_ID}" > /out/schema-migration-id; \
    printf '%s\n' "${PLUGIN_COMMIT}" > /out/upstream-commit

FROM jellyfin/jellyfin:10.11.11

RUN apt-get update \
    && apt-get install -y --no-install-recommends mariadb-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=plugin-build /out/ /jellyfin-mysql/plugin/
COPY --from=plugin-build /src/LICENSE /usr/share/doc/jellyfin-mysql/COPYING
COPY meta.json /jellyfin-mysql/plugin/meta.json
COPY docker/database.xml /jellyfin-mysql/database.xml
COPY docker/entrypoint.sh /jellyfin-mysql/entrypoint.sh
RUN chmod 0755 /jellyfin-mysql/entrypoint.sh

ENTRYPOINT ["/jellyfin-mysql/entrypoint.sh"]
