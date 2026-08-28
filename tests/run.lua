local tests = {}
local failures = 0
local selection_fixture = vim.fn.getcwd() .. '/tests/fixtures/selection.md'

local function test(name, body) table.insert(tests, { name = name, body = body }) end

local function assert_equal(actual, expected)
  if vim.deep_equal(actual, expected) then return end
  error(string.format('expected %s, got %s', vim.inspect(expected), vim.inspect(actual)), 2)
end

local function with_cli_stubs(stubs, body)
  local cli = require('herdr-context.cli')
  local original = {}

  for name, replacement in pairs(stubs) do
    original[name] = cli[name]
    cli[name] = replacement
  end

  local ok, err = xpcall(body, debug.traceback)
  for name, value in pairs(original) do
    cli[name] = value
  end
  if not ok then error(err, 0) end
end

local function with_environment(workspace_id, tab_id, body)
  local original_workspace = vim.env.HERDR_WORKSPACE_ID
  local original_tab = vim.env.HERDR_TAB_ID
  vim.env.HERDR_WORKSPACE_ID = workspace_id
  vim.env.HERDR_TAB_ID = tab_id

  local ok, err = xpcall(body, debug.traceback)
  vim.env.HERDR_WORKSPACE_ID = original_workspace
  vim.env.HERDR_TAB_ID = original_tab
  if not ok then error(err, 0) end
end

local function with_notification_capture(body)
  local original = vim.notify
  local notifications = {}
  vim.notify = function(message, level) table.insert(notifications, { message = message, level = level }) end

  local ok, err = xpcall(function() body(notifications) end, debug.traceback)
  vim.notify = original
  if not ok then error(err, 0) end
end

local diagnostics_namespace = vim.api.nvim_create_namespace('herdr-context-test')

local function with_diagnostics(buf, items, body)
  vim.diagnostic.set(diagnostics_namespace, buf, items)

  local ok, err = xpcall(body, debug.traceback)
  vim.diagnostic.reset(diagnostics_namespace, buf)
  if not ok then error(err, 0) end
end

local function with_modified_selection(body)
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# changed' })
  vim.api.nvim_buf_set_mark(buf, '<', 1, 2, {})
  vim.api.nvim_buf_set_mark(buf, '>', 1, 6, {})

  local ok, err = xpcall(function() body(buf) end, debug.traceback)
  vim.cmd('edit!')
  vim.cmd('silent! %bwipeout!')
  if not ok then error(err, 0) end
end

local function single_agent_stubs(record)
  return {
    list_agents = function(callback)
      callback({
        ok = true,
        value = {
          agents = {
            { agent = 'omp', workspace_id = 'w1', tab_id = 't1', pane_id = 'w1:p1', foreground_cwd = vim.fn.getcwd() },
          },
        },
      })
    end,
    send_text = function(_, text, callback)
      record(text)
      callback({ ok = true, value = {} })
    end,
    focus = function(_, callback) callback({ ok = true, value = {} }) end,
  }
end

local function readme_diagnostics()
  return {
    { lnum = 1, col = 0, severity = vim.diagnostic.severity.INFO, message = 'stale badge', source = 'markdownlint' },
  }
end

local function sample_diagnostics()
  return {
    {
      lnum = 2,
      col = 0,
      end_lnum = 2,
      end_col = 5,
      severity = vim.diagnostic.severity.ERROR,
      message = 'undefined global `value`',
      source = 'lua_ls',
      code = 'undefined-global',
    },
    {
      lnum = 0,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = 'unused\nvariable',
      source = 'lua_ls',
    },
    { lnum = 3, col = 0, end_lnum = 4, end_col = 0, severity = vim.diagnostic.severity.HINT, message = 'block' },
  }
end

local function with_ui_select(replacement, body)
  local original = vim.ui.select
  vim.ui.select = replacement

  local ok, err = xpcall(body, debug.traceback)
  vim.ui.select = original
  if not ok then error(err, 0) end
end

test('formats a relative file through the agent adapter', function()
  local context = require('herdr-context.context')
  local normalized = context.for_agent({ file = '/workspace/lua/plugin.lua' }, '/workspace')
  assert_equal(normalized.relative_file, 'lua/plugin.lua')
  assert_equal(require('herdr-context.adapters').format({ agent = 'omp' }, normalized), ' @lua/plugin.lua ')
end)

test('registers concrete adapters with a generic fallback', function()
  local adapters = require('herdr-context.adapters')
  local expected = ' @plugin.lua '
  local context = { relative_file = 'plugin.lua' }

  assert_equal(adapters.get('omp').format(context), expected)
  assert_equal(adapters.get('pi').format(context), expected)
  assert_equal(adapters.get('claude').format(context), expected)
  assert_equal(adapters.get('opencode').format(context), expected)
  assert_equal(adapters.get('agy').format(context), expected)
  assert_equal(adapters.get('codex').format(context), ' plugin.lua ')
  assert_equal(adapters.get('codex').format({ relative_file = 'lua/my plugin.lua' }), ' "lua/my plugin.lua" ')
  assert_equal(adapters.get('unknown'), adapters.registry.generic)
  assert_equal(adapters.get('omp') == adapters.get('pi'), false)
  assert_equal(adapters.get('claude') == adapters.get('opencode'), false)
  assert_equal(adapters.get('codex') == adapters.get('omp'), false)
end)

