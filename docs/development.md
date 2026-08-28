# Development and release

## Repository layout

| Path | Purpose |
| --- | --- |
| `lua/herdr-context/init.lua` | Public API, setup, commands, and mappings |
| `lua/herdr-context/context.lua` | File checks, selections, and paths |
| `lua/herdr-context/diagnostics.lua` | Diagnostic collection and formatting |
| `lua/herdr-context/quickfix.lua` | Quickfix and location list collection |
| `lua/herdr-context/text.lua` | Shared one-line text normalization |
| `lua/herdr-context/messages.lua` | Message and notification history |
| `lua/herdr-context/messages/*.lua` | Notification backend adapters |
| `lua/herdr-context/router.lua` | Agent routing, validation, and picker labels |
| `lua/herdr-context/adapters.lua` | Agent reference formats |
| `lua/herdr-context/cli.lua` | Herdr commands and response parsing |
| `lua/herdr-context/health.lua` | `:checkhealth herdr-context` |
| `doc/herdr-context.txt` | Neovim help |
| `tests/run.lua` | Deterministic behavior tests |
| `tests/smoke.lua` | Command, failure, and health tests |
| `tests/visual.lua` | Visual-mode mapping test |
| `tests/compat/*.lua` | Notification plugin compatibility tests |
| `tests/fixtures/herdr` | Fixture Herdr executable |
| `scripts/release.py` | Release automation |

## Operation flow

See [Behavior and routing](behavior.md) for user-visible rules.

1. `context.lua` collects file input through `diagnostics.lua` or `quickfix.lua` when needed.
   `messages.lua` collects message and notification input.
2. `cli.lua` lists agents.
3. `router.lua` selects candidates.
4. `vim.ui.select` handles multiple candidates.
5. `adapters.lua` formats file context.
6. `cli.lua` places the text.
7. `cli.lua` focuses the agent.

An error stops the flow. Placement must succeed before focus starts. `cli.lua` validates every Herdr
response before another module uses it.

Each module in `messages/` reads one notification backend. Its `collect()` function returns records
with `message`, `level`, and `title`. An unavailable or failing backend returns no records.

## Commands

| Command | Purpose |
| --- | --- |
| `just format` | Format Lua |
| `just format-check` | Check Lua formatting |
| `just test` | Run deterministic tests |
| `just smoke` | Run fixture-backed scenarios |
| `just verify` | Run formatting, tests, and smoke scenarios |
| `just install-test-plugins [mode]` | Install notification plugins |
| `just compat [mode]` | Run notification compatibility tests |
| `just update-test-plugin-pins` | Update compatibility pins |

Compatibility mode is `pinned` by default. Use `latest` to test current plugin branches:

```bash
just compat latest
```

Compatibility tests need network access, so `just verify` does not run them. Set `NVIM` to test
another Neovim binary:

```bash
NVIM=/path/to/nvim just verify
```

## Tests

`tests/minimal_init.lua` loads the working tree with `--noplugin`. `tests/harness.lua` makes Neovim
exit with a failure status when a test fails.

| Suite | Use |
| --- | --- |
| `tests/run.lua` | Data, callbacks, formatting, routing, and public API behavior |
| `tests/smoke.lua` | `vim.system`, commands, failures, and health output |
| `tests/visual.lua` | Neovim modes and mappings |
| `tests/compat/` | External notification APIs |

Test observable results such as command order, sent text, notifications, and selected targets. Do
not test source text or private helper names.

### Notification compatibility

Each compatibility test loads one real backend:

| Test | Backend |
| --- | --- |
| `nvim_notify.lua` | nvim-notify |
| `mini_notify.lua` | mini.notify |
| `snacks_notifier.lua` | Snacks.notifier |
| `noice.lua` | noice.nvim |
| `send.lua` | Full send path with mini.notify |

Pinned versions keep pull requests reproducible. The daily `latest` run detects upstream changes.
Noice uses an internal API, so run `just compat latest` after changing its adapter.

Update pins only after all adapters pass:

```bash
just compat latest
just update-test-plugin-pins
```

## Manual test in Herdr

Run the working tree from a Herdr pane:

```bash
nvim \
  --cmd "set runtimepath^=$PWD" \
  --cmd "lua require('herdr-context').setup({ mappings = { buffer = 'gs' } })"
```

1. Run `:checkhealth herdr-context`.
2. Send a saved file with `gs`.
3. Check that the agent receives a relative file reference.
4. Send complete lines in Visual-line mode.
5. Check that the agent receives an inclusive range.
6. Send part of a line in characterwise Visual mode.
7. Check that the agent receives the range and exact fenced text.
8. Leave the inserted text unsubmitted.

With several agents, check the picker and cancel once to confirm that cancellation sends nothing.

## Add or change an agent adapter

An agent adapter formats references. It does not route agents or run Herdr commands.

1. Add the formatter to `lua/herdr-context/adapters.lua`.
2. Register the exact Herdr agent kind.
3. Add whole-file and range tests to `tests/run.lua`.
4. Test partial selections if the syntax differs.
5. Update `README.md`, `docs/behavior.md`, and `doc/herdr-context.txt`.
6. Run `just verify`.

Keep the surrounding spaces unless the agent requires another format. Keep selected text after the
reference.

## Continuous integration

`.github/workflows/ci.yml` checks formatting, tests, smoke scenarios, and pinned compatibility on
Neovim 0.10.4 and stable.

`.github/workflows/compat-latest.yml` tests current notification plugin branches each day. A failure
opens or updates an issue with the `plugin-drift` label. This workflow does not gate pull requests or
change pins.

Both workflows use the fixture Herdr executable.

## Release

Add user-visible changes under `## [Unreleased]` in `CHANGELOG.md`. From a clean `main` branch, run:

```bash
just release <version>
```

Use `MAJOR.MINOR.PATCH`. The command:

1. Checks the branch, working tree, version, tag, and changelog.
2. Adds the dated changelog section.
3. Runs `just verify`.
4. Creates the release commit and `v<version>` tag.
5. Prints push and undo commands.

Push after review:

```bash
git push origin main && git push origin v<version>
```

Use `just release <version> --push` to push from the release command.

The tag starts `.github/workflows/release.yml`. It validates the changelog, runs checks on Neovim
0.10.4 and stable, and creates the GitHub release.
