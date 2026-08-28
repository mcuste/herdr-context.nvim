# Development and release

## Repository layout

| Path | Purpose |
| --- | --- |
| `lua/herdr-context/init.lua` | Public API, configuration, commands, mappings, and operation control |
| `lua/herdr-context/context.lua` | File validation, Visual selection capture, and relative paths |
| `lua/herdr-context/diagnostics.lua` | Diagnostic collection, line ranges, and one-line text |
| `lua/herdr-context/messages.lua` | Neovim message history collection and notification formatting |
| `lua/herdr-context/messages/*.lua` | One normalized history adapter for each external notification backend |
| `lua/herdr-context/router.lua` | Workspace and tab routing, target validation, and picker labels |
| `lua/herdr-context/adapters.lua` | OMP, Pi, Claude Code, Codex, and generic reference formats |
| `lua/herdr-context/cli.lua` | Herdr process calls and JSON response parsing |
| `lua/herdr-context/health.lua` | `:checkhealth herdr-context` implementation |
| `doc/herdr-context.txt` | Neovim help shown by `:help herdr-context` |
| `tests/run.lua` | Deterministic behavior tests inside headless Neovim |
| `tests/smoke.lua` | End-to-end command, failure, and health scenarios against the fixture CLI |
| `tests/visual.lua` | A real Visual-mode mapping scenario against the fixture CLI |
| `tests/harness.lua` | Runs one test file and makes Neovim exit nonzero when it fails |
| `tests/compat/*.lua` | Compatibility tests against the real notification plugins |
| `tests/compat/pins.txt` | Plugin repositories and pinned commits for the compatibility tests |
| `tests/fixtures/herdr` | Deterministic replacement for the Herdr executable |
| `tests/fixtures/selection.md` | Stable file content for selection tests |
| `scripts/install-test-plugins.sh` | Clones the notification plugins used by the compatibility tests |
| `scripts/update-test-plugin-pins.sh` | Moves the pins to the checked out plugin commits |
| `scripts/release.py` | Release checks, changelog update, commit, tag, and optional push |
| `scripts/check-version.py` | Release tag and changelog validation in GitHub Actions |

## Operation order

The public functions validate editor input before starting asynchronous Herdr work. The remaining
operation follows the sequence in [Behavior and routing](behavior.md):

1. `context.lua` creates file-based records, or `messages.lua` collects message and notification history.
2. `cli.lua` lists agents through `vim.system`.
3. `router.lua` limits the candidates to the current workspace and preferred tab.
4. `vim.ui.select` chooses a target when several candidates remain.
5. `adapters.lua` formats file-based context for the selected agent.
6. `cli.lua` places the text in the pane.
7. `cli.lua` focuses the pane after successful placement.


Each callback returns immediately after an error. A failed earlier operation must not start a later
one. In particular, text placement must succeed before focus starts.

The CLI parser checks every Herdr response before another module uses it. Successful list responses
must contain lists with valid records. Failed responses prefer Herdr's structured error message and
otherwise use stderr or a fixed fallback. Text-placement and focus commands accept successful empty
output because current Herdr versions do not need to return a body.

### Notification source adapters

Each module below `messages/` owns one external notification API. Its `collect()` function detects an
already loaded backend, reads only that backend's history, and normalizes records to `message`,
`level`, and `title`. It returns an empty list after an unavailable or failing API. `messages.lua`
has no backend field access. Update only the affected source adapter when a plugin API changes.

## Commands

```bash
just --list
just format
just format-check
just test
just smoke
just verify
just compat
just compat latest
```

| Command | Purpose |
| --- | --- |
| `just format` | Format Lua with StyLua |
| `just format-check` | Check Lua formatting without changing files |
| `just test` | Run deterministic module and operation tests in headless Neovim |
| `just smoke` | Run fixture-backed command, Visual-mode, failure, and health scenarios |
| `just verify` | Run the formatting check and both test suites |
| `just install-test-plugins [mode]` | Clone the notification plugins into `.test-plugins/` |
| `just compat [mode]` | Run the notification plugin compatibility tests |
| `just update-test-plugin-pins` | Move the pins to the commits in `.test-plugins/` |

`mode` is `pinned` (default) or `latest`. `pinned` checks out the commits in `tests/compat/pins.txt`.
`latest` checks out the default branch of each plugin. `just compat` needs network access, so it is
not part of `just verify`.

`NVIM=/path/to/nvim just verify` selects another Neovim binary. CI uses this to cover Neovim 0.10
and stable.

## Test design

`tests/minimal_init.lua` adds the repository to `runtimepath`. The suites run with `--noplugin`, so an
installed copy of herdr-context.nvim cannot replace the working copy.

Every suite runs through `tests/harness.lua`, which reads the test file from `HERDR_TEST_FILE`. Neovim
exits with status 0 after an error in a `-c` command, so the harness catches the error and calls
`cquit 1`. Without it a failing suite would still pass in CI.

`tests/run.lua` replaces process calls and picker calls in memory. It covers reference formatting,
selection capture, diagnostic collection, CLI parsing, candidate choice, target validation, picker
labels, setup, and the public send functions.

Diagnostic tests set records with `vim.diagnostic.set()` in a test namespace, so they need no
language server.

Selection tests open `tests/fixtures/selection.md` so README edits cannot change their input.

`tests/smoke.lua` puts `tests/fixtures` first on `PATH`. The fixture records exact commands and input
text while returning the same JSON shapes as Herdr. Named scenarios cover successful operations,
command failures, picker cancellation, missing environment, unavailable executables, and health
results.

`tests/visual.lua` enters Visual mode, invokes a configured mapping through Neovim's input path, and
checks the exact text sent to the fixture. Keep this scenario when changing mappings, Visual-mode
capture, or command registration.

