local shared = dofile('tests/compat/shared.lua')

require('noice').setup({ notify = { enabled = true } })
-- Noice defers its own setup to VimEnter, which fires after every -c command.
vim.cmd('doautocmd VimEnter')

vim.notify(shared.message, vim.log.levels.WARN, { title = shared.title })

local collected = shared.wait_for_collected()
local body = shared.assert_section(collected, 'noice.nvim notifications')
shared.assert_label(body, '[WARN')
shared.pass('noice.nvim')
