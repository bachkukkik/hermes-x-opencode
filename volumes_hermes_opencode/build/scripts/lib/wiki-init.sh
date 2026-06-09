# lib/wiki-init.sh - initialize wiki directory for llm-wiki skill - sourced by entrypoint.sh

init_wiki() {
    if [ -z "${WIKI_DIR:-}" ]; then
        echo "!! WIKI_DIR not set, skipping wiki init."
        return
    fi

    if [ -f "$WIKI_DIR/SCHEMA.md" ]; then
        echo "== Wiki already initialized at $WIKI_DIR"
        export WIKI_PATH="$WIKI_DIR"
        return
    fi

    echo "== Initializing wiki at $WIKI_DIR"
    mkdir -p "$WIKI_DIR"/{raw/{articles,papers,transcripts,assets},entities,concepts,comparisons,queries}

    cat > "$WIKI_DIR/SCHEMA.md" << 'SCHEMAEOF'
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

    cat > "$WIKI_DIR/index.md" << 'INDEXEOF'
# Wiki Index

> Content catalog. Every wiki page listed with a one-line summary.
> Last updated: INIT_DATE | Total pages: 0

## Entities

## Concepts

## Comparisons

## Queries
INDEXEOF

    sed -i "s/INIT_DATE/$(date +%Y-%m-%d)/" "$WIKI_DIR/index.md"

    cat > "$WIKI_DIR/log.md" << 'LOGEOF'
# Wiki Log

> Chronological record of all wiki actions. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`

## [LOG_DATE] create | Wiki initialized
- Domain: Hermes x OpenCode Docker Stack
- Structure created with SCHEMA.md, index.md, log.md
LOGEOF

    sed -i "s/LOG_DATE/$(date +%Y-%m-%d)/" "$WIKI_DIR/log.md"

    chown -R hermeswebui:hermeswebui "$WIKI_DIR" 2>/dev/null || true
    export WIKI_PATH="$WIKI_DIR"
    echo "== Wiki initialized at $WIKI_DIR"
}
