local root = vim.fn.getcwd()
local log = vim.fn.tempname()
local text_log = log .. '.text'

local function read_calls(count)
  local completed = vim.wait(
    2000,
    function() return vim.fn.filereadable(log) == 1 and #vim.fn.readfile(log) == count end,
    10
  )
  if not completed then
    vim.fn.delete(log)
    error('Timed out while waiting for Herdr commands')
  end

  local calls = vim.fn.readfile(log)
  vim.fn.delete(log)
  return calls
end

local function read_text()
  local text = table.concat(vim.fn.readfile(text_log, 'b'), '\n')
  vim.fn.delete(text_log)
  return text
end

local function assert_equal(actual, expected)
  if vim.deep_equal(actual, expected) then return end
  error(string.format('Expected %s, got %s', vim.inspect(expected), vim.inspect(actual)))
end

local function with_notifications(body)
  local original = vim.notify
  local notifications = {}
  vim.notify = function(message, level) table.insert(notifications, { message = message, level = level }) end

  local ok, err = xpcall(function() body(notifications) end, debug.traceback)
  vim.notify = original
  if not ok then error(err, 0) end
end

local function wait_for_notification(notifications)
  if not vim.wait(2000, function() return #notifications > 0 end, 10) then
    error('Timed out while waiting for a notification')
  end
end

local function with_health_capture(body)
  local original = {
    start = vim.health.start,
    ok = vim.health.ok,
    warn = vim.health.warn,
    error = vim.health.error,
  }
  local messages = {}
  for kind in pairs(original) do
    vim.health[kind] = function(message) table.insert(messages, { kind = kind, message = message }) end
  end

  local ok, err = xpcall(function() body(messages) end, debug.traceback)
  for kind, value in pairs(original) do
    vim.health[kind] = value
  end
  if not ok then error(err, 0) end
end

local function with_herdr_location(workspace_id, tab_id, body)
  local original_workspace_id = vim.env.HERDR_WORKSPACE_ID
  local original_tab_id = vim.env.HERDR_TAB_ID
  vim.env.HERDR_WORKSPACE_ID = workspace_id
  vim.env.HERDR_TAB_ID = tab_id

  local ok, err = xpcall(body, debug.traceback)
  vim.env.HERDR_WORKSPACE_ID = original_workspace_id
  vim.env.HERDR_TAB_ID = original_tab_id
  if not ok then error(err, 0) end
end
local function with_path(path, body)
  local original = vim.env.PATH
  vim.env.PATH = path
  local ok, err = xpcall(body, debug.traceback)
  vim.env.PATH = original
  if not ok then error(err, 0) end
end

local function assert_health(scenario, expected_messages, expected_calls)
  vim.env.HERDR_CONTEXT_TEST_SCENARIO = scenario
  with_health_capture(function(messages)
    require('herdr-context.health').check()
    assert_equal(messages, expected_messages)
  end)
  assert_equal(read_calls(#expected_calls), expected_calls)
end

vim.fn.delete(log)
vim.fn.delete(text_log)
vim.env.PATH = root .. '/tests/fixtures:' .. vim.env.PATH
vim.env.HERDR_CONTEXT_TEST_LOG = log
vim.env.HERDR_WORKSPACE_ID = 'smoke-w'
vim.env.HERDR_TAB_ID = 'smoke-t'

vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/README.md'))
require('herdr-context').setup()
with_notifications(function(notifications)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { '# unsaved' })
  vim.cmd('HerdrContextSendBuffer')
  assert_equal(notifications[1].message, 'The current buffer has unsaved changes.')
  assert_equal(notifications[1].level, vim.log.levels.WARN)
  assert_equal(vim.fn.filereadable(log), 0)
  vim.cmd('edit!')
end)

vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'single'
vim.cmd('HerdrContextSendBuffer')
assert_equal(read_calls(3), {
  'agent|list||',
  'pane|send-text|smoke:p1|<text>',
  'agent|focus|smoke:p1|',
})
assert_equal(read_text(), ' @README.md ')

vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/CHANGELOG.md'))
vim.cmd('HerdrContextSendBuffers')
assert_equal(read_calls(3), {
  'agent|list||',
  'pane|send-text|smoke:p1|<text>',
  'agent|focus|smoke:p1|',
})
assert_equal(read_text(), ' @README.md \n @CHANGELOG.md ')

vim.bo.filetype = 'markdown'
vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
vim.api.nvim_buf_set_mark(0, '>', 1, 4, {})
vim.cmd("'<,'>HerdrContextSendBuffers")
assert_equal(read_calls(3), {
  'agent|list||',
  'pane|send-text|smoke:p1|<text>',
  'agent|focus|smoke:p1|',
})
assert_equal(read_text(), ' @README.md \n @CHANGELOG.md#L1-1 \n\n```markdown\n# Cha\n```')
vim.cmd('bwipeout!')

vim.bo.filetype = 'markdown'
vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
vim.api.nvim_buf_set_mark(0, '>', 1, 6, {})
vim.cmd("'<,'>HerdrContextSendSelection")
assert_equal(read_calls(3), {
  'agent|list||',
  'pane|send-text|smoke:p1|<text>',
  'agent|focus|smoke:p1|',
})
assert_equal(read_text(), ' @README.md#L1-1 \n\n```markdown\n# herdr\n```')

local diagnostics_namespace = vim.api.nvim_create_namespace('herdr-context-smoke')
vim.diagnostic.set(diagnostics_namespace, 0, {
  {
    lnum = 0,
    col = 0,
    severity = vim.diagnostic.severity.ERROR,
    message = 'first line\nmust be a heading',
    source = 'markdownlint',
    code = 'MD041',
  },
  { lnum = 4, col = 0, severity = vim.diagnostic.severity.WARN, message = 'line is too long', source = 'markdownlint' },
})
vim.cmd('HerdrContextSendDiagnostics')
assert_equal(read_calls(3), {
  'agent|list||',
  'pane|send-text|smoke:p1|<text>',
  'agent|focus|smoke:p1|',
})
assert_equal(
  read_text(),
  ' @README.md#L1-1 ERROR first line must be a heading [markdownlint MD041] \n'
    .. ' @README.md#L5-5 WARN line is too long [markdownlint] '
)

vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
vim.api.nvim_buf_set_mark(0, '>', 1, 6, {})
vim.cmd("'<,'>HerdrContextSendDiagnostics")
assert_equal(read_calls(3), {
  'agent|list||',
  'pane|send-text|smoke:p1|<text>',
  'agent|focus|smoke:p1|',
})
assert_equal(read_text(), ' @README.md#L1-1 ERROR first line must be a heading [markdownlint MD041] ')

vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/CHANGELOG.md'))
vim.diagnostic.set(diagnostics_namespace, 0, {
  { lnum = 6, col = 0, severity = vim.diagnostic.severity.HINT, message = 'empty section', source = 'changelog' },
})
vim.cmd('HerdrContextSendBuffersDiagnostics')
assert_equal(read_calls(3), {
  'agent|list||',
  'pane|send-text|smoke:p1|<text>',
  'agent|focus|smoke:p1|',
})
assert_equal(
  read_text(),
  ' @README.md#L1-1 ERROR first line must be a heading [markdownlint MD041] \n'
    .. ' @README.md#L5-5 WARN line is too long [markdownlint] \n'
    .. ' @CHANGELOG.md#L7-7 HINT empty section [changelog] '
)
vim.cmd('bwipeout!')

with_notifications(function(notifications)
  vim.diagnostic.reset(diagnostics_namespace, 0)
  vim.cmd('HerdrContextSendBuffersDiagnostics')
  assert_equal(notifications[1].message, 'No open buffer has diagnostics.')
  assert_equal(notifications[1].level, vim.log.levels.WARN)
  vim.cmd('HerdrContextSendDiagnostics')
  assert_equal(notifications[2].message, 'The current buffer has no diagnostics.')
  assert_equal(vim.fn.filereadable(log), 0)
end)

local labels
local original_select = vim.ui.select
vim.ui.select = function(choices, options, callback)
  labels = vim.tbl_map(options.format_item, choices)
  callback(choices[2])
end

vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'multiple'
vim.cmd('HerdrContextSendBuffer')
local calls = read_calls(4)
vim.ui.select = original_select

assert_equal(labels, {
  '[1] ○  Agent: omp  Tab: Agents  CWD: ' .. root,
  '[2] ●  Agent: omp  Tab: Agents  CWD: ' .. root,
})
assert_equal(calls, {
  'agent|list||',
  'tab|list|--workspace|smoke-w',
  'pane|send-text|smoke:p3|<text>',
  'agent|focus|smoke:p3|',
})
assert_equal(read_text(), ' @README.md ')

with_notifications(function(notifications)
  vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'agent-failure'
  vim.cmd('HerdrContextSendBuffer')
  wait_for_notification(notifications)
  assert_equal(read_calls(1), { 'agent|list||' })
  assert_equal(notifications[1].message, 'Could not list Herdr agents: could not list agents')
end)

with_notifications(function(notifications)
  vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'tabs-failure'
  vim.cmd('HerdrContextSendBuffer')
  wait_for_notification(notifications)
  assert_equal(read_calls(2), {
    'agent|list||',
    'tab|list|--workspace|smoke-w',
  })
  assert_equal(notifications[1].message, 'Could not list Herdr tabs: could not list tabs')
end)

with_notifications(function(notifications)
  vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'send-failure'
  vim.cmd('HerdrContextSendBuffer')
  wait_for_notification(notifications)
  assert_equal(read_calls(2), {
    'agent|list||',
    'pane|send-text|smoke:p1|<text>',
  })
  assert_equal(notifications[1].message, 'Could not place context in the agent input: could not place input')
  assert_equal(notifications[1].level, vim.log.levels.ERROR)
end)

with_notifications(function(notifications)
  vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'focus-failure'
  vim.cmd('HerdrContextSendBuffer')
  wait_for_notification(notifications)
  assert_equal(read_calls(3), {
    'agent|list||',
    'pane|send-text|smoke:p1|<text>',
    'agent|focus|smoke:p1|',
  })
  assert_equal(
    notifications[1].message,
    'Context was placed, but the agent could not be focused: could not focus agent'
  )
end)

local cancel_select_original = vim.ui.select
local picker_called = false
vim.ui.select = function(_, _, callback)
  picker_called = true
  callback(nil)
end
vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'multiple'
vim.cmd('HerdrContextSendBuffer')
if not vim.wait(2000, function() return picker_called end, 10) then error('Timed out while waiting for the picker') end
local cancel_calls = read_calls(2)
vim.ui.select = cancel_select_original
assert_equal(cancel_calls, {
  'agent|list||',
  'tab|list|--workspace|smoke-w',
})

vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'single'
with_health_capture(function(messages)
  require('herdr-context.health').check()
  assert_equal(messages, {
    { kind = 'start', message = 'herdr-context.nvim' },
    { kind = 'ok', message = 'Neovim 0.10 or later is available' },
    { kind = 'ok', message = 'herdr 0.7.5' },
    { kind = 'ok', message = 'HERDR_WORKSPACE_ID is set' },
    { kind = 'ok', message = 'HERDR_TAB_ID is set' },
    { kind = 'ok', message = 'Herdr accepted `agent list`' },
    { kind = 'ok', message = 'Herdr accepted `tab list`' },
  })
end)
assert_equal(read_calls(3), {
  '--version|||',
  'agent|list||',
  'tab|list|--workspace|smoke-w',
})
assert_health('old-version', {
  { kind = 'start', message = 'herdr-context.nvim' },
  { kind = 'ok', message = 'Neovim 0.10 or later is available' },
  { kind = 'error', message = 'Herdr 0.7.5 or later is required' },
  { kind = 'ok', message = 'HERDR_WORKSPACE_ID is set' },
  { kind = 'ok', message = 'HERDR_TAB_ID is set' },
  { kind = 'ok', message = 'Herdr accepted `agent list`' },
  { kind = 'ok', message = 'Herdr accepted `tab list`' },
}, {
  '--version|||',
  'agent|list||',
  'tab|list|--workspace|smoke-w',
})

assert_health('malformed-version', {
  { kind = 'start', message = 'herdr-context.nvim' },
  { kind = 'ok', message = 'Neovim 0.10 or later is available' },
  { kind = 'warn', message = 'Could not parse the Herdr version' },
  { kind = 'ok', message = 'HERDR_WORKSPACE_ID is set' },
  { kind = 'ok', message = 'HERDR_TAB_ID is set' },
  { kind = 'ok', message = 'Herdr accepted `agent list`' },
  { kind = 'ok', message = 'Herdr accepted `tab list`' },
}, {
  '--version|||',
  'agent|list||',
  'tab|list|--workspace|smoke-w',
})

assert_health('version-failure', {
  { kind = 'start', message = 'herdr-context.nvim' },
  { kind = 'ok', message = 'Neovim 0.10 or later is available' },
  { kind = 'error', message = 'Could not run `herdr --version`' },
  { kind = 'ok', message = 'HERDR_WORKSPACE_ID is set' },
  { kind = 'ok', message = 'HERDR_TAB_ID is set' },
  { kind = 'ok', message = 'Herdr accepted `agent list`' },
  { kind = 'ok', message = 'Herdr accepted `tab list`' },
}, {
  '--version|||',
  'agent|list||',
  'tab|list|--workspace|smoke-w',
})

assert_health('agent-failure', {
  { kind = 'start', message = 'herdr-context.nvim' },
  { kind = 'ok', message = 'Neovim 0.10 or later is available' },
  { kind = 'ok', message = 'herdr 0.7.5' },
  { kind = 'ok', message = 'HERDR_WORKSPACE_ID is set' },
  { kind = 'ok', message = 'HERDR_TAB_ID is set' },
  { kind = 'error', message = 'Herdr did not accept `agent list`' },
  { kind = 'ok', message = 'Herdr accepted `tab list`' },
}, {
  '--version|||',
  'agent|list||',
  'tab|list|--workspace|smoke-w',
})

assert_health('tabs-failure', {
  { kind = 'start', message = 'herdr-context.nvim' },
  { kind = 'ok', message = 'Neovim 0.10 or later is available' },
  { kind = 'ok', message = 'herdr 0.7.5' },
  { kind = 'ok', message = 'HERDR_WORKSPACE_ID is set' },
  { kind = 'ok', message = 'HERDR_TAB_ID is set' },
  { kind = 'ok', message = 'Herdr accepted `agent list`' },
  { kind = 'error', message = 'Herdr did not accept `tab list`' },
}, {
  '--version|||',
  'agent|list||',
  'tab|list|--workspace|smoke-w',
})

with_path(root, function()
  with_health_capture(function(messages)
    require('herdr-context.health').check()
    assert_equal(messages, {
      { kind = 'start', message = 'herdr-context.nvim' },
      { kind = 'ok', message = 'Neovim 0.10 or later is available' },
      { kind = 'error', message = 'Herdr CLI was not found in PATH' },
    })
  end)
  assert_equal(vim.fn.filereadable(log), 0)
end)

with_herdr_location('', '', function()
  with_health_capture(function(messages)
    require('herdr-context.health').check()
    assert_equal(messages, {
      { kind = 'start', message = 'herdr-context.nvim' },
      { kind = 'ok', message = 'Neovim 0.10 or later is available' },
      { kind = 'ok', message = 'herdr 0.7.5' },
      { kind = 'warn', message = 'HERDR_WORKSPACE_ID is not set; run Neovim inside a Herdr pane' },
      { kind = 'warn', message = 'HERDR_TAB_ID is not set; run Neovim inside a Herdr pane' },
      { kind = 'ok', message = 'Herdr accepted `agent list`' },
    })
  end)
  assert_equal(read_calls(2), {
    '--version|||',
    'agent|list||',
  })
end)
print('Smoke test passed')
