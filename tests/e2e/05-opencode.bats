#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "AC8: opencode binary available and reports version" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" opencode --version
    [ "$status" -eq 0 ]
}

@test "AC21: OpenCode skills installed" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local count
    count=$(docker exec "$cid" find /home/hermeswebui/.config/opencode/skills -name "SKILL.md" 2>/dev/null | wc -l)
    [ "$count" -gt 0 ]
}

@test "AC23: opencode serve health endpoint returns healthy" {
    run curl -sf "$(opencode_base)/global/health"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"healthy": *true'
}

@test "AC24: Hermes skills present after staging copy" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local count
    count=$(docker exec "$cid" find /home/hermeswebui/.hermes/skills -name "SKILL.md" 2>/dev/null | wc -l)
    [ "$count" -gt 0 ]
}

@test "AC22: security mode permission rules applied" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local mode="${OPENCODE_SECURITY_MODE:-strict}"
    local expected
    case "$mode" in
        strict)   expected=31 ;;
        standard) expected=22 ;;
        yolo)     expected=0  ;;
        *)        expected=31 ;;
    esac
    if [ "$expected" -eq 0 ]; then
        local has_permission
        has_permission=$(docker exec "$cid" python3 -c "
import json
c = json.load(open('/home/hermeswebui/.config/opencode/opencode.jsonc'))
print(c.get('permission', ''))
" 2>/dev/null)
        [ "$has_permission" = "allow" ]
    else
        local count
        count=$(docker exec "$cid" python3 -c "
import json
c = json.load(open('/home/hermeswebui/.config/opencode/opencode.jsonc'))
print(len(c.get('permission', {}).get('bash', {})))
" 2>/dev/null)
        [ "$count" -ge "$expected" ]
    fi
}
