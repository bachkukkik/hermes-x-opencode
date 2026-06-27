# 22 — Profiles and the Righthand-Man Orchestrator

## What

A **profile** is a named Hermes persona + configuration bundle. Each profile lives under `${HERMES_HOME}/profiles/<name>/` and carries its own `config.yaml`, `.env`, `SOUL.md` (persona), `skills/`, and related state. Switching profiles swaps the persona, skills, and settings Hermes runs with — without touching the default configuration.

The **`righthand-man`** profile is a pre-seeded **orchestrator persona**. Its `SOUL.md` installs a strict operating doctrine that guarantees the `/goal` decomposition format: every request is decomposed into a numbered goal list, and work is routed through a fixed division of labor across skills (loaded via `skill_view`) and built-in Hermes tools (always available). The orchestrator never codes directly — it plans, investigates, defines success criteria, delegates all code edits to subagents, and verifies results against real output.

## Why

- **Reproducible orchestrator across rebuilds.** The profile is seeded on first boot by the container entrypoint, so a fresh `docker compose build` / `up` always yields a selectable `righthand-man` profile. It does not have to be hand-created after each rebuild.
- **Guaranteed operating doctrine.** Because `SOUL.md` is injected fresh into every system prompt, loading the `righthand-man` profile deterministically activates the `/goal` decomposition habit and the routing doctrine — the persona is enforced per-message, not just at session start.
- **Separation of "doer" vs "orchestrator".** The default profile is a general-purpose agent. `righthand-man` is the disciplined senior orchestrator: it plans, delegates, and verifies rather than charging past the fog of war. Keeping these as distinct profiles lets the operator choose the right behavior for the job.

## How

### First-boot seeding in the container

The profile is provisioned by `lib/profile-righthand-man.sh` (`seed_righthand_man()`), sourced and called early in `entrypoint.sh` — after config/agent setup, before the WebUI and gateway start, so the profile is selectable by the time services are up.

The **clone** is idempotent — if the profile directory already exists with a valid `config.yaml`, the clone step skips to avoid overwriting local config customizations. However, the **SOUL.md overwrite**, **skill sync**, and **config.yaml sync** now run on **every boot**, not just the first seed. Starting from the 2026-06-26 update, the SOUL.md is overwritten and skills are synced on every boot — not just the first seed — so doctrine updates and new skills propagate across rebuilds without manual intervention. Starting from the 2026-06-27 update, config.yaml is also synced on every boot so the righthand-man profile always uses the latest model/provider config from `generate_config()`.

The seeding logic:

