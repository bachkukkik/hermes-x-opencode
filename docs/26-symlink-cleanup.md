# 26 — Symlink Cleanup

## What

`lib/symlink-cleanup.sh` removes stale skill symlinks and cache snapshots that can cause infinite directory loops or stale skill resolution at runtime.

## Why

- When Hermes or OpenCode skills are installed, the installer can create a `skills` symlink inside the skills directory itself (pointing to the parent), forming a directory loop. This breaks `find`, `ls`, and skill-scanning operations.
- The `.skills_prompt_snapshot.json` file in `~/.hermes/` can persist stale skill metadata across boots, causing the Hermes agent to load outdated skill definitions.

## How

The module defines a single function `cleanup_symlink_loops()` sourced by `entrypoint.sh`.

### Function signature

```bash
cleanup_symlink_loops()
```

No parameters. Reads environment variables defined in `lib/constants.sh`.

### Environment variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `OPENCODE_SKILLS_DIR` | `lib/constants.sh` | OpenCode skills directory (`/home/hermeswebui/.config/opencode/skills`) |
| `HERMES_SKILLS_DIR` | `lib/constants.sh` | Hermes skills directory (`/home/hermeswebui/.hermes/skills`) |

### Operations

1. **Symlink loop removal** — Runs `find` in both `$OPENCODE_SKILLS_DIR` and `$HERMES_SKILLS_DIR` with `-maxdepth 1 -type l -name "skills" -delete` to remove any `skills` symlink at the top level of each skills directory.
2. **Snapshot removal** — Deletes `/home/hermeswebui/.hermes/.skills_prompt_snapshot.json` to force Hermes to regenerate its skill prompt snapshot on next boot.

Both operations use `|| true` guards — failures never abort the entrypoint.

## Verification

```bash
# Check no stale 'skills' symlinks exist
docker exec <container> find /home/hermeswebui/.hermes/skills /home/hermeswebui/.config/opencode/skills -maxdepth 1 -type l -name "skills"
# (should return empty)

# Check snapshot is absent
docker exec <container> test -f /home/hermeswebui/.hermes/.skills_prompt_snapshot.json && echo "EXISTS" || echo "CLEAN"
# (should print "CLEAN")
```

## What Works

- Removes directory loops that would break skill scanning.
- Forces fresh skill prompt snapshots on every boot, ensuring the agent sees current skill definitions.
- Fast — operates on a fixed set of paths with `-maxdepth 1`.

## What Fails

- **Legitimate `skills` symlinks removed:** If a skill category legitimately contains a symlink named `skills` (unlikely but possible), this removes it indiscriminately.
- **Non-idempotent snapshot removal:** Deleting `.skills_prompt_snapshot.json` every boot means Hermes regenerates the snapshot on each start, adding a small delay to agent initialization.

## Resolution

- The `skills` symlink pattern is a known installer bug. Removing it is always safe — no skill should contain a self-referencing `skills` symlink.
- Snapshot regeneration is a one-time cost per boot (typically under a second). The benefit of fresh skill metadata outweighs the small startup delay.

## Verdict

A surgical 8-line utility that prevents a specific class of runtime bugs. Simple, fast, and safe.
