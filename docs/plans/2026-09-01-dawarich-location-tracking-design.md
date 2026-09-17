# Dawarich location tracking on osgiliath

Date: 2026-09-01

## Goal

Run [Dawarich](https://dawarich.app/) — a self-hosted alternative to Google
Location History — on osgiliath, fed from two sources:

1. **Home Assistant**, for continuous phone location.
2. **intervals.icu**, for GPS-bearing workouts, exported as GPX and imported
   into Dawarich by a polling script.

## Dawarich service

nixpkgs 25.11 ships `services.dawarich` (dawarich 1.7.5), so no containers are
needed. `services/dawarich.nix` is a thin `agindin.services.dawarich` wrapper in
the usual repo style. New port: `globalVars.ports.dawarich = 8420`.

### Database

`database.createLocally = false`. The database is instead declared through this
repo's own Postgres module:

- `agindin.services.postgres.ensureUsers = [ "dawarich" ]`
- `agindin.services.postgres.extensions = [ (ps: [ ps.postgis ]) ]`
- an appended `postgresql-setup` `ExecStartPost` running
  `CREATE EXTENSION IF NOT EXISTS postgis; SELECT postgis_extensions_upgrade();`
  against the `dawarich` database

That last step is exactly what the upstream module does inside its
`createLocally` branch; replicating it is the whole cost of opting out. The
benefit is that `postgres-backup` dumps the database along with every other one,
which the upstream path would not have given us.

Upstream's database defaults (`host = /run/postgresql`, `port = 5432`, name and
user both `dawarich`) already match this repo's Postgres, so nothing else needs
overriding.

### Redis

`redis.createLocally = true` — a dedicated `redis-dawarich` server on a Unix
socket. The module handles the socket group membership for the service units.

### Reverse proxy

`configureNginx = false`; Caddy serves it via `agindin.services.caddy.proxyHosts`.
A plain `reverse_proxy` is enough. Upstream's nginx virtual host exists only to
serve `${pkgs.dawarich}/public` directly and fall through to Puma, and
dawarich's `config/environments/production.rb` sets
`config.public_file_server.enabled = true` unconditionally — so Puma serves its
own assets. Caddy proxies the `/cable` ActionCable websocket transparently.

`APPLICATION_PROTOCOL = "https"` is set so Rails generates correct absolute URLs
and secure cookies behind Caddy's TLS. Note this also turns on `force_ssl`,
which is why nothing should talk to the service over plain HTTP on localhost.

### Authentication

Dawarich supports generic OIDC in self-hosted mode, so it authenticates against
the existing Pocket ID at `auth.gindin.xyz` rather than local passwords:

| Variable | Value |
| --- | --- |
| `OIDC_ISSUER` | `https://auth.gindin.xyz` (discovery mode) |
| `OIDC_REDIRECT_URI` | `https://dawarich.gindin.xyz/users/auth/openid_connect/callback` |
| `OIDC_PROVIDER_NAME` | `Pocket ID` |
| `OIDC_AUTO_REGISTER` | `true` |
| `ALLOW_EMAIL_PASSWORD_REGISTRATION` | left at its `false` default |

`OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` come from a new
`secrets/dawarich-oidc-env.age`, passed via `extraEnvFiles`. The Pocket ID
client itself is created by hand in the Pocket ID UI, as bookorbit's is.

`secretKeyBaseFile` is left `null`: the module generates one under
`/var/lib/dawarich/secrets/`, a path that is both persisted and backed up, so
there is nothing to manage by hand.

### First-boot sequence

Enabling OIDC takes the password form away. Dawarich's
`ApplicationHelper#email_password_login_enabled?` returns
`DawarichSettings.registration_enabled?` once OIDC is on, and that reads
`ALLOW_EMAIL_PASSWORD_REGISTRATION` — so the login form is gated on the *signup*
setting, which is off here. The admin `demo@dawarich.app` that `rails db:seed`
creates is therefore unreachable, and OIDC accounts are not admin:
`Auth::FindOrCreateOauthUser#create_new_user` sets only email, password,
provider and uid. Dawarich 1.7.5 has no group- or role-claim mapping either, so
admin cannot come from Pocket ID.

Admin is set in the database instead, by an `adminEmails` option and a
`dawarich-promote-admins` oneshot:

```sql
UPDATE users SET admin = true WHERE email = :'email' AND NOT admin;
```

The SQL arrives on psql's stdin rather than through `-c`, because psql only
interpolates `:'email'` for input read from stdin or a file — with `-c` it
reaches the server verbatim and is a syntax error. The unit has no
`RemainAfterExit` and runs on every switch, because the row does not exist until
the account's first OIDC sign-in; the same reasoning as
`postgresql-refresh-template-collations` in `services/postgres.nix`.

So the first deploy is: sign in through Pocket ID once, deploy again to pick up
admin, then delete the stranded demo user from Settings -> Users and copy the
API key from your account page.

### Home Assistant

Deliberately not declarative. Install `AlbinLind/dawarich-home-assistant` through
HACS, point it at `https://dawarich.gindin.xyz` with the API key from above, and
select the phone's `device_tracker` entity.

## intervals.icu sync

`packages/intervals-dawarich-sync.nix` packages a Python script
(`writers.writePython3Bin`, `requests`); `services/intervals-dawarich-sync.nix`
runs it as a hardened oneshot plus timer under its own system user, mirroring
`services/headache-sync.nix`.

Each run:

1. `GET /api/v1/athlete/{id}/activities?oldest=&newest=`, HTTP Basic with
   username `API_KEY` and the token as password.
2. Skip activities already recorded in the state file.
3. Skip activities without GPS — `stream_types` must contain `latlng`, though an
   activity that omits the key entirely is attempted anyway and classified by
   the GPX download — and skip virtual ones: `type` starting with `Virtual`, or
   `trainer == true`, or `source == "ZWIFT"`. All three are checked because Zwift
   GPX files carry real Watopia coordinates, which would otherwise plot as trips
   to the middle of the Pacific. The listing deliberately does not pass a
   `fields` filter: intervals.icu drops unrecognised field names silently, and a
   missing `stream_types` would then read as "nothing has GPS" — a no-op run
   that reports success.
4. `GET /api/v1/activity/{id}/gpx-file`, then `POST /api/v1/imports` to Dawarich
   as a multipart `file` field with `Authorization: Bearer <key>`.
5. Record the uploaded id and flush the state file after *every* upload, so an
   interrupted run never re-uploads.

The window is `1970-01-01`..now until the first complete pass, at which point the
state file's `backfill_complete` flag narrows it to `lookbackDays` (default 14).
Full history therefore lands on the first run, paced by `uploadDelaySeconds`
(default 2) so the uploads trickle into Sidekiq rather than arriving at once.

`dawarichUrl` defaults to `https://dawarich.gindin.xyz` and must go through
Caddy: `force_ssl` means a plain-HTTP request to `127.0.0.1:8420` gets redirected
rather than served.

Secrets live in `secrets/intervals-dawarich-sync-env.age`
(`INTERVALS_API_KEY`, `DAWARICH_API_KEY`).

## Rollout

Two deploys, because the Dawarich API key cannot exist before the first login:

1. Dawarich and its Pocket ID client. Do the first-boot sequence above.
2. Create `intervals-dawarich-sync-env.age` with both keys, enable the sync.
