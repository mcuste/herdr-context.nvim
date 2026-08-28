local M = {}

local function fence(text)
  local longest = 0
  for ticks in text:gmatch('`+') do
    longest = math.max(longest, #ticks)
  end
  return string.rep('`', math.max(3, longest + 1))
end

function M.format(history)
  if type(history) ~= 'string' or history:find('%S') == nil then return nil, "Neovim's message history is empty." end

  history = history:gsub('\n+$', '')
  local marker = fence(history)
  return string.format(' Neovim messages:\n\n%stext\n%s\n%s ', marker, history, marker)
end

function M.collect()
  local result = vim.api.nvim_exec2('messages', { output = true })
  return M.format(result.output)
end

return M
