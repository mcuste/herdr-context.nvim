# herdr-context.nvim

<p>
  <a href="https://github.com/mcuste/herdr-context.nvim/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/mcuste/herdr-context.nvim/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://neovim.io/"><img alt="Neovim 0.10+" src="https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&amp;logoColor=white"></a>
  <a href="https://herdr.dev/"><img alt="Herdr 0.7.5+" src="https://img.shields.io/badge/Herdr-0.7.5%2B-555555"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
</p>

![herdr-context.nvim demo](docs/demo/herdr-context-demo.gif)

Send context from Neovim to a coding agent in [Herdr](https://herdr.dev/) with one command. It finds the right agent,
places the context in its prompt, and focuses its pane. When several agents match, it asks you to pick one.

It can send:

- the current file, or a visual selection in it
- every open buffer
- the diagnostics of the current file, the selection, or every open file
- the quickfix list or the location list
- the message and notification histories

File references use the syntax that the selected agent expects. The plugin never submits the prompt,
so you can change it first.

The plugin supports every agent that Herdr detects. It has no Neovim plugin dependencies and works
with any `vim.ui.select` provider.

## How it works

![How herdr-context.nvim places context](docs/diagrams/context-delivery.svg)

How automated agent picking works:

<img src="docs/diagrams/agent-selection.svg" alt="Agent selection flow">

Picking uses `vim.ui.select`. Tab preference is strict: if the only agent in your tab is blocked, the
plugin refuses it and does not send to another tab.

### What is added to the prompt

The examples below use OMP syntax. Each agent has its own, see [Reference formats](#reference-formats).

Current file:

```text
 @lua/plugin.lua
```

All open files:

```text
 @README.md
 @lua/plugin.lua
```

Whole lines selected in Visual mode:

```text
 @lua/plugin.lua#L18-19
```

Part of a line, or a block selection. Line numbers cannot describe the exact characters, so the
selected text comes with it:

````text
 @lua/plugin.lua#L18-19

```lua
local value = build()
return value
```
````

Current file and its diagnostics. A diagnostic already names the file and its lines, so no separate
file reference is placed:

```text
 @lua/plugin.lua#L18-19 ERROR undefined global `value` [lua_ls undefined-global]
 @lua/plugin.lua#L31-31 WARN unused variable [lua_ls]
```

A Visual selection and its diagnostics. Only the diagnostics in the selected lines are placed:

```text
 @lua/plugin.lua#L18-19 ERROR undefined global `value` [lua_ls undefined-global]
```

All open files and their diagnostics. A file without a diagnostic keeps its plain reference:

```text
 @README.md#L1-1 ERROR first line must be a heading [markdownlint MD041]
 @lua/plugin.lua#L18-19 WARN unused variable [lua_ls]
 @docs/behavior.md
```

The quickfix list or the location list. Each entry keeps its own text:

```text
 @lua/plugin.lua#L18-18 local value = build()
 @lua/plugin.lua#L31-31 return value
 @README.md#L3-3 send the value
```

Message and notification history:

````text
 Neovim messages:

```text
build failed
stack trace
```

 mini.notify notifications:

```text
[WARN]
build failed
```
````

These rules cover file references:

- Save first. A reference points at the file on disk. The plugin refuses or skips a modified buffer.
  A partial-line or block selection is the exception, because it sends the text itself. Diagnostics
  always need a saved file.
- Paths are shortened. An agent working in `/work/project` gets `@lua/plugin.lua`, not
  `@/work/project/lua/plugin.lua`. A file outside the agent's directory keeps its full path.
- No extra file context is added.

The message command sends the complete `:messages` history. It has no limit and reads no selection.
Active [nvim-notify](https://github.com/rcarriga/nvim-notify),
[mini.notify](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-notify.md),
[Snacks.notifier](https://github.com/folke/snacks.nvim/blob/main/docs/notifier.md), and
[noice.nvim](https://github.com/folke/noice.nvim) backends add their retained notifications in
labelled sections.

[Behavior and routing](docs/behavior.md) has the exact rules for every operation.

## Requirements

- Neovim 0.10 or later
- Herdr 0.7.5 or later
- Neovim running inside a Herdr pane
- A current buffer backed by a file on disk for file-based operations

Run `:checkhealth herdr-context` after installation to check the first three requirements.

## Install

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'mcuste/herdr-context.nvim',
  opts = {
    mappings = {
      buffer = '<leader>aa',
      buffers = '<leader>aA',
      diagnostics = '<leader>ad',
      buffers_diagnostics = '<leader>aD',
      messages = '<leader>am',
      quickfix = '<leader>aq',
      quickfix_all = '<leader>aQ',
      loclist = '<leader>al',
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
      buffer = '<leader>aa',
      buffers = '<leader>aA',
      diagnostics = '<leader>ad',
      buffers_diagnostics = '<leader>aD',
      messages = '<leader>am',
      quickfix = '<leader>aq',
      quickfix_all = '<leader>aQ',
      loclist = '<leader>al',
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
      buffer = '<leader>aa',
      buffers = '<leader>aA',
      diagnostics = '<leader>ad',
      buffers_diagnostics = '<leader>aD',
      messages = '<leader>am',
      quickfix = '<leader>aq',
      quickfix_all = '<leader>aQ',
      loclist = '<leader>al',
    },
  })
end)
```

Each configured mapping works in Normal and Visual mode. Use different keys for each action.
Mappings with an empty value are not created.

Quickfix sends at most 50 entries by default. Set `quickfix = { limit = 0 }` in `opts` or `setup()`
to remove the limit.

## Commands

| Command                               | Selection | Action                                                                 |
| ------------------------------------- | --------- | ---------------------------------------------------------------------- |
| `:HerdrContextSendBuffer`             | Used      | Place a reference to the current file or selected range                |
| `:HerdrContextSendBuffers`            | Used      | Place a reference to every open file                                   |
| `:HerdrContextSendDiagnostics`        | Used      | Place a reference to every diagnostic in the current file or selection |
| `:HerdrContextSendBuffersDiagnostics` | Used      | Place a reference to every diagnostic in the open files                |
| `:HerdrContextSendQuickfix`           | Ignored   | Place a reference to each quickfix entry, up to `quickfix.limit`       |
| `:HerdrContextSendQuickfixAll`        | Ignored   | Place a reference to each quickfix entry, with no limit                |
| `:HerdrContextSendLoclist`            | Ignored   | Place a reference to each entry in the window location list            |
| `:HerdrContextSendMessages`           | Ignored   | Place the complete message and notification histories                  |
| `:checkhealth herdr-context`          | Ignored   | Check Neovim, Herdr, and the current Herdr environment                 |

Every command runs in Normal and Visual mode. `Selection` says whether the command reads the Visual
selection, or the Ex range that Neovim creates after leaving Visual mode.

## Reference formats

The selected agent determines the reference syntax.

For `lua/plugin.lua` and lines 18 through 42:

| Agent              | Whole file        | Selected lines                 |
| ------------------ | ----------------- | ------------------------------ |
| Amp                | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Antigravity        | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Claude Code        | `@lua/plugin.lua` | `@lua/plugin.lua#18-42`        |
| Cline              | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Codex              | `lua/plugin.lua`  | `lua/plugin.lua Lines 18-42.`  |
| Copilot CLI        | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Cursor             | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Devin              | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Droid              | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Gemini CLI         | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Grok CLI           | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Hermes             | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Kilo Code          | `@lua/plugin.lua` | `@lua/plugin.lua#18-42`        |
| Kimi CLI           | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Kiro CLI           | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Maki               | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Mastra Code        | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| OMP                | `@lua/plugin.lua` | `@lua/plugin.lua#L18-42`       |
| opencode           | `@lua/plugin.lua` | `@lua/plugin.lua#18-42`        |
| Pi                 | `@lua/plugin.lua` | `@lua/plugin.lua#L18-42`       |
| Qoder CLI          | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Qwen Code          | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |
| Unknown agent type | `@lua/plugin.lua` | `@lua/plugin.lua Lines 18-42.` |

A diagnostic keeps the reference format from the table above and appends severity, a one-line
message, and the reporting source and code when present:

```text
OMP / Pi:    @lua/plugin.lua#L18-42 ERROR undefined global `value` [lua_ls undefined-global]
Claude Code: @lua/plugin.lua#18-42 ERROR undefined global `value` [lua_ls undefined-global]
```

A quickfix entry appends its own text in the same place.

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
    buffers = '',
    diagnostics = '',
    buffers_diagnostics = '',
    messages = '',
    quickfix = '',
    quickfix_all = '',
    loclist = '',
  },
  quickfix = {
    limit = 50,
  },
})
```

| Option                         | Mode           | Default  | Purpose                           |
| ------------------------------ | -------------- | -------- | --------------------------------- |
| `mappings.buffer`              | Normal, Visual | Disabled | Call `send_buffer()`              |
| `mappings.buffers`             | Normal, Visual | Disabled | Call `send_buffers()`             |
| `mappings.diagnostics`         | Normal, Visual | Disabled | Call `send_diagnostics()`         |
| `mappings.buffers_diagnostics` | Normal, Visual | Disabled | Call `send_buffers_diagnostics()` |
| `mappings.messages`            | Normal, Visual | Disabled | Call `send_messages()`            |
| `mappings.quickfix`            | Normal, Visual | Disabled | Call `send_quickfix()`            |
| `mappings.quickfix_all`        | Normal, Visual | Disabled | Call `send_quickfix_all()`        |
| `mappings.loclist`             | Normal, Visual | Disabled | Call `send_loclist()`             |
| `quickfix.limit`               | Any            | `50`     | Largest number of list references |

An empty string disables that mapping. Setup always creates all eight user commands.

`quickfix.limit` applies to `send_quickfix()` only. A longer list is cut, and Neovim reports how
many references it sent. `0` removes the limit. `send_quickfix_all()` always sends the whole list.
A location list holds the results of one window, so `send_loclist()` has no limit.

## Lua API

```lua
local herdr_context = require('herdr-context')

