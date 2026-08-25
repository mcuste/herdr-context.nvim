local root = vim.fn.getcwd()
local log = root .. '/.herdr-context-smoke.log'
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

vim.fn.delete(log)
vim.fn.delete(text_log)
vim.env.PATH = root .. '/tests/fixtures:' .. vim.env.PATH
vim.env.HERDR_CONTEXT_TEST_LOG = log
vim.env.HERDR_WORKSPACE_ID = 'smoke-w'
vim.env.HERDR_TAB_ID = 'smoke-t'

vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/README.md'))
require('herdr-context').setup()

vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'single'
vim.cmd('HerdrContextSendBuffer')
assert_equal(read_calls(3), {
  'agent|list||',
  'pane|send-text|smoke:p1|<text>',
  'agent|focus|smoke:p1|',
})
assert_equal(read_text(), ' @README.md ')

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
  'Agents > omp (smoke:p2) | idle | ' .. root,
  'Agents > omp (smoke:p3) | working | ' .. root,
})
assert_equal(calls, {
  'agent|list||',
  'tab|list|--workspace|smoke-w',
  'pane|send-text|smoke:p3|<text>',
  'agent|focus|smoke:p3|',
})
assert_equal(read_text(), ' @README.md ')

print('Smoke test passed')
