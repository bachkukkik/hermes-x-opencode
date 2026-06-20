# 19 — Security Doctrine

## What

The security doctrine is the set of standing orders and permission rules that govern what the OpenCode agent is allowed to do at runtime. It has two halves: (1) the human-authored rules in `AGENTS.md` — mandated skills, code-quality rules, and the security-mode matrix — and (2) the machine-enforced permission block injected into `opencode.jsonc` at container boot. The `AGENTS.md` half is advisory to the agent; the `opencode.jsonc` half is enforced by the OpenCode tool-execution layer regardless of what the LLM does.

The doctrine is verified by `tests/e2e/07-doctrine.bats` (17 tests), the second-largest test file. No other doc referenced it before this one.

## Why

- Makes security policy declarative and reproducible — the same `AGENTS.md` and `OPENCODE_SECURITY_MODE` produce the same permission block every boot
- Separates intent (`AGENTS.md`, human-readable) from enforcement (`opencode.jsonc`, machine-checked) so a compromised model cannot talk its way out of a deny rule
- Gives operators a single knob (`OPENCODE_SECURITY_MODE`) to trade safety for flexibility across deployment trust levels
- The permission rules are model-independent: even if the LLM fully complies with a prompt-injection payload, the tool-execution layer blocks the action

## How

### The two halves

| Half | Source | Enforced by | Mutable at runtime? |
|------|--------|-------------|---------------------|
| Standing orders (mandated skills, code-quality rules, security-mode matrix) | `AGENTS.md` in the workspace | Agent reads + operator review | No (regenerated is not applicable; it is tracked in git) |
| Permission block (`bash`/`read`/`edit`/`glob`/`grep` rules) | `config-opencode.sh` case statement, driven by `OPENCODE_SECURITY_MODE` | OpenCode tool-execution layer | No (`opencode.jsonc` is regenerated every boot) |

### Security modes

The `OPENCODE_SECURITY_MODE` environment variable selects the permission profile. Three modes are defined in `AGENTS.md` section 5 and implemented in `config-opencode.sh`:

| Mode | `OPENCODE_SECURITY_MODE` | Bash rules | Interpreters | `.env` files | Use case |
|------|--------------------------|-----------|-------------|--------------|----------|
| Strict | `strict` (default) | 31 | DENIED | DENIED | Production |
| Standard | `standard` | 22 | ALLOWED | DENIED | Development |
| Yolo | `yolo` | 0 (allow all) | ALLOWED | ALLOWED | Trusted sandbox |

- **Strict** adds nine interpreter one-liner deny rules (`python3 -c *`, `node -e *`, `perl -e *`, `ruby -e *`, `bash -c *`, `sh -c *`, etc.) on top of the standard set, blocking the known env-exfiltration vectors.
- **Standard** keeps the env-dump and `.env`-access deny rules but lets interpreters run, which is convenient for development work.
- **Yolo** emits `"permission": "allow"`, removing all permission checks entirely. Only the `cc-safety-net` plugin (destructive git blocking) remains active. Use only in isolated, throwaway environments.

Mode changes require a container restart: `docker compose up -d`.

### Permission block generation

`generate_opencode_config()` in `lib/config-opencode.sh` builds the `permission` block with a `case "$security_mode"` statement (lines 111–254):

- **`yolo`** → `permission_block='"permission": "allow",'` (one line, no rule object).
- **`standard`** → a heredoc with `.env` deny rules on `read`/`edit`/`glob`/`grep` plus a 22-entry `bash` object.
- **`strict` / `*`** → the same heredoc plus nine interpreter deny rules appended to the `bash` object, totalling 31 entries. `strict` is the default (`*)` fallback), so an unrecognized or unset mode still yields the safest profile.

OpenCode evaluates bash rules with **last-match-wins** semantics: the broad `"*": "allow"` rule is written first, then specific deny rules override it. Appending new deny rules is therefore always safe. The same `.env` deny pattern (`".env*": "deny"`, `"*/.env*": "deny"`, `"*.env": "deny"`) is applied to `read`, `edit`, `glob`, and `grep` in both `strict` and `standard`.

The full rule listing for strict mode is documented in `13 — Security Hardening`.

### What `07-doctrine.bats` asserts

The doctrine test file checks both halves end to end:

