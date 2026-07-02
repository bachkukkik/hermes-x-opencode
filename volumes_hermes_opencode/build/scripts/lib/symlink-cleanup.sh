#!/usr/bin/env bash
# ── Symlink cleanup ────────────────────────────────────────────────────────

cleanup_symlink_loops() {
    find "$OPENCODE_SKILLS_DIR" "$HERMES_SKILLS_DIR" \
        -maxdepth 1 -type l -name "skills" -delete 2>/dev/null || true
    rm -f /home/hermeswebui/.hermes/.skills_prompt_snapshot.json 2>/dev/null || true
}