herdr_context.setup({
  mappings = {
    buffer = '<leader>aa',
    buffers = '<leader>aA',
  },
})

herdr_context.send_buffer()
herdr_context.send_buffers()
herdr_context.send_diagnostics()
herdr_context.send_buffers_diagnostics()
herdr_context.send_quickfix()
herdr_context.send_quickfix_all()
herdr_context.send_loclist()
herdr_context.send_messages()
```

| Function                     | Action                                                                  |
| ---------------------------- | ----------------------------------------------------------------------- |
| `setup(config)`              | Validate configuration, create commands, and create configured mappings |
| `send_buffer()`              | Place a reference to the current saved file or Visual selection         |
| `send_buffers()`             | Place a reference to every open saved file                              |
| `send_diagnostics()`         | Place a reference to every diagnostic in the current file or selection  |
| `send_buffers_diagnostics()` | Place a reference to every diagnostic in the open files                 |
| `send_quickfix()`            | Place a reference to each quickfix entry, up to `quickfix.limit`        |
| `send_quickfix_all()`        | Place a reference to each quickfix entry, with no limit                 |
| `send_loclist()`             | Place a reference to each entry in the window location list             |
| `send_messages()`            | Place the complete message and notification histories                   |

## Failure behavior

The plugin stops before each dependent action when something fails:

| Failure                                                        | Result                                                                  |
| -------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Missing file, unsaved whole-file input, or unsaved whole lines | No Herdr command runs                                                   |
| No open buffer saved on disk                                   | No Herdr command runs                                                   |
| No diagnostic in the current file, selection, or open files    | No Herdr command runs                                                   |
| Empty list, or no list entry saved on disk                     | No Herdr command runs                                                   |
| Empty message and notification history                         | No Herdr command runs                                                   |
| Missing Herdr environment or failed agent list                 | No text is placed                                                       |
| Failed tab list or cancelled picker                            | No text is placed                                                       |
| Invalid or blocked target                                      | No text is placed                                                       |
| Failed `pane send-text`                                        | The target is not focused                                               |
| Failed `agent focus`                                           | The text remains in the target input and Neovim reports the focus error |

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