1. **Clone guard (idempotent)** — if the profile directory already exists with a valid `config.yaml`, the clone step is skipped. The SOUL.md overwrite, config.yaml sync, and skill sync (steps 4–6) still execute every boot.
2. **CLI guard** — if `/app/venv/bin/hermes` does not exist (the venv binary isn't on PATH), warn and defer to the next boot.
3. **Clone** — `hermes profile create righthand-man --clone --no-alias` run as `hermeswebui` so ownership is correct. `--clone` copies `config.yaml`, `.env`, `SOUL.md`, and `skills/` from the active (default) profile. `--no-alias` avoids interactive wrapper-script prompts. A clone failure is non-fatal: it logs and retries on the next boot.
4. **Overwrite `SOUL.md`** — the cloned persona is replaced with the curated orchestrator doctrine via an embedded heredoc. This is the key step: the clone only copies the *default* persona; the curated doctrine is what makes this an orchestrator profile.
5. **`chown -R hermeswebui:hermeswebui`** — correct ownership of the entire profile directory.
6. **Sync config.yaml from default** — copies `$HERMES_HOME/config.yaml` into the righthand-man profile on every boot so the righthand-man profile always uses the same model and provider as the default profile (consumer of `generate_config()` output). Runs every boot regardless of clone guard.

The doctrine text is **embedded directly in the function** (a quoted `<<'SOULEOF'` heredoc), not read from the build tree. The build directory is not copied into the image — only the `lib/*.sh` scripts land at `/usr/local/bin/lib/`. Embedding the content makes the seed fully self-contained at runtime.

The canonical doctrine source is also kept in the build tree at `volumes_hermes_opencode/build/righthand-man/SOUL.md` for documentation and diffing purposes.

### Host-side profile

A `righthand-man` profile is also created directly on the **host** (under `~/.hermes/profiles/righthand-man`) for use outside the container. The container seeding mirrors this so the in-container and host personas stay in sync.

### The `SOUL.md` mechanism

`SOUL.md` is the **persona file**. Hermes injects its contents fresh into the system prompt for **every message** — it is not a one-shot bootstrap. This is what makes a profile's doctrine reliable: the orchestrator behavior is reasserted on each turn, so it does not drift over a long session.

## How to use it

### CLI

```bash
# Run a one-shot prompt under the orchestrator persona.
hermes -p righthand-man "Decompose and delegate: add a health-check endpoint"

# Interactive session under the profile.
hermes -p righthand-man
```

Inside the container the CLI is at `/app/venv/bin/hermes`:

```bash
docker exec -it <container> su -s /bin/bash hermeswebui -c '/app/venv/bin/hermes -p righthand-man'
```

### WebUI

Use the **profile switcher** in the Hermes WebUI (`:8787`) to select `righthand-man` for a chat session. Because the profile is seeded before the WebUI starts, it appears in the switcher on first boot.

## Routing doctrine

This is the core of the `righthand-man` doctrine. Every task is routed through a fixed division of labor across **skills** (loaded via `skill_view`) and **built-in Hermes tools** (always available, no skill load needed):

### Skills

| Skill | Owns |
|-------|------|
| **PM** (`create-prd`, `test-scenarios`, `intended-vs-implemented`) | PRD authoring, problem triage, success-criteria definition, verification policy |
| **karpathy-guidelines** | Codebase investigation, resource analysis, surfacing assumptions |
| **opencode-plan-build-orchestrator** | **ALL coding tasks** — every code edit goes to subagents |
| **dogfood** | Systematic exploratory QA of web apps — find bugs, capture evidence, produce structured reports |
| **security-best-practices** | Security review of all code changes |
| **webapp-testing** | Comprehensive test authoring and execution |
| **coding-agents-docs-guideline** | Document all changes in the repo |
| **yeet** | All git commit/push/branch operations |

### Built-in Hermes tools

| Tool | Owns |
|------|------|
| **kanban** (`hermes kanban create/swarm/list/assign/claim`) | Task delegation, wave decomposition, reconciliation — SQLite-backed shared board |
| **browser** (CDP toolset, port 9222) | Agent-x-human-in-the-loop browser use — navigate, click, type, screenshot, VNC handoff for human logins/CAPTCHAs |

The orchestrator (`righthand-man`) itself performs investigation, planning, PRD, and file-ops directly, but **delegates every code change** to subagents via `opencode-plan-build-orchestrator`. It defines verifiable success criteria *before* delegating and verifies against real tool output *after*.

## The `/goal` format

The doctrine requires that every user request be framed as a numbered goal list before acting:

```
/goal
1. <goal1>
2. <goal2>
3. ...
```

This forces decomposition up front and makes progress trackable. Combined with the "don't plan past the fog of war" rule, it means the orchestrator resolves only the decisions at the current frontier first — investigate the unknowns, surface the genuine forks, get them decided — then build.

## Verification

```bash
# Syntax check of the seed function.
bash -n volumes_hermes_opencode/build/scripts/lib/profile-righthand-man.sh

# Confirm the seed function is wired into the entrypoint.
grep -n 'profile-righthand-man\|seed_righthand_man' \
    volumes_hermes_opencode/build/scripts/entrypoint.sh

# Inside a running container: confirm the profile was seeded.
docker exec <container> ls -la /home/hermeswebui/.hermes/profiles/righthand-man/

# Confirm the doctrine is the curated one (not the default persona).
docker exec <container> head -1 /home/hermeswebui/.hermes/profiles/righthand-man/SOUL.md
# Expect: # Righthand-Man — Orchestrator Persona
```

## What Works

- Clone is idempotent (skips if profile dir exists with valid `config.yaml`); SOUL.md overwrite and skill sync run on every boot, propagating doctrine updates and new skills without manual intervention
- Self-contained seed: no runtime dependency on the build tree (doctrine embedded via heredoc)
- Correct ownership: cloned and chowned as `hermeswebui`
- Non-fatal on failure: a missing CLI or a failed clone logs and retries next boot; it never blocks container startup
- Seeded before services start, so the profile is selectable in the WebUI on first boot
- Doctrine injected fresh per message, so the orchestrator behavior does not drift

## Verdict

The `righthand-man` profile gives the stack a reproducible, doctrine-enforced orchestrator persona. Because it is seeded at container build/boot time (not hand-created), it survives rebuilds; because its `SOUL.md` is re-injected every message, the routing doctrine and `/goal` decomposition are reliably enforced rather than hoped for. Use it when you want disciplined decomposition and delegation; use the default profile for general-purpose direct execution.