A new observable behavior should have one test at the lowest useful level:

- Use `tests/run.lua` for deterministic data or callback behavior.
- Use `tests/smoke.lua` when the result depends on a real `vim.system` process or health output.
- Use `tests/visual.lua` only when Neovim mode and key handling are part of the behavior.
- Use `tests/compat/` only when the behavior depends on an external plugin API.

Do not assert source text or internal helper names. Assert the command order, placed text,
notification, selected target, or public configuration instead.

## Notification plugin compatibility tests

`tests/run.lua` passes hand-built record shapes to the source adapters. Those tests cannot see an
upstream API change, and `messages.lua` hides an adapter failure on purpose, so a changed API would
silently drop a notification history. The compatibility tests close that gap.

`just compat` starts one headless Neovim process per backend. Each process adds only the working tree
and that backend's runtime paths, so the adapters cannot read another backend's history:

| Test file | Runtime paths | Backend |
| --- | --- | --- |
| `tests/compat/nvim_notify.lua` | `nvim-notify` | `require('notify')` |
| `tests/compat/mini_notify.lua` | `mini.nvim` | `MiniNotify` |
| `tests/compat/snacks_notifier.lua` | `snacks.nvim` | `Snacks.notifier` |
| `tests/compat/noice.lua` | `noice.nvim`, `nui.nvim` | `noice.message.manager` |
| `tests/compat/send.lua` | `mini.nvim` | `send_messages()` against the fixture CLI |

Each test configures the real plugin, emits one warning with a title and two marked lines, then waits
for `messages.collect()` to return a labelled fenced section holding both lines. `tests/compat/shared.lua`
polls the collected output with `vim.wait()`, so no test sleeps. The per-backend tests stop at
`messages.collect()`. `tests/compat/send.lua` covers the whole send path once.

Noice is the least stable adapter, because it reads `noice.message.manager` and each message's
`content()` from an internal module path. Run `just compat latest` before trusting an adapter change.

The pins keep the pull request lane deterministic. Without them an unrelated upstream commit could
fail a pull request that changed nothing, and no one could merge until someone fixed an external
plugin. The `latest` lane answers the other question, whether upstream moved, and stays outside the
gate for the same reason.

Move the pins after an adapter works against a newer plugin version. Nothing moves them
automatically:

```bash
just compat latest
just update-test-plugin-pins
```

## Testing inside Herdr

Run the working copy from a real Herdr pane:

```bash
nvim \
  --cmd "set runtimepath^=$PWD" \
  --cmd "lua require('herdr-context').setup({ mappings = { buffer = 'gs' } })"
```

Then verify the user path:

1. Run `:checkhealth herdr-context`.
2. Open a saved file below the agent's working directory.
3. Press `gs` in Normal mode.
4. Confirm the agent receives a relative whole-file reference.
5. Return to Neovim.
6. Select complete lines with Visual-line mode.
7. Press `gs`.
8. Confirm the agent receives the adapter's inclusive range.
9. Return to Neovim.
10. Select part of a line with characterwise Visual mode.
11. Press `gs`.
12. Confirm the agent receives the range and exact fenced text.
13. Leave the inserted text unsubmitted until you press Enter yourself.

When several agents share the selected tab or workspace, confirm that your configured
`vim.ui.select` provider shows every candidate and that cancellation sends nothing.

## Adding or changing an adapter

An adapter owns only text formatting. Routing, file validation, and Herdr commands stay shared.

1. Add a formatter in `lua/herdr-context/adapters.lua`.
2. Register it under the exact agent kind returned by Herdr.
3. Add whole-file and range cases to `tests/run.lua`.
4. Add partial-selection coverage when its reference syntax differs.
5. Update the format tables in `README.md`, `docs/behavior.md`, and `doc/herdr-context.txt`.
6. Run `just verify`.

Keep one leading and one trailing space unless the target agent requires different spacing.
Preserve the selected text after the reference when `context.selection` is present.

## Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests. It checks StyLua formatting,
runs `just test` plus `just smoke`, and runs `just compat pinned` against Neovim 0.10.4 and stable.
The pinned commits make this lane reproducible, so it can gate pull requests.

`.github/workflows/compat-latest.yml` runs `just compat latest` every day and on manual dispatch,
against current Neovim stable. An upstream change can turn it red without any change here, so it is
not a pull request gate. On failure it opens or comments on an issue labelled `plugin-drift`, and it
closes that issue after the tests pass again. It does not change the pins and opens no pull request.
This lane needs `issues: write`.

Both workflows use the fixture Herdr executable and do not need a live Herdr workspace.

## Release

User-visible changes belong under `## [Unreleased]` in `CHANGELOG.md`.

Prepare a release from a clean `main` branch:

```bash
just release <version>
```

The version must use `MAJOR.MINOR.PATCH`. The script performs these actions:

1. Refuse a release with tracked changes, the wrong branch, an existing tag, an empty Unreleased
   section, or a version that is not newer.
2. Add a dated changelog heading for the requested version.
3. Run `just verify`.
4. Restore `CHANGELOG.md` when verification fails.
5. Commit `CHANGELOG.md` as `chore: release <version>`.
6. Create the `v<version>` tag.
7. Print the separate push and undo commands.

Push after reviewing the commit and tag:

```bash
git push origin main && git push origin v<version>
```

Or let the release command push both refs:

```bash
just release <version> --push
```

Pushing the tag starts `.github/workflows/release.yml`. It validates the tag against the changelog,
checks formatting, tests Neovim 0.10.4 and stable, and creates a GitHub release with the matching
changelog section after both test jobs pass.