test('formats native and fallback line ranges', function()
  local adapters = require('herdr-context.adapters')
  local context = {
    relative_file = 'lua/plugin.lua',
    start_line = 18,
    end_line = 42,
    range = true,
  }

  assert_equal(adapters.get('omp').format(context), ' @lua/plugin.lua#L18-42 ')
  assert_equal(adapters.get('pi').format(context), ' @lua/plugin.lua#L18-42 ')
  assert_equal(adapters.get('claude').format(context), ' @lua/plugin.lua#18-42 ')
  assert_equal(adapters.get('opencode').format(context), ' @lua/plugin.lua#18-42 ')
  assert_equal(adapters.get('agy').format(context), ' @lua/plugin.lua Lines 18-42. ')
  assert_equal(adapters.get('codex').format(context), ' lua/plugin.lua Lines 18-42. ')
  assert_equal(adapters.get('unknown').format(context), ' @lua/plugin.lua Lines 18-42. ')
end)

test('appends partial selection content after native ranges', function()
  local adapters = require('herdr-context.adapters')
  local context = {
    relative_file = 'lua/plugin.lua',
    filetype = 'lua',
    start_line = 18,
    end_line = 18,
    range = true,
    whole_lines = false,
    selection = 'local value',
  }
  local expected = ' @lua/plugin.lua#L18-18 \n\n```lua\nlocal value\n```'

  assert_equal(adapters.get('omp').format(context), expected)
  context.selection = 'local ``` value'
  assert_equal(adapters.get('omp').format(context), ' @lua/plugin.lua#L18-18 \n\n````lua\nlocal ``` value\n````')
end)

test('appends diagnostic text after the reference', function()
  local adapters = require('herdr-context.adapters')
  local context = {
    relative_file = 'lua/plugin.lua',
    start_line = 18,
    end_line = 20,
    range = true,
    diagnostic = 'ERROR undefined global `value` [lua_ls undefined-global]',
  }

  assert_equal(
    adapters.get('omp').format(context),
    ' @lua/plugin.lua#L18-20 ERROR undefined global `value` [lua_ls undefined-global] '
  )
  assert_equal(
    adapters.get('claude').format(context),
    ' @lua/plugin.lua#18-20 ERROR undefined global `value` [lua_ls undefined-global] '
  )
  assert_equal(
    adapters.get('opencode').format(context),
    ' @lua/plugin.lua#18-20 ERROR undefined global `value` [lua_ls undefined-global] '
  )
  assert_equal(
    adapters.get('codex').format(context),
    ' lua/plugin.lua Lines 18-20. ERROR undefined global `value` [lua_ls undefined-global] '
  )
end)

test('puts every reference on its own line', function()
  local adapters = require('herdr-context.adapters')
  local contexts = { { relative_file = 'lua/plugin.lua' }, { relative_file = 'README.md' } }

  assert_equal(adapters.format_many({ agent = 'omp' }, contexts), ' @lua/plugin.lua \n @README.md ')
  assert_equal(adapters.format_many({ agent = 'codex' }, contexts), ' lua/plugin.lua \n README.md ')
  assert_equal(adapters.format_many({ agent = 'omp' }, { contexts[1] }), ' @lua/plugin.lua ')
end)

test('keeps selected text with its own reference', function()
  local adapters = require('herdr-context.adapters')
  local contexts = {
    {
      relative_file = 'README.md',
      filetype = 'markdown',
      start_line = 3,
      end_line = 3,
      range = true,
      selection = '# title',
    },
    { relative_file = 'lua/plugin.lua' },
  }

  assert_equal(
    adapters.format_many({ agent = 'omp' }, contexts),
    ' @README.md#L3-3 \n\n```markdown\n# title\n```\n @lua/plugin.lua '
  )
end)

test('collects every listed buffer saved on disk', function()
  local plugin_file = vim.fs.normalize(vim.fn.getcwd() .. '/lua/herdr-context/init.lua')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  vim.cmd('edit ' .. vim.fn.fnameescape(plugin_file))
  vim.cmd('enew')
  local scratch = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { 'unsaved' })

  local contexts, skipped = require('herdr-context.context').from_buffers()
  vim.cmd('silent! %bwipeout!')

  assert_equal(vim.tbl_map(function(item) return item.file end, contexts), { selection_fixture, plugin_file })
  assert_equal(skipped, 1)
end)

test('includes a listed buffer that is not loaded yet', function()
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local readme = vim.fs.normalize(vim.fn.getcwd() .. '/README.md')
  local unloaded = vim.fn.bufadd(readme)
  vim.bo[unloaded].buflisted = true

  local contexts, skipped = require('herdr-context.context').from_buffers()
  local loaded = vim.api.nvim_buf_is_loaded(unloaded)
  vim.cmd('silent! %bwipeout!')

  assert_equal(loaded, false)
  assert_equal(vim.tbl_map(function(item) return item.file end, contexts), { selection_fixture, readme })
  assert_equal(skipped, 0)
end)

