#!/usr/bin/env bash
set -euo pipefail

DST=/opt/hermes-skills-staging/software-development

mkdir -p "$DST/security-best-practices" "$DST/webapp-testing"

cat > "$DST/security-best-practices/SKILL.md" << 'EOF'
---
name: security-best-practices
description: Security best practices for all code changes
version: 0.1.0
status: stub
---

# Security Best Practices

> **STUB SKILL** — placeholder mandated by AGENTS.md.

## When to Use
Load on every task involving code changes.

## Core Principles
- No shell=True in subprocess calls
- No hardcoded secrets
- Validate all user input
- Safe defaults (deny by default)
EOF

cat > "$DST/webapp-testing/SKILL.md" << 'EOF'
---
name: webapp-testing
description: Write and run comprehensive tests
version: 0.1.0
status: stub
---

# Web Application Testing

> **STUB SKILL** — placeholder mandated by AGENTS.md.

## When to Use
Load on every task involving testing.

## Core Principles
- Write tests before or alongside code changes
- Cover happy path, edge cases, error conditions
- Run full test suite before declaring complete
- Tests must pass in CI
EOF

echo "Stub skills created."
