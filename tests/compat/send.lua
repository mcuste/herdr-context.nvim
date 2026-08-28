local shared = dofile('tests/compat/shared.lua')

local root = vim.fn.getcwd()
local log = vim.fn.tempname()
local text_log = log .. '.text'

vim.env.PATH = root .. '/tests/fixtures:' .. vim.env.PATH
vim.env.HERDR_CONTEXT_TEST_LOG = log
vim.env.HERDR_CONTEXT_TEST_SCENARIO = 'single'
vim.env.HERDR_WORKSPACE_ID = 'smoke-w'
vim.env.HERDR_TAB_ID = 'smoke-t'

require('mini.notify').setup()
MiniNotify.add(shared.message, 'WARN')
shared.assert_section(shared.wait_for_collected(), 'mini.notify notifications')

require('herdr-context').setup()
vim.cmd('HerdrContextSendMessages')

if not vim.wait(5000, function() return vim.fn.filereadable(text_log) == 1 end, 20) then
  error('Herdr never received the message history')
end
local sent = table.concat(vim.fn.readfile(text_log, 'b'), '\n')
vim.fn.delete(log)
vim.fn.delete(text_log)

if not shared.contains(sent, shared.marker) then error(string.format('Herdr received %s', vim.inspect(sent))) end
shared.pass('send_messages')
