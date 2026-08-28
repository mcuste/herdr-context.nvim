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
    HERDR_TEST_FILE=tests/run.lua {{ nvim }} --headless --noplugin -u tests/minimal_init.lua \
        -c "lua dofile('tests/harness.lua')" \
        -c "qa!"

smoke:
    HERDR_TEST_FILE=tests/smoke.lua {{ nvim }} --headless --noplugin -u tests/minimal_init.lua \
        -c "lua dofile('tests/harness.lua')" \
        -c "qa!"
    HERDR_TEST_FILE=tests/visual.lua {{ nvim }} --headless --noplugin -u tests/minimal_init.lua \
        -c "lua dofile('tests/harness.lua')" \
        -c "qa!"

verify: format-check test smoke

# Clone the notification plugins used by the compatibility tests.
# mode is "pinned" (tests/compat/pins.txt) or "latest" (default branches).
install-test-plugins mode='pinned':
    scripts/install-test-plugins.sh {{ mode }}

# Run one headless Neovim per notification backend against the real plugin.
compat mode='pinned': (install-test-plugins mode)
    just _compat nvim_notify nvim-notify
    just _compat mini_notify mini.nvim
    just _compat snacks_notifier snacks.nvim
    just _compat noice noice.nvim,nui.nvim
    just _compat send mini.nvim

# Move tests/compat/pins.txt to the commits currently in .test-plugins/.
# Run this after "just compat latest" passes.
update-test-plugin-pins:
    scripts/update-test-plugin-pins.sh

_compat file plugins:
    HERDR_TEST_FILE=tests/compat/{{ file }}.lua HERDR_TEST_PLUGINS={{ plugins }} \
        {{ nvim }} --headless -u tests/compat/init.lua \
        -c "lua dofile('tests/harness.lua')" \
        -c "qa!"

demo:
    vhs docs/demo/herdr-context-demo.tape

release version *args:
    python3 scripts/release.py "$@"
