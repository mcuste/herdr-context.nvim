local root = vim.fn.getcwd()
local log = vim.fn.tempname()
local text_log = log .. '.text'

local function assert_equal(actual, expected)
  if vim.deep_equal(actual, expected) then return end
  error(string.format('Expected %s, got %s', vim.inspect(expected), vim.inspect(actual)))
end

local function read_calls(count)
  local completed = vim.wait(
    2000,
    function() return vim.fn.filereadable(log) == 1 and #vim.fn.readfile(log) == count end,
    10
  )
  if not completed then error('Timed out while waiting for Herdr commands') end

  local calls = vim.fn.readfile(log)
  vim.fn.delete(log)
  return calls
end

local function read_text()
  local text = table.concat(vim.fn.readfile(text_log, 'b'), '\n')
  vim.fn.delete(text_log)
  return text
end

local cases = {
  character = {
    first = { 0, 1, 1, 0 },
    key = 'v',
    last = { 1, 6 },
    mode = 'v',
    text = ' @README.md#L1-1 \n\n```markdown\n# herdr\n```',
  },
}

local selection = cases.character

vim.env.PATH = root .. '/tests/fixtures:' .. vim.env.PATH
vim.env.HERDR_CONTEXT_TEST_LOG = log
vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'single'
vim.env.HERDR_WORKSPACE_ID = 'smoke-w'
vim.env.HERDR_TAB_ID = 'smoke-t'

vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/README.md'))
vim.bo.filetype = 'markdown'
local mapping = 'gs'
require('herdr-context').setup({ mappings = { selection = mapping } })

vim.api.nvim_win_set_cursor(0, selection.last[1] == 1 and { 1, 0 } or { 3, 0 })
vim.cmd('normal! ' .. vim.keycode(selection.key))
vim.api.nvim_win_set_cursor(0, selection.last)
assert_equal(vim.fn.mode(), selection.mode)
vim.api.nvim_feedkeys(vim.keycode(mapping), 'mx', false)

assert_equal(read_calls(3), {
  'agent|list||',
  'pane|send-text|smoke:p1|<text>',
  'agent|focus|smoke:p1|',
})
assert_equal(read_text(), selection.text)
vim.keymap.del('x', mapping)
print('Visual selection smoke test passed')
