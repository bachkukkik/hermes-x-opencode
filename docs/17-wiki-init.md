# 17 — Wiki Initialization (llm-wiki skill)

## Overview

The wiki initialization step creates a personal knowledge base directory structure at container startup, enabling the `llm-wiki` skill. This is sourced from `lib/wiki-init.sh` (84 lines) and called by the entrypoint between `ensure_agent()` and the WebUI background init.

## When it runs

```
 8. ensure_agent()              — copies agent source to bind mount
 8b. init_wiki()               — ← this step
 8c. append_skills_external_dirs() — registers external skills
```

The function runs after `ensure_agent()` because the agent's llm-wiki skill may reference the wiki directory. It runs before the WebUI starts so the knowledge base is ready when the agent first loads.

## WIKI_DIR

The wiki location is controlled by `WIKI_DIR` (set in `lib/constants.sh`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `WIKI_DIR` | `${HERMES_HOME}/wiki` | Wiki root directory |
| `WIKI_PATH` | (exported by init_wiki) | Resolved path for agent consumption |

Optional host sharing via the `HERMES_WIKI_VOLUME` env var in `docker-compose.yml` allows mounting the wiki to a host path.

## Initialization

`init_wiki()` is **idempotent**: if `$WIKI_DIR/SCHEMA.md` already exists, it skips initialization and exports `WIKI_PATH`. This means first-boot creation and subsequent boots are handled by the same code path.

### Directory structure (created on first boot)

```
$WIKI_DIR/
├── SCHEMA.md          # Domain, conventions, frontmatter spec, tag taxonomy
├── index.md           # Content catalog (every wiki page listed with summary)
├── log.md             # Chronological action log (append-only)
├── raw/
│   ├── articles/      # Ingested source material
│   ├── papers/        # Research papers
│   ├── transcripts/   # Conversation transcripts
│   └── assets/        # Images, diagrams, data files
├── entities/          # Person, tool, service pages
├── concepts/          # Idea, pattern, architecture pages
├── comparisons/       # Side-by-side analyses
└── queries/           # Saved research queries
```

### SCHEMA.md backbone

The schema defines:
- **Domain**: "Hermes x OpenCode Docker Stack — container architecture, configuration, testing, and operations"
- **Conventions**: lowercase hyphenated filenames, YAML frontmatter, `[[wikilinks]]`, minimum 2 outbound links per page
- **Frontmatter spec**: title, created/updated dates, type (entity/concept/comparison/query), tags, sources
- **Tag taxonomy**: service, component, infrastructure, configuration, process, pattern, testing, security, integration, core, optional, build-time, runtime

### Ownership

All created directories and files are chowned to `hermeswebui:hermeswebui` so the agent process can read and write them. The `chown -R` is wrapped in `2>/dev/null || true` because it may already be owned correctly on subsequent boots.

## Skipping

If `WIKI_DIR` is empty or unset, `init_wiki()` logs a warning and returns immediately:

```
!! WIKI_DIR not set, skipping wiki init.
```

## Persistence

The wiki directory lives on the Hermes home bind mount (`volumes_hermes_opencode/data/hermes-home/wiki`), so all wiki content persists across container restarts. On first boot the directory is created from scratch; on subsequent boots `init_wiki()` detects `SCHEMA.md` and skips.

## Test coverage

| Test File | Covers |
|-----------|--------|
| `tests/e2e/14-wiki-init.bats` | Wiki dir exists, SCHEMA.md exists, subdirs created, SCHEMA.md content, index/log exist |

## Integration with llm-wiki skill

The `llm-wiki` skill (installed at build time from `skills/research/`) uses the wiki for:
- Ingesting sources into `raw/articles/`
- Creating entity/concept pages with `[[wikilinks]]`
- Maintaining `index.md` (auto-updated when pages are added)
- Appending actions to `log.md`
- Querying the interlinked markdown knowledge base

The skill reads `WIKI_PATH` from the environment to locate the wiki root.
