# Forgejo operations

Forgejo is the authoritative destination after the staged cutover below. GitHub
stays unarchived as a push mirror. It is not a second development destination.
The instance is single-user and reachable only over Tailscale at
`https://git.gindin.xyz`; Git SSH uses port 2222 and user `git`.

## Services and credentials

`agindin.services.forgejo.enable` installs Forgejo, its recovery account, a
consistent snapshot/restore check, the CI VM, and the deployment controller.
Consumers with missing credentials remain stopped so the initial server can be
bootstrapped without putting placeholder tokens in the Nix store.

The recovery password is encrypted in `secrets/forgejo-recovery-password.age`.
It creates `forgejo-recovery` only when that account is absent; subsequent
switches do not reset its password. Use Pocket ID with the regular `aidengindin`
account; keep the recovery account for outages and enable local 2FA on it.

The Pocket ID client callback is
`https://git.gindin.xyz/user/oauth2/PocketID/callback`. Store `OIDC_CLIENT_ID` and
`OIDC_CLIENT_SECRET` as environment assignments in `forgejo-oidc-env.age`.
The idempotent `forgejo-oidc` service creates or updates the `PocketID` source.
Account auto-registration is disabled; the provisioned account with your email
can link to the trusted Pocket ID source at sign-in.

`provision.py automation` writes these agenix files using osgiliath's and
khazad-dum's SSH recipients:

- `forgejo-runner-env.age`: repository runner registration `TOKEN`.
- `forgejo-controller-env.age`: repository-scoped bot token, numeric owner/bot
  IDs, Forgejo webhook secret, and Hermes webhook secret.
- `forgejo-hermes-env.age`: the same repository bot token and Hermes webhook
  secret. It is added to the existing gateway, not a second Hermes instance.

Keep the mirror token in `forgejo-mirror-token.age`. Its GitHub fine-grained
permissions are Contents and Workflows read/write, limited to this repository.
Forgejo stores the configured mirror credential in its protected application
state. The optional `UPSTREAM_GITHUB_TOKEN` Actions secret is for public upstream
lookups, separate from the mirror token; without it uBlock uses the public API.

The VM's host key and the controller's store-reader key are generated on
osgiliath, persisted, and backed up in `/var/lib/forgejo-automation`. Known-host
pinning is derived from that generated host key, never from `ssh-keyscan`.
Only the guest's own host key, the store-reader **public** key, and its runner
registration credential cross into the VM as systemd credentials.

## Migration sequence

Run commands from the repository root with Python 3 and `age` available. The
scripts never print tokens. Protect the temporary bootstrap directory (0700),
keep credentials out of shell history, and remove it after revoking the temporary
migration token. Example paths below are private local working files.

1. Build with `nix run .#colmena -- build --on osgiliath --parallel 1`, then deploy
   osgiliath. Before new files have been added to Git, use `path:.#colmena` and
   pass `-f path:.` to Colmena. Verify `forgejo`, `forgejo-recovery-account`,
   `forgejo-oidc`, and `forgejo-restore-check` unit results.
2. Run `python3 scripts/forgejo/migrate.py snapshot --snapshot /tmp/forgejo-migration`.
   This preserves a bare mirror, a Git bundle, issues, PRs, reviews, comments,
   releases, labels, and milestones. Copy it to durable backup storage before
   deleting the temporary copy.
3. Decrypt the recovery password into a mode-0600 file. Run
   `python3 scripts/forgejo/provision.py accounts --state /tmp/forgejo-bootstrap --recovery-password-file /tmp/recovery-password`.
   The protected `credentials.json` contains the temporary admin token and
   bootstrap account credentials. Do not print or commit it.
4. Supply `FORGEJO_URL`, `FORGEJO_TOKEN` (temporary administrator), and
   `GITHUB_MIGRATION_TOKEN` to `migrate.py import --snapshot /tmp/forgejo-migration`.
   Wait for the import to finish; a timed-out request must be inspected in
   Forgejo before retrying. Never create a pull mirror: the imported repository
   must be writable.
5. Run the `verify` phase. It compares branch/tag hashes, PR titles/counts,
   issue counts, labels, and release tags and writes `verification.json`.
   Spot-check imported comments/reviews, wiki contents, and release attachments
   against `github.json`. GitHub Actions history and reviewer identities do not
   necessarily transfer; the source export remains the historical reference.
   Initial migration result: all 77 PRs were present; GitHub contained zero
   reviews, zero review comments, one PR discussion comment, nine labels, no
   milestones, and no releases. PR 15 preserved that comment byte-for-byte and
   at the same instant, but attributed it to `Ghost` instead of `aidengindin`.
   GitHub had its wiki feature enabled but no wiki repository; Forgejo likewise
   has no wiki contents. The author-attribution loss is the only observed import
   gap.
6. Supply the dedicated `GITHUB_MIRROR_TOKEN` and run the `mirror` phase. It
   refuses divergent refs before enabling Forgejo's force-push mirror. Confirm
   a successful sync and no mirror error.
7. Run `provision.py automation --state /tmp/forgejo-bootstrap`. It creates the
   scoped bot credential, required build checks, webhook, Actions secrets, and
   encrypted runtime files. Build/deploy osgiliath again to start the runner,
   controller, and Hermes route. Preserve the runtime files in Git.
8. Push this implementation to a Forgejo branch and open a PR. Verify the build
   and repair paths below before merging. The scheduled updater exists only on
   the default branch, so do not merge it until GitHub Actions is disabled.
9. Once restoration, import, mirror, and CI checks pass, create the
   `manual-verification-complete` marker in the snapshot directory and run the
   `cutover` phase. It checks mirror status/ref equality, disables GitHub
   Actions, updates its description, changes `origin`, and retains `github`.
   Then merge the implementation PR to enable the Forgejo weekly schedule.