| Test | Block | Asserts |
|------|-------|---------|
| D2.3, D3.1 | Doctrine loading | `AGENTS.md` is present in the workspace and references all 5 mandated skills |
| D5.1, D5.2, D5.3 | Security compliance | `AGENTS.md` contains the `shell=True` prohibition, the `User-Agent: hermes-agent` standing order, and the strict/standard/yolo mode table |
| D6.1 | Mode compliance | The `bash` rule count in `opencode.jsonc` matches `OPENCODE_SECURITY_MODE` (31 / 22 / 0), or `permission` equals `"allow"` in yolo |
| D6.2 | Structural validity | The permission block is either `"allow"` (yolo) or a `bash` dict with at least 22 rules |
| D7.1 | User isolation | Gateway and opencode serve run as `hermeswebui`, not root |

The remaining tests (D1.x API connectivity, D2.1/D2.2 config & skills audit, D4.1 gateway auth, D7.2 env propagation) cover adjacent behaviour and are kept in this file because the doctrine spans the whole stack.

## Verification

Count the bash rules in the generated config (strict should be 31, standard 22):

```bash
C=$(docker compose ps -q hermes-opencode)
docker exec "$C" python3 -c "import json,re; t=open('/home/hermeswebui/.config/opencode/opencode.jsonc').read(); t=re.sub(r'(?<![:a-zA-Z])//.*',' ',t); c=json.loads(t); print(len(c.get('permission',{}).get('bash',{})))"
```

Confirm the active mode and that yolo collapses to `"allow"`:

```bash
docker exec "$C" bash -lc 'echo "OPENCODE_SECURITY_MODE=${OPENCODE_SECURITY_MODE:-strict}"'
docker exec "$C" python3 -c "import json,re; t=open('/home/hermeswebui/.config/opencode/opencode.jsonc').read(); t=re.sub(r'(?<![:a-zA-Z])//.*',' ',t); print(json.loads(t).get('permission'))"
```

Confirm the doctrine is present in the workspace and references the mandated skills:

```bash
docker exec "$C" test -f /workspace/AGENTS.md
docker exec "$C" grep -c 'karpathy\|security-best-practices\|webapp-testing\|coding-agents-docs-guideline\|yeet' /workspace/AGENTS.md
```

Confirm services run as a non-root user:

```bash
docker exec "$C" bash -c 'ps -eo user:20,args | grep -E "hermes gateway|opencode serve" | grep -v grep | grep -v "su " | awk "{print \$1}"'
```

Run the doctrine test suite:

```bash
bats tests/e2e/07-doctrine.bats
```

## What Works

- A single `OPENCODE_SECURITY_MODE` value deterministically selects the entire permission profile
- The `case` statement defaults to `strict`, so an unset or mistyped mode yields the safest block rather than an empty one
- Last-match-wins semantics make the deny list append-safe — adding rules never weakens existing policy
- The permission rules are model-independent: a fully compliant LLM still cannot execute a denied command
- `07-doctrine.bats` verifies both the human-readable doctrine (`AGENTS.md` contents) and the machine-enforced block (`opencode.jsonc` rule counts) in one file

## What Fails

- **`yolo` disables all rules:** `"permission": "allow"` removes every permission check. Only `cc-safety-net` remains. Never use with real API keys.
- **Custom interpreters not in the deny list:** `lua`, `php -r`, `awk` ENVIRON are not blocked by rules. Mitigated by not being installed in the container image.
- **Env vars are not isolated by user:** User isolation (`hermeswebui`) prevents filesystem writes but all three services still see the same environment variables from the docker-compose `environment:` pass-through.
- **Whitespace-based bypasses are untested:** Extra spaces or tabs in command strings may evade `cc-safety-net` pattern matching.

## Resolution

- Use `strict` (the default) for any deployment with real API keys. Use `standard` only on a trusted dev machine that needs interpreter access. Use `yolo` only in isolated, throwaway sandboxes.
- If additional interpreters are installed in the image, append the corresponding `-c`/`-e` deny rules to the strict branch of the `case` statement in `config-opencode.sh`.
- For true environment-variable isolation, switch from docker-compose `environment:` pass-through to Docker secrets or Kubernetes secret mounts (an architectural change beyond this scope).

## Verdict

The doctrine pairs a human-readable policy (`AGENTS.md`) with a machine-enforced permission block (`opencode.jsonc`) selected by one env var. The default `strict` profile blocks all tested exfiltration and destructive-command vectors; `standard` trades interpreter blocking for development convenience; `yolo` is escape-hatch only. The permission layer is model-independent, so even a fully-injected agent cannot bypass it.
