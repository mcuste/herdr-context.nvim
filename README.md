# herdr-context.nvim

<p>
  <a href="https://github.com/mcuste/herdr-context.nvim/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/mcuste/herdr-context.nvim/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://neovim.io/"><img alt="Neovim 0.10+" src="https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&amp;logoColor=white"></a>
  <a href="https://herdr.dev/"><img alt="Herdr 0.7.5+" src="https://img.shields.io/badge/Herdr-0.7.5%2B-555555"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
</p>

Send the current file or visual selection from Neovim to a coding agent in
[Herdr](https://herdr.dev/), a terminal workspace for coding agents. One command finds the right
agent, places the file reference in its prompt using the syntax it expects, and focuses its pane.
You can add to or change the prompt before submitting it.

The plugin supports OMP, Pi, Claude Code, and Codex import syntax. It has no Neovim plugin
dependencies and works with any `vim.ui.select` provider.

## How it works

![How herdr-context.nvim places a file reference](docs/diagrams/context-delivery.svg)

Agent selection follows these steps:

1. Check the current Herdr tab.
2. If the tab has one agent, select it automatically.
3. Open `vim.ui.select` when the tab has several agents.
4. Check the other tabs in the workspace when the current tab has no agents.
5. If one workspace agent remains, select it automatically.
6. Open `vim.ui.select` when several workspace agents remain.
7. Notify the user and stop without changing any prompt when the workspace has no agents.

### What is added to the prompt

| What you send from Neovim | What the plugin adds | Why |
| --- | --- | --- |
| Current file | A file reference | The agent can read the complete file from disk |
| One or more whole lines selected in Visual mode | A file reference with the inclusive start and end lines | The agent can read only that range from disk |
| Part of a line or a block selection | A ranged file reference followed by the exact selected text in a fenced code block | Line numbers alone cannot describe the exact characters or block |

The current-file operation and whole-line Visual selections point to the version on disk. The plugin
refuses them when the buffer has unsaved changes. A partial-line or block selection can
include unsaved changes because its exact text is added to the prompt. The file must already exist
on disk in every case.

Before adding the text, the plugin makes the path relative to the selected agent's working directory
when possible. It then formats the path and range using that agent's syntax. It does not add an
instruction or submit the prompt.

## Requirements

- Neovim 0.10 or later
- Herdr 0.7.5 or later
- Neovim running inside a Herdr pane
- A current buffer backed by a file on disk

Run `:checkhealth herdr-context` after installation to check the first three requirements.

## Install

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'mcuste/herdr-context.nvim',
  opts = {
    mappings = {
      buffer = '<leader>ac',
      selection = '<leader>ac',
    },
  },
}
```

### [MiniMax](https://nvim-mini.org/MiniMax/)

Add the matching block below the `add` and `later` helpers in MiniMax's `plugin/40_plugins.lua`.

Neovim 0.12 or later:

```lua
later(function()
  add({ 'https://github.com/mcuste/herdr-context.nvim' })
  require('herdr-context').setup({
    mappings = {
      buffer = '<leader>ac',
      selection = '<leader>ac',
    },
  })
end)
```

Neovim 0.10 or 0.11:

```lua
later(function()
  add('mcuste/herdr-context.nvim')
  require('herdr-context').setup({
    mappings = {
      buffer = '<leader>ac',
      selection = '<leader>ac',
    },
  })
end)
```

Both mappings can use the same keys because one applies in Normal mode and the other in Visual
mode. No mappings are created unless you configure them.

## Commands

| Command | Mode | Action |
| --- | --- | --- |
| `:HerdrContextSendBuffer` | Normal | Place a reference to the current file |
| `:HerdrContextSendSelection` | Visual | Place a reference to the selected range |
| `:checkhealth herdr-context` | Any | Check Neovim, Herdr, and the current Herdr environment |

The selection command accepts the Ex range that Neovim creates after a Visual-mode selection.

## Reference formats

The selected agent determines the reference syntax.

For `lua/plugin.lua` and lines 18 through 42:

| Agent | Whole file | Selected lines |
| --- | --- | --- |
| OMP | ` @lua/plugin.lua ` | ` @lua/plugin.lua#L18-42 ` |
| Pi | ` @lua/plugin.lua ` | ` @lua/plugin.lua#L18-42 ` |
| Claude Code | ` @lua/plugin.lua ` | ` @lua/plugin.lua#18-42 ` |
| Codex | ` lua/plugin.lua ` | ` lua/plugin.lua Lines 18-42. ` |
| Unknown agent type | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |

Codex paths that contain spaces are enclosed in double quotes.

## Picker

Neovim supplies the default `vim.ui.select` picker. A UI plugin can replace it.
herdr-context.nvim does not depend on Telescope, mini.pick, snacks.nvim, or another picker.

Each picker row starts with a stable `[n]` match key, followed by the Herdr status marker, harness,
tab, optional pane title, and working directory:

```text
[2] ○  Agent: codex  Tab: API  Title: Fix routing  CWD: /work/project
```

Selecting a blocked agent is refused. Cancelling the picker changes nothing.

## Configuration

The complete default configuration is:

```lua
require('herdr-context').setup({
  mappings = {
    buffer = '',
    selection = '',
  },
})
```

| Option | Mode | Default | Purpose |
| --- | --- | --- | --- |
| `mappings.buffer` | Normal | Disabled | Call `send_buffer()` |
| `mappings.selection` | Visual | Disabled | Call `send_selection()` |

An empty string disables that mapping. Setup always creates both user commands.

## Lua API

```lua
local herdr_context = require('herdr-context')

herdr_context.setup({
  mappings = {
    buffer = '<leader>ac',
    selection = '<leader>ac',
  },
})

herdr_context.send_buffer()
herdr_context.send_selection()
```

| Function | Action |
| --- | --- |
| `setup(config)` | Validate configuration, create commands, and create configured mappings |
| `send_buffer()` | Place a reference to the current saved file |
| `send_selection()` | Place a reference to the current or most recent Visual selection |

## Failure behavior

The plugin stops before each dependent action when something fails:

| Failure | Result |
| --- | --- |
| Missing file, unsaved whole-file input, or unsaved whole lines | No Herdr command runs |
| Missing Herdr environment or failed agent list | No text is placed |
| Failed tab list or cancelled picker | No text is placed |
| Invalid or blocked target | No text is placed |
| Failed `pane send-text` | The target is not focused |
| Failed `agent focus` | The text remains in the target input and Neovim reports the focus error |

The plugin does not write buffers, start agents, or press Enter in an agent pane.

## Health and troubleshooting

Run:

```vim
:checkhealth herdr-context
```

The check reports:

- the Neovim version
- the Herdr executable and version
- `HERDR_WORKSPACE_ID` and `HERDR_TAB_ID`
- whether Herdr accepts the agent and tab list commands

If the environment variables are missing, start Neovim from a Herdr pane. If the commands do not
exist, make sure your plugin manager called `setup()`. Neovim reports delivery and focus failures
through `vim.notify`.

## Documentation

- [Behavior and routing](docs/behavior.md)
- [Development and release](docs/development.md)
- [`:help herdr-context`](doc/herdr-context.txt)
- [Changelog](CHANGELOG.md)

## Development

```sh
just verify
```

This checks formatting and runs the deterministic and end-to-end test suites. See
[Development and release](docs/development.md) for the repository layout, local testing, CI, and
release process.

## License

[MIT](LICENSE)
