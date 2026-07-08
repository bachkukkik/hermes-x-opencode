# 31 — Port Utils

## What

`lib/port-utils.sh` provides a single function `wait_for_port()` that polls a TCP port until it accepts connections (with optional HTTP health endpoint check). Used throughout the entrypoint to ensure services are ready before proceeding to dependent startup steps.

## Why

- The entrypoint starts multiple background services in dependency order
- Each service must be ready before the next startup step or health gate
- Provides consistent timeout handling across all services
- Uses both `curl` (HTTP health checks) and `nc -z` (TCP fallback) for reliability
- Does NOT exit on timeout — the caller decides how to handle failures

## How

### Function signature

```bash
wait_for_port <port> [timeout] [label] [health_path]
```

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `port` | (required) | TCP port number |
| `timeout` | 120 | Max wait in seconds |
| `label` | `"port $port"` | Log label |
| `health_path` | `/health` | HTTP health path (empty to skip) |

Returns 0 if ready, 1 on timeout.
