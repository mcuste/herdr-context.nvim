# herdr-context.nvim

Place the current Neovim file or visual line range in a Herdr agent's input,
then focus that agent. The plugin does not submit the input.

## Requirements

- Neovim 0.10 or later
- Herdr 0.7.5 or later
- Neovim running inside a Herdr pane

## Installation

With `lazy.nvim`:

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

No Neovim plugin dependencies are required.

## Setup

```lua
require('herdr-context').setup({
  mappings = {
    buffer = '<leader>ac',
    selection = '<leader>ac',
  },
})
```

Both mappings are disabled by default. Setup creates `:HerdrContextSendBuffer` and `:HerdrContextSendSelection`.

## Behavior

`send_buffer()` and `send_selection()` perform these actions:

1. Require a file that exists on disk.
2. Read `HERDR_WORKSPACE_ID` and `HERDR_TAB_ID`.
3. Run `herdr agent list`.
4. Prefer agents in the current Herdr tab.
5. Fall back to agents elsewhere in the current workspace.
6. Open `vim.ui.select` when the selected scope has several agents.
7. Format the file reference with the selected harness adapter.
8. Place the reference with `herdr pane send-text`.
9. Focus the selected agent with `herdr agent focus`.

`send_selection()` sends only the range reference when whole lines are selected. A partial-line or block selection also appends the exact selected content as a fenced code block. Each adapter uses its range syntax:

| Harness | Buffer | Lines 18-42 |
| --- | --- | --- |
| OMP | ` @path ` | ` @path#L18-42 ` |
| Pi | ` @path ` | ` @path#L18-42 ` |
| Claude Code | ` @path ` | ` @path#18-42 ` |
| Codex | ` path ` | ` path Lines 18-42. ` |
| Unknown | ` @path ` | ` @path Lines 18-42. ` |

The leading and trailing spaces are intentional. They keep the reference separate from existing agent input.

Full-buffer and whole-line operations reject unsaved changes. Partial selections include their current buffer content, so they remain exact when the buffer is modified.

Picker rows begin with a stable `[n]` match key and an Herdr status glyph. They use `[n]  status  Agent: harness  Tab: name  Title: pane title  CWD: working directory`; pane IDs stay internal.

The plugin never submits the inserted text. Add context or edit it before you press Enter.

Run `:checkhealth herdr-context` to check Neovim, Herdr, and the required environment variables.

## Development

```sh
just verify
```

Run `just --list` to see the formatting, test, smoke, and release commands.

## Releases

1. Add user-visible changes under `Unreleased` in [CHANGELOG.md](CHANGELOG.md).
2. Commit all tracked changes on `main`.
3. Run `just release <version>`.
4. Push `main` and the new tag with the commands printed by the release script.

Use `just release <version> --push` to perform the final push automatically. The release command dates the changelog entry, runs `just verify`, creates `chore: release <version>`, and tags it as `v<version>`.

Pushing the tag runs the release workflow. It validates the changelog, tests Neovim 0.10 and stable, and publishes a GitHub release.

## License

MIT
