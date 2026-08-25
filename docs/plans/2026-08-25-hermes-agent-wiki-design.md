# An agent-owned wiki for Hermes

2026-08-25

## Goal

Give Hermes a persistent, self-managed knowledge base as interlinked markdown,
with a small always-injected pointer into it. The wiki is the agent's own —
autonomously maintained, not synced anywhere, not opened by a human editor.

## Why not a memory provider

Hermes already has three memory layers, and the gap is not another store:

1. `MEMORY.md` / `USER.md` — bounded (2200 / 1375 chars), injected into every
   system prompt, already active.
2. `session_search` — FTS5 over past conversations.
3. Pluggable memory providers — of the eight bundled, only `holographic` and
   `honcho` are viable under Nix (see the 2026-08-24 MCP design doc).

What is missing is an *unbounded, structured, linkable* layer. A wiki of
markdown files is portable, greppable, and infinitely extensible, and Hermes
ships the skills to drive one.

## What Hermes already provides

Two bundled skills, already in the store via `HERMES_BUNDLED_PLUGINS`:

- `research/llm-wiki` — an implementation of Karpathy's LLM Wiki pattern.
  Defines a three-layer layout (immutable `raw/`, agent-owned `entities/`,
  `concepts/`, `comparisons/`, `queries/`, and a `SCHEMA.md` holding
  conventions and the tag taxonomy), plus `index.md` as content catalog and an
  append-only `log.md`. Driven by `WIKI_PATH`.
- `note-taking/obsidian` — generic markdown-vault mechanics: read, list,
  search, create, append, wikilinks. Driven by `OBSIDIAN_VAULT_PATH`. Nothing
  about it requires Obsidian itself; `llm-wiki` documents pointing both env
  vars at one directory.

The Matrix toolset needs nothing enabled. `hermes-matrix` uses
`_HERMES_CORE_TOOLS`, which already carries `read_file`, `write_file`, `patch`,
`search_files`, `skills_list`, `skill_view`, `execute_code` (needed by the lint
pass's programmatic link scan) and `cronjob`.

## Design

### Location

`/var/lib/hermes/wiki`, mode 0750, owned by the hermes user.

The unit runs `ProtectSystem=strict`, `ProtectHome=true` (forced in our
module) and `ReadWritePaths = [stateDir, workingDirectory]`, so the wiki must
live under the state dir. An assertion enforces this, mirroring the existing
`matrix.recoveryKeyOutputFile` assertion.

Hermes' file tools do not fight this. `_resolve_path_for_task` returns absolute
paths resolved-but-unanchored — there is no tool-level sandbox. The workspace
root only feeds `_path_resolution_warning`, which warns when a *relative* path
escapes. The real boundary is systemd.

Deliberately not under `workspace/`: that is the terminal cwd and the
filesystem MCP root — scratch space for task work. The wiki is stable and
separate.

Impermanence and restic need no change; both already list `stateDir` wholesale.
Restic coverage means a bad agent edit is recoverable point-in-time, which is
the safety property a git repo would have provided without needing any sync.

### Env wiring

`WIKI_PATH` and `OBSIDIAN_VAULT_PATH` both point at the wiki, set through
`services.hermes-agent.environment` (the module merges them into
`$HERMES_HOME/.env`). Neither is secret. The `environmentTrigger` added when
the Matrix gateway landed hashes that attrset, so changing the path actually
restarts the gateway rather than silently no-opping.

### The injected pointer

`SOUL.md` loads from `HERMES_HOME`, which the `documents` option cannot reach —
it installs into `workingDirectory`. Context-file discovery scans the cwd in
priority order (`.hermes.md` → `AGENTS.md` → `CLAUDE.md` → `.cursorrules`,
first found wins), and nothing creates `.hermes.md` there. So the pointer ships
as `documents."AGENTS.md"`, landing at `/var/lib/hermes/workspace/AGENTS.md`.

Not `MEMORY.md`: that file is capped at 2200 chars with the agent instructed to
consolidate or replace when full, so a pointer placed there can be evicted by
the agent's own pruning. `AGENTS.md` is capped at ~20k (model-scaled) and Nix
owns it. The module installs it with `install -m 0640`, a copy rather than a
store symlink, so the agent can edit it but every deploy restores the declared
version.

The document carries the literal absolute path, because both skills warn that
file tools do not expand shell variables.

### Maintenance

`cronjob` is in `_HERMES_CORE_TOOLS`, and `gateway/run.py` resolves and starts
an in-process cron scheduler that `hermes-agent.service` is already running. So
Hermes can schedule its own maintenance from Matrix — no systemd timer, no CLI
session.

The intended job is a weekly lint, which the skill already specifies: orphan
pages, broken wikilinks, index-versus-filesystem completeness, frontmatter
validation, >90-day staleness, flagged contradictions, sha256 source drift,
oversized pages, tag audit and log rotation. It appends a result line to
`log.md` and should report into the Matrix home room, so maintenance is visible
rather than silent.

This matters because it is the only real enforcement available. Built-in memory
has runtime hooks — a nudge every 10 user turns, a flush turn before context
loss, hard char caps forcing consolidation. The wiki skill has only
prompt-level discipline: an orientation ritual and a pitfalls list, firing only
when the model judges the skill relevant. Scheduling the lint converts wiki
upkeep from a hope into a job with a report.

Cron jobs live in `$HERMES_HOME/cron/jobs.json` — mutable runtime state with no
declarative Nix surface. Impermanence and restic cover it, but it is the one
part of this that is not in the repo. If lost, it is recreated by asking.

### Bootstrap

Initialization is a conversation, not a deploy: ask Hermes to initialize the
wiki, which creates `SCHEMA.md`, `index.md`, `log.md` and the directory layout.
The `SCHEMA.md` domain should be this infrastructure and its operations rather
than a research topic, with a tag taxonomy to match.

## Risk

The wiki becomes a persistent prompt-injection surface. Context files are run
through `_scan_context_content` before injection, so `AGENTS.md` is checked, but
wiki *pages* are read at runtime via `read_file`, and the `fetch` and web tools
are enabled. Content ingested into `raw/` from the web is read back in later
sessions as trusted-looking notes. The skill's immutability rule for `raw/`
limits drift but does not address this. It argues for actually reading the lint
reports.

## Changes

- `services/hermes.nix` — `agindin.services.hermes.wiki.{enable,path}`, an
  assertion that the path is under the state dir, a tmpfiles rule, the two env
  vars, and `documents."AGENTS.md"`.
- `hosts/osgiliath/services.nix` — enable it.

No new packages, no new secrets, no new services.
