#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
session=${HERDR_CONTEXT_DEMO_SESSION:-herdr-context-demo}
server_log="$project_root/docs/demo/.herdr-server.log"
user_herdr_config=${HERDR_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml}
if [[ -f $user_herdr_config ]]; then
  export HERDR_CONFIG_PATH=$user_herdr_config
fi

cleanup() {
  herdr session stop "$session" >/dev/null 2>&1 || true
  herdr session delete "$session" >/dev/null 2>&1 || true
  rm -f "$server_log"
}

json_value() {
  python3 -c "import json, sys; print(json.load(sys.stdin)$1)"
}

start_agent() {
  local pane_id=$1
  local kind=$2
  local name=$3
  local display=$4
  shift 4

  herdr --session "$session" pane rename "$pane_id" "$display" >/dev/null
  herdr --session "$session" agent start "$name" \
    --kind "$kind" \
    --pane "$pane_id" \
    --timeout 60000 \
    -- \
    "$@" >/dev/null
}

start_server() {
  herdr --session "$session" server >"$server_log" 2>&1 &

  for _ in {1..100}; do
    if herdr --session "$session" workspace list >/dev/null 2>&1; then
      return
    fi
    sleep 0.05
  done

  cat "$server_log" >&2
  return 1
}

start_demo() {
  unset HERDR_ENV HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_PANE_ID HERDR_TERMINAL_ID
  cleanup
  trap cleanup EXIT
  trap 'exit 130' INT HUP TERM
  start_server

  local workspace workspace_id root_pane tab_id split agent_pane
  workspace=$(herdr --session "$session" workspace create \
    --cwd "$project_root" \
    --label herdr-context.nvim \
    --no-focus)
  workspace_id=$(printf '%s' "$workspace" | json_value "['result']['workspace']['workspace_id']")
  root_pane=$(printf '%s' "$workspace" | json_value "['result']['root_pane']['pane_id']")
  tab_id=$(printf '%s' "$workspace" | json_value "['result']['tab']['tab_id']")

  herdr --session "$session" tab rename "$tab_id" Showcase >/dev/null
  herdr --session "$session" pane rename "$root_pane" Neovim >/dev/null

  split=$(herdr --session "$session" pane split "$root_pane" \
    --direction right \
    --ratio 0.42 \
    --cwd "$project_root" \
    --no-focus)
  agent_pane=$(printf '%s' "$split" | json_value "['result']['pane']['pane_id']")

  start_agent "$agent_pane" omp omp OMP --no-session

  herdr --session "$session" pane run "$root_pane" \
    "nvim -n --cmd 'set runtimepath^=.' -c \"lua require('herdr-context').setup({ mappings = { buffer = 'gs', buffers = 'gS', selection = 'gs' } })\" docs/demo/context-example.lua docs/demo/context-helpers.lua"
  herdr --session "$session" pane wait-output "$root_pane" \
    --match 'herdr-context.nvim demo' \
    --timeout 10000 >/dev/null
  herdr --session "$session" workspace focus "$workspace_id" >/dev/null
  "$project_root/docs/demo/start-herdr-context-demo.sh" schedule-agent "$agent_pane" \
    >/dev/null 2>&1 &

  herdr --session "$session"
}

add_picker_agent() {
  local source_pane=$1
  local split agent_pane

  split=$(herdr --session "$session" pane split "$source_pane" \
    --direction down \
    --ratio 0.5 \
    --cwd "$project_root" \
    --no-focus)
  agent_pane=$(printf '%s' "$split" | json_value "['result']['pane']['pane_id']")

  start_agent "$agent_pane" claude claude Claude
  herdr --session "$session" pane focus \
    --direction left \
    --pane "$source_pane" >/dev/null
}

schedule_picker_agent() {
  sleep 50
  add_picker_agent "$1"
}

for command in bash claude herdr nvim omp python3; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  }
done

case ${1:-start} in
start)
  start_demo
  ;;
schedule-agent)
  schedule_picker_agent "$2"
  ;;
clean)
  cleanup
  ;;
*)
  printf 'usage: %s [start|schedule-agent PANE_ID|clean]\n' "$0" >&2
  exit 2
  ;;
esac
