#!/usr/bin/env python3
"""Fix #20: Patch providers.py to check key_env for provider status display.

Upstream: https://github.com/nesquena/hermes-webui (not yet fixed as of v0.51.340)
The runtime's _resolve_key() already handles key_env; this brings the display in sync.

Patches two functions:
1. _provider_has_key() - add key_env check after providers.<id>.api_key check
2. get_providers() custom_providers scan - add key_env check before providers.append
"""
import os
import sys

path = '/apptoo/api/providers.py'

try:
    with open(path) as f:
        src = f.read()
except FileNotFoundError:
    print('!! Fix #20: providers.py not found (image structure may have changed)')
    sys.exit(0)

# Patch 1: _provider_has_key() - add key_env check after providers.<id>.api_key
p1_old = (
    '            if _provider_value_counts_as_api_key(provider_id, provider_cfg.get("api_key")):\n'
    '                return True\n'
    '    # Check custom_providers'
)
p1_new = (
    '            if _provider_value_counts_as_api_key(provider_id, provider_cfg.get("api_key")):\n'
    '                return True\n'
    '            key_env = str(provider_cfg.get("key_env") or "").strip()\n'
    '            if key_env and os.getenv(key_env, "").strip():\n'
    '                return True\n'
    '    # Check custom_providers'
)

if p1_old in src:
    src = src.replace(p1_old, p1_new, 1)
    print('== Fix #20 patch 1 applied (_provider_has_key key_env fallback)')
else:
    print('!! Fix #20 patch 1 SKIPPED (pattern not found)')

# Patch 2: get_providers() custom provider scan - add key_env check before providers.append
# Anchor updated for upstream refactor (cp_api_key->cp_key, added credential-pool fallback).
p2_old = (
    '            # Fallback: check credential pool (key added via hermes auth add)\n'
    '            if not cp_has_key:\n'
    '                try:\n'
    '                    from api.config import _has_explicit_pool_credentials\n'
    '                    if _has_explicit_pool_credentials(cp_id):\n'
    '                        cp_has_key = True\n'
    '                except ImportError:\n'
    '                    pass\n'
    '            providers.append({'
)
p2_new = (
    '            # Fallback: check credential pool (key added via hermes auth add)\n'
    '            if not cp_has_key:\n'
    '                try:\n'
    '                    from api.config import _has_explicit_pool_credentials\n'
    '                    if _has_explicit_pool_credentials(cp_id):\n'
    '                        cp_has_key = True\n'
    '                except ImportError:\n'
    '                    pass\n'
    '            if not cp_has_key:\n'
    '                key_env = str(cp.get("key_env") or "").strip()\n'
    '                if key_env:\n'
    '                    cp_has_key = bool(os.getenv(key_env, "").strip())\n'
    '            providers.append({'
)

if p2_old in src:
    src = src.replace(p2_old, p2_new, 1)
    print('== Fix #20 patch 2 applied (get_providers key_env fallback)')
else:
    print('!! Fix #20 patch 2 SKIPPED (pattern not found)')

with open(path, 'w') as f:
    f.write(src)
print('== Fix #20: patching complete')
