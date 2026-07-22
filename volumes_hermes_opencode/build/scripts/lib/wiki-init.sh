# lib/wiki-init.sh - initialize wiki directory for llm-wiki skill - sourced by entrypoint.sh

init_wiki() {
    if [ -z "${HERMES_WIKI_PATH:-}" ]; then
        echo "!! HERMES_WIKI_PATH not set, skipping wiki init."
        return
    fi

    if [ -f "${HERMES_WIKI_PATH}/SCHEMA.md" ]; then
        echo "== Wiki already initialized at ${HERMES_WIKI_PATH}"
        export WIKI_PATH="${HERMES_WIKI_PATH}"
        return
    fi

    echo "== Initializing wiki at ${HERMES_WIKI_PATH}"
    mkdir -p "${HERMES_WIKI_PATH}"/{raw/{articles,papers,transcripts,assets},entities,concepts,comparisons,queries}

    cat > "${HERMES_WIKI_PATH}/SCHEMA.md" << 'SCHEMAEOF'
# Wiki Schema

## Domain
Hermes x OpenCode Docker Stack — container architecture, configuration, testing, and operations.

## Conventions
- File names: lowercase, hyphens, no spaces
- Every wiki page starts with YAML frontmatter
- Use [[wikilinks]] to link between pages (minimum 2 outbound links per page)
- When updating a page, always bump the updated date
- Every new page must be added to index.md
- Every action must be appended to log.md

## Frontmatter
  ```yaml
  ---
  title: Page Title
  created: YYYY-MM-DD
  updated: YYYY-MM-DD
  type: entity | concept | comparison | query
  tags: [from taxonomy below]
  sources: [raw/articles/source-name.md]
  ---
  ```

## Tag Taxonomy
- service, component, infrastructure, configuration
- process, pattern, testing, security
- integration, core, optional
- build-time, runtime
SCHEMAEOF

    cat > "${HERMES_WIKI_PATH}/index.md" << 'INDEXEOF'
# Wiki Index

> Content catalog. Every wiki page listed with a one-line summary.
> Last updated: INIT_DATE | Total pages: 0

## Entities

## Concepts

## Comparisons

## Queries
INDEXEOF

    sed -i "s/INIT_DATE/$(date +%Y-%m-%d)/" "${HERMES_WIKI_PATH}/index.md"

    cat > "${HERMES_WIKI_PATH}/log.md" << 'LOGEOF'
# Wiki Log

> Chronological record of all wiki actions. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`

## [LOG_DATE] create | Wiki initialized
- Domain: Hermes x OpenCode Docker Stack
- Structure created with SCHEMA.md, index.md, log.md
LOGEOF

    sed -i "s/LOG_DATE/$(date +%Y-%m-%d)/" "${HERMES_WIKI_PATH}/log.md"

    chown -R hermeswebui:hermeswebui "${HERMES_WIKI_PATH}" 2>/dev/null || true
    export WIKI_PATH="${HERMES_WIKI_PATH}"
    echo "== Wiki initialized at ${HERMES_WIKI_PATH}"
}
