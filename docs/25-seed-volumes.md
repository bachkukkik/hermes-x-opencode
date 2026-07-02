# 25 — Seed Volumes

## What

`lib/seed-volumes.sh` copies staged skills from build-time paths into runtime bind-mounted volumes and sets up root symlinks so both the `hermeswebui` user and root can access configuration and skills.

## Why

- The Docker build installs skills to `/opt/hermes-skills-staging` and `/home/hermeswebui/.config/opencode/skills`, but `~/.hermes` is a bind-mounted volume that starts empty on first boot. The seeding step bridges this gap.
- Root-launched processes (e.g., entrypoint setup scripts) need their own config symlinks because they read from `/root/.config/` rather than `/home/hermeswebui/.config/`.
- Docker creates bind-mounted directories owned by `root:root`. The seeding step re-assigns ownership to the `hermeswebui` user so services running under that UID can read and write.

## How

The module defines a single function `seed_volumes()` sourced by `entrypoint.sh`.

### Function signature

```bash
seed_volumes()
```

No parameters. Reads environment variables defined in `lib/constants.sh`.

### Environment variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `SKIP_SKILL_INSTALL` | `.env` | When set to `1`, skips all seeding and returns immediately |
| `OPENCODE_SKILLS_DIR` | `lib/constants.sh` | Target directory for OpenCode skills (`/home/hermeswebui/.config/opencode/skills`) |
| `HERMES_SKILLS_DIR` | `lib/constants.sh` | Target directory for Hermes skills (`/home/hermeswebui/.hermes/skills`) |
| `OPENCODE_CONFIG` | `lib/constants.sh` | Path to `opencode.jsonc` |
| `CONFIG` | `lib/constants.sh` | Path to Hermes `config.yaml` |
| `OPENCODE_USER` | `lib/constants.sh` | Non-root user (`hermeswebui`) for `chown` operations |
| `HERMES_HOME` | `lib/constants.sh` | Hermes state directory (`/home/hermeswebui/.hermes`) |

### Operations

1. **Skip gate** — If `SKIP_SKILL_INSTALL=1`, logs and returns immediately.
2. **OpenCode skills** — Creates `$OPENCODE_SKILLS_DIR`, then copies `/opt/opencode-skills-staging/.` into it using `cp -rn` (no-clobber, recursive).
3. **Hermes skills** — Creates `$HERMES_SKILLS_DIR`, then copies `/opt/hermes-skills-staging/.` into it using `cp -rn`.
4. **Root symlinks** — Creates `/root/.config/opencode` and `/root/.hermes`, then symlinks `$OPENCODE_CONFIG`, `$OPENCODE_SKILLS_DIR`, `$CONFIG`, and `$HERMES_SKILLS_DIR` into `/root/.config/` and `/root/.hermes/` so root processes see the same config and skills.
5. **Ownership** — Runs `chown -R` on `/workspace`, `/app/.od`, and `$HERMES_HOME` to assign ownership to `${OPENCODE_USER}:${OPENCODE_USER}`.

All operations use `|| true` guards — failures are logged but never abort the entrypoint.

## Verification

```bash
# After container starts, check skill directories are populated
docker exec <container> ls /home/hermeswebui/.hermes/skills/ | head -5
docker exec <container> ls /home/hermeswebui/.config/opencode/skills/ | head -5

# Check root symlinks resolve correctly
docker exec <container> readlink /root/.hermes/config.yaml
docker exec <container> readlink /root/.config/opencode/opencode.jsonc

# Check ownership
docker exec <container> ls -ld /workspace /app/.od /home/hermeswebui/.hermes
```

## What Works

- Skills copy is near-instant (`cp -rn` from staging to bind mount).
- Root symlinks allow root processes to access the same config and skills as `hermeswebui`.
- Ownership correction ensures `hermeswebui` can read/write bind-mounted directories.
- `SKIP_SKILL_INSTALL=1` provides a clean skip path for CI or debugging.
- Idempotent — re-copying skills on every boot is safe with `cp -rn`.

## What Fails

- **Staging directory missing:** If `/opt/hermes-skills-staging` or `/opt/opencode-skills-staging` is absent (build failed or image corrupted), seeding silently skips that step with no skills available at runtime.
- **Bind mount ownership races:** If another container process writes to `/workspace` or `$HERMES_HOME` before seeding runs, the `chown -R` can briefly lock directories.

## Resolution

- The Dockerfile verification step (step 10 in `04 — Build Pipeline`) confirms staging directories exist. If the build passes, staging is guaranteed.
- Ownership races are unlikely because `seed_volumes()` runs before any service starts in the entrypoint sequence.

## Verdict

A small, focused utility that bridges build-time staging with runtime bind mounts. The `|| true` guards make it resilient, and the `SKIP_SKILL_INSTALL` flag provides operational flexibility.
