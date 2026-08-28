local M = {}

-- Every test emits this marker so an assertion cannot match unrelated output.
M.marker = 'herdr-compat-7f3a'
M.lines = { M.marker .. ' first line', M.marker .. ' second line' }
M.message = table.concat(M.lines, '\n')
M.title = 'Herdr Compat'

local function contains(text, expected) return type(text) == 'string' and text:find(expected, 1, true) ~= nil end

M.contains = contains

-- Backends render on a timer, so poll the real output instead of sleeping.
function M.wait_for_collected()
  local messages = require('herdr-context.messages')
  local collected
  vim.wait(5000, function()
    collected = messages.collect()
    return contains(collected, M.marker)
  end, 20)
  return collected
end

-- Return the body of the fenced section the adapter labels with `name`.
function M.assert_section(collected, name)
  if not contains(collected, M.marker) then
    error(string.format('%s history never reached collect(). Got %s', name, vim.inspect(collected)))
  end

  local pattern = name:gsub('%p', '%%%0') .. ':\n\n(`+)text\n(.-)\n%1'
  local _, body = collected:match(pattern)
  if body == nil then error(string.format('No fenced "%s" section in %s', name, vim.inspect(collected))) end

  for _, line in ipairs(M.lines) do
    if not contains(body, line) then
      error(string.format('The "%s" section lost %q. Got %s', name, line, vim.inspect(body)))
    end
  end
  return body
end

function M.assert_label(body, expected)
  if not contains(body, expected) then error(string.format('Expected label %q in %s', expected, vim.inspect(body))) end
end

-- Write straight to stdout. Noice takes over the Neovim message system.
function M.pass(name)
  io.stdout:write(name .. ' compatibility test passed\n')
  io.stdout:flush()
end

return M
