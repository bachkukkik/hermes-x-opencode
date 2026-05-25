# 07 — Volume Layout

## What

The project uses a `volumes_hermes_opencode/` directory to separate build artifacts from persistent runtime data, both managed as bind mounts via docker-compose.

## Why

- Keeps the root directory clean — only `docker-compose.yml`, `.env`, and documentation live at the project root
- Separates build context (`build/`) from runtime data (`data/`) so that rebuilding the image does not risk losing persistent state
- Uses bind mounts instead of Docker named volumes, making data visible on the host filesystem for backup and inspection
- `.gitignore` and `.dockerignore` at each level prevent build artifacts and runtime data from being committed or included in the build context

## How

### Directory structure

```
.
├── docker-compose.yml
├── .env / .env.example
├── .gitignore
├── PRD.md / README.md
└── volumes_hermes_opencode/
    ├── build/                          # Docker build context
    │   ├── Dockerfile
    │   ├── .dockerignore
    │   └── scripts/
    │       └── entrypoint.sh
    ├── data/                           # Persistent runtime data (bind mounts)
    │   ├── hermes-home/
    │   │   ├── .gitkeep
    │   │   ├── config.yaml             # Generated at runtime
    │   │   ├── hermes-agent/           # Copied from staging on first boot
    │   │   ├── state.db                # Session history (SQLite)
    │   │   ├── skills/
    │   │   ├── logs/
    │   │   ├── webui/
    │   │   └── ...
    │   └── workspace/
    │       └── .gitkeep
    ├── .gitignore                      # Ignores data contents, keeps .gitkeep
    ├── .dockerignore                   # Excludes data/ from build context
    └── .gitkeep
```

### Bind mounts

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `./volumes_hermes_opencode/data/hermes-home` | `/home/hermeswebui/.hermes` | Agent config, sessions, skills, state.db |
| `${HERMES_WORKSPACE:-./volumes_hermes_opencode/data/workspace}` | `/workspace` | User project workspace |

### First-start agent copy

The bind mount at `/home/hermeswebui/.hermes` starts empty on first boot. The entrypoint's `ensure_agent()` function copies the hermes-agent from `/opt/hermes-agent-staging` (baked into the image) to the bind mount. Subsequent boots detect the agent and skip the copy.

### .gitignore (volumes_hermes_opencode/)

```
data/hermes-home/*
!data/hermes-home/.gitkeep

data/workspace/*
!data/workspace/.gitkeep
```

This tracks the directory structure and `.gitkeep` files while ignoring all runtime data.

### .dockerignore (volumes_hermes_opencode/)

```
data/
.git
.gitignore
```

Prevents the data directory from being sent as build context. Only `build/` content is relevant for the Docker build.

### .dockerignore (volumes_hermes_opencode/build/)

```
.git
.env
*.pyc
__pycache__
workspace/
```

Standard Docker build exclusions.

### .gitignore (root)

```
.env
workspace/
```

## Verification

```bash
ls -la volumes_hermes_opencode/build/
ls -la volumes_hermes_opencode/data/hermes-home/
docker exec <container> ls /home/hermeswebui/.hermes/hermes-agent/pyproject.toml
docker exec <container> ls /workspace/
```

## What Works

- Build context is isolated in `build/` — no runtime data leaks into the image
- Bind mounts make all persistent data visible on the host for backup
- `.gitignore` correctly excludes runtime data while preserving directory structure via `.gitkeep`
- Agent source persists across container rebuilds (stored in the bind mount, not the image layer)
- Directory structure is created by `git clone` — no manual setup required

## What Fails

- **First boot requires agent copy:** The bind mount starts empty. The entrypoint must copy the agent from staging, adding ~2 seconds to first boot. Subsequent boots skip this.
- **Bind mount ownership:** Files written by the container (as root) are owned by root on the host. This may cause permission issues if the host user needs to read or modify them.
- **No backup automation:** Data lives in `data/` with no automated backup mechanism. Manual backup requires copying the bind mount directories.

## Resolution

- The agent copy is automatic and fast (~2s). No action needed.
- The WebUI's init script sets up UID/GID via `WANTED_UID`/`WANTED_GID`. Match these to your host user (set `HOST_UID` and `HOST_GID` in `.env`) to avoid permission issues.
- Back up `volumes_hermes_opencode/data/` manually or via a cron job. The SQLite database (`state.db`) should be backed up when the container is stopped to avoid corruption.

## Verdict

The volume layout cleanly separates build and runtime concerns. Bind mounts provide visibility and persistence without Docker named volumes. The main operational concern is file ownership, which is addressed by the UID/GID mapping in `.env`.
