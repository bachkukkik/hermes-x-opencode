# lib/constants.sh - path and user variable declarations - sourced by entrypoint.sh

export HERMES_HOME="/home/hermeswebui/.hermes"
CONFIG="/home/hermeswebui/.hermes/config.yaml"
AGENT_DIR="/home/hermeswebui/.hermes/hermes-agent"
STAGING_DIR="/opt/hermes-agent-staging"
HERMES_SKILLS_DIR="/home/hermeswebui/.hermes/skills"
WIKI_DIR="${WIKI_PATH:-/home/hermeswebui/.hermes/wiki}"
OPENCODE_USER="hermeswebui"
OPENCODE_USER_HOME="/home/${OPENCODE_USER}"
OPENCODE_CONFIG="${OPENCODE_USER_HOME}/.config/opencode/opencode.jsonc"
OPENCODE_SKILLS_DIR="${OPENCODE_USER_HOME}/.config/opencode/skills"