test('replaces only the current buffer with the focused context', function()
  local context = require('herdr-context.context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.normalize(vim.fn.getcwd() .. '/README.md')))
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local focus = context.from_selection(0, 'v', { 1, 2 }, { 1, 6 })

  local contexts = context.from_buffers(focus)
  vim.cmd('silent! %bwipeout!')

  assert_equal(#contexts, 2)
  assert_equal(contexts[1].range, nil)
  assert_equal(contexts[2], focus)
end)

test('keeps an absolute file outside the agent working directory', function()
  local context = require('herdr-context.context')
  local normalized = context.for_agent({ file = '/other/plugin.lua' }, '/workspace')
  assert_equal(normalized.relative_file, '/other/plugin.lua')
end)

test('does not treat a path prefix as a parent directory', function()
  local context = require('herdr-context.context')
  local normalized = context.for_agent({ file = '/workspace/plugin.lua' }, '/work')
  assert_equal(normalized.relative_file, '/workspace/plugin.lua')
end)

test('normalizes an inclusive visual line range', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()
  local selection = require('herdr-context.context').from_selection(buf, 'V', { 2, 0 }, { 1, 0 })

  assert_equal(selection.start_line, 1)
  assert_equal(selection.end_line, 2)
  assert_equal(selection.range, true)
  assert_equal(selection.whole_lines, true)
  assert_equal(selection.selection, nil)
  assert_equal(selection.modified, false)
end)

test('keeps partial single-line selection content', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()
  local selection = require('herdr-context.context').from_selection(buf, 'v', { 1, 2 }, { 1, 6 })

  assert_equal(selection.start_line, 1)
  assert_equal(selection.end_line, 1)
  assert_equal(selection.whole_lines, false)
  assert_equal(selection.selection, 'herdr')
end)
test('keeps partial block selection content', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()
  local selection = require('herdr-context.context').from_selection(buf, '\22', { 3, 0 }, { 4, 3 })

  assert_equal(selection.start_line, 3)
  assert_equal(selection.end_line, 4)
  assert_equal(selection.whole_lines, false)
  assert_equal(selection.selection, 'Plac\nthen')
end)

test('keeps modified partial content but rejects modified whole lines', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '# changed' })

  local context = require('herdr-context.context')
  local partial = context.from_selection(buf, 'v', { 1, 2 }, { 1, 8 })
  local whole, whole_error = context.from_selection(buf, 'V', { 1, 0 }, { 1, 0 })
  vim.cmd('edit!')

  assert_equal(partial.selection, 'changed')
  assert_equal(partial.modified, true)
  assert_equal(whole, nil)
  assert_equal(whole_error, 'The current buffer has unsaved changes.')
end)

test('sorts diagnostics by line and severity and shortens a multiline message', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()

  with_diagnostics(buf, sample_diagnostics(), function()
    local items = require('herdr-context.diagnostics').collect(buf)
    assert_equal(items, {
      { start_line = 1, end_line = 1, severity = 2, text = 'WARN unused variable [lua_ls]' },
      {
        start_line = 3,
        end_line = 3,
        severity = 1,
        text = 'ERROR undefined global `value` [lua_ls undefined-global]',
      },
      { start_line = 4, end_line = 4, severity = 4, text = 'HINT block' },
    })
  end)
end)

test('keeps only diagnostics that overlap a line range', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()

  with_diagnostics(buf, sample_diagnostics(), function()
    local diagnostics = require('herdr-context.diagnostics')
    assert_equal(vim.tbl_map(function(item) return item.start_line end, diagnostics.collect(buf, 3, 4)), { 3, 4 })
    assert_equal(vim.tbl_map(function(item) return item.start_line end, diagnostics.collect(buf, 1, 1)), { 1 })
    assert_equal(diagnostics.collect(buf, 2, 2), {})
  end)
end)

test('formats a diagnostic with fallbacks for missing fields', function()
  local text = require('herdr-context.diagnostics').text
  local cases = {
    {
      input = {
        severity = vim.diagnostic.severity.ERROR,
        message = 'undefined global `value`',
        source = 'lua_ls',
        code = 'undefined-global',
      },
      expected = 'ERROR undefined global `value` [lua_ls undefined-global]',
    },
    {
      input = { severity = vim.diagnostic.severity.ERROR, message = 'type mismatch', source = 'tsserver', code = 2345 },
      expected = 'ERROR type mismatch [tsserver 2345]',
    },
    {
      input = { severity = vim.diagnostic.severity.WARN, message = 'unused import', code = 'no-unused' },
      expected = 'WARN unused import [no-unused]',
    },
    { input = { severity = vim.diagnostic.severity.INFO, message = 'no source' }, expected = 'INFO no source' },
    { input = { message = 'no severity' }, expected = 'UNKNOWN no severity' },
    { input = { severity = vim.diagnostic.severity.HINT }, expected = 'HINT ' },
  }

  for _, case in ipairs(cases) do
    assert_equal(text(case.input), case.expected)
  end
end)

test('orders diagnostics on one line by severity and then by message', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()
  local one_line = {
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = 'second warning' },
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.HINT, message = 'a hint' },
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = 'first warning' },
  }

  with_diagnostics(buf, one_line, function()
    local items = require('herdr-context.diagnostics').collect(buf)
    assert_equal(vim.tbl_map(function(item) return item.text end, items), {
      'WARN first warning',
      'WARN second warning',
      'HINT a hint',
    })
  end)
end)

