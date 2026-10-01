# Jellyfin with MariaDB

A fresh Jellyfin 10.11.11 instance using the experimental
[canepan MySQL provider](https://github.com/canepan/jellyfin-plugin-mysql),
pinned to commit `85fef358c8bf0ca9c0119a02f6e9e697fea161a8`.

The Dockerfile fetches the upstream source, generates its MariaDB schema,
compiles the plugin and packages its dependencies/metadata with the official
Jellyfin image and MariaDB client tools. No .NET installation, submodule or
pre-generated migration source is required outside the image build.

`20260807000000_InitialCreate` is the initial schema identifier for this pinned
provider/server pair. The build replaces EF's generated timestamp with this
fixed identifier before compiling, so rebuilds do not attempt to create the
same tables again. It creates a new database schema; it does not import SQLite
users, watch history or library metadata. Changing the server/provider version
requires a separate schema-upgrade plan, not merely changing the image tag.

## Deployment

The existing home-lab Argo `ci-build` workflow performs clone, Kaniko build/push,
`BUILD_TAG` substitution, `kubectl apply` and Discord notification. It pushes
`jellyfin-mysql:<commit>` to the existing registry and deploys
`localhost:31234/jellyfin-mysql:$BUILD_TAG` from `k8s.template.yaml`.
No workflow changes or Helmfile image-promotion step are needed.

Home-lab manages the repository registration, the existing SOPS-encrypted
`deployments/database-credentials` Secret for the shared `cluster` DB account,
and the namespace-local `paul-steele.com` TLS certificate. Database credentials must never be added to
this repository, connection XML or image layers.

Before enabling the signed GitHub push webhook:

1. Create the empty `jellyfin` database on `192.168.0.101:3307` using
   `utf8mb4`/`utf8mb4_nopad_bin`. Reuse the existing shared `cluster` account;
   do not create another DB user or change its credentials/grants. The server
   has TLS disabled, so `MYSQL_SSLMODE=Disabled` explicitly matches this LAN
   endpoint. Confirm network access and schema permissions.
2. Verify the existing credential Secret and apply the wildcard certificate
   through home-lab.
3. Create empty NFS directories `/volume1/files/jellyfin-mysql/config` and
   `/volume1/files/jellyfin-mysql/cache` with suitable permissions.
4. Record the old `video` Helm release definition/revision, then uninstall
   only that release. Keep `/volume1/files/jellyfin/config` and
   `/volume1/files/jellyfin/cache` untouched for rollback.
5. Enable the existing signed webhook at
   `https://ci-events.paul-steele.com/api/v1/events/ci/push` and trigger a build.

The new Deployment runs in `deployments`, uses `Recreate` and one replica, and
retains `https://video.paul-steele.com` plus the existing `/media` NFS mount.

## Fresh setup and verification

The operator completes Jellyfin's initial setup wizard, creates the admin/users,
adds libraries under `/media` and starts the initial scan. Old SQLite/config
files are not copied into the new instance. Restrict ordinary client access
until the admin account is configured.

Check startup logs for the MySQL provider and schema creation, then verify
`BaseItems`, `Users`, `UserData` and `__EFMigrationsHistory` in MariaDB. Test
login, scanning, search, direct playback and transcoding. Create watch/resume
state and restart/redeploy to verify it persists in MariaDB. Rebuilding this
pinned image must not rerun `InitialCreate`.

## Backups and rollback

The image includes `mariadb-dump`/`mariadb` for the provider's schema-change
backup hooks. Verify the existing home-lab database backup CronJob includes
`jellyfin`; it overwrites the latest SQL file, so retain a dated dump before
future upgrades. Jellyfin's config directory also needs normal NAS backups.

For rollback, disable the new webhook and drain pending workflows, stop/remove
this Deployment/Service/Ingress, then recover and reapply the recorded old
`video` Helm release against its untouched original NFS paths. Never run both
owners simultaneously. This returns to the old instance, not to state created
in the fresh MariaDB database.

## Delivery choice

The selected custom image keeps Jellyfin, provider/dependencies and MariaDB
backup tools together in one build. Keeping the stock image instead would
require a separately versioned plugin bundle on NFS and external SQL backup
commands because the stock image lacks MariaDB client tools. That alternative
is not implemented here.

## License

GPL-3.0. The provider is by canepan and derives from JPVenson/Jellyfin.Pgsql.
The upstream license is included in the repository and runtime image.
