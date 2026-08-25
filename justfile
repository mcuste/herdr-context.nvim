set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

nvim := env_var_or_default("NVIM", "nvim")

default:
    @just --list

format:
    stylua .

format-check:
    stylua --check .

test:
    {{ nvim }} --headless --noplugin -u tests/minimal_init.lua \
        -c "lua dofile('tests/run.lua')" \
        -c "qa!"

smoke:
    {{ nvim }} --headless --noplugin -u tests/minimal_init.lua \
        -c "lua dofile('tests/smoke.lua')" \
        -c "qa!"

verify: format-check test smoke

release version *args:
    python3 scripts/release.py "$@"