10. Revoke the temporary `migration-bootstrap` recovery-account token and
    remove plaintext bootstrap files. Retain the encrypted recovery secret,
    migration export, and verification report. The verified pre-migration bundle
    and GitHub metadata are retained at
    `/var/lib/forgejo-automation/migration/pre-forgejo-2026-09-07`, which is
    included in both configured Restic destinations.

Git remotes are shared by Git worktrees. Cutover changes the common repository's
`origin`, including other worktrees. A frozen GitHub archive is incompatible with
receiving mirror updates. Mirror deletions propagate; do not make independent
GitHub commits.

## CI and repair loop

The VM has 6 vCPUs, 8 GiB RAM, a 100 GiB sparse disk, and capacity one. It runs
Forgejo Runner 13.1 from the stable pin using its supported legacy registration
flow. Upgrading to a runner that removes registration tokens requires a
UUID/token configuration migration; do not silently swap its configuration.

PR events and update-branch pushes build all four hosts at the exact PR head.
Each host has a `colmena/<hostname>` status and a JSON manifest under
`/var/lib/forgejo-ci/results/<sha>/<host>.json`. Colmena's own hive supplies the
closure path. Successful results are GC-rooted and reused on duplicate events.
Roots stay while the SHA is a current PR head; old roots have a seven-day grace
period. Nix GC runs before every uncached host build and weekly, reclaiming failed
outputs while preserving successful rooted closures. The guest disables Nix's
persistent evaluation cache so post-GC evaluations cannot reference deleted store
paths. Server, runner, and workflow timeouts are all 12 hours for Weathertop's
custom-kernel build. Failed job workspaces are cleaned of untracked files.

The weekly updater runs Sunday 00:00 UTC and can be dispatched manually. It uses
`automation/update`, performs each existing updater, publishes partial edits when
one fails, and records `Update-Cycle` in the PR body. Ordinary pushes refuse
concurrent branch changes.

When a CI job completes, it sends a signed webhook through the tailnet-only
`/_automation/events` route. The controller waits for builds to settle and verifies the
repository/bot/status through Forgejo, filters to the update PR, and sends a signed
local webhook to Hermes. Periodic reconciliation covers lost webhook deliveries.
The route rechecks the head and failures, deduplicates by SHA, and permits three
attempts per update cycle. Hermes has a checkout per SHA, commits directly using
a normal repository-scoped bot token, and pushes to trigger another build.
No automatic merge or deployment occurs. The 30-minute repair instruction is an
agent instruction; the persisted attempt counter is the enforced loop bound.

The controller persistently queues and deduplicates notifications, then uses a
signed loopback Hermes webhook route to deliver them directly to the configured
Matrix home room without an agent turn. It reports only terminal four-host build
results, Hermes repair starts and exhaustion, and deployment outcomes. Forgejo
statuses, logs, and PR comments remain the durable record.

## Deploy a PR

Comment as your configured Forgejo user:

```
/deploy osgiliath,lorien
/deploy @server
/deploy @mobile
```

Commands pin the current SHA and validate targets against the controller's
inventory. Unknown selectors and shell syntax are rejected. Selected hosts must
pass; unrelated host failures do not block deployment. If builds are missing,
the controller dispatches CI. Changing the PR before activation cancels the
request.

Deployment runs on osgiliath, **not** in the CI VM. The controller pulls the
selected closures over the restricted SSH export connection, roots them locally,
then copies/activates them on targets. It never evaluates or rebuilds PR code on
the deployment host. Only this authenticated import uses `--no-check-sigs`;
normal store signature policy remains enabled.

Ensure every remote target has received the updated deployment wrapper supporting
read-only generation queries. All target host keys must be pinned before first
use; weathertop may need enrollment when it is online. Do not use an unattended
`ssh-keyscan` result as the trust source.

The SQLite journal in `/var/lib/forgejo-automation/controller` serializes requests
and remembers each activation and previous generation. Osgiliath deploys last.
After interruption, the controller checks `/run/current-system`; it records an
already-active closure without activating twice. An ambiguous interruption stops
for inspection. A partial failure never silently rolls back previously deployed
hosts. Restore a recorded previous profile manually with the existing deployment
account, then activate that profile with `switch-to-configuration switch`.

## Backups and recovery

`forgejo-snapshot` briefly stops Forgejo (including its built-in SSH server), copies
application state, dumps PostgreSQL, and atomically publishes
`/var/backup/forgejo/current`. An EXIT trap restarts Forgejo even on failure.
Both Restic destinations require the snapshot service first. The restore-check
unit restores the dump into a scratch database, checks the repository table,
runs `git fsck` on every snapshotted bare repository, then drops the scratch DB.
It refuses to reuse/delete an existing scratch database.

For full recovery, stop Forgejo, restore `current/state` to `/var/lib/forgejo`
with original ownership, and restore `database.dump` into a clean `forgejo`
database owned by `forgejo`. Restore application secrets with that snapshot,
not from a different backup generation. Start Forgejo and verify sign-in,
clone/push, mirror credentials, and Actions. Restore transport identities and the
controller journal from the same recovery point before enabling automation.
The CI disk is disposable cache and is not backed up.

## Verification

Run `python3 -m unittest discover -s tests/forgejo -v` and build osgiliath with
Colmena. Live acceptance includes a passing PR, a failing PR, exact-SHA closure
transfer without rebuilding, unauthorized/duplicate comments, selected-host gates,
stale heads, offline hosts, partial deployment, controller restart recovery, and
failure → Hermes commit → fresh CI. Test repair exhaustion and concurrent edits.
Check `systemctl --failed` and `journalctl -u forgejo-controller -u forgejo-ci-vm`.
The existing Alloy/systemd monitoring collects service failures.
