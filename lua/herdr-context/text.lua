local M = {}

-- Agent input holds one entry per line.
function M.single_line(message)
  if type(message) ~= 'string' then return '' end
  local text = message:gsub('%s+', ' ')
  return vim.trim(text)
end

return M
