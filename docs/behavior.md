# Behavior and routing

This page defines what the plugin sends and how it selects an agent.

![Context delivery sequence](diagrams/context-delivery.svg)

## Editor input

File operations require a normal buffer and a file that exists on disk. The plugin normalizes each
path before it calls Herdr.

### Files

- `send_buffer()` sends the current file. It refuses unsaved changes because the reference must
  match the file on disk.
- `send_buffers()` sends saved, listed file buffers in buffer order. It skips invalid or modified
  buffers and reports the count. It stops if no valid buffer remains.
- In Visual mode, the current buffer can include a selection. Other buffers use whole-file
  references.

### Diagnostics

`send_diagnostics()` reads `vim.diagnostic.get()` and sends one ranged reference per diagnostic.

- A selection keeps diagnostics on overlapping lines.
- Unsaved changes are refused.
- Results are sorted by line, severity, and message.
- No matching diagnostic stops the operation.

`send_buffers_diagnostics()` checks every buffer used by `send_buffers()`. Files without diagnostics
keep a whole-file reference. A selection limits diagnostics in the current buffer.

### Quickfix and location lists

`send_quickfix()` reads `getqflist()`. `send_loclist()` reads `getloclist(0)`. They read list items,
not quickfix window text.

Each valid item becomes a reference followed by its text:

```text
 @lua/plugin.lua#L18-18 local value = build()
```

- Items without a valid file are skipped.
- An item without a line becomes a whole-file reference.
- Duplicate ranges merge their unique text with `; `.
- Results keep list order.
- Multiline item text becomes one line.
- `quickfix.limit` limits `send_quickfix()` to 50 references by default. Use `0` or
  `send_quickfix_all()` for the full list.
- An empty list stops the operation.

### Messages and notifications

`send_messages()` sends the full `:messages` history. Active nvim-notify, mini.notify,
Snacks.notifier, and noice.nvim backends add their retained notifications in separate sections.
Noice adds only `notify` events, which avoids duplicate Neovim messages.

This operation ignores selections, needs no file buffer, and stops if every history is empty.

### Visual selections

`send_buffer()` supports characterwise, linewise, and blockwise selections.

| Selection | Text sent | Modified buffer |
| --- | --- | --- |
| Complete lines | Ranged reference | Refused |
| Partial lines | Ranged reference and selected text | Allowed |
| Block | Ranged reference and rectangular text | Allowed |

Selected text uses a fenced code block with the buffer filetype:

````text
 @lua/plugin.lua#L18-20

```lua
local value = build()
return value
```
````

The file must exist on disk. For a modified buffer, the reference gives the location and the fence
contains the current text. Ex ranges use the latest `'<` and `'>` marks.

## Agent routing

The plugin requires `HERDR_WORKSPACE_ID` and `HERDR_TAB_ID`.

1. Run `herdr agent list`.
2. Keep agents in the current workspace.
3. Prefer agents in the current tab.
4. If the tab has no agent, use all agents in the workspace.
5. Select the only match directly.
6. For several matches, run `herdr tab list --workspace <workspace-id>`.
7. Open `vim.ui.select`.
8. Reject a blocked agent or one without a pane identifier.
9. Place the text, then focus the agent.

Current-tab preference is strict. A blocked agent in the current tab stops routing instead of sending
to another tab.

## Picker

The plugin uses `vim.ui.select`, so any compatible UI plugin can replace the default picker.
Candidates follow Herdr tab order, then pane identifier order. `[n]` gives each row a stable search
key.

```text
[2] ○  Agent: codex  Tab: API  Title: Fix routing  CWD: /work/project
```

| Part | Value |
| --- | --- |
| `[2]` | Candidate position |
| `○` | Agent state |
| `Agent` | `name`, `agent`, or `kind` |
| `Tab` | Label, number, or identifier |
| `Title` | Pane title |
| `CWD` | Foreground directory, then agent directory |

State markers:

| State | Marker |
| --- | --- |
| `blocked`, `working`, `done` | `●` |
| `idle` | `○` |
| Missing or unknown | `·` |

Cancelling the picker sends nothing.

## Paths

The plugin uses the agent's `foreground_cwd`, then `cwd`. Files inside that directory use relative
paths. Other files use absolute paths. Path checks use directory boundaries. Windows checks ignore
case.

## Reference formats

The agent `kind` selects the format. If `kind` is missing, the plugin uses `agent`. Unknown values
use the generic format.

| Adapter | Whole file | Lines 18 through 42 |
| --- | --- | --- |
| Amp | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Antigravity | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Claude Code | ` @lua/plugin.lua ` | ` @lua/plugin.lua#18-42 ` |
| Cline | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Codex | ` lua/plugin.lua ` | ` lua/plugin.lua Lines 18-42. ` |
| Copilot CLI | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Cursor | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Devin | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Droid | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Gemini CLI | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Grok CLI | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Hermes | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Kilo Code | ` @lua/plugin.lua ` | ` @lua/plugin.lua#18-42 ` |
| Kimi CLI | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Kiro CLI | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Maki | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Mastra Code | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| OMP | ` @lua/plugin.lua ` | ` @lua/plugin.lua#L18-42 ` |
| opencode | ` @lua/plugin.lua ` | ` @lua/plugin.lua#18-42 ` |
| Pi | ` @lua/plugin.lua ` | ` @lua/plugin.lua#L18-42 ` |
| Qoder CLI | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Qwen Code | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |
| Generic | ` @lua/plugin.lua ` | ` @lua/plugin.lua Lines 18-42. ` |

References have surrounding spaces so they do not join existing input. Codex quotes paths with
spaces. Gemini CLI and Qwen Code escape spaces and shell characters. Kiro CLI uses plain text.

Diagnostic references add severity, message, source, and code when available. Quickfix references
add item text. A range ending at column 0 ends on the previous line.

## Herdr commands

The plugin passes argument arrays to `vim.system`. It does not build shell commands.

1. `herdr agent list`
2. `herdr tab list --workspace <workspace-id>` when a picker is needed
3. `herdr pane send-text <pane-id> <text>`
4. `herdr agent focus <pane-id>`

Focus runs only after placement succeeds. The plugin does not submit the prompt.

## Failures

| Failure | Result |
| --- | --- |
| Invalid input, empty list, or no matching content | Warning; no Herdr command |
| Missing Herdr environment | Error; no Herdr command |
| Agent list failure or invalid response | Error; no routing |
| No workspace agent | Warning; no placement |
| Tab list failure or invalid response | Error; no picker |
| Picker cancelled | No notification; no placement |
| Invalid target | Error; no placement |
| Blocked target | Warning; no placement |
| Placement failure | Error; no focus |
| Focus failure | Error; placed text remains |

Notifications use `vim.notify` with the title `herdr-context.nvim`.

## Limits

- The plugin does not save or modify buffers.
- File operations send references, not full file contents.
- Only partial-line and block selections include source text.
- The plugin does not run linters or change Neovim lists and histories.
- The plugin does not start agents, change workspaces, submit prompts, or define a picker UI.