test('keeps a diagnostic that starts above the selected lines', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()
  local spanning = {
    {
      lnum = 1,
      col = 0,
      end_lnum = 3,
      end_col = 8,
      severity = vim.diagnostic.severity.ERROR,
      message = 'unclosed block',
    },
  }

  with_diagnostics(buf, spanning, function()
    local diagnostics = require('herdr-context.diagnostics')
    assert_equal(diagnostics.collect(buf, 3, 3), {
      { start_line = 2, end_line = 4, severity = 1, text = 'ERROR unclosed block' },
    })
    assert_equal(diagnostics.collect(buf, 1, 1), {})
  end)
end)

test('builds one context for each diagnostic and none for the file', function()
  local context = require('herdr-context.context')
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()

  with_diagnostics(buf, sample_diagnostics(), function()
    local contexts = context.with_diagnostics(buf, context.from_buffer(buf))
    assert_equal(#contexts, 3)
    assert_equal(contexts[1].file, selection_fixture)
    assert_equal(contexts[1].range, true)
    assert_equal(contexts[1].start_line, 1)
    assert_equal(contexts[1].diagnostic, 'WARN unused variable [lua_ls]')
  end)
end)

test('refuses diagnostics for an empty list and for unsaved changes', function()
  local context = require('herdr-context.context')
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()
  local base = context.from_buffer(buf)

  local empty, empty_error = context.with_diagnostics(buf, base)
  assert_equal(empty, nil)
  assert_equal(empty_error, 'The current buffer has no diagnostics.')

  with_diagnostics(buf, sample_diagnostics(), function()
    local selection, selection_error =
      context.with_diagnostics(buf, context.from_selection(buf, 'V', { 2, 0 }, { 2, 0 }))
    assert_equal(selection, nil)
    assert_equal(selection_error, 'The visual selection has no diagnostics.')

    local modified, modified_error = context.with_diagnostics(buf, vim.tbl_extend('force', base, { modified = true }))
    assert_equal(modified, nil)
    assert_equal(modified_error, 'The current buffer has unsaved changes.')
  end)
end)

test('parses a Herdr agent list response into records', function()
  local cli = require('herdr-context.cli')
  local stdout = vim.json.encode({
    id = 'cli:agent:list',
    result = {
      type = 'agent_list',
      agents = {
        {
          pane_id = 'w1:p1',
          workspace_id = 'w1',
          tab_id = 't1',
          terminal_title_stripped = 'Review picker',
        },
      },
    },
  })
  local result = cli.parse_agent_list(cli.parse_result({ code = 0, stdout = stdout, stderr = '' }))
  assert_equal(result.ok, true)
  assert_equal(result.value.agents, {
    { pane_id = 'w1:p1', workspace_id = 'w1', tab_id = 't1', terminal_title_stripped = 'Review picker' },
  })
end)

test('uses a structured Herdr error message', function()
  local cli = require('herdr-context.cli')
  local stdout = vim.json.encode({
    id = 'cli:agent:prompt',
    error = { code = 'agent_blocked', message = 'agent target is blocked' },
  })
  local result = cli.parse_result({ code = 1, stdout = stdout, stderr = '' })
  assert_equal(result, { ok = false, code = 1, error = 'agent target is blocked' })
end)

test('rejects invalid successful CLI output', function()
  local cli = require('herdr-context.cli')
  local result = cli.parse_result({ code = 0, stdout = 'not json', stderr = '' })
  assert_equal(result, { ok = false, code = 0, error = 'Herdr returned invalid JSON.' })
end)

test('accepts successful empty output for side-effect commands', function()
  local result = require('herdr-context.cli').parse_result({ code = 0, stdout = '', stderr = '' }, true)
  assert_equal(result, { ok = true, code = 0, value = {} })
end)

test('normalizes CLI protocol failure responses', function()
  local parse_result = require('herdr-context.cli').parse_result
  local cases = {
    {
      input = { code = 1, stdout = '', stderr = 'permission denied' },
      expected = { ok = false, code = 1, error = 'permission denied' },
    },
    {
      input = { code = 0, stdout = '{"error":{"message":"agent is unavailable"}}', stderr = '' },
      expected = { ok = false, code = 0, error = 'agent is unavailable' },
    },
    {
      input = { code = 0, stdout = '{}', stderr = '' },
      expected = { ok = false, code = 0, error = 'Herdr response has no result.' },
    },
    {
      input = { code = 0, stdout = '', stderr = '' },
      expected = { ok = false, code = 0, error = 'Herdr returned no JSON output.' },
    },
  }

  for _, case in ipairs(cases) do
    assert_equal(parse_result(case.input), case.expected)
  end
end)

test('rejects malformed Herdr list records at the CLI boundary', function()
  local cli = require('herdr-context.cli')
  local result = cli.parse_agent_list({ ok = true, code = 0, value = { agents = { { pane_id = 1 } } } })
  assert_equal(result, { ok = false, code = 0, error = 'Herdr response has an invalid pane_id.' })
end)

test('rejects incomplete tab records at the CLI boundary', function()
  local cli = require('herdr-context.cli')
  local result = cli.parse_tab_list({ ok = true, code = 0, value = { tabs = { { label = 'Agents' } } } })
  assert_equal(result, { ok = false, code = 0, error = 'Herdr response has an invalid tab identifier.' })
end)

test('prefers every agent in the current tab', function()
  local router = require('herdr-context.router')
  local current_one = { workspace_id = 'w1', tab_id = 't1', pane_id = 'p1' }
  local current_two = { workspace_id = 'w1', tab_id = 't1', pane_id = 'p2' }
  local other = { workspace_id = 'w1', tab_id = 't2', pane_id = 'p3' }
  local candidates = router.candidates({ other, current_one, current_two }, 'w1', 't1')
  assert_equal(candidates, { current_one, current_two })
end)

test('falls back to every agent in the workspace', function()
  local router = require('herdr-context.router')
  local first = { workspace_id = 'w1', tab_id = 't2', pane_id = 'p1' }
  local second = { workspace_id = 'w1', tab_id = 't3', pane_id = 'p2' }
  local candidates = router.candidates({ first, second }, 'w1', 't1')
  assert_equal(candidates, { first, second })
end)

test('reports an empty workspace', function()
  local router = require('herdr-context.router')
  local candidates, err = router.candidates({
    { workspace_id = 'w2', tab_id = 't2', pane_id = 'p2' },
  }, 'w1', 't1')
  assert_equal(candidates, nil)
  assert_equal(err.code, 'no_agents')
end)

test('defensively rejects a non-list of agents', function()
  local candidates, err = require('herdr-context.router').candidates({ named = {} }, 'w1', 't1')
  assert_equal(candidates, nil)
  assert_equal(err.code, 'invalid_agents')
end)

test('parses an agent delivery target before sending', function()
  local router = require('herdr-context.router')
  local target = router.delivery_target({
    agent = 'omp',
    pane_id = 'p1',
    foreground_cwd = '/work',
    cwd = '/fallback',
  })
  assert_equal(target, { pane_id = 'p1', kind = 'omp', foreground_cwd = '/work', cwd = '/fallback' })

  local blocked, err = router.delivery_target({ pane_id = 'p1', agent_status = 'blocked' })
  assert_equal(blocked, nil)
  assert_equal(err.code, 'blocked')
end)

test('formats indexed agent, tab, title, and cwd choices', function()
  local router = require('herdr-context.router')
  local choices = router.make_choices({
    { agent = 'omp', tab_id = 't1', pane_id = 'p3', agent_status = 'working', title = 'Review changes' },
    {
      agent = 'omp',
      tab_id = 't1',
      pane_id = 'p2',
      agent_status = 'idle',
      terminal_title_stripped = 'Fix picker labels',
      foreground_cwd = '/work',
    },
  }, {
    { tab_id = 't1', label = 'Editor' },
  })
  assert_equal(choices[1].label, '[1] ○  Agent: omp  Tab: Editor  Title: Fix picker labels  CWD: /work')
  assert_equal(choices[2].label, '[2] ●  Agent: omp  Tab: Editor  Title: Review changes')
end)

test('uses Herdr status glyphs for every state', function()
  local choices = require('herdr-context.router').make_choices({
    { agent = 'omp', tab_id = 't1', pane_id = 'p1', agent_status = 'blocked' },
    { agent = 'omp', tab_id = 't1', pane_id = 'p2', agent_status = 'done' },
    { agent = 'omp', tab_id = 't1', pane_id = 'p3' },
  }, {})
  assert_equal(vim.tbl_map(function(choice) return choice.label end, choices), {
    '[1] ●  Agent: omp  Tab: t1',
    '[2] ●  Agent: omp  Tab: t1',
    '[3] ·  Agent: omp  Tab: t1',
  })
end)

test('falls back to and sends through one workspace agent', function()
  local plugin = require('herdr-context')
  local file = vim.fs.normalize(vim.fn.getcwd() .. '/README.md')
  vim.cmd('edit ' .. vim.fn.fnameescape(file))

  local calls = {}
  local stubs = {
    list_agents = function(callback)
      table.insert(calls, { 'list' })
      callback({
        ok = true,
        value = {
          agents = {
            {
              workspace_id = 'w1',
              tab_id = 't2',
              pane_id = 'w1:p2',
              agent_status = 'working',
              foreground_cwd = vim.fn.getcwd(),
            },
          },
        },
      })
    end,
    list_tabs = function() error('tab metadata should not be requested for one candidate') end,
    send_text = function(target, text, callback)
      table.insert(calls, { 'text', target, text })
      callback({ ok = true, value = {} })
    end,
    focus = function(target, callback)
      table.insert(calls, { 'focus', target })
      callback({ ok = true, value = {} })
    end,
  }

  with_environment('w1', 't1', function() with_cli_stubs(stubs, plugin.send_buffer) end)

  assert_equal(calls, {
    { 'list' },
    { 'text', 'w1:p2', ' @README.md ' },
    { 'focus', 'w1:p2' },
  })
end)

test('selects among multiple agents in the current tab', function()
  local plugin = require('herdr-context')
  local file = vim.fs.normalize(vim.fn.getcwd() .. '/README.md')
  vim.cmd('edit ' .. vim.fn.fnameescape(file))

  local calls = {}
  local labels
  local stubs = {
    list_agents = function(callback)
      table.insert(calls, { 'list' })
      callback({
        ok = true,
        value = {
          agents = {
            {
              agent = 'omp',
              workspace_id = 'w1',
              tab_id = 't1',
              pane_id = 'w1:p3',
              agent_status = 'working',
              foreground_cwd = vim.fn.getcwd(),
            },
            {
              agent = 'omp',
              workspace_id = 'w1',
              tab_id = 't1',
              pane_id = 'w1:p2',
              agent_status = 'idle',
              foreground_cwd = vim.fn.getcwd(),
            },
          },
        },
      })
    end,
    list_tabs = function(workspace_id, callback)
      table.insert(calls, { 'tabs', workspace_id })
      callback({ ok = true, value = { tabs = { { tab_id = 't1', label = 'Editor' } } } })
    end,
    send_text = function(target, text, callback)
      table.insert(calls, { 'text', target, text })
      callback({ ok = true, value = {} })
    end,
    focus = function(target, callback)
      table.insert(calls, { 'focus', target })
      callback({ ok = true, value = {} })
    end,
  }

  local select = function(choices, options, callback)
    assert_equal(options.prompt, 'Select a Herdr agent:')
    labels = vim.tbl_map(options.format_item, choices)
    callback(choices[2])
  end

  with_environment('w1', 't1', function()
    with_cli_stubs(stubs, function() with_ui_select(select, plugin.send_buffer) end)
  end)

  assert_equal(labels, {
    '[1] ○  Agent: omp  Tab: Editor  CWD: ' .. vim.fn.getcwd(),
    '[2] ●  Agent: omp  Tab: Editor  CWD: ' .. vim.fn.getcwd(),
  })
  assert_equal(calls, {
    { 'list' },
    { 'tabs', 'w1' },
    { 'text', 'w1:p3', ' @README.md ' },
    { 'focus', 'w1:p3' },
  })
end)

test('does not send to a blocked agent', function()
  local plugin = require('herdr-context')
  local file = vim.fs.normalize(vim.fn.getcwd() .. '/README.md')
  vim.cmd('edit ' .. vim.fn.fnameescape(file))

  local text_called = false
  local stubs = {
    list_agents = function(callback)
      callback({
        ok = true,
        value = {
          agents = {
            {
              workspace_id = 'w1',
              tab_id = 't1',
              pane_id = 'w1:p2',
              agent_status = 'blocked',
            },
          },
        },
      })
    end,
    send_text = function() text_called = true end,
  }

  with_notification_capture(function(notifications)
    with_environment('w1', 't1', function() with_cli_stubs(stubs, plugin.send_buffer) end)
    assert_equal(notifications[1].message, 'The selected Herdr agent is blocked; no input was sent.')
    assert_equal(notifications[1].level, vim.log.levels.WARN)
  end)
  assert_equal(text_called, false)
end)

test('sends every open buffer as one reference list', function()
  local plugin = require('herdr-context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.normalize(vim.fn.getcwd() .. '/README.md')))
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.normalize(vim.fn.getcwd() .. '/CHANGELOG.md')))

  local calls = {}
  local stubs = {
    list_agents = function(callback)
      callback({
        ok = true,
        value = {
          agents = {
            {
              workspace_id = 'w1',
              tab_id = 't1',
              pane_id = 'w1:p1',
              agent_status = 'idle',
              foreground_cwd = vim.fn.getcwd(),
            },
          },
        },
      })
    end,
    send_text = function(target, text, callback)
      table.insert(calls, { 'text', target, text })
      callback({ ok = true, value = {} })
    end,
    focus = function(target, callback)
      table.insert(calls, { 'focus', target })
      callback({ ok = true, value = {} })
    end,
  }

  with_environment('w1', 't1', function() with_cli_stubs(stubs, plugin.send_buffers) end)
  vim.cmd('silent! %bwipeout!')

  assert_equal(calls, {
    { 'text', 'w1:p1', ' @README.md \n @CHANGELOG.md ' },
    { 'focus', 'w1:p1' },
  })
end)

