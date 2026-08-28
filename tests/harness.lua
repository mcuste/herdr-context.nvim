-- Run the test file named by HERDR_TEST_FILE and exit nonzero when it fails.
-- Neovim still exits with 0 after an error in a -c command, so without this
-- wrapper CI cannot see a failing test.
local file = vim.env.HERDR_TEST_FILE
if file == nil or file == '' then
  io.stderr:write('HERDR_TEST_FILE is not set\n')
  io.stderr:flush()
  vim.cmd('cquit 2')
  return
end

local ok, err = xpcall(dofile, debug.traceback, file)
if not ok then
  io.stderr:write(string.format('%s failed:\n%s\n', file, tostring(err)))
  io.stderr:flush()
  vim.cmd('cquit 1')
end
