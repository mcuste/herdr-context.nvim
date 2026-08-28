-- Minimal init for the compatibility tests. HERDR_TEST_PLUGINS names the
-- plugin directories to add, so each backend runs without the other three.
-- Plugin scripts stay enabled because Snacks registers commands from plugin/.
for _, path in ipairs({
  vim.fn.stdpath('config'),
  vim.fn.stdpath('config') .. '/after',
  vim.fn.stdpath('data') .. '/site',
  vim.fn.stdpath('data') .. '/site/after',
}) do
  vim.opt.runtimepath:remove(path)
end
vim.opt.packpath = vim.env.VIMRUNTIME

vim.opt.runtimepath:append(vim.fn.getcwd())
vim.o.swapfile = false

local directory = vim.env.HERDR_TEST_PLUGIN_DIR or (vim.fn.getcwd() .. '/.test-plugins')
for name in (vim.env.HERDR_TEST_PLUGINS or ''):gmatch('[^,]+') do
  local path = directory .. '/' .. name
  if vim.fn.isdirectory(path) == 0 then error('Missing test plugin: ' .. path) end
  vim.opt.runtimepath:append(path)
end