test('sends the current selection with the other open buffers', function()
  local plugin = require('herdr-context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.normalize(vim.fn.getcwd() .. '/README.md')))
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  vim.bo.filetype = 'markdown'

  local sent
  local stubs = single_agent_stubs(function(text) sent = text end)

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  with_environment('w1', 't1', function() with_cli_stubs(stubs, plugin.send_buffers) end)
  vim.cmd('normal! ' .. vim.keycode('<Esc>'))
  vim.cmd('silent! %bwipeout!')

  assert_equal(sent, ' @README.md \n @tests/fixtures/selection.md#L1-1 \n\n```markdown\n# herdr\n```')
end)

test('reports skipped buffers and refuses when none is saved', function()
  local plugin = require('herdr-context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('enew')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'unsaved' })

  local text_called = false
  with_notification_capture(function(notifications)
    with_environment('w1', 't1', function()
      with_cli_stubs({ send_text = function() text_called = true end }, plugin.send_buffers)
    end)
    assert_equal(notifications[1].message, 'No open buffer is saved on disk.')

    vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.normalize(vim.fn.getcwd() .. '/README.md')))
    with_environment('', '', function()
      with_cli_stubs({ send_text = function() text_called = true end }, plugin.send_buffers)
    end)
    assert_equal(notifications[2].message, 'Skipped 1 buffer with unsaved changes or no file on disk.')
  end)
  vim.cmd('silent! %bwipeout!')

  assert_equal(text_called, false)
end)

