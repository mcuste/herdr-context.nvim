local tests = {}
local failures = 0

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
  assert_equal(adapters.get('codex').format(context), ' plugin.lua ')
  assert_equal(adapters.get('codex').format({ relative_file = 'lua/my plugin.lua' }), ' "lua/my plugin.lua" ')
  assert_equal(adapters.get('unknown'), adapters.registry.generic)
  assert_equal(adapters.get('omp') == adapters.get('pi'), false)
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
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.getcwd() .. '/README.md'))
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
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.getcwd() .. '/README.md'))
  local buf = vim.api.nvim_get_current_buf()
  local selection = require('herdr-context.context').from_selection(buf, 'v', { 1, 2 }, { 1, 6 })

  assert_equal(selection.start_line, 1)
  assert_equal(selection.end_line, 1)
  assert_equal(selection.whole_lines, false)
  assert_equal(selection.selection, 'herdr')
end)
test('keeps partial block selection content', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.getcwd() .. '/README.md'))
  local buf = vim.api.nvim_get_current_buf()
  local selection = require('herdr-context.context').from_selection(buf, '\22', { 3, 0 }, { 4, 3 })

  assert_equal(selection.start_line, 3)
  assert_equal(selection.end_line, 4)
  assert_equal(selection.whole_lines, false)
  assert_equal(selection.selection, 'Plac\nthen')
end)

test('keeps modified partial content but rejects modified whole lines', function()
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.getcwd() .. '/README.md'))
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
  end)
  assert_equal(text_called, false)
end)

test('setup creates the command without a default mapping', function()
  local plugin = require('herdr-context')
  plugin.setup()
  assert_equal(plugin.config.mappings.buffer, '')
  assert_equal(plugin.config.mappings.selection, '')

  plugin.setup({ mappings = { buffer = '<leader>ac' } })
  assert_equal(plugin.config.mappings.buffer, '<leader>ac')
  assert_equal(plugin.config.mappings.selection, '')
end)

test('setup registers configured normal and visual mappings', function()
  local plugin = require('herdr-context')
  local buffer_mapping = '<Plug>(herdr-context-test-buffer)'
  local selection_mapping = '<Plug>(herdr-context-test-selection)'

  plugin.setup({ mappings = { buffer = buffer_mapping, selection = selection_mapping } })

  assert_equal(vim.fn.maparg(buffer_mapping, 'n', false, true).lhs, buffer_mapping)
  assert_equal(vim.fn.maparg(selection_mapping, 'x', false, true).lhs, selection_mapping)
  vim.keymap.del('n', buffer_mapping)
  vim.keymap.del('x', selection_mapping)
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