test('sends the file with every diagnostic below it', function()
  local plugin = require('herdr-context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()

  local sent
  local stubs = single_agent_stubs(function(text) sent = text end)

  with_diagnostics(buf, sample_diagnostics(), function()
    with_environment('w1', 't1', function() with_cli_stubs(stubs, plugin.send_diagnostics) end)
  end)
  vim.cmd('silent! %bwipeout!')

  assert_equal(
    sent,
    ' @tests/fixtures/selection.md#L1-1 WARN unused variable [lua_ls] \n'
      .. ' @tests/fixtures/selection.md#L3-3 ERROR undefined global `value` [lua_ls undefined-global] \n'
      .. ' @tests/fixtures/selection.md#L4-4 HINT block '
  )
end)

test('sends only the diagnostics inside the selection', function()
  local plugin = require('herdr-context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()

  local sent
  local stubs = single_agent_stubs(function(text) sent = text end)

  local last_column = #vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1] - 1
  vim.api.nvim_buf_set_mark(buf, '<', 3, 0, {})
  vim.api.nvim_buf_set_mark(buf, '>', 4, last_column, {})
  with_diagnostics(buf, sample_diagnostics(), function()
    with_environment('w1', 't1', function()
      with_cli_stubs(stubs, function() plugin.send_diagnostics({ range = 2 }) end)
    end)
  end)
  vim.cmd('silent! %bwipeout!')

  assert_equal(
    sent,
    ' @tests/fixtures/selection.md#L3-3 ERROR undefined global `value` [lua_ls undefined-global] \n'
      .. ' @tests/fixtures/selection.md#L4-4 HINT block '
  )
end)

test('sends every open file with its own diagnostics below it', function()
  local plugin = require('herdr-context')
  vim.cmd('silent! %bwipeout!')
  local readme = vim.fs.normalize(vim.fn.getcwd() .. '/README.md')
  vim.cmd('edit ' .. vim.fn.fnameescape(readme))
  local readme_buf = vim.api.nvim_get_current_buf()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local fixture_buf = vim.api.nvim_get_current_buf()

  local sent
  local stubs = single_agent_stubs(function(text) sent = text end)

  with_diagnostics(readme_buf, readme_diagnostics(), function()
    with_diagnostics(fixture_buf, sample_diagnostics(), function()
      with_environment('w1', 't1', function() with_cli_stubs(stubs, plugin.send_buffers_diagnostics) end)
    end)
  end)
  vim.cmd('silent! %bwipeout!')

  assert_equal(
    sent,
    ' @README.md#L2-2 INFO stale badge [markdownlint] \n'
      .. ' @tests/fixtures/selection.md#L1-1 WARN unused variable [lua_ls] \n'
      .. ' @tests/fixtures/selection.md#L3-3 ERROR undefined global `value` [lua_ls undefined-global] \n'
      .. ' @tests/fixtures/selection.md#L4-4 HINT block '
  )
end)

test('limits the selection to the current file and keeps every other file whole', function()
  local plugin = require('herdr-context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.normalize(vim.fn.getcwd() .. '/README.md')))
  local readme_buf = vim.api.nvim_get_current_buf()
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local fixture_buf = vim.api.nvim_get_current_buf()

  local sent
  local stubs = single_agent_stubs(function(text) sent = text end)
  local last_column = #vim.api.nvim_buf_get_lines(fixture_buf, 3, 4, false)[1] - 1
  vim.api.nvim_buf_set_mark(fixture_buf, '<', 3, 0, {})
  vim.api.nvim_buf_set_mark(fixture_buf, '>', 4, last_column, {})

  with_diagnostics(readme_buf, readme_diagnostics(), function()
    with_diagnostics(fixture_buf, sample_diagnostics(), function()
      with_environment('w1', 't1', function()
        with_cli_stubs(stubs, function() plugin.send_buffers_diagnostics({ range = 2 }) end)
      end)
    end)
  end)
  vim.cmd('silent! %bwipeout!')

  assert_equal(
    sent,
    ' @README.md#L2-2 INFO stale badge [markdownlint] \n'
      .. ' @tests/fixtures/selection.md#L3-3 ERROR undefined global `value` [lua_ls undefined-global] \n'
      .. ' @tests/fixtures/selection.md#L4-4 HINT block '
  )
end)

test('keeps a file without diagnostics in the all-files list', function()
  local context = require('herdr-context.context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.normalize(vim.fn.getcwd() .. '/README.md')))
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))
  local buf = vim.api.nvim_get_current_buf()

  local contexts, skipped, reported
  with_diagnostics(buf, sample_diagnostics(), function()
    contexts, skipped, reported = context.from_buffers_with_diagnostics()
  end)
  vim.cmd('silent! %bwipeout!')

  assert_equal(skipped, 0)
  assert_equal(reported, 3)
  assert_equal(#contexts, 4)
  assert_equal(contexts[1].range, nil)
  assert_equal(contexts[1].diagnostic, nil)
  assert_equal(contexts[2].diagnostic, 'WARN unused variable [lua_ls]')
end)

test('reports that no open buffer has diagnostics', function()
  local plugin = require('herdr-context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))

  local text_called = false
  with_notification_capture(function(notifications)
    with_environment('w1', 't1', function()
      with_cli_stubs({ send_text = function() text_called = true end }, plugin.send_buffers_diagnostics)
    end)
    assert_equal(notifications[1].message, 'No open buffer has diagnostics.')
    assert_equal(notifications[1].level, vim.log.levels.WARN)
  end)
  vim.cmd('silent! %bwipeout!')

  assert_equal(text_called, false)
end)

test('refuses a diagnostics send when the selected buffer is modified', function()
  local plugin = require('herdr-context')
  local text_called = false

  with_modified_selection(function()
    with_notification_capture(function(notifications)
      with_environment('w1', 't1', function()
        with_cli_stubs(
          { send_text = function() text_called = true end },
          function() plugin.send_diagnostics({ range = 2 }) end
        )
      end)
      assert_equal(notifications[1].message, 'The current buffer has unsaved changes.')
      assert_equal(notifications[1].level, vim.log.levels.WARN)
    end)
  end)

  assert_equal(text_called, false)
end)

test('refuses an all-files diagnostics send when the selected buffer is modified', function()
  local plugin = require('herdr-context')
  local text_called = false

  with_modified_selection(function()
    with_notification_capture(function(notifications)
      with_environment('w1', 't1', function()
        with_cli_stubs(
          { send_text = function() text_called = true end },
          function() plugin.send_buffers_diagnostics({ range = 2 }) end
        )
      end)
      assert_equal(notifications[1].message, 'The current buffer has unsaved changes.')
      assert_equal(notifications[1].level, vim.log.levels.WARN)
    end)
  end)

  assert_equal(text_called, false)
end)

test('reports a buffer without diagnostics before any Herdr command', function()
  local plugin = require('herdr-context')
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. vim.fn.fnameescape(selection_fixture))

  local text_called = false
  with_notification_capture(function(notifications)
    with_environment('w1', 't1', function()
      with_cli_stubs({ send_text = function() text_called = true end }, plugin.send_diagnostics)
    end)
    assert_equal(notifications[1].message, 'The current buffer has no diagnostics.')
    assert_equal(notifications[1].level, vim.log.levels.WARN)
  end)
  vim.cmd('silent! %bwipeout!')

  assert_equal(text_called, false)
end)

test('setup creates the command without a default mapping', function()
  local plugin = require('herdr-context')
  plugin.setup()
  assert_equal(vim.fn.exists(':HerdrContextSendBuffer'), 2)
  assert_equal(vim.fn.exists(':HerdrContextSendSelection'), 0)
  assert_equal(plugin.config.mappings.buffer, '')
  assert_equal(plugin.config.mappings.buffers, '')
  assert_equal(plugin.config.mappings.diagnostics, '')
  assert_equal(plugin.config.mappings.buffers_diagnostics, '')

  plugin.setup({ mappings = { buffer = '<leader>ac' } })
  assert_equal(plugin.config.mappings.buffer, '<leader>ac')
  assert_equal(plugin.config.mappings.diagnostics, '')
  assert_equal(plugin.config.mappings.buffers_diagnostics, '')
end)

test('setup registers configured normal and visual mappings', function()
  local plugin = require('herdr-context')
  local buffer_mapping = '<Plug>(herdr-context-test-buffer)'
  local diagnostics_mapping = '<Plug>(herdr-context-test-diagnostics)'
  local buffers_diagnostics_mapping = '<Plug>(herdr-context-test-buffers-diagnostics)'

  plugin.setup({
    mappings = {
      buffer = buffer_mapping,
      diagnostics = diagnostics_mapping,
      buffers_diagnostics = buffers_diagnostics_mapping,
    },
  })

  assert_equal(vim.fn.maparg(buffer_mapping, 'n', false, true).lhs, buffer_mapping)
  assert_equal(vim.fn.maparg(buffer_mapping, 'x', false, true).lhs, buffer_mapping)
  assert_equal(vim.fn.maparg(diagnostics_mapping, 'n', false, true).lhs, diagnostics_mapping)
  assert_equal(vim.fn.maparg(diagnostics_mapping, 'x', false, true).lhs, diagnostics_mapping)
  assert_equal(vim.fn.maparg(buffers_diagnostics_mapping, 'n', false, true).lhs, buffers_diagnostics_mapping)
  assert_equal(vim.fn.maparg(buffers_diagnostics_mapping, 'x', false, true).lhs, buffers_diagnostics_mapping)
  vim.keymap.del('n', buffer_mapping)
  vim.keymap.del('x', buffer_mapping)
  vim.keymap.del('n', diagnostics_mapping)
  vim.keymap.del('x', diagnostics_mapping)
  vim.keymap.del('n', buffers_diagnostics_mapping)
  vim.keymap.del('x', buffers_diagnostics_mapping)
end)

test('rejects an invalid mapping before replacing configuration', function()
  local plugin = require('herdr-context')
  plugin.setup({ mappings = { buffer = 'x' } })
  local ok = pcall(plugin.setup, { mappings = { buffer = false } })
  assert_equal(ok, false)
  assert_equal(plugin.config.mappings.buffer, 'x')
end)

for _, case in ipairs(tests) do
  local ok, err = xpcall(case.body, debug.traceback)
  if ok then
    print('ok - ' .. case.name)
  else
    failures = failures + 1
    print('not ok - ' .. case.name)
    print(err)
  end
end

if failures > 0 then
  print(string.format('%d of %d tests failed', failures, #tests))
  vim.cmd('cquit 1')
end

print(string.format('%d tests passed', #tests))
